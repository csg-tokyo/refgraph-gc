
#ifndef BLOOMFILTER64_H
#define BLOOMFILTER64_H

#include "refgraph.h"

typedef uint64_t bloomfilter64_t;

extern const int bloomfilter64_N;
extern const int bloomfilter64_K;

extern uint64_t bloomfilter64_internal_state;

void bloomfilter64_update_internal_state();
void bloomfilter64_clear(bloomfilter64_t* self);
void bloomfilter64_insert(bloomfilter64_t* self, uint64_t x);
void bloomfilter64_make_sticky(bloomfilter64_t* self);
bloomfilter64_t bloomfilter64_union(bloomfilter64_t x, bloomfilter64_t y);
int bloomfilter64_includes(bloomfilter64_t x, bloomfilter64_t y);
int bloomfilter64_is_empty(bloomfilter64_t x);
int bloomfilter64_is_sticky(bloomfilter64_t x);
int bloomfilter64_is_not_sticky(bloomfilter64_t x);

int bloomfilter64_popcount(bloomfilter64_t x);
VALUE rb_bloomfilter64_new();
VALUE rb_bloomfilter64_new_with_value(bloomfilter64_t init);
VALUE rb_bloomfilter64_insert(VALUE self, VALUE x);
VALUE rb_bloomfilter64_union(VALUE self, VALUE x);
VALUE rb_bloomfilter64_includes(VALUE self, VALUE another);
VALUE rb_bloomfilter64_popcount(VALUE self);
VALUE rb_bloomfilter64_equals(VALUE self, VALUE another);
VALUE rb_bloomfilter64_not_equals(VALUE self, VALUE another);
VALUE rb_bloomfilter64_is_empty(VALUE self);
VALUE rb_bloomfilter64_is_sticky(VALUE self);
VALUE rb_bloomfilter64_to_string(VALUE self);

void Init_refgraph_bloomfilter64(VALUE mRefgraph);

#endif  // BLOOMFILTER64_H
