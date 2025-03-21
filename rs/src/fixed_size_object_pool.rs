use crossbeam_channel::{Receiver, Sender};
use std::{ffi::c_ulong, time::Duration};

pub struct FixedSizeObjectPool {
    pool: Vec<c_ulong>,
    tx: Sender<usize>,
    rx: Receiver<usize>,
    timeout: Duration,
}

#[repr(C)]
pub struct PooledItem {
    pub idx: usize,
    pub rbobj: c_ulong,
}

impl FixedSizeObjectPool {
    fn new() -> Self {
        let (tx, rx) = crossbeam_channel::unbounded();

        Self {
            pool: vec![],
            tx,
            rx,
            timeout: Duration::MAX,
        }
    }

    fn init(
        &mut self,
        size: usize,
        timeout_in_ms: u64,
        rb_make_obj: extern "C" fn(c_ulong) -> c_ulong,
    ) {
        self.timeout = Duration::from_millis(timeout_in_ms);

        self.pool = Vec::with_capacity(size);
        for idx in 0..size {
            self.pool.push((rb_make_obj)(0));
            self.tx.send(idx).unwrap();
        }
    }

    fn mark(&self, f: extern "C" fn(c_ulong)) {
        for item in self.pool.iter() {
            f(*item);
        }
    }

    fn checkout(&mut self) -> Option<PooledItem> {
        let idx = self.rx.recv_timeout(self.timeout).ok()?;
        Some(PooledItem {
            idx,
            rbobj: self.pool[idx],
        })
    }

    fn checkin(&mut self, idx: usize) {
        self.tx.send(idx).unwrap();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fixed_size_object_pool_alloc(pool: *mut FixedSizeObjectPool) {
    unsafe { pool.write(FixedSizeObjectPool::new()) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fixed_size_object_pool_init(
    pool: *mut FixedSizeObjectPool,
    max_size: usize,
    timeout_in_ms: u64,
    rb_make_obj: extern "C" fn(c_ulong) -> c_ulong,
) {
    let pool = unsafe { pool.as_mut().unwrap() };
    pool.init(max_size, timeout_in_ms, rb_make_obj);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fixed_size_object_pool_drop(pool: *mut FixedSizeObjectPool) {
    unsafe { std::ptr::drop_in_place(pool) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fixed_size_object_pool_mark(
    pool: *const FixedSizeObjectPool,
    f: extern "C" fn(c_ulong),
) {
    let pool = unsafe { pool.as_ref().unwrap() };
    pool.mark(f);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fixed_size_object_pool_checkout(
    pool: *mut FixedSizeObjectPool,
) -> PooledItem {
    let pool = unsafe { pool.as_mut().unwrap() };
    pool.checkout().unwrap_or(PooledItem { idx: 0, rbobj: 0 })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn fixed_size_object_pool_checkin(
    pool: *mut FixedSizeObjectPool,
    idx: usize,
) {
    let pool = unsafe { pool.as_mut().unwrap() };
    pool.checkin(idx);
}

pub const FIXED_SIZE_OBJECT_POOL_SIZE: usize = 72;

#[test]
fn test_concurrent_hash_map() {
    assert_eq!(
        FIXED_SIZE_OBJECT_POOL_SIZE,
        std::mem::size_of::<FixedSizeObjectPool>(),
        "size mismatch"
    );
    assert!(crate::is_sync_and_send::<FixedSizeObjectPool>());
}
