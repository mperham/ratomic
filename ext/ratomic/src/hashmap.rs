use dashmap::mapref::entry::Entry;
use rb_sys::{rb_eql, rb_hash, VALUE};

#[derive(Debug)]
struct RubyHashEql(VALUE);

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

pub struct MapStore {
    map: dashmap::DashMap<RubyHashEql, VALUE>,
}

impl MapStore {
    pub fn new() -> Self {
        Self {
            map: dashmap::DashMap::new(),
        }
    }

    pub fn get(&self, key: VALUE) -> Option<VALUE> {
        self.map.get(&RubyHashEql(key)).map(|v| *v)
    }

    pub fn contains_key(&self, key: VALUE) -> bool {
        self.map.contains_key(&RubyHashEql(key))
    }

    pub fn set(&self, key: VALUE, value: VALUE) {
        self.map.insert(RubyHashEql(key), value);
    }

    pub fn delete(&self, key: VALUE) -> Option<VALUE> {
        self.map.remove(&RubyHashEql(key)).map(|(_, value)| value)
    }

    pub fn clear(&self) {
        self.map.clear()
    }

    pub fn size(&self) -> usize {
        self.map.len()
    }

    pub fn fetch_and_modify<F>(&self, key: VALUE, f: F)
    where
        F: FnOnce(VALUE) -> VALUE,
    {
        self.map.alter(&RubyHashEql(key), |_, value| f(value));
    }

    pub fn compute<F, E>(&self, key: VALUE, missing: VALUE, f: F) -> Result<VALUE, E>
    where
        F: FnOnce(VALUE) -> Result<VALUE, E>,
    {
        match self.map.entry(RubyHashEql(key)) {
            Entry::Occupied(mut entry) => {
                let new_value = f(*entry.get())?;
                entry.insert(new_value);
                Ok(new_value)
            }
            Entry::Vacant(entry) => {
                let new_value = f(missing)?;
                entry.insert(new_value);
                Ok(new_value)
            }
        }
    }

    pub fn fetch_or_store<F, E>(&self, key: VALUE, f: F) -> Result<VALUE, E>
    where
        F: FnOnce() -> Result<VALUE, E>,
    {
        match self.map.entry(RubyHashEql(key)) {
            Entry::Occupied(entry) => Ok(*entry.get()),
            Entry::Vacant(entry) => {
                let value = f()?;
                entry.insert(value);
                Ok(value)
            }
        }
    }

    pub fn upsert<F, E>(&self, key: VALUE, initial: VALUE, f: F) -> Result<VALUE, E>
    where
        F: FnOnce(VALUE) -> Result<VALUE, E>,
    {
        match self.map.entry(RubyHashEql(key)) {
            Entry::Occupied(mut entry) => {
                let new_value = f(*entry.get())?;
                entry.insert(new_value);
                Ok(new_value)
            }
            Entry::Vacant(entry) => {
                entry.insert(initial);
                Ok(initial)
            }
        }
    }

    pub fn mark<F>(&self, f: F)
    where
        F: Fn(VALUE),
    {
        for pair in self.map.iter() {
            f(pair.key().0);
            f(*pair.value());
        }
    }
}

impl Default for MapStore {
    fn default() -> Self {
        Self::new()
    }
}
