/**
 * Basic checker of reachability.
 */

#include "refgraph.h"
#include "queue.h"
#include "basic.h"

typedef uintptr_t bits_t;

struct tracer {
    queue_t queue;
    VALUE ignored;
};

static void* allocate_bitmap(void* old_value, size_t size)
{
    return calloc(size, sizeof(bits_t));
}

static void allocate_markbits()
{
    /* update the extension pointer in every heap page
       by calling allocate_bitmap().
     */
    refgraph_for_each_heap_page_extension(allocate_bitmap);
}

static void* free_bitmap(void* old_value, size_t size)
{
    free(old_value);
    return NULL;
}

static void deallocate_markbits()
{
    /* visit the extension pointer in every heap page
       to deallocate the data for the extension.
     */
    refgraph_for_each_heap_page_extension(free_bitmap);
}

static void trace_object(VALUE obj, void* tracer) {
    struct tracer* t = (struct tracer*)tracer;
    if (rb_objspace_markable_object_p(obj)) {
        bits_t* bitmap = (bits_t*)refgraph_heap_page_extension(obj);
        uintptr_t b = refgraph_marked_in_bitmap(bitmap, obj);
        if (!b) {
            refgraph_mark_in_bitmap(bitmap, obj);
            if (CLASS_OF(obj) != t->ignored) {
                queue_t* q = (queue_t*)&t->queue;
                enqueue(q, obj);
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

/*
  def reachable(from, to, T): (Object, WeakRef|T) -> boolish

  Tests whether the "to" object is reachable from the "from" object.
  "to" must be a weak reference to the "to" object.

  "T" should be a class object representing Refgraph::HiddenRef or
  a similar class providing __getobj__().
 */
static VALUE refgraph_reachable(VALUE klass, VALUE from, VALUE to,
                                VALUE hidden_ref_class)
{
    if (!rb_objspace_markable_object_p(to))
        return Qfalse;

    struct tracer tracer;

    allocate_markbits();
    init_queue(&tracer.queue);
    tracer.ignored = hidden_ref_class;

    trace_object(from, &tracer);
    while (!empty_queue(&tracer.queue)) {
        VALUE v = dequeue(&tracer.queue);
        trace_children(&tracer, v);
    }

    /* Don't retrieve the tested object until tracing finishes. */

    /* Assume that the following calls to  rb_* never cause memory
       allocation or object moves.  Those may destory bitmaps for marking.
     */
    VALUE obj = rb_funcall(to, rb_intern("__getobj__"), 0);
    if (!rb_objspace_markable_object_p(obj))
        return Qfalse;

    bits_t* bitmap = (bits_t*)refgraph_heap_page_extension(obj);
    uintptr_t b = refgraph_marked_in_bitmap(bitmap, obj);

    destruct_queue(&tracer.queue);
    deallocate_markbits();
    return b ? Qtrue : Qfalse;
}

static void trace_root_object(const char *category, VALUE obj, void* tracer)
{
    trace_object(obj, tracer);
}

/*
  def reachable_from_root(obj, T): (WeakRef|T) -> boolish

  Tests the reachability from the root to the given object.
  obj is a weak reference to the object tested.

  "T" should be a class object representing Refgraph::HiddenRef or
  a similar class providing __getobj__().
*/
static VALUE refgraph_reachable_from_root(VALUE klass, VALUE weakref_to_obj,
                                          VALUE hidden_ref_class)
{
    struct tracer tracer;

    allocate_markbits();
    init_queue(&tracer.queue);
    tracer.ignored = hidden_ref_class;

    /* Assume that the following calls to  rb_* never cause memory
       allocation or object moves.  Those may destory bitmaps for marking.
     */

    rb_objspace_reachable_objects_from_root(trace_root_object, (void*)&tracer);
    while (!empty_queue(&tracer.queue)) {
        VALUE v = dequeue(&tracer.queue);
        trace_children(&tracer, v);
    }

    /* The root set for rb_objspace_reachable_objects_from_root() includes
     * the local variables in this C function.  So don't retrieve the tested
     * object until rb_objspace_reachable_objects_from_root() returns.
     */
    VALUE obj = rb_funcall(weakref_to_obj, rb_intern("__getobj__"), 0);
    if (!rb_objspace_markable_object_p(obj))
        return Qfalse;

    bits_t* bitmap = (bits_t*)refgraph_heap_page_extension(obj);
    uintptr_t b = refgraph_marked_in_bitmap(bitmap, obj);

    destruct_queue(&tracer.queue);
    deallocate_markbits();
    return b ? Qtrue : Qfalse;
}

void Init_refgraph_basic(VALUE mRefgraph)
{
    rb_define_singleton_method(mRefgraph, "reachable",
                               refgraph_reachable, 3);
    rb_define_singleton_method(mRefgraph, "reachable_from_root",
                               refgraph_reachable_from_root, 2);
}
