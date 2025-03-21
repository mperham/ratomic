#include "rust-atomics.h"
#include <ruby.h>

void rb_concurrent_hash_map_mark(void *);
void rb_concurrent_hash_map_free(void *);

const rb_data_type_t concurrent_hash_map_data = {
    .function = {.dfree = rb_concurrent_hash_map_free,
                 .dmark = rb_concurrent_hash_map_mark},
    .flags = RUBY_TYPED_FROZEN_SHAREABLE};

void rb_concurrent_hash_map_free(void *ptr) {
  concurrent_hash_map_t *hashmap = ptr;
  concurrent_hash_map_drop(hashmap);
}

void rb_concurrent_hash_map_mark(void *ptr) {
  concurrent_hash_map_t *hashmap = ptr;
  concurrent_hash_map_mark(hashmap, rb_gc_mark);
}

VALUE rb_concurrent_hash_map_alloc(VALUE klass) {
  concurrent_hash_map_t *hashmap;
  TypedData_Make_Struct0(obj, klass, concurrent_hash_map_t,
                         CONCURRENT_HASH_MAP_SIZE, &concurrent_hash_map_data,
                         hashmap);
  concurrent_hash_map_init(hashmap);
  VALUE rb_cRactor = rb_const_get(rb_cObject, rb_intern("Ractor"));
  rb_funcall(rb_cRactor, rb_intern("make_shareable"), 1, obj);
  return obj;
}

VALUE rb_concurrent_hash_map_get(VALUE self, VALUE key) {
  concurrent_hash_map_t *hashmap;
  TypedData_Get_Struct(self, concurrent_hash_map_t, &concurrent_hash_map_data,
                       hashmap);
  return concurrent_hash_map_get(hashmap, key, Qnil);
}

VALUE rb_concurrent_hash_map_set(VALUE self, VALUE key, VALUE value) {
  concurrent_hash_map_t *hashmap;
  TypedData_Get_Struct(self, concurrent_hash_map_t, &concurrent_hash_map_data,
                       hashmap);
  concurrent_hash_map_set(hashmap, key, value);
  return Qnil;
}

VALUE rb_concurrent_hash_map_clear(VALUE self) {
  concurrent_hash_map_t *hashmap;
  TypedData_Get_Struct(self, concurrent_hash_map_t, &concurrent_hash_map_data,
                       hashmap);
  concurrent_hash_map_clear(hashmap);
  return Qnil;
}

VALUE rb_concurrent_hash_map_fetch_and_modify(VALUE self, VALUE key) {
  rb_need_block();
  concurrent_hash_map_t *hashmap;
  TypedData_Get_Struct(self, concurrent_hash_map_t, &concurrent_hash_map_data,
                       hashmap);
  concurrent_hash_map_fetch_and_modify(hashmap, key, rb_yield);
  return Qnil;
}

static void init_hashmap(VALUE rb_mRoot) {
  VALUE rb_cConcurrentHashMap =
      rb_define_class_under(rb_mRoot, "ConcurrentHashMap", rb_cObject);
  rb_define_alloc_func(rb_cConcurrentHashMap, rb_concurrent_hash_map_alloc);
  rb_define_method(rb_cConcurrentHashMap, "get", rb_concurrent_hash_map_get, 1);
  rb_define_method(rb_cConcurrentHashMap, "set", rb_concurrent_hash_map_set, 2);
  rb_define_method(rb_cConcurrentHashMap, "clear", rb_concurrent_hash_map_clear,
                   0);
  rb_define_method(rb_cConcurrentHashMap, "fetch_and_modify",
                   rb_concurrent_hash_map_fetch_and_modify, 1);
}
