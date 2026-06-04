mod counter;
mod fixed_size_object_pool;
mod gc_guard;
mod hashmap;
mod mpmc_queue;
mod sem;

use counter::AtomicCounter;
use fixed_size_object_pool::FixedSizeObjectPool;
use hashmap::MapStore;
use magnus::{
    data_type_builder, method, IntoValue,
    prelude::*,
    typed_data::{DataType, DataTypeFunctions},
    value::Lazy,
    Error, RClass, Ruby, TryConvert, TypedData, Value,
};
use mpmc_queue::MpmcQueue;
use rb_sys::{rb_ext_ractor_safe, rb_thread_call_without_gvl, ruby_special_consts, VALUE};
use parking_lot::Mutex;
use std::{ffi::c_void, mem::transmute};

fn value_to_raw(value: Value) -> VALUE {
    unsafe { transmute::<Value, VALUE>(value) }
}

unsafe fn value_from_raw(raw: VALUE) -> Value {
    transmute::<VALUE, Value>(raw)
}

fn qnil_raw() -> VALUE {
    ruby_special_consts::RUBY_Qnil as VALUE
}

fn make_shareable(ruby: &Ruby, value: Value) -> Result<Value, Error> {
    value.freeze();
    let ractor: RClass = ruby.class_object().const_get("Ractor")?;
    ractor.funcall("make_shareable", (value,))
}

struct Counter(AtomicCounter);

impl Counter {
    fn new(ruby: &Ruby, class: RClass) -> Result<Value, Error> {
        let value = ruby.wrap_as(Self(AtomicCounter::new(0)), class).as_value();
        make_shareable(ruby, value)
    }

    fn increment(&self, amt: u64) {
        self.0.inc(amt);
    }

    fn decrement(&self, amt: u64) {
        self.0.dec(amt);
    }

    fn read(&self) -> u64 {
        self.0.read()
    }
}

impl DataTypeFunctions for Counter {}

unsafe impl TypedData for Counter {
    fn class(ruby: &Ruby) -> RClass {
        static CLASS: Lazy<RClass> = Lazy::new(|ruby| {
            let class = ruby.define_module("Ratomic")
                .unwrap()
                .define_class("Counter", ruby.class_object())
                .unwrap();
            class.undef_default_alloc_func();
            class
        });
        ruby.get_inner(&CLASS)
    }

    fn data_type() -> &'static DataType {
        static DATA_TYPE: DataType =
            data_type_builder!(Counter, "ratomic/counter").frozen_shareable().build();
        &DATA_TYPE
    }
}

struct HashMap(MapStore);

impl HashMap {
    fn new(ruby: &Ruby, class: RClass) -> Result<Value, Error> {
        let value = ruby.wrap_as(Self(MapStore::new()), class).as_value();
        make_shareable(ruby, value)
    }

    fn get(ruby: &Ruby, rb_self: &Self, key: Value) -> Value {
        let raw = rb_self.0.get(value_to_raw(key)).unwrap_or_else(qnil_raw);
        unsafe { value_from_raw(raw) }.into_value_with(ruby)
    }

    fn contains_key(&self, key: Value) -> bool {
        self.0.contains_key(value_to_raw(key))
    }

    fn set(&self, key: Value, value: Value) {
        self.0.set(value_to_raw(key), value_to_raw(value));
    }

    fn delete(ruby: &Ruby, rb_self: &Self, key: Value) -> Value {
        let raw = rb_self.0.delete(value_to_raw(key)).unwrap_or_else(qnil_raw);
        unsafe { value_from_raw(raw) }.into_value_with(ruby)
    }

    fn clear(&self) {
        self.0.clear();
    }

    fn size(&self) -> usize {
        self.0.size()
    }

    fn fetch_and_modify(ruby: &Ruby, rb_self: &Self, key: Value) -> Result<(), Error> {
        if !ruby.block_given() {
            return Err(Error::new(
                ruby.exception_local_jump_error(),
                "no block given",
            ));
        }

        let proc = ruby.block_proc()?;
        let mut error = None;
        rb_self.0.fetch_and_modify(value_to_raw(key), |value| {
            match proc.call::<_, Value>((unsafe { value_from_raw(value) },)) {
                Ok(result) => value_to_raw(result),
                Err(err) => {
                    error = Some(err);
                    value
                }
            }
        });

        if let Some(err) = error {
            Err(err)
        } else {
            Ok(())
        }
    }
}

impl DataTypeFunctions for HashMap {
    fn mark(&self, marker: &magnus::gc::Marker) {
        self.0.mark(|value| marker.mark(unsafe { value_from_raw(value) }));
    }
}

unsafe impl TypedData for HashMap {
    fn class(ruby: &Ruby) -> RClass {
        static CLASS: Lazy<RClass> = Lazy::new(|ruby| {
            let class = ruby.define_module("Ratomic")
                .unwrap()
                .define_class("Map", ruby.class_object())
                .unwrap();
            class.undef_default_alloc_func();
            class
        });
        ruby.get_inner(&CLASS)
    }

    fn data_type() -> &'static DataType {
        static DATA_TYPE: DataType = data_type_builder!(HashMap, "ratomic/hashmap")
            .mark()
            .frozen_shareable()
            .build();
        &DATA_TYPE
    }
}

struct Queue(MpmcQueue);

struct PushPayload<'a> {
    queue: &'a MpmcQueue,
    item: VALUE,
}

unsafe extern "C" fn push_without_gvl(payload: *mut c_void) -> *mut c_void {
    let payload = &*(payload as *const PushPayload<'_>);
    payload.queue.push(payload.item);
    std::ptr::null_mut()
}

unsafe extern "C" fn pop_without_gvl(queue: *mut c_void) -> *mut c_void {
    let queue = &*(queue as *const MpmcQueue);
    queue.pop() as *mut c_void
}

impl Queue {
    fn new(ruby: &Ruby, class: RClass, capacity: Value) -> Result<Value, Error> {
        if !capacity.is_kind_of(ruby.class_integer()) {
            return Err(Error::new(
                ruby.exception_type_error(),
                "no implicit conversion into Integer",
            ));
        }
        let capacity = i64::try_convert(capacity)?;
        if capacity < 1 || capacity > (1 << 20) {
            return Err(Error::new(
                ruby.exception_arg_error(),
                "queue capacity must be between 1 and 1048576",
            ));
        }
        let capacity = capacity as usize;

        let value = ruby
            .wrap_as(Self(MpmcQueue::new(capacity, qnil_raw())), class)
            .as_value();
        make_shareable(ruby, value)
    }

    fn push(&self, item: Value) {
        let mut payload = PushPayload {
            queue: &self.0,
            item: value_to_raw(item),
        };
        unsafe {
            rb_thread_call_without_gvl(
                Some(push_without_gvl),
                &mut payload as *mut PushPayload<'_> as *mut c_void,
                None,
                std::ptr::null_mut(),
            );
        }
    }

    fn pop(&self) -> Value {
        let raw = unsafe {
            rb_thread_call_without_gvl(
                Some(pop_without_gvl),
                &self.0 as *const MpmcQueue as *mut c_void,
                None,
                std::ptr::null_mut(),
            ) as VALUE
        };
        unsafe { value_from_raw(raw) }
    }

    fn peek(&self) -> Option<Value> {
        self.0.peek().map(|raw| unsafe { value_from_raw(raw) })
    }

    fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    fn size(&self) -> usize {
        self.0.size()
    }
}

impl DataTypeFunctions for Queue {
    fn mark(&self, marker: &magnus::gc::Marker) {
        self.0.mark(|value| marker.mark(unsafe { value_from_raw(value) }));
    }
}

unsafe impl TypedData for Queue {
    fn class(ruby: &Ruby) -> RClass {
        static CLASS: Lazy<RClass> = Lazy::new(|ruby| {
            let class = ruby.define_module("Ratomic")
                .unwrap()
                .define_class("Queue", ruby.class_object())
                .unwrap();
            class.undef_default_alloc_func();
            class
        });
        ruby.get_inner(&CLASS)
    }

    fn data_type() -> &'static DataType {
        static DATA_TYPE: DataType = data_type_builder!(Queue, "ratomic/queue")
            .mark()
            .frozen_shareable()
            .build();
        &DATA_TYPE
    }
}

struct Pool(Mutex<Option<FixedSizeObjectPool>>);

impl Pool {
    fn new(ruby: &Ruby, class: RClass, args: &[Value]) -> Result<Value, Error> {
        if args.len() > 2 {
            return Err(Error::new(
                ruby.exception_arg_error(),
                format!("wrong number of arguments (given {}, expected 0..2)", args.len()),
            ));
        }
        let size = args
            .first()
            .copied()
            .map(usize::try_convert)
            .transpose()?
            .unwrap_or(5);
        let timeout_ms = args
            .get(1)
            .copied()
            .map(f64::try_convert)
            .transpose()?
            .map(|timeout| (timeout * 1000.0) as u64)
            .unwrap_or(1000);

        if size == 0 {
            return Err(Error::new(ruby.exception_arg_error(), "pool size must be positive"));
        }
        if !ruby.block_given() {
            return Err(Error::new(
                ruby.exception_local_jump_error(),
                "no block given",
            ));
        }

        let value = ruby.wrap_as(Self(Mutex::new(None)), class).as_value();
        let value = make_shareable(ruby, value)?;

        let mut pool = Vec::with_capacity(size);
        for _ in 0..size {
            let value: Value = ruby.yield_value(())?;
            pool.push(value_to_raw(value));
        }

        let rb_self: &Self = TryConvert::try_convert(value)?;
        *rb_self.0.lock() = Some(FixedSizeObjectPool::new(pool, timeout_ms));
        Ok(value)
    }

    fn checkout(ruby: &Ruby, rb_self: &Self) -> Option<magnus::RArray> {
        rb_self
            .0
            .lock()
            .as_ref()
            .and_then(FixedSizeObjectPool::checkout)
            .map(|item| {
                ruby.ary_new_from_values(&[
                    unsafe { value_from_raw(item.rbobj) },
                    item.idx.into_value_with(ruby),
                ])
            })
    }

    fn checkin(&self, idx: usize) {
        if let Some(pool) = self.0.lock().as_ref() {
            pool.checkin(idx);
        }
    }
}

impl DataTypeFunctions for Pool {
    fn mark(&self, marker: &magnus::gc::Marker) {
        if let Some(pool) = self.0.lock().as_ref() {
            pool.mark(|value| marker.mark(unsafe { value_from_raw(value) }));
        }
    }
}

unsafe impl TypedData for Pool {
    fn class(ruby: &Ruby) -> RClass {
        static CLASS: Lazy<RClass> = Lazy::new(|ruby| {
            let class = ruby.define_module("Ratomic")
                .unwrap()
                .define_class("FixedSizeObjectPool", ruby.class_object())
                .unwrap();
            class.undef_default_alloc_func();
            class
        });
        ruby.get_inner(&CLASS)
    }

    fn data_type() -> &'static DataType {
        static DATA_TYPE: DataType = data_type_builder!(Pool, "ratomic/pool")
            .mark()
            .frozen_shareable()
            .build();
        &DATA_TYPE
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    unsafe { rb_ext_ractor_safe(true) };

    let root = ruby.define_module("Ratomic")?;

    let counter = root.define_class("Counter", ruby.class_object())?;
    counter.undef_default_alloc_func();
    counter.define_singleton_method("new", method!(Counter::new, 0))?;
    counter.define_method("increment", method!(Counter::increment, 1))?;
    counter.define_method("decrement", method!(Counter::decrement, 1))?;
    counter.define_method("read", method!(Counter::read, 0))?;

    let hashmap = root.define_class("Map", ruby.class_object())?;
    hashmap.undef_default_alloc_func();
    hashmap.define_singleton_method("new", method!(HashMap::new, 0))?;
    hashmap.define_method("get", method!(HashMap::get, 1))?;
    hashmap.define_method("key?", method!(HashMap::contains_key, 1))?;
    hashmap.define_method("set", method!(HashMap::set, 2))?;
    hashmap.define_method("delete", method!(HashMap::delete, 1))?;
    hashmap.define_method("clear", method!(HashMap::clear, 0))?;
    hashmap.define_method("size", method!(HashMap::size, 0))?;
    hashmap.define_method("fetch_and_modify", method!(HashMap::fetch_and_modify, 1))?;

    let queue = root.define_class("Queue", ruby.class_object())?;
    queue.undef_default_alloc_func();
    queue.define_singleton_method("new", method!(Queue::new, 1))?;
    queue.define_method("push", method!(Queue::push, 1))?;
    queue.define_method("pop", method!(Queue::pop, 0))?;
    queue.define_method("peek", method!(Queue::peek, 0))?;
    queue.define_method("empty?", method!(Queue::is_empty, 0))?;
    queue.define_method("length", method!(Queue::size, 0))?;
    queue.define_method("size", method!(Queue::size, 0))?;

    let pool = root.define_class("FixedSizeObjectPool", ruby.class_object())?;
    pool.undef_default_alloc_func();
    pool.define_singleton_method("new", method!(Pool::new, -1))?;
    pool.define_method("checkout", method!(Pool::checkout, 0))?;
    pool.define_method("checkin", method!(Pool::checkin, 1))?;

    Ok(())
}
