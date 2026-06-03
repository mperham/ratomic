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
