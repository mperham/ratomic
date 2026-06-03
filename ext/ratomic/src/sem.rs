use std::sync::{Condvar, Mutex};

pub(crate) struct Semaphore {
    // Wrap the state in a heap-allocated Box so the raw pointer `self.inner` remains stable
    inner: *mut SemaphoreInner,
}

struct SemaphoreInner {
    lock: Mutex<u32>, // the current count of permits
    cvar: Condvar,
}

impl Semaphore {
    pub(crate) fn alloc() -> Self {
        Self {
            inner: std::ptr::null_mut(),
        }
    }

    pub(crate) fn init(&mut self, initial: u32) {
        let inner_struct = SemaphoreInner {
            lock: Mutex::new(initial),
            cvar: Condvar::new(),
        };
        // Box into raw pointer to manage memory life manually
        self.inner = Box::into_raw(Box::new(inner_struct));
    }

    pub(crate) fn post(&self) {
        if self.inner.is_null() {
            return;
        }
        
        let inner = unsafe { &*self.inner };
        let mut count = inner.lock.lock().unwrap();
        *count += 1;
        
        // notify to wake up a waiting thread
        inner.cvar.notify_one();
    }

    pub(crate) fn wait(&self) {
        if self.inner.is_null() {
            return;
        }

        let inner = unsafe { &*self.inner };
        let mut count = inner.lock.lock().unwrap();
        
        // Block the thread while there are no available permits
        while *count == 0 {
            count = inner.cvar.wait(count).unwrap();
        }
        
        *count -= 1;
    }
}

impl Drop for Semaphore {
    fn drop(&mut self) {
        if !self.inner.is_null() {
            unsafe {
                // Safely reclaim and drop the heap allocated struct
                let _ = Box::from_raw(self.inner);
            }
            self.inner = std::ptr::null_mut();
        }
    }
}

unsafe impl Send for Semaphore {}
unsafe impl Sync for Semaphore {}
