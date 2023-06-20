# frozen_string_literal: true

require "test_helper"

module Refgraph
  def self.define_js_utils
    Jscall.exec <<CODE
    // returns the indexes of remote references in JavaScript
    function check_references() {
      [exported, imported] = Ruby.get_exported_imported()
      const imported_live = []
      const imported_zombi = []
      const exported_live = []
      const exported_detached = []
      imported.objects.forEach((wref, index) => {
        if (wref !== null && wref !== undefined)
          if (wref.deref() == undefined)
            imported_zombi.push(index)
          else
            imported_live.push(index)
      })
      exported.objects.forEach((ref, index) => {
        if (typeof ref !== 'number')
          if (ref === null)
            exported_detached.push(index)
          else
            exported_live.push(index)
      })
      return [imported_live, imported_zombi,
              exported_live, exported_detached, 'import/import-zombi/export/export-detached']
    }
    // returns the numbrer of remote references in JavaScript
    function count_references() {
      [exported, imported] = Ruby.get_exported_imported()
      let imported_live = 0
      let imported_zombi = 0
      let exported_live = 0
      let exported_detached = 0
      imported.objects.forEach((wref) => {
        if (wref !== null && wref !== undefined)
          if (wref.deref() == undefined)
            imported_zombi++
          else
            imported_live++
      })
      exported.objects.forEach((ref) => {
        if (typeof ref !== 'number')
          if (ref === null)
            exported_detached++
          else
            exported_live++
      })
      return [imported_live, imported_zombi,
              exported_live, exported_detached,
              'import/import-zombi/export/export-detached']
      }
CODE
  end

  # Returns export/import tables
  #
  def self.check_references
    exported, imported = Jscall.__getpipe__.get_exported_imported

    eobjs = exported.objects.__getobj__
    exported_indexes = []
    eobjs.each_index do |i|
      exported_indexes.push(i) unless eobjs[i].is_a?(Numeric)
    end

    iobjs = imported.objects.__getobj__
    imported_indexs = []
    iobjs.each_index do |i|
      imported_indexs.push(i) if iobjs[i]&.weakref_alive?
    end

    return [imported_indexs, exported_indexes, 'import/export']
  end

  # Returns the numbrer of remote references (including Zombi) in Ruby
  def self.count_references
    exported, imported = Jscall.__getpipe__.get_exported_imported

    eobjs = exported.objects.__getobj__
    exported_indexes = 0
    eobjs.each do |e|
      exported_indexes += 1 unless e.is_a?(Numeric)
    end

    iobjs = imported.objects.__getobj__
    imported_indexs = 0
    imported_zombi = 0
    iobjs.each do |e|
      unless e.nil?
        if e.weakref_alive?
          imported_indexs += 1
        else
          imported_zombi += 1
        end
      end
    end

    return [imported_indexs, imported_zombi, exported_indexes, 'import/import-zombi/export']
  end
end

class TestRefgraph < Minitest::Test
  # include Refgraph

  def setup
    Refgraph.force_immediate_gc false
    Refgraph.config
    def_jsclass
  end

  def teardown
    Jscall.close
  end

  def test_that_it_has_a_version_number
    refute_nil ::Refgraph::VERSION
  end

  def test_with_javascript_gc
    Refgraph.force_immediate_gc
    Refgraph.config
  end

  def test_empty_refgraph
    Refgraph.gc
  end

  class Simple
    attr_accessor :js, :js2
    def initialize(jsobj=nil)
        @js = jsobj
    end
  end

  def def_jsclass
    Jscall.exec <<CODE
      class JSimple {
        constructor(robj) { this.ruby = robj }
        get_rb() { return this.ruby }
      }

      function make_jsobj(robj) {
        return new JSimple(robj)
      }
CODE
    Refgraph.define_js_utils
  end

  def test_w_shape
    s = Simple.new
    4.times do
      s = Simple.new(Jscall.make_jsobj(s))
    end
    Refgraph.gc
    jsrefs = Jscall.check_references
    assert_equal Simple, s.js.get_rb.class
    assert_equal 4, jsrefs[0].size
    assert_equal 1, jsrefs[2].size
    assert_equal 3, jsrefs[3].size

    rbrefs = Refgraph.check_references
    assert_equal 4, rbrefs[0].size
    assert_equal 4, rbrefs[1].size
  end

  def test_w_shape_chain_looped
    Refgraph.force_immediate_gc
    Jscall.close
    def_jsclass
    3.times do
      s = s0 = Simple.new
      4.times do
        s = Simple.new(Jscall.make_jsobj(s))
      end
      s0.js = s.js
      s = nil       # s0 = nil
      Refgraph.gc
      Jscall.exec 'global.gc()'
    end
    GC.start
    # p Refgraph.check_references
    # p Jscall.check_references
  end

  # def test_w_shape_long_chain_looped
  #   # Refgraph.force_immediate_gc     # this rather obstructs GC
  #   Jscall.close
  #   def_jsclass
  #   3.times do
  #     s = s0 = Simple.new
  #     100.times do
  #       s = Simple.new(Jscall.make_jsobj(s))
  #     end
  #     s0.js = s.js
  #     s = s0 = nil
  #     Refgraph.gc
  #     Jscall.exec 'global.gc()'
  #     GC.start
  #   end
  #   Jscall.scavenge_references
  #   GC.start  # makes import references be zombies
  #   Jscall.exec 'global.gc()'
  #   Jscall.scavenge_references
  #   rbrefs = Refgraph.count_references
  #   assert_equal 0, rbrefs[0]
  #   assert_equal 0, rbrefs[1]
  # end

  def test_w_loop_without_refgraph
    Refgraph.force_immediate_gc
    Jscall.close
    def_jsclass

    3.times do
      s = Simple.new
      10.times do
        s = Simple.new(Jscall.make_jsobj(s))
      end
      s = nil
      GC.start
      Jscall.exec 'global.gc()'
      Jscall.scavenge_references
    end

    9.times do |i|
      GC.start
      Jscall.exec 'global.gc()'
      Jscall.scavenge_references

      # without Refgraph.gc, only one reference is reclaimed for every GC.
      rbrefs = Refgraph.count_references
      assert_equal 25 - i, rbrefs[0]
      assert_equal 27 - i, rbrefs[2]
    end
  end
end
