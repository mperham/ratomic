#include "rust-atomics.h"
#include <ruby.h>

const rb_data_type_t atomic_counter_data = {
    .function = {.dfree = RUBY_DEFAULT_FREE},
    .flags = RUBY_TYPED_FROZEN_SHAREABLE};

VALUE rb_atomic_counter_alloc(VALUE klass) {
  atomic_counter_t *counter;
  TypedData_Make_Struct0(obj, klass, atomic_counter_t, ATOMIC_COUNTER_SIZE,
                         &atomic_counter_data, counter);
  atomic_counter_init(counter, 0);
  VALUE rb_cRactor = rb_const_get(rb_cObject, rb_intern("Ractor"));
  rb_funcall(rb_cRactor, rb_intern("make_shareable"), 1, obj);
  return obj;
}

VALUE rb_atomic_counter_increment(VALUE self) {
  atomic_counter_t *counter;
  TypedData_Get_Struct(self, atomic_counter_t, &atomic_counter_data, counter);
  atomic_counter_increment(counter);
  return Qnil;
}

VALUE rb_atomic_counter_read(VALUE self) {
  atomic_counter_t *counter;
  TypedData_Get_Struct(self, atomic_counter_t, &atomic_counter_data, counter);
  return LONG2FIX(atomic_counter_read(counter));
}

static void init_counter(VALUE rb_mCAtomics) {
  VALUE rb_cAtomicCounter =
      rb_define_class_under(rb_mCAtomics, "Counter", rb_cObject);
  rb_define_alloc_func(rb_cAtomicCounter, rb_atomic_counter_alloc);
  rb_define_method(rb_cAtomicCounter, "increment", rb_atomic_counter_increment,
                   0);
  rb_define_method(rb_cAtomicCounter, "read", rb_atomic_counter_read, 0);
}
