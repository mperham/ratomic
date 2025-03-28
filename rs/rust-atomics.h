#ifndef RUST_ATOMICS_H
#define RUST_ATOMICS_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define ATOMIC_COUNTER_SIZE 8

#define CONCURRENT_HASH_MAP_SIZE 40

#define FIXED_SIZE_OBJECT_POOL_SIZE 72

#define MPMC_QUEUE_OBJECT_SIZE 80

typedef struct atomic_counter_t atomic_counter_t;

typedef struct concurrent_hash_map_t concurrent_hash_map_t;

typedef struct fixed_size_object_pool_t fixed_size_object_pool_t;

typedef struct mpmc_queue_t mpmc_queue_t;

typedef struct {
  uintptr_t idx;
  unsigned long rbobj;
} PooledItem;

void atomic_counter_init(atomic_counter_t *counter, uint64_t n);

void atomic_counter_increment(const atomic_counter_t *counter, uint64_t amt);

void atomic_counter_decrement(const atomic_counter_t *counter, uint64_t amt);

uint64_t atomic_counter_read(const atomic_counter_t *counter);

extern unsigned long rb_hash(unsigned long obj);

extern int rb_eql(unsigned long lhs, unsigned long rhs);

void concurrent_hash_map_init(concurrent_hash_map_t *hashmap);

void concurrent_hash_map_drop(concurrent_hash_map_t *hashmap);

void concurrent_hash_map_clear(const concurrent_hash_map_t *hashmap);

size_t concurrent_hash_map_size(const concurrent_hash_map_t *hashmap);

unsigned long concurrent_hash_map_get(const concurrent_hash_map_t *hashmap,
                                      unsigned long key,
                                      unsigned long fallback);

void concurrent_hash_map_set(const concurrent_hash_map_t *hashmap,
                             unsigned long key,
                             unsigned long value);

void concurrent_hash_map_mark(const concurrent_hash_map_t *hashmap, void (*f)(unsigned long));

void concurrent_hash_map_fetch_and_modify(const concurrent_hash_map_t *hashmap,
                                          unsigned long key,
                                          unsigned long (*f)(unsigned long));

void fixed_size_object_pool_alloc(fixed_size_object_pool_t *pool);

void fixed_size_object_pool_init(fixed_size_object_pool_t *pool,
                                 uintptr_t max_size,
                                 uint64_t timeout_in_ms,
                                 unsigned long (*rb_make_obj)(unsigned long));

void fixed_size_object_pool_drop(fixed_size_object_pool_t *pool);

void fixed_size_object_pool_mark(const fixed_size_object_pool_t *pool, void (*f)(unsigned long));

PooledItem fixed_size_object_pool_checkout(fixed_size_object_pool_t *pool);

void fixed_size_object_pool_checkin(fixed_size_object_pool_t *pool, uintptr_t idx);

void mpmc_queue_alloc(mpmc_queue_t *q);

void mpmc_queue_init(mpmc_queue_t *q, uintptr_t capacity, unsigned long default_);

void mpmc_queue_drop(mpmc_queue_t *q);

void mpmc_queue_mark(const mpmc_queue_t *q, void (*f)(unsigned long));

void *mpmc_queue_push(void *push_paylod);

void *mpmc_queue_pop(void *q);

#endif  /* RUST_ATOMICS_H */
