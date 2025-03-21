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
  TypedData_Get_Struct(self, mpmc_queue_t, &mpmc_queue_data, queue);
  mpmc_queue_init(queue, FIX2LONG(cap), Qnil);
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

static void init_mpmc_queue(VALUE rb_mRoot) {
  VALUE rb_cMpmcQueue =
      rb_define_class_under(rb_mRoot, "Queue", rb_cObject);
  rb_define_alloc_func(rb_cMpmcQueue, rb_mpmc_queue_alloc);

  rb_define_method(rb_cMpmcQueue, "initialize", rb_mpmc_queue_initialize, 1);
  rb_define_method(rb_cMpmcQueue, "push", rb_mpmc_queue_push, 1);
  rb_define_method(rb_cMpmcQueue, "pop", rb_mpmc_queue_pop, 0);
}
