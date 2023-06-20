#ifndef RBIMPL_GC_H                                  /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_GC_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries.  They could be written in C++98.
 * @brief      Registering values to the GC.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Inform the garbage collector that `valptr` points to a live Ruby object that
 * should not be moved. Note that extensions should use this API on global
 * constants instead of assuming constants defined in Ruby are always alive.
 * Ruby code can remove global constants.
 */
void rb_gc_register_address(VALUE *valptr);

/**
 * An alias for `rb_gc_register_address()`.
 */
void rb_global_variable(VALUE *);

/**
 * Inform the garbage collector that a pointer previously passed to
 * `rb_gc_register_address()` no longer points to a live Ruby object.
 */
void rb_gc_unregister_address(VALUE *valptr);

/**
 * Inform the garbage collector that `object` is a live Ruby object that should
 * not be moved.
 *
 * See also: rb_gc_register_address()
 */
void rb_gc_register_mark_object(VALUE object);

/**
 * functions moved from ruby-refgraph/gc.h
 */
void rb_objspace_reachable_objects_from(VALUE obj, void (func)(VALUE, void *), void *data);
void rb_objspace_reachable_objects_from_root(void (func)(const char *category, VALUE, void *), void *data);
int rb_objspace_markable_object_p(VALUE obj);

/**
 * functions added for refgraph
 */
void* refgraph_heap_page_extension(VALUE p);
void refgraph_for_each_heap_page_extension(void* callback(void*, size_t));
size_t refgraph_num_in_page(VALUE p);
uintptr_t refgraph_marked_in_bitmap(uintptr_t* bits, VALUE p);
void refgraph_mark_in_bitmap(uintptr_t* bits, VALUE p);
void refgraph_clear_in_bitmap(uintptr_t* bits, VALUE p);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_GC_H */
