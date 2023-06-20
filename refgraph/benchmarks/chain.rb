# Make many long chains.
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

def make_chain(n, subchain_length)
    node = nil
    n.times do
        node = Node.new(Jscall.make_jsobj(node))
        (subchain_length - 1).times do
            node = Node.new(node)
        end
    end
    node
end

require_relative './inspect'

def benchmark_body(m, n, length, subchain_length)
    m.times do
        chains = Array.new(n).map {|e| make_chain(length, subchain_length) }
    end
end

def run_benchmark_loop(length = 100, subchain_length = 1, refgraph = false)
    define_js_class
    10.times do |n|
        t0 = Refgraph.clock
        benchmark_body(10, 10, length, subchain_length)
        p "#{Refgraph.clock(t0)} for 10 x 10 x make_chain(#{length},#{subchain_length}) :#{n}"
        p Refgraph.count_references
        t0 = Refgraph.clock
        GC.start
        p "Ruby GC: #{Refgraph.clock(t0)}"
        if refgraph
            t0 = Refgraph.clock
            Refgraph.gc
            p Refgraph.clock(t0)
        end
    end
end

def benchmark
    require_relative './install_refgraph'
    Refgraph.gc_off

    if ARGV.length == 0
        puts 'ruby chain.rb <length = 100> <subchain_length = 1> <refgraph = false>'
        puts 'ruby chain.rb false'
        puts 'ruby chain.rb 100 1'
        puts 'ruby chain.rb 10 100 true'
    elsif ARGV.length == 1
        run_benchmark_loop(100, 1, ARGV[0] == 'true')
    elsif ARGV.length == 2
        run_benchmark_loop(ARGV[0].to_i, ARGV[1].to_i, false)
    else
        run_benchmark_loop(ARGV[0].to_i, ARGV[1].to_i, ARGV[2] == 'true')
    end
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
        benchmark_body(10, 10, 100, 1)
        Refgraph.logging(t00)
    end
end

#benchmark
run_benchmark
