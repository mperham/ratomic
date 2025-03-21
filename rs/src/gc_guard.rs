use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

pub(crate) struct GcGuard {
    locked: AtomicBool,
    count: AtomicUsize,
}

impl GcGuard {
    pub(crate) fn alloc() -> Self {
        GcGuard {
            locked: AtomicBool::new(false),
            count: AtomicUsize::new(0),
        }
    }

    pub(crate) fn init(&mut self) {
        self.locked.store(false, Ordering::Relaxed);
        self.count.store(0, Ordering::Relaxed);
    }

    fn add_consumer(&self) {
        self.count.fetch_add(1, Ordering::SeqCst);
    }
    fn remove_consumer(&self) {
        self.count.fetch_sub(1, Ordering::SeqCst);
    }
    fn wait_for_no_consumers(&self) {
        loop {
            let count = self.count.load(Ordering::SeqCst);
            if count == 0 {
                #[cfg(feature = "simulation")]
                eprintln!("[producer] 0 running consumers");
                break;
            } else {
                // spin until they are done
                #[cfg(feature = "simulation")]
                eprintln!("[producer] waiting for {count} consumers to finish");
            }
        }
    }

    fn lock(&self) {
        self.locked.store(true, Ordering::SeqCst);
    }
    fn unlock(&self) {
        self.locked.store(false, Ordering::SeqCst)
    }
    fn is_locked(&self) -> bool {
        self.locked.load(Ordering::SeqCst)
    }
    fn wait_until_unlocked(&self) {
        while self.is_locked() {
            // spin
        }
    }

    pub(crate) fn acquire_as_gc<F, T>(&self, f: F) -> T
    where
        F: FnOnce() -> T,
    {
        #[cfg(feature = "simulation")]
        eprintln!("Locking consumers");
        self.lock();
        #[cfg(feature = "simulation")]
        eprintln!("Waiting for consumers to finish");
        self.wait_for_no_consumers();
        #[cfg(feature = "simulation")]
        eprintln!("All consumers have finished");
        let out = f();
        #[cfg(feature = "simulation")]
        eprintln!("Unlocking consumers");
        self.unlock();
        out
    }

    pub(crate) fn acquire_as_consumer<F, T>(&self, f: F) -> T
    where
        F: FnOnce() -> T,
    {
        if self.is_locked() {
            self.wait_until_unlocked();
        }
        self.add_consumer();
        let out = f();
        self.remove_consumer();
        out
    }
}
