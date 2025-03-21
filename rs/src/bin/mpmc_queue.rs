use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use libc::c_ulong;
use rust_atomics::MpmcQueue;

const RUN_GC_EVERY: Duration = Duration::from_millis(1000);
const PUSH_ITERATIONS: u64 = 5;
const THREADS_COUNT: u8 = 10;

fn main() {
    let q = make_q(16);

    let mut consumers = vec![];
    for _ in 0..THREADS_COUNT {
        consumers.push(start_consumer(Arc::clone(&q)));
    }

    let last_pushed_value = start_producer(Arc::clone(&q));

    let mut consumed = vec![];
    for consumer in consumers {
        let mut data = consumer.join().unwrap();
        consumed.append(&mut data);
    }

    consumed.sort_unstable();

    for (prev, next) in consumed.iter().zip(consumed.iter().skip(1)) {
        assert_eq!(*prev + 1, *next);
    }

    assert_eq!(*consumed.last().unwrap(), last_pushed_value);
}

fn make_q(buffer_size: usize) -> Arc<MpmcQueue> {
    Arc::new(MpmcQueue::new(buffer_size, 0))
}

const END: c_ulong = c_ulong::MAX;
fn push_end(q: &MpmcQueue) {
    q.push(END);
}
fn pop(q: &MpmcQueue) -> Option<c_ulong> {
    match q.pop() {
        END => None,
        other => Some(other),
    }
}

fn start_consumer(q: Arc<MpmcQueue>) -> std::thread::JoinHandle<Vec<c_ulong>> {
    std::thread::spawn(move || {
        let mut popped = vec![];

        while let Some(value) = pop(&q) {
            eprintln!("[{:?}] popped {value}", std::thread::current().id());
            popped.push(value);
        }

        popped
    })
}

fn start_producer(q: Arc<MpmcQueue>) -> c_ulong {
    let mut value = 1;

    for _ in 0..PUSH_ITERATIONS {
        // push for `RUN_GC_EVERY`
        let start = Instant::now();
        while Instant::now() - start < RUN_GC_EVERY {
            q.push(value);
            value += 1;
        }

        q.acquire_as_gc(|| {
            eprintln!("===== GC START ======");
            std::thread::sleep(Duration::from_millis(1000));
            eprintln!("===== GC END ========");
        });
    }

    for _ in 0..THREADS_COUNT {
        push_end(&q);
    }

    value - 1
}
