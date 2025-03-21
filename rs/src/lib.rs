#![expect(clippy::missing_safety_doc)]

mod counter;
pub use counter::*;

mod hashmap;
pub use hashmap::*;

mod fixed_size_object_pool;
pub use fixed_size_object_pool::*;

mod mpmc_queue;
pub use mpmc_queue::*;

mod gc_guard;
pub(crate) use gc_guard::GcGuard;

mod sem;

#[cfg(test)]
pub(crate) fn is_sync_and_send<T: Sync + Send>() -> bool {
    true
}
