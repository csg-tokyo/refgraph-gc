require 'refgraph'

module Jscall
  class PipeToJs
    alias original_send_command send_command

    def send_with_piggyback(cmd)
      threashold = 100
      @reclaimed_remote_references ||= 0
      @send_counter += 1
      if @send_counter > threashold
        @send_counter = 0
        dead_refs = @imported.dead_references()
        if dead_refs.length > 0
          @reclaimed_remote_references += dead_refs.length
          cmd = cmd.dup
          cmd[5] = dead_refs
        end
        current_time = Refgraph.clock
        @last_refgraph_gc_time ||= current_time
        if current_time > @last_refgraph_gc_time + 1 # after 1 sec.
          @should_run_refgraph_gc = true
        end
      end
      return cmd
    end

    def send_command(cmd)
      if @should_run_refgraph_gc
        @should_run_refgraph_gc = false
        run_refgraph_gc
        @last_refgraph_gc_time = Refgraph.clock
      end

      original_send_command(cmd)
    end

    attr_accessor :run_gc_before_refgraph
    attr_accessor :refgraph_gc_off
    attr_accessor :refgraph_run_counter

    def run_refgraph_gc
      if @refgraph_gc_off.nil?
        @refgraph_gc_time ||= 0
        @refgraph_run_counter ||= 0
        GC.start if @run_gc_before_refgraph
        t0 = Refgraph.clock
        Refgraph.gc
        @refgraph_gc_time += Refgraph.clock - t0
        @refgraph_run_counter += 1
      end
    end

    def refgraph_gc_time
      t = @refgraph_gc_time
      @refgraph_gc_time = 0
      t.nil? ? 0 : t
    end
  end
end

module Refgraph
  def self.gc_off(yes=true)
    Jscall.__getpipe__.refgraph_gc_off = yes || nil
  end

  def self.run_ruby_gc(yes=true)
    Jscall.__getpipe__.run_gc_before_refgraph = yes
  end

  # How many times Refgraph GC has run since this method was called.
  def self.run_counter
    pipe = Jscall.__getpipe__
    count = pipe.refgraph_run_counter
    pipe.refgraph_run_counter = 0
    if count.nil? then 0 else count end
  end

  def self.gc_time
    Jscall.__getpipe__.refgraph_gc_time
  end
end
