# A few methods useful for inspection.
# This file is not automatically loaded.

require 'objspace'

module Jscall
  class PipeToJs
    def send_with_piggyback(cmd)
      threashold = 100
      @reclaimed_remote_references ||= 0
      @send_counter += 1
      if (@send_counter > threashold)
        @send_counter = 0
        dead_refs = @imported.dead_references()
        if (dead_refs.length > 0)
          @reclaimed_remote_references += dead_refs.length
          cmd2 = cmd.dup
          cmd2[5] = dead_refs
          return cmd2
        end
      end
      return cmd
    end
    attr_accessor :reclaimed_remote_references
  end
end

module Refgraph
  def self.reclaimed_remote_references
    pipe = Jscall.__getpipe__
    count = pipe.reclaimed_remote_references
    pipe.reclaimed_remote_references = 0
    if count.nil? then 0 else count end
  end

  # define JavaSript functions for inspecting export/import tables.
  # They are invoked by Jscall.check_references() or Jscall.count_references().
  #
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

  # define JavaSript functions for inspecting memory usage.
  def self.define_js_mem_utils
    Jscall.exec <<CODE
      // returns the used heap memory size in bytes
      function get_heap_memory_usage() {
        return process.memoryUsage().heapUsed
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

  def self.gc
  end

  def self.gc_off(yes=true)
  end

  def self.run_ruby_gc(yes=true)
  end

  def self.run_counter
    0
  end

  def self.gc_time
    0
  end

  def self.get_log
    []
  end

  def self.config(**kw)
    Jscall.config(**kw)
  end

  # get time in seconds
  def self.clock(t0 = nil, msg = '', t1 = nil)
    if t0
      t = clock - t0
      t = t1 - t0 unless t1.nil?
      if t < 1
        "#{msg}#{"%#.03f" % (t * 1000)} msec."
      else
        "#{msg}#{"%#.03f" % t} sec."
      end
    else
      # equivalent to the following code in C.
      # #include <time.h>
      # struct timespec t;
      # clock_gettime(CLOCK_MONOTONIC, &t);
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  def self.logging(t0)
    Refgraph.gc_off
    puts clock(t0, 'total time: ')
    puts clock(0, 'gc time: ',  GC::Profiler.total_time)

    unless @js_mem_utils_defined
      define_js_mem_utils
      @js_mem_utils_defined = true
    end

    reclaimed = reclaimed_remote_references
    jsHeap = Jscall.get_heap_memory_usage / 1_000_000.0
    rbHeap = ObjectSpace.memsize_of_all / 1_000_000.0
    puts "reclaimed=#{reclaimed}. Rb=#{"%#.2f" % rbHeap}Mb, Js=#{"%#.2f" % jsHeap}Mb"
    puts clock(0, "Refgraph-gc count: #{Refgraph.run_counter}, time: ", Refgraph.gc_time)
    puts "refgraph size: #{Refgraph.get_log}"
    p count_references()
    Refgraph.gc_off(false)
    GC::Profiler.total_time    # reset counters
  end
end
