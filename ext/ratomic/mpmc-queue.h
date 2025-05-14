#include "rust-atomics.h"
#include <ruby.h>
#include <ruby/thread.h>

void rb_mpmc_queue_mark(void *);
void rb_mpmc_queue_free(void *);

const rb_data_type_t mpmc_queue_data = {
    .function = {.dfree = rb_mpmc_queue_free, .dmark = rb_mpmc_queue_mark},
    .flags = RUBY_TYPED_FROZEN_SHAREABLE};

void rb_mpmc_queue_free(void *ptr) {
  mpmc_queue_t *queue = ptr;
  mpmc_queue_drop(queue);
}

void rb_mpmc_queue_mark(void *ptr) {
  mpmc_queue_t *queue = ptr;
  mpmc_queue_mark(queue, rb_gc_mark);
}

VALUE rb_mpmc_queue_alloc(VALUE klass) {
  mpmc_queue_t *queue;
  TypedData_Make_Struct0(obj, klass, mpmc_queue_t, MPMC_QUEUE_OBJECT_SIZE,
                         &mpmc_queue_data, queue);
  mpmc_queue_alloc(queue);
  VALUE rb_cRactor = rb_const_get(rb_cObject, rb_intern("Ractor"));
  rb_funcall(rb_cRactor, rb_intern("make_shareable"), 1, obj);
  return obj;
}

VALUE rb_mpmc_queue_initialize(VALUE self, VALUE cap) {
  mpmc_queue_t *queue;

  Check_Type(cap, T_FIXNUM);
  long capacity = FIX2LONG(cap);

  if (capacity < 1)
    rb_raise(rb_eArgError, "capacity must be a positive Integer greater than 0");
  if (capacity > (1L << 20))
    rb_raise(rb_eArgError, "capacity too large (max: %lu)", 1L << 20);

  TypedData_Get_Struct(self, mpmc_queue_t, &mpmc_queue_data, queue);
  mpmc_queue_init(queue, capacity, Qnil);
  return Qnil;
}

typedef struct {
  mpmc_queue_t *queue;
  VALUE value;
} push_payload_t;

VALUE rb_mpmc_queue_push(VALUE self, VALUE value) {
  mpmc_queue_t *queue;
  TypedData_Get_Struct(self, mpmc_queue_t, &mpmc_queue_data, queue);
  push_payload_t push_payload = {.queue = queue, .value = value};
  rb_thread_call_without_gvl(mpmc_queue_push, &push_payload, NULL, NULL);
  return Qtrue;
}

VALUE rb_mpmc_queue_pop(VALUE self) {
  mpmc_queue_t *queue;
  TypedData_Get_Struct(self, mpmc_queue_t, &mpmc_queue_data, queue);
  void *ptr = rb_thread_call_without_gvl(mpmc_queue_pop, queue, NULL, NULL);
  VALUE item = (VALUE)ptr;
  return item;
}

VALUE rb_mpmc_queue_peek(VALUE self) {
  mpmc_queue_t *queue;
  TypedData_Get_Struct(self, mpmc_queue_t, &mpmc_queue_data, queue);
  void *ptr = rb_thread_call_without_gvl(mpmc_queue_peek, queue, NULL, NULL);

  if (ptr == NULL) {
    return Qnil;
  }
  VALUE item = (VALUE)ptr;
  return item;
}

VALUE rb_mpmc_queue_is_empty(VALUE self) {
  mpmc_queue_t *queue;
  TypedData_Get_Struct(self, mpmc_queue_t, &mpmc_queue_data, queue);
  void *ptr = rb_thread_call_without_gvl(mpmc_queue_is_empty, queue, NULL, NULL);
  VALUE is_empty = (VALUE)ptr;
  return is_empty ? Qtrue : Qfalse;
}

VALUE rb_mpmc_queue_size(VALUE self) {
  mpmc_queue_t *queue;
  TypedData_Get_Struct(self, mpmc_queue_t, &mpmc_queue_data, queue);
  void *ptr = rb_thread_call_without_gvl(mpmc_queue_size, queue, NULL, NULL);
  size_t size = (size_t)ptr;
  return LONG2NUM(size);
}

static void init_mpmc_queue(VALUE rb_mRoot) {
  VALUE rb_cMpmcQueue =
      rb_define_class_under(rb_mRoot, "Queue", rb_cObject);
  rb_define_alloc_func(rb_cMpmcQueue, rb_mpmc_queue_alloc);

  rb_define_method(rb_cMpmcQueue, "initialize", rb_mpmc_queue_initialize, 1);
  rb_define_method(rb_cMpmcQueue, "push", rb_mpmc_queue_push, 1);
  rb_define_method(rb_cMpmcQueue, "pop", rb_mpmc_queue_pop, 0);
  rb_define_method(rb_cMpmcQueue, "peek", rb_mpmc_queue_peek, 0);
  rb_define_method(rb_cMpmcQueue, "empty?", rb_mpmc_queue_is_empty, 0); 
  rb_define_method(rb_cMpmcQueue, "length", rb_mpmc_queue_size, 0);
  rb_define_alias(rb_cMpmcQueue, "size", "length");
}
