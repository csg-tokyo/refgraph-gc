#include "refgraph.h"
#include "queue.h"
#include "basic.h"
#include "simple.h"
#include "bloomfilter64.h"
#include "batchpropagation.h"

VALUE rb_mRefgraph;

void
Init_refgraph(void)
{
  rb_mRefgraph = rb_define_module("Refgraph");
  Init_refgraph_basic(rb_mRefgraph);
  Init_refgraph_queue(rb_mRefgraph);
  Init_refgraph_simple(rb_mRefgraph);
  Init_refgraph_bloomfilter64(rb_mRefgraph);
  Init_refgraph_batchpropagation(rb_mRefgraph);
}
