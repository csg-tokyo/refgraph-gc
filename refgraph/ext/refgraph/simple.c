/**
 * Simple checker of reachability.
 */

#include "refgraph.h"
#include "queue.h"
#include "simple.h"

#define MONITOR_GRAPH_SIZE      1

typedef uintptr_t bits_t;

struct tracer {
    queue_t queue;
    VALUE ignored;
    int mode;
    VALUE* reachable_outbounds;
    long num_of_reachable_outbounds;
};

#define ROOT_MODE       0    /* tracing from the root set */
#define REF_MODE        1    /* tracing from inbound references */
#define OUT_MODE        2    /* outbound references */

typedef struct {
    /* bitmaps. 0: from root, 1: from an inbound reference, 2: outbound references */
    void* maps[3];
    int dirty;
} gcmark;

#ifdef MONITOR_GRAPH_SIZE
static long root_set_count = 0;
static long refgraph_edges_count = 0;
#endif

static void* allocate_bitmap(void* old_value, size_t size)
{
    gcmark* gc = malloc(sizeof(gcmark));
    gc->maps[ROOT_MODE] = calloc(size, sizeof(bits_t));
    gc->maps[REF_MODE] = calloc(size, sizeof(bits_t));
    gc->maps[OUT_MODE] = calloc(size, sizeof(bits_t));
    gc->dirty = FALSE;
    return gc;
}

/* update the extension pointer in every heap page
   by calling allocate_bitmap().
*/
static void allocate_markbits()
{
    refgraph_for_each_heap_page_extension(allocate_bitmap);
}


static void* free_bitmap(void* old_value, size_t size)
{
    gcmark* old = (gcmark*)old_value;
    free(old->maps[OUT_MODE]);
    free(old->maps[REF_MODE]);
    free(old->maps[ROOT_MODE]);
    free(old_value);
    return NULL;
}

/* visit the extension pointer in every heap page
   to deallocate the data for the extension.
*/
static void deallocate_markbits()
{
    refgraph_for_each_heap_page_extension(free_bitmap);
}

static void* clear_ref_bitmap(void* old_value, size_t size)
{
    gcmark* old = (gcmark*)old_value;
    if (!old) {
        // the mark table is not initialized.
        // it may happen because the string construction may create a new heap page during simply_make.
        old = (gcmark*)allocate_bitmap(old_value, size);
        memset(old->maps[ROOT_MODE], -1, sizeof(bits_t) * size);
    }

    if (old->dirty) {
        memset(old->maps[REF_MODE], 0, sizeof(bits_t) * size);
        old->dirty = FALSE;
    }

    return old;
}

/* visit the extension pointer in every heap page
   to clear the bitmap for REF_MODE.
*/
static void clear_ref_markbits()
{
    refgraph_for_each_heap_page_extension(clear_ref_bitmap);
}

inline static int unreachable_from_root(gcmark* gc, VALUE obj)
{
    return !refgraph_marked_in_bitmap(gc->maps[ROOT_MODE], obj);
}

static void trace_object(VALUE obj, void* tracer) {
    struct tracer* t = (struct tracer*)tracer;
    if (rb_objspace_markable_object_p(obj)) {
        gcmark* gc = (gcmark*)refgraph_heap_page_extension(obj);
        if (t->mode == ROOT_MODE || unreachable_from_root(gc, obj)) {
            uintptr_t b = refgraph_marked_in_bitmap(gc->maps[t->mode], obj);
            if (!b) {
                refgraph_mark_in_bitmap(gc->maps[t->mode], obj);
                if (t->mode == REF_MODE) {
                    gc->dirty = TRUE;
                    uintptr_t is_out = refgraph_marked_in_bitmap(gc->maps[OUT_MODE], obj);
                    if (is_out)
                        t->reachable_outbounds[t->num_of_reachable_outbounds++] = obj;
                }
                if (CLASS_OF(obj) != t->ignored) {
                    queue_t* q = (queue_t*)&t->queue;
                    enqueue(q, obj);
                }
            }
        }
    }
}

static void trace_children(struct tracer* t, VALUE obj) {
    /* rb_objspace_reachable_objects_from() does not visit
       the objects that WeakRef or WeakMap objects refer to.
    */
    rb_objspace_reachable_objects_from(obj, trace_object, (void*)t);
}

static void trace_root_object(const char *category, VALUE obj, void* tracer)
{
    trace_object(obj, tracer);
}

static void mark_outbounds(VALUE* out_ary, long out_len)
{
    for (long j = 0; j < out_len; j++) {
        VALUE out = out_ary[j];
        if (out != Qnil) {
            gcmark* gc = (gcmark*)refgraph_heap_page_extension(out);
            refgraph_mark_in_bitmap(gc->maps[OUT_MODE], out);
        }
    }
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
 * dref_weakrefs(array, len, getobj):
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
    VALUE result = rb_eval_string("String.new('{\"root\":[', capacity: 1_000_000)");
    int empty = TRUE;
    for (long i = 0; i < len; i++) {
        VALUE out = out_ary[i];
        if (out != Qnil) {
            gcmark* gc = (gcmark*)refgraph_heap_page_extension(out);
            uintptr_t b
                = refgraph_marked_in_bitmap(gc->maps[ROOT_MODE], out);
            if (b) {
#ifdef MONITOR_GRAPH_SIZE
                root_set_count++;
#endif
                append_num_to_str(result, i, !empty);
                if (empty)
                    empty = FALSE;
            }
        }
    }

    rb_str_cat(result, "]", 1);
    return result;
}

static void append_to_json(VALUE result, long inbound, struct tracer* tracer)
{
    int empty = TRUE;
    for (long j = 0; j < tracer->num_of_reachable_outbounds; j++) {
        VALUE idobj = rb_iv_get(tracer->reachable_outbounds[j], "@id");
        long id = NUM2LONG(idobj);
        if (empty) {
            empty = FALSE;
            rb_str_cat(result, ",\"", 2);
            append_num_to_str(result, inbound, FALSE);
            rb_str_cat(result, "\":[", 3);
            append_num_to_str(result, id, FALSE);
        }
        else
            append_num_to_str(result, id, TRUE);

#ifdef MONITOR_GRAPH_SIZE
        refgraph_edges_count++;
#endif
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
simply_make_refgraph(VALUE kclass, VALUE inbounds, VALUE outbounds,
                     VALUE hidden_ref_class)
{
    struct tracer tracer;

    allocate_markbits();
    init_queue(&tracer.queue);
    tracer.ignored = hidden_ref_class;
    rb_gc_disable();

    /* mark objects reachable from the root set */
    tracer.mode = ROOT_MODE;
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
    tracer.mode = REF_MODE;
    VALUE getobj = rb_intern("__getobj__");
    VALUE in_ary = rb_funcall(inbounds, getobj, 0);
    Check_Type(in_ary, T_ARRAY);
    VALUE out_ary = rb_funcall(outbounds, getobj, 0);
    Check_Type(out_ary, T_ARRAY);
    long out_len = RARRAY_LENINT(out_ary);
    VALUE* out_objs = deref_weakrefs(out_ary, out_len, getobj);

#ifdef MONITOR_GRAPH_SIZE
    root_set_count = 0;
    refgraph_edges_count = 0;
#endif

    VALUE result = make_json_for_root(out_objs, out_len);

    mark_outbounds(out_objs, out_len);
    tracer.reachable_outbounds = (VALUE*)malloc(sizeof(VALUE*) * out_len);

    long len = RARRAY_LENINT(in_ary);
    for (long i = 0; i < len; i++) {
        VALUE from = rb_ary_entry(in_ary, i);
        if (!FIXNUM_P(from) && from != Qnil) {
            tracer.num_of_reachable_outbounds = 0;
            trace_object(from, &tracer);
            while (!empty_queue(&tracer.queue)) {
                VALUE v = dequeue(&tracer.queue);
                trace_children(&tracer, v);
            }

            /* Don't retrieve the outbound references
               until tracing finishes. */
            append_to_json(result, i, &tracer);
            clear_ref_markbits();
        }
    }

    free(tracer.reachable_outbounds);
    rb_str_cat(result, "}", 1);
    free(out_objs);
    rb_gc_enable();
    destruct_queue(&tracer.queue);
    deallocate_markbits();
    return result;
}

#ifdef MONITOR_GRAPH_SIZE
static VALUE get_root_set_count(VALUE kclass) {
    return LONG2FIX(root_set_count);
}

static VALUE get_refgraph_edges_count(VALUE kclass) {
    return LONG2FIX(refgraph_edges_count);
}
#endif

void Init_refgraph_simple(VALUE mRefgraph)
{
    rb_define_singleton_method(mRefgraph, "simply_make",
                               simply_make_refgraph, 3);
#ifdef MONITOR_GRAPH_SIZE
    rb_define_singleton_method(mRefgraph, "get_root_set_count",
                               get_root_set_count, 0);
    rb_define_singleton_method(mRefgraph, "get_refgraph_edges_count",
                               get_refgraph_edges_count, 0);
#endif
}
