use std::ffi::{c_int, c_ulong};

#[derive(Debug)]
struct RubyHashEql(c_ulong);

impl PartialEq for RubyHashEql {
    fn eq(&self, other: &Self) -> bool {
        unsafe { rb_eql(self.0, other.0) != 0 }
    }
}
impl Eq for RubyHashEql {}

impl std::hash::Hash for RubyHashEql {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        let ruby_hash = unsafe { rb_hash(self.0) };
        ruby_hash.hash(state);
    }
}

pub struct ConcurrentHashMap {
    map: dashmap::DashMap<RubyHashEql, c_ulong>,
}

unsafe extern "C" {
    fn rb_hash(obj: c_ulong) -> c_ulong;
    fn rb_eql(lhs: c_ulong, rhs: c_ulong) -> c_int;
}

impl ConcurrentHashMap {
    fn new() -> Self {
        Self {
            map: dashmap::DashMap::new(),
        }
    }

    fn get(&self, key: c_ulong) -> Option<c_ulong> {
        let key = RubyHashEql(key);
        self.map.get(&key).map(|v| *v)
    }

    fn set(&self, key: c_ulong, value: c_ulong) {
        let key = RubyHashEql(key);
        self.map.insert(key, value);
    }

    fn clear(&self) {
        self.map.clear()
    }

    fn fetch_and_modify(&self, key: c_ulong, f: extern "C" fn(c_ulong) -> c_ulong) {
        let key = RubyHashEql(key);
        self.map.alter(&key, |_, v| f(v));
    }

    fn mark(&self, f: extern "C" fn(c_ulong)) {
        for pair in self.map.iter() {
            f(pair.key().0);
            f(*pair.value());
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn concurrent_hash_map_init(hashmap: *mut ConcurrentHashMap) {
    unsafe { hashmap.write(ConcurrentHashMap::new()) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn concurrent_hash_map_drop(hashmap: *mut ConcurrentHashMap) {
    unsafe { std::ptr::drop_in_place(hashmap) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn concurrent_hash_map_clear(hashmap: *const ConcurrentHashMap) {
    let hashmap = unsafe { hashmap.as_ref().unwrap() };
    hashmap.clear();
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn concurrent_hash_map_get(
    hashmap: *const ConcurrentHashMap,
    key: c_ulong,
    fallback: c_ulong,
) -> c_ulong {
    let hashmap = unsafe { hashmap.as_ref().unwrap() };
    hashmap.get(key).unwrap_or(fallback)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn concurrent_hash_map_set(
    hashmap: *const ConcurrentHashMap,
    key: c_ulong,
    value: c_ulong,
) {
    let hashmap = unsafe { hashmap.as_ref().unwrap() };
    hashmap.set(key, value);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn concurrent_hash_map_mark(
    hashmap: *const ConcurrentHashMap,
    f: extern "C" fn(c_ulong),
) {
    let hashmap = unsafe { hashmap.as_ref().unwrap() };
    hashmap.mark(f);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn concurrent_hash_map_fetch_and_modify(
    hashmap: *const ConcurrentHashMap,
    key: c_ulong,
    f: extern "C" fn(c_ulong) -> c_ulong,
) {
    let hashmap = unsafe { hashmap.as_ref().unwrap() };
    hashmap.fetch_and_modify(key, f);
}

pub const CONCURRENT_HASH_MAP_SIZE: usize = 40;

#[test]
fn test_concurrent_hash_map() {
    assert_eq!(
        CONCURRENT_HASH_MAP_SIZE,
        std::mem::size_of::<ConcurrentHashMap>(),
        "size mismatch"
    );

    assert!(crate::is_sync_and_send::<ConcurrentHashMap>());
}
