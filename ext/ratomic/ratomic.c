#include "counter.h"
#include "fixed-size-object-pool.h"
#include "hashmap.h"
#include "mpmc-queue.h"
#include <ruby.h>

RUBY_FUNC_EXPORTED void Init_ratomic(void) {
  rb_ext_ractor_safe(true);

  VALUE rb_mRoot = rb_define_module("Ratomic");

  init_counter(rb_mRoot);
  init_hashmap(rb_mRoot);
  init_fixed_size_object_pool(rb_mRoot);
  init_mpmc_queue(rb_mRoot);
}
