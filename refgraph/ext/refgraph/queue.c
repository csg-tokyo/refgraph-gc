/**
 * Methods for testing.
 */

#include "refgraph.h"
#include "queue.h"

static queue_t queue;

static VALUE do_init(VALUE kclass)
{
    init_queue(&queue);
    return Qnil;
}

static VALUE do_free(VALUE kclass)
{
    destruct_queue(&queue);
    return Qnil;
}

static VALUE do_print(VALUE kclass)
{
    VALUE s = rb_sprintf("head %lu, tail %lu, length %lu",
                         queue.head, queue.tail, queue.values_length);
    VALUE res = rb_ary_new();
    rb_ary_push(res, s);
    size_t h = queue.head;
    size_t t = queue.tail;
    for (size_t i = 0; i < queue.values_length; i++)
        if (h < t) {
            if (h <= i && i < t)
                rb_ary_push(res, queue.values[i]);
        }
        else if (t < h) {
            if (i < t || h <= i)
                rb_ary_push(res, queue.values[i]);
            else if (i == t)
                rb_ary_push(res, Qnil);
        }

    return res;
}

static VALUE do_dequeue(VALUE kclass)
{
    return dequeue(&queue);
}

static VALUE do_enqueue(VALUE kclass, VALUE v)
{
    enqueue(&queue, v);
    return v;
}

static VALUE check_empty(VALUE kclass)
{
    if (empty_queue(&queue))
        return Qtrue;
    else
        return Qfalse;
}

void Init_refgraph_queue(VALUE mRefgraph)
{
    VALUE mQueue = rb_define_module_under(mRefgraph, "Queue");
    rb_define_singleton_method(mQueue, "init", do_init, 0);
    rb_define_singleton_method(mQueue, "free", do_free, 0);
    rb_define_singleton_method(mQueue, "to_s", do_print, 0);
    rb_define_singleton_method(mQueue, "dequeue", do_dequeue, 0);
    rb_define_singleton_method(mQueue, "enqueue", do_enqueue, 1);
    rb_define_singleton_method(mQueue, "empty", check_empty, 0);
}
