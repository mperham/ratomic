use crate::{gc_guard::GcGuard, sem::Semaphore};
use rb_sys::VALUE;
use std::{
    cell::Cell,
    sync::atomic::{AtomicUsize, Ordering},
};

struct QueueElement {
    sequence: AtomicUsize,
    data: Cell<VALUE>,
}

unsafe impl Send for QueueElement {}
unsafe impl Sync for QueueElement {}

pub struct MpmcQueue {
    buffer: Vec<QueueElement>,
    buffer_size: usize,
    enqueue_pos: AtomicUsize,
    dequeue_pos: AtomicUsize,
    gc_guard: GcGuard,
    read_sem: Semaphore,
    write_sem: Semaphore,
}

impl MpmcQueue {
    pub fn new(buffer_size: usize, default: VALUE) -> Self {
        let mut buffer = Vec::with_capacity(buffer_size);
        for i in 0..buffer_size {
            buffer.push(QueueElement {
                sequence: AtomicUsize::new(i),
                data: Cell::new(default),
            });
        }

        let mut gc_guard = GcGuard::alloc();
        gc_guard.init();
        let mut read_sem = Semaphore::alloc();
        read_sem.init(0);
        let mut write_sem = Semaphore::alloc();
        write_sem.init(buffer_size as u32);

        Self {
            buffer,
            buffer_size,
            enqueue_pos: AtomicUsize::new(0),
            dequeue_pos: AtomicUsize::new(0),
            gc_guard,
            read_sem,
            write_sem,
        }
    }

    fn try_push(&self, data: VALUE) -> bool {
        let mut cell;
        let mut pos = self.enqueue_pos.load(Ordering::Relaxed);
        loop {
            cell = &self.buffer[pos % self.buffer_size];
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

    fn try_pop(&self) -> Option<VALUE> {
        let mut cell;
        let mut pos = self.dequeue_pos.load(Ordering::Relaxed);
        loop {
            cell = &self.buffer[pos % self.buffer_size];
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
            .store(pos + self.buffer_size, Ordering::Release);
        self.write_sem.post();

        #[cfg(feature = "simulation")]
        std::thread::sleep(std::time::Duration::from_millis(100));

        Some(data)
    }

    pub fn push(&self, data: VALUE) {
        loop {
            if self.try_push(data) {
                return;
            }
            self.write_sem.wait();
        }
    }

    pub fn pop(&self) -> VALUE {
        loop {
            if let Some(data) = self.gc_guard.acquire_as_consumer(|| self.try_pop()) {
                return data;
            }
            self.read_sem.wait();
        }
    }

    pub fn peek(&self) -> Option<VALUE> {
        let pos = self.dequeue_pos.load(Ordering::Relaxed);
        let cell = &self.buffer[pos % self.buffer_size];
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
        self.enqueue_pos
            .load(Ordering::Relaxed)
            .wrapping_sub(self.dequeue_pos.load(Ordering::Relaxed))
    }

    pub fn mark<F>(&self, mark: F)
    where
        F: Fn(VALUE),
    {
        self.gc_guard.acquire_as_gc(|| {
            for item in self.buffer.iter() {
                mark(item.data.get());
            }
        });
    }
}
