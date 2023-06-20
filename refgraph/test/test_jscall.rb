# Test Jscall and refgraph.mjs without loading Refgraph.

# To run this program,
#   ruby -I ./lib -I ./test test/test_refgraph.rb
#
# or, for interactive debugging,
#
# irb -I ./lib -I ./test
# load 'test_refgraph.rb'

# frozen_string_literal: true

require "benchmark"
require "test_helper"
require "jscall"

module Jscall
    class Exported
        def objs
            @objects
        end
    end

    class Imported
        def objs
            @objects.__getobj__
        end

        def getobj(idx)
            wref = @objects.__getobj__[idx]
            if  wref&.weakref_alive?
                wref.__getobj__
            else
                nil
            end
        end
    end
end

class TestJscallRefgraph < Minitest::Test
    def self.configure
        Jscall.config(module_names: [['Refgraph', "#{__dir__}/../lib/refgraph/refgraph.mjs"]], options: '--expose-gc')
    end

    class Simple
        attr_accessor :js2
        def initialize(jsobj=nil)
            @js = jsobj
        end
        def get_js
            @js
        end
    end

    def self.def_jsclass
        Jscall.exec <<CODE
            class JSimple {
                constructor(robj) { this.ruby = robj }
                get_rb() { return this.ruby }
            }
            function make_jsobj(robj) {
                return new JSimple(robj)
            }
            function make_jsobj_and_discard(robj) {
                new JSimple(robj)
            }
            function do_gc(edges) {
                return Refgraph.gc_manager.run(edges, Ruby.get_exported_imported())
            }
            function check_references() {
                [exported, imported] = Ruby.get_exported_imported()
                const imported_live = []
                const imported_zombi = []
                const exported_live = []
                const exported_detached = []
                imported.objects.forEach((wref, index) => {
                    if (wref !== null && wref !== undefined)
                        if (wref.deref() === undefined)
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
                return ['import', imported_live, 'import zombi', imported_zombi,
                        'export', exported_live, 'export detached', exported_detached]
            }
CODE
    end

    def self.get_exported
        Jscall.__getpipe__.instance_variable_get :@exported
    end

    def self.get_imported
        Jscall.__getpipe__.instance_variable_get :@imported
    end

    def self.refgraph_gc(edges)
        Jscall.do_gc(edges)
    end

    def refgraph_gc(edges)
        self.class.refgraph_gc(edges)
    end

    def setup
        clazz = self.class
        clazz.configure
        clazz.def_jsclass
    end

    def teardown
        Jscall.close
    end

    def test_basic_refgraph
        s = Simple.new
        4.times do
            s = Simple.new(Jscall.make_jsobj(s))
        end
        # p Jscall.check_references()
        refgraph_gc '{ "root": [1], "0": [0] }'
        refs = Jscall.check_references()
        assert_equal [1], refs[5]           # export
        assert_equal [0, 2, 3], refs[7]     # export detached
    end

    def test_empty_refgraph
        Jscall.funcall("Refgraph.gc", '{ "root": [] }')
        refs = Jscall.check_references
        assert_equal [], refs[1]           # import
        assert_equal [], refs[5]           # export
        assert_equal [], refs[7]           # export detached
    end

    def test_no_js_objects_from_ruby_root
        s = Simple.new
        4.times do
            s = Simple.new(Jscall.make_jsobj(s))
        end
        refgraph_gc '{ "root": [], "0": [1] }'
        refs = Jscall.check_references()
        assert_equal [], refs[5]               # export
        assert_equal [0, 1, 2, 3], refs[7]     # export detached
    end

    def test_dead_import
        # [s] -> rb0 <- js0
        # rb1 <- js1 <- rb2 <- js2 <- rb3 <- js3 <- rb4 <- [s2]
        s = Simple.new
        Jscall.make_jsobj_and_discard(s)
        s2 = Simple.new
        3.times do
            s2 = Simple.new(Jscall.make_jsobj(s2))
        end
        Jscall.exec 'global.gc()'
        refgraph_gc '{ "root": [2], "2": [0], "3": [1] }'
        refs = Jscall.check_references()
        assert_equal [0], refs[3]              # import zombi
        assert_equal [2], refs[5]              # export
        assert_equal [0, 1], refs[7]           # export detached
    end

    def test_randomly_ordered_refgraph
        # [s] -> rb0 <- js0
        # rb1 <- js1 <- rb2 <- js2 <- rb3 <- js3 <- rb4 <- [s2]
        # rb1    <-     rb2    <-     rb3
        s = Simple.new
        Jscall.make_jsobj_and_discard(s)
        s2 = Simple.new
        3.times do
            s1 = s2
            s2 = Simple.new(Jscall.make_jsobj(s2))
            s2.js2 = s1
        end
        s2.js2 = nil
        Jscall.exec 'global.gc()'
        refgraph_gc '{ "3": [1, 0], "root": [2], "2": [0] }'
        refs = Jscall.check_references()
        assert_equal [0], refs[3]              # import zombi
        assert_equal [2], refs[5]              # export
        assert_equal [0, 1], refs[7]           # export detached
    end

    def test_run_gc_twice
        s = Simple.new
        3.times do
            s = Simple.new(Jscall.make_jsobj(s))
        end
        Jscall.exec 'global.gc()'
        refgraph_gc '{ "root": [2], "2": [1], "1": [0] }'
        refs = Jscall.check_references()
        assert_equal [], refs[3]               # import zombi
        assert_equal [2], refs[5]              # export
        assert_equal [0, 1], refs[7]           # export detached
        Jscall.exec 'global.gc()'
        refgraph_gc '{ "root": [2], "2": [1], "1": [0] }'
        assert_equal [], refs[3]               # import zombi
        assert_equal [2], refs[5]              # export
        assert_equal [0, 1], refs[7]           # export detached
    end

    def test_run_gc_twice2
        s = Simple.new
        3.times do
            s = Simple.new(Jscall.make_jsobj(s))
        end
        Jscall.exec 'global.gc()'
        refgraph_gc '{ "root": [2], "2": [1], "1": [0] }'
        s2 = s.get_js.get_rb
        Jscall.exec 'global.gc()'
        refgraph_gc '{ "root": [1, 2], "2": [1], "1": [0] }'
        refs = Jscall.check_references()
        assert_equal [], refs[3]               # import zombi
        assert_equal [1, 2], refs[5]           # export
        assert_equal [0], refs[7]              # export detached
    end

    def test_export_after_gc
        Jscall.exec <<CODE
            function check_hashtable(obj) {
                [exported, imported] = Ruby.get_exported_imported()
                return exported.hashtable.get(obj.get_rb())
            }
CODE
        js = Jscall.make_jsobj(Simple.new)
        assert_equal 0, js.__get_id
        js2 = Jscall.make_jsobj(js)
        refute_nil Jscall.check_hashtable(js2)
        2.times do
            js = Jscall.make_jsobj(Simple.new(js))
        end
        refgraph_gc '{ "root": [1, 3], "2": [2], "1": [0] }'
        Jscall.exec 'global.gc()'
        assert_equal ["import", [0, 1, 2], "import zombi", [], "export", [1, 3], "export detached", [0, 2]],
                     Jscall.check_references()
        assert_nil Jscall.check_hashtable(js2)
        js0 = js2.get_rb
        assert_equal 0, js0.__get_id            # export 0th again.
        refs = Jscall.check_references()
        assert_equal [0, 1, 3], refs[5]         # export
        assert_equal [2], refs[7]               # export detached
    end
end
