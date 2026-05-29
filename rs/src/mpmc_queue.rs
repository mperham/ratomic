use crate::{GcGuard, sem::Semaphore};
use std::{
    cell::Cell,
    ffi::c_ulong,
    sync::atomic::{AtomicUsize, Ordering},
};
use std::ffi::c_void;

struct QueueElement {
    sequence: AtomicUsize,
    data: Cell<c_ulong>,
}

unsafe impl Send for QueueElement {}
unsafe impl Sync for QueueElement {}

pub struct MpmcQueue {
    buffer: Vec<QueueElement>,
    buffer_mask: usize,
    enqueue_pos: AtomicUsize,
    dequeue_pos: AtomicUsize,

    gc_guard: GcGuard,
    read_sem: Semaphore,
    write_sem: Semaphore,
}

impl MpmcQueue {
    fn alloc() -> Self {
        Self {
            buffer: vec![],
            buffer_mask: 0,
            enqueue_pos: AtomicUsize::new(0),
            dequeue_pos: AtomicUsize::new(0),

            gc_guard: GcGuard::alloc(),
            read_sem: Semaphore::alloc(),
            write_sem: Semaphore::alloc(),
        }
    }

    fn init(&mut self, buffer_size: usize, default: c_ulong) {
        let mut buffer = Vec::with_capacity(buffer_size.next_power_of_two());
        for i in 0..buffer_size {
            buffer.push(QueueElement {
                sequence: AtomicUsize::new(i),
                data: Cell::new(default),
            });
        }

        self.buffer_mask = buffer_size - 1;
        self.buffer = buffer;
        self.enqueue_pos.store(0, Ordering::Relaxed);
        self.dequeue_pos.store(0, Ordering::Relaxed);

        self.gc_guard.init();
        self.read_sem.init(0);
        self.write_sem.init(buffer_size as u32);
    }

    pub fn new(buffer_size: usize, default: c_ulong) -> Self {
        let mut q = Self::alloc();
        q.init(buffer_size, default);
        q
    }

    fn try_push(&self, data: c_ulong) -> bool {
        let mut cell;
        let mut pos = self.enqueue_pos.load(Ordering::Relaxed);
        loop {
            cell = &self.buffer[pos & self.buffer_mask];
            let seq = cell.sequence.load(Ordering::Acquire);
            let diff = seq as isize - pos as isize;
            if diff == 0 {
                if self
                    .enqueue_pos
                    .compare_exchange_weak(pos, pos + 1, Ordering::Relaxed, Ordering::Relaxed)
                    .is_ok()
                {
                    break;
                }
            } else if diff < 0 {
                return false;
            } else {
                pos = self.enqueue_pos.load(Ordering::Relaxed);
            }
        }
        cell.data.set(data);
        cell.sequence.store(pos + 1, Ordering::Release);
        self.read_sem.post();
        true
    }

    fn try_pop(&self) -> Option<c_ulong> {
        let mut cell;
        let mut pos = self.dequeue_pos.load(Ordering::Relaxed);
        loop {
            cell = &self.buffer[pos & self.buffer_mask];
            let seq = cell.sequence.load(Ordering::Acquire);
            let diff = seq as isize - (pos + 1) as isize;
            if diff == 0 {
                if self
                    .dequeue_pos
                    .compare_exchange_weak(pos, pos + 1, Ordering::Relaxed, Ordering::Relaxed)
                    .is_ok()
                {
                    break;
                }
            } else if diff < 0 {
                return None;
            } else {
                pos = self.dequeue_pos.load(Ordering::Relaxed);
            }
        }

        let data = cell.data.get();
        cell.sequence
            .store(pos + self.buffer_mask + 1, Ordering::Release);
        self.write_sem.post();

        #[cfg(feature = "simulation")]
        std::thread::sleep(std::time::Duration::from_millis(100));

        Some(data)
    }

    pub fn push(&self, data: c_ulong) {
        loop {
            if self.try_push(data) {
                return;
            }
            self.write_sem.wait();
        }
    }

    pub fn pop(&self) -> c_ulong {
        loop {
            if let Some(data) = self.gc_guard.acquire_as_consumer(|| self.try_pop()) {
                return data;
            }
            self.read_sem.wait();
            // self.read_sem
                // .wait_for(std::time::Duration::from_millis(100));
        }
    }

    pub fn peek(&self) -> Option<c_ulong> {
        let pos = self.dequeue_pos.load(Ordering::Relaxed);
        let cell = &self.buffer[pos & self.buffer_mask];
        let seq = cell.sequence.load(Ordering::Acquire);
        let diff = seq as isize - (pos + 1) as isize;
        if diff == 0 {
            Some(cell.data.get())
        } else {
            None
        }
    }

    pub fn is_empty(&self) -> bool {
        self.dequeue_pos.load(Ordering::Relaxed) == self.enqueue_pos.load(Ordering::Relaxed)
    }

    pub fn size(&self) -> usize {
        self.enqueue_pos.load(Ordering::Relaxed).wrapping_sub(self.dequeue_pos.load(Ordering::Relaxed))
    }

    pub fn acquire_as_gc<F, T>(&self, f: F) -> T
    where
        F: FnOnce() -> T,
    {
        self.gc_guard.acquire_as_gc(f)
    }

    fn foreach<F>(&self, f: F)
    where
        F: Fn(c_ulong),
    {
        for item in self.buffer.iter() {
            let value = item.data.get();
            f(value);
        }
    }

    fn mark(&self, mark: extern "C" fn(c_ulong)) {
        self.acquire_as_gc(|| {
            self.foreach(|item| {
                mark(item);
            });
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mpmc_queue_alloc(q: *mut MpmcQueue) {
    unsafe { q.write(MpmcQueue::alloc()) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mpmc_queue_init(q: *mut MpmcQueue, capacity: usize, default: c_ulong) {
    let q = unsafe { q.as_mut().unwrap() };
    q.init(capacity, default);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mpmc_queue_drop(q: *mut MpmcQueue) {
    unsafe { std::ptr::drop_in_place(q) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mpmc_queue_mark(q: *const MpmcQueue, f: extern "C" fn(c_ulong)) {
    let q = unsafe { q.as_ref().unwrap() };
    q.mark(f);
}

#[repr(C)]
pub struct MpmcQueuePushPayload {
    queue: *mut MpmcQueue,
    item: c_ulong,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mpmc_queue_push(
    push_paylod: *mut std::ffi::c_void,
) -> *mut std::ffi::c_void {
    let push_payload = unsafe { push_paylod.cast::<MpmcQueuePushPayload>().as_ref().unwrap() };
    let q = unsafe { push_payload.queue.as_ref().unwrap() };
    q.push(push_payload.item);
    return std::ptr::null_mut();
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mpmc_queue_pop(q: *mut std::ffi::c_void) -> *mut c_void {
    let q = unsafe { q.cast::<MpmcQueue>().as_ref().unwrap() };
    let item = q.pop();
    std::ptr::with_exposed_provenance_mut::<c_void>(item.try_into().unwrap())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mpmc_queue_peek(q: *mut std::ffi::c_void) -> *mut std::ffi::c_void {
    let q = unsafe { q.cast::<MpmcQueue>().as_ref().unwrap() };
    let item = q.peek();
    if let Some(item) = item {
        return std::ptr::with_exposed_provenance_mut::<c_void>(item.try_into().unwrap());
    }
    std::ptr::null_mut()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mpmc_queue_is_empty(q: *mut std::ffi::c_void) -> bool {
  let q = unsafe { q.cast::<MpmcQueue>().as_ref().unwrap() };
  q.is_empty()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mpmc_queue_size(q: *mut std::ffi::c_void) -> usize {
    let q = unsafe { q.cast::<MpmcQueue>().as_ref().unwrap() };
    q.size()
}

pub const MPMC_QUEUE_OBJECT_SIZE: usize = 80;

#[test]
fn test_mpmc_queue_size() {
    assert_eq!(
        MPMC_QUEUE_OBJECT_SIZE,
        std::mem::size_of::<MpmcQueue>(),
        "size mismatch"
    );

    assert!(crate::is_sync_and_send::<MpmcQueue>());
}
