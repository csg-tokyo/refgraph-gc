
/**
 * Bloom Filter: A fixed-size probabilistic data structure to represent a set of values
 */

#include "bloomfilter64.h"

const int bloomfilter64_N = 64;
const int bloomfilter64_K = 5;

inline static uint64_t xorshift_64_1(uint64_t x) {
    x ^= x << 29;
    x ^= x >> 27;
    x ^= x << 37;
    return x;
}

inline static uint64_t xorshift_64_2(uint64_t x) {
    x ^= x << 12;
    x ^= x >> 3;
    x ^= x << 13;
    return x;
}

uint64_t bloomfilter64_internal_state = 0xafb2041e061071dbllu;

void bloomfilter64_update_internal_state() {
    bloomfilter64_internal_state = xorshift_64_1(bloomfilter64_internal_state);
}

void bloomfilter64_clear(bloomfilter64_t* self) {
    *self = 0llu;
}

void bloomfilter64_insert(bloomfilter64_t* self, uint64_t x) {
    uint64_t ys[bloomfilter64_K];
    ys[0] = x ^ bloomfilter64_internal_state;
    for (int i = 1; i < bloomfilter64_K; i++) {
        ys[i] = xorshift_64_2(ys[i - 1]);
    }
    for (int i = 0; i < bloomfilter64_K; i++) {
        ys[i] %= bloomfilter64_N - i;
    }
    for (int i = bloomfilter64_K - 1; i >= 0; i--) {
        for (int j = i + 1; j < bloomfilter64_K; j++) {
            if (ys[j] >= ys[i]) {
                ys[j]++;
            }
        }
    }
    for (int i = 0; i < bloomfilter64_K; i++) {
        *self |= ((bloomfilter64_t)1llu) << ys[i];
    }
}

void bloomfilter64_make_sticky(bloomfilter64_t* self) {
    *self = ~(bloomfilter64_t)0;
}

bloomfilter64_t bloomfilter64_union(bloomfilter64_t x, bloomfilter64_t y) {
    return x | y;
}

int bloomfilter64_includes(bloomfilter64_t x, bloomfilter64_t y) {
    return (x | y) == x;
}

int bloomfilter64_is_empty(bloomfilter64_t x) {
    return !x;
}

int bloomfilter64_is_sticky(bloomfilter64_t x) {
    return !~x;
}

int bloomfilter64_is_not_sticky(bloomfilter64_t x) {
    return !bloomfilter64_is_sticky(x);
}

int bloomfilter64_popcount(bloomfilter64_t x) {
    bloomfilter64_t x1 = x;
    bloomfilter64_t x2 = (x1 & 0x5555555555555555llu) + ((x1 & 0xaaaaaaaaaaaaaaaallu) >> 1);
    bloomfilter64_t x3 = (x2 & 0x3333333333333333llu) + ((x2 & 0xccccccccccccccccllu) >> 2);
    bloomfilter64_t x4 = (x3 & 0x0f0f0f0f0f0f0f0fllu) + ((x3 & 0xf0f0f0f0f0f0f0f0llu) >> 4);
    bloomfilter64_t x5 = (x4 & 0x00ff00ff00ff00ffllu) + ((x4 & 0xff00ff00ff00ff00llu) >> 8);
    bloomfilter64_t x6 = (x5 & 0x0000ffff0000ffffllu) + ((x5 & 0xffff0000ffff0000llu) >> 16);
    bloomfilter64_t x7 = (x6 & 0x00000000ffffffffllu) + ((x6 & 0xffffffff00000000llu) >> 32);
    return (int)x7;
}

static VALUE rb_cBloomFilter64;

VALUE rb_bloomfilter64_new() {
    bloomfilter64_t* data = calloc(1, sizeof(bloomfilter64_t));
    return Data_Wrap_Struct(rb_cBloomFilter64, 0, free, data);
}

VALUE rb_bloomfilter64_new_with_value(bloomfilter64_t init) {
    bloomfilter64_t* data = malloc(sizeof(bloomfilter64_t));
    *data = init;
    return Data_Wrap_Struct(rb_cBloomFilter64, 0, 0, data);
}

VALUE rb_bloomfilter64_insert(VALUE self, VALUE x) {
    bloomfilter64_t* self_data;
    Data_Get_Struct(self, bloomfilter64_t, self_data);
    bloomfilter64_insert(self_data, (uint64_t)NUM2ULL(x));
    return self;
}

VALUE rb_bloomfilter64_union(VALUE self, VALUE x) {
    bloomfilter64_t* self_data;
    bloomfilter64_t* x_data;
    Data_Get_Struct(self, bloomfilter64_t, self_data);
    Data_Get_Struct(self, bloomfilter64_t, x_data);
    return rb_bloomfilter64_new_with_value(bloomfilter64_union(*self_data, *x_data));
}

VALUE rb_bloomfilter64_includes(VALUE self, VALUE another) {
    bloomfilter64_t* self_data;
    bloomfilter64_t* another_data;
    Data_Get_Struct(self, bloomfilter64_t, self_data);
    Data_Get_Struct(self, bloomfilter64_t, another_data);
    return bloomfilter64_includes(*self_data, *another_data) ? Qtrue : Qfalse;
}

VALUE rb_bloomfilter64_popcount(VALUE self) {
    bloomfilter64_t* self_data;
    Data_Get_Struct(self, bloomfilter64_t, self_data);
    return INT2FIX(bloomfilter64_popcount(*self_data));
}

VALUE rb_bloomfilter64_equals(VALUE self, VALUE another) {
    bloomfilter64_t* self_data;
    bloomfilter64_t* another_data;
    Data_Get_Struct(self, bloomfilter64_t, self_data);
    Data_Get_Struct(self, bloomfilter64_t, another_data);
    return (*self_data == *another_data) ? Qtrue : Qfalse;
}

VALUE rb_bloomfilter64_not_equals(VALUE self, VALUE another) {
    bloomfilter64_t* self_data;
    bloomfilter64_t* another_data;
    Data_Get_Struct(self, bloomfilter64_t, self_data);
    Data_Get_Struct(self, bloomfilter64_t, another_data);
    return (*self_data != *another_data) ? Qtrue : Qfalse;
}

VALUE rb_bloomfilter64_is_empty(VALUE self) {
    bloomfilter64_t* self_data;
    Data_Get_Struct(self, bloomfilter64_t, self_data);
    return bloomfilter64_is_empty(*self_data) ? Qtrue : Qfalse;
}

VALUE rb_bloomfilter64_is_sticky(VALUE self) {
    bloomfilter64_t* self_data;
    Data_Get_Struct(self, bloomfilter64_t, self_data);
    return bloomfilter64_is_sticky(*self_data) ? Qtrue : Qfalse;
}

VALUE rb_bloomfilter64_to_string(VALUE self) {
    bloomfilter64_t* self_data;
    Data_Get_Struct(self, bloomfilter64_t, self_data);
    VALUE result = rb_str_new2("Refgraph::BloomFilter64(");
    for (bloomfilter64_t i = ((bloomfilter64_t) 1) << 63; i; i >>= 1) {
        if (*self_data & i) {
            rb_str_cat(result, "1", 1);
        } else {
            rb_str_cat(result, "0", 1);
        }
    }
    rb_str_cat(result, ")", 1);
    return result;
}

void Init_refgraph_bloomfilter64(VALUE mRefgraph) {
    rb_cBloomFilter64 = rb_define_class_under(mRefgraph, "BloomFilter64", rb_cObject);
    rb_global_variable(&rb_cBloomFilter64);
    rb_define_const(rb_cBloomFilter64, "N", INT2FIX(bloomfilter64_N));
    rb_define_const(rb_cBloomFilter64, "K", INT2FIX(bloomfilter64_K));
    rb_define_singleton_method(rb_cBloomFilter64, "new", rb_bloomfilter64_new, 0);
    rb_define_method(rb_cBloomFilter64, "<<", rb_bloomfilter64_insert, 1);
    rb_define_method(rb_cBloomFilter64, "|", rb_bloomfilter64_union, 1);
    rb_define_method(rb_cBloomFilter64, "include?", rb_bloomfilter64_includes, 1);
    rb_define_method(rb_cBloomFilter64, "==", rb_bloomfilter64_equals, 1);
    rb_define_method(rb_cBloomFilter64, "!=", rb_bloomfilter64_not_equals, 1);
    rb_define_method(rb_cBloomFilter64, "popcount", rb_bloomfilter64_popcount, 0);
    rb_define_method(rb_cBloomFilter64, "empty?", rb_bloomfilter64_is_empty, 0);
    rb_define_method(rb_cBloomFilter64, "sticky?", rb_bloomfilter64_is_sticky, 0);
    rb_define_method(rb_cBloomFilter64, "to_s", rb_bloomfilter64_to_string, 0);
}
