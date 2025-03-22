use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Debug)]
pub struct AtomicCounter {
    value: AtomicU64,
}

impl AtomicCounter {
    pub fn new(n: u64) -> Self {
        Self {
            value: AtomicU64::new(n),
        }
    }

    pub fn inc(&self, amt: u64) {
        self.value.fetch_add(amt, Ordering::Relaxed);
    }

    pub fn dec(&self, amt: u64) {
        self.value.fetch_sub(amt, Ordering::Relaxed);
    }

    pub fn read(&self) -> u64 {
        self.value.load(Ordering::Relaxed)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn atomic_counter_init(counter: *mut AtomicCounter, n: u64) {
    unsafe { counter.write(AtomicCounter::new(n)) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn atomic_counter_increment(counter: *const AtomicCounter, amt: u64) {
    let counter = unsafe { counter.as_ref().unwrap() };
    counter.inc(amt);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn atomic_counter_decrement(counter: *const AtomicCounter, amt: u64) {
    let counter = unsafe { counter.as_ref().unwrap() };
    counter.dec(amt);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn atomic_counter_read(counter: *const AtomicCounter) -> u64 {
    let counter = unsafe { counter.as_ref().unwrap() };
    counter.read()
}

pub const ATOMIC_COUNTER_SIZE: usize = 8;

#[test]
fn test_atomic_counter() {
    assert_eq!(ATOMIC_COUNTER_SIZE, std::mem::size_of::<AtomicCounter>());
    assert!(crate::is_sync_and_send::<AtomicCounter>());
}
