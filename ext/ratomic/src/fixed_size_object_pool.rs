use crossbeam_channel::{Receiver, Sender};
use rb_sys::VALUE;
use std::time::Duration;

pub struct FixedSizeObjectPool {
    pool: Vec<VALUE>,
    tx: Sender<usize>,
    rx: Receiver<usize>,
    timeout: Duration,
}

pub struct PooledItem {
    pub idx: usize,
    pub rbobj: VALUE,
}

impl FixedSizeObjectPool {
    pub fn new(pool: Vec<VALUE>, timeout_in_ms: u64) -> Self {
        let (tx, rx) = crossbeam_channel::unbounded();
        for idx in 0..pool.len() {
            tx.send(idx).unwrap();
        }

        Self {
            pool,
            tx,
            rx,
            timeout: Duration::from_millis(timeout_in_ms),
        }
    }

    pub fn mark<F>(&self, f: F)
    where
        F: Fn(VALUE),
    {
        for item in self.pool.iter() {
            f(*item);
        }
    }

    pub fn checkout(&self) -> Option<PooledItem> {
        let idx = self.rx.recv_timeout(self.timeout).ok()?;
        Some(PooledItem {
            idx,
            rbobj: self.pool[idx],
        })
    }

    pub fn checkin(&self, idx: usize) {
        self.tx.send(idx).unwrap();
    }
}
