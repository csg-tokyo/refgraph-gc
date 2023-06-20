# Make many loops
#

require 'jscall'

class Node
    attr_accessor :next
    def initialize(obj = nil)
        @next = obj
    end
end

def define_js_class
    Jscall.exec <<CODE
        class JSNode {
            constructor(next) { this.next = next }
            get_next() { return this.next }
        }

        function make_jsobj(robj) {
            return new JSNode(robj)
        }
CODE
end

# make a ZigZag loop.  The number of objects is n * 2.
def make_loop(n)
    node = first = Node.new(nil)
    (n - 1).times do
        node = Node.new(Jscall.make_jsobj(node))
    end
    first.next = Jscall.make_jsobj(node)
    node
end

def benchmark_loop(n, loop_len, loop_num)
    n.times do
        loops = Array.new(loop_num).map {|e| make_loop(loop_len) }
        loops.each do |start|
            obj = start
            (loop_len * 2).times do
                obj = obj.next
            end
            unless obj == start
                p obj
                p start
                raise "a loop is broken"
            end
        end
    end
end

require_relative './inspect'

def run_benchmark_loop(loop_len, loop_num, refgraph = false, use_bloom = false)
    Refgraph.use_bloomfilter(use_bloom)
    define_js_class
    10.times do
        10.times do
            loops = Array.new(loop_num).map {|e| make_loop(loop_len) }
        end
        p Refgraph.count_references
        t0 = Refgraph.clock
        GC.start
        puts "Ruby GC: #{Refgraph.clock(t0)}"
        if refgraph
            t0 = Refgraph.clock
            Refgraph.gc
            puts "Refgraph.gc #{Refgraph.clock(t0)}"
        end
    end
end

# ruby loop.rb 2 100         # no refgraph gc
# ruby loop.rb 2 100 false   # with refgraph gc
# ruby loop.rb 2 100 true    # with refgraph gc and bloom_filter
def benchmark()
    require_relative './install_refgraph'
    Refgraph.gc_off
    run_benchmark_loop(ARGV[0].to_i, ARGV[1].to_i, ARGV.length > 2, ARGV[2] == 'true')
end

def run_benchmark()
    if ARGV.length > 0 && ARGV[0] == 'true'
        require './install_refgraph'
    end

    if ARGV.length > 1 && ARGV[1] == 'true'
        Refgraph.force_immediate_gc
    end

    define_js_class
    GC::Profiler.enable
    10.times do
        t00 = Refgraph.clock
        benchmark_loop(50, 2, 100)
        Refgraph.logging(t00)
    end
end

#benchmark
run_benchmark
