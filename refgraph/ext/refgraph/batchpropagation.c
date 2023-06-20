
/**
 * Bloomfilter-based checker of reachability.
 * probabilistic mark batch propagation
 */

#include "refgraph.h"
#include "queue.h"
#include "bloomfilter64.h"

typedef bloomfilter64_t* bloomfilter64map_t;

bloomfilter64_t bloomfilter64map_get_at(bloomfilter64map_t table, VALUE obj) {
    return table[refgraph_num_in_page(obj)];
}

bloomfilter64_t bloomfilter64map_set_at(bloomfilter64map_t table, VALUE obj, bloomfilter64_t value) {
    return table[refgraph_num_in_page(obj)] = value;
}

struct pmbp64_tracer {
    queue_t         queue;
    bloomfilter64_t propagating;
    VALUE           ignored;
};

static void* allocate_bloomfilter64map(void* old_value, size_t size)
{
    // CHECKIT: `size' denotes the bitmap size.  How can I get the number of objects that a heap page can contain?
    bloomfilter64map_t table = calloc(size * 64, sizeof(bloomfilter64_t));
    return table;
}

/* update the extension pointer in every heap page
   by calling allocate_bitmap().
*/
static void allocate_mark_tables() {
    refgraph_for_each_heap_page_extension(allocate_bloomfilter64map);
}


static void* free_bloomfilter64map(void* old_value, size_t size) {
    free(old_value);
    return NULL;
}

/* visit the extension pointer in every heap page
   to deallocate the data for the extension.
*/
static void deallocate_mark_tables() {
    refgraph_for_each_heap_page_extension(free_bloomfilter64map);
}

static void* clear_bloomfilter64map(void* old_value, size_t size) {
    memset(old_value, 0, size * sizeof(bloomfilter64_t));
    return old_value;
}

static void clear_mark_tables() {
    refgraph_for_each_heap_page_extension(clear_bloomfilter64map);
}

inline static int reachable_from_root(void* table, VALUE obj) {
    return bloomfilter64_is_sticky(bloomfilter64map_get_at((bloomfilter64map_t)table, obj));
}

inline static int unreachable_from_root(void* table, VALUE obj) {
    return bloomfilter64_is_not_sticky(bloomfilter64map_get_at((bloomfilter64map_t)table, obj));
}

static void trace_object(VALUE obj, void* tracer) {
    struct pmbp64_tracer* t = tracer;
    if (rb_objspace_markable_object_p(obj)) {
        bloomfilter64map_t table       = (bloomfilter64map_t)refgraph_heap_page_extension(obj);
        bloomfilter64_t    old_value   = bloomfilter64map_get_at(table, obj);
        bloomfilter64_t    propagating = t->propagating;
        bloomfilter64_t    new_value   = bloomfilter64_union(old_value, propagating);
        if (bloomfilter64_includes(old_value, new_value)) { return; }
        bloomfilter64map_set_at(table, obj, new_value);
        if (CLASS_OF(obj) != t->ignored) {
            queue_t* q = (queue_t*)&t->queue;
            enqueue(q, obj);
        }
    }
}

static void trace_children(struct pmbp64_tracer* t, VALUE obj) {
    /* rb_objspace_reachable_objects_from() does not visit
       the objects that WeakRef or WeakMap objects refer to.
    */
    bloomfilter64map_t table = (bloomfilter64map_t)refgraph_heap_page_extension(obj);
    t->propagating = bloomfilter64map_get_at(table, obj);
    rb_objspace_reachable_objects_from(obj, trace_object, (void*)t);
}

static void trace_root_object(const char *category, VALUE obj, void* tracer) {
    struct pmbp64_tracer* t = tracer;
    bloomfilter64_make_sticky(&t->propagating);
    trace_object(obj, tracer);
}

static void trace_inbound_object(VALUE obj, struct pmbp64_tracer* t) {
    bloomfilter64_clear(&t->propagating);
    bloomfilter64_insert(&t->propagating, (uint64_t)obj);
    trace_object(obj, (void*)t);
}

/** Appends a positive integer to the given Ruby string.
 */
static void append_num_to_str(VALUE str, long num, int with_comma)
{
    char buf[32];
    int top = sizeof(buf) - 1;
    buf[top] = '\0';
    if (num <= 0)
        buf[--top] = '0';
    else
        while (num > 0) {
            int d = num % 10;
            buf[--top] = '0' + d;
            num /= 10;
        }

    if (with_comma)
        buf[--top] = ',';

    rb_str_cat(str, &buf[top], sizeof(buf) - 1 - top);
}

/**
 * deref_weakrefs(array, len, getobj):
 * (Array[WeakRef], long, Symbol) -> Array[Object]
 *
 * Retrieve the objects that the weak references contained in the array
 * refer to.  Dereferencing a weak reference is slow.
 */
static VALUE* deref_weakrefs(VALUE array, long len, VALUE getobj)
{
    VALUE alive = rb_intern("weakref_alive?");
    VALUE* result = malloc(sizeof(VALUE) * len);
    for (long i = 0; i < len; i++) {
        result[i] = Qnil;
        VALUE wref = rb_ary_entry(array, i);
        if (!FIXNUM_P(wref) && wref != Qnil
            && RTEST(rb_funcall(wref, alive, 0))) {
            VALUE out = rb_funcall(wref, getobj, 0);
            if (out != Qnil && rb_objspace_markable_object_p(out))
                result[i] = out;
        }
    }
    return result;
}

static VALUE make_json_for_root(VALUE* out_ary, long len)
{
    VALUE result = rb_str_new2("{ \"root\": [");
    int empty = TRUE;
    for (long i = 0; i < len; i++) {
        VALUE out = out_ary[i];
        if (out != Qnil) {
            bloomfilter64map_t table = refgraph_heap_page_extension(out);
            if (reachable_from_root(table, out)) {
                append_num_to_str(result, i, !empty);
                if (empty)
                    empty = FALSE;
            }
        }
    }

    rb_str_cat(result, "]", 1);
    return result;
}

static void append_to_json(VALUE result, long inbound_index, VALUE inbound,
                           VALUE* out_ary, long out_len, VALUE getobj)
{
    int empty = TRUE;
    for (long j = 0; j < out_len; j++) {
        VALUE out = out_ary[j];
        if (out != Qnil) {
            bloomfilter64map_t table = refgraph_heap_page_extension(out);
            bloomfilter64_t mark = bloomfilter64map_get_at(table, out);
            if (bloomfilter64_is_sticky(mark)) { continue; }
            bloomfilter64_t init;
            bloomfilter64_clear(&init);
            bloomfilter64_insert(&init, (uint64_t)inbound);
            if (bloomfilter64_includes(mark, init)) {
                if (empty) {
                    empty = FALSE;
                    rb_str_cat(result, ",\n\"", 3);
                    append_num_to_str(result, inbound_index, FALSE);
                    rb_str_cat(result, "\":[", 3);
                    append_num_to_str(result, j, FALSE);
                }
                else
                    append_num_to_str(result, j, TRUE);
            }
        }
    }
    if (!empty)
        rb_str_cat(result, "]", 1);
}

/**
  def simply_make_refgraph(inbounds, outbounds, T):
    (T[Array[Object]], T[Array[WeakRef]], Class)
    -> String

  Make a mapping from inbound remote references to outbound remote
  references.  It also enumerates the outbound remote referneces
  reachable from the root set.

  T must be a class object for ::Refgraph::HiddenRef or a similar
  class providing the __getobj__ method.

  An element of both inbounds and outbounds may contain nil or a fixnum.
  The returned value is a JSON string.  It is { "root": [] }
  when outbounds is an empty array.  When it is
    { "root": [2, 5], "2": [3, 7] },
  then:
    inbounds          outbounds
       2   refers to   3 and 7
     root  refers to   2 and 5
 */
static VALUE
make_refgraph_by_batch_propagation(VALUE kclass, VALUE inbounds,
                                   VALUE outbounds, VALUE hidden_ref_class)
{
    struct pmbp64_tracer tracer;

    allocate_mark_tables();
    init_queue(&tracer.queue);
    tracer.ignored = hidden_ref_class;
    rb_gc_disable();

    /* mark objects reachable from the root set */
    rb_objspace_reachable_objects_from_root(trace_root_object,
                                            (void*)&tracer);
    while (!empty_queue(&tracer.queue)) {
        VALUE v = dequeue(&tracer.queue);
        trace_children(&tracer, v);
    }

    /* The root set for rb_objspace_reachable_objects_from_root() includes
     * the local variables in this C function.  So don't retrieve the tested
     * object until rb_objspace_reachable_objects_from_root() returns.
     */

    /* mark objects reachable from the inbounds */
    VALUE getobj = rb_intern("__getobj__");
    VALUE in_ary = rb_funcall(inbounds, getobj, 0);
    Check_Type(in_ary, T_ARRAY);
    VALUE out_ary = rb_funcall(outbounds, getobj, 0);
    Check_Type(out_ary, T_ARRAY);
    long out_len = RARRAY_LENINT(out_ary);
    VALUE* out_objs = deref_weakrefs(out_ary, out_len, getobj);

    long len = RARRAY_LENINT(in_ary);
    for (long i = 0; i < len; i++) {
        VALUE from = rb_ary_entry(in_ary, i);
        if (!FIXNUM_P(from) && from != Qnil) {
            trace_inbound_object(from, &tracer);
        }
    }

    while (!empty_queue(&tracer.queue)) {
        VALUE v = dequeue(&tracer.queue);
        trace_children(&tracer, v);
    }

    VALUE result = make_json_for_root(out_objs, out_len);

    for (long i = 0; i < len; i++) {
        VALUE from = rb_ary_entry(in_ary, i);
        if (!FIXNUM_P(from) && from != Qnil) {
            append_to_json(result, i, from, out_objs, out_len, getobj);
        }
    }

    free(out_objs);
    rb_gc_enable();
    rb_str_cat(result, " }", 2);
    destruct_queue(&tracer.queue);
    deallocate_mark_tables();
    return result;
}

void Init_refgraph_batchpropagation(VALUE mRefgraph)
{
    rb_define_singleton_method(mRefgraph, "make_by_batch_propagation",
                               make_refgraph_by_batch_propagation, 3);
}
