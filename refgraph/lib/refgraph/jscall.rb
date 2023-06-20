# A briding interface between refgraph and jscall

require "jscall"

module Refgraph
  @bloomfilter = false
  @immediate_gc = false
  @size_log = []

  def self.config(**kw)
    refgraph_file = [["Refgraph", "#{__dir__}", "/refgraph.mjs"]]
    kw = {} if kw.nil?
    if kw.include? :module_names
      kw[:module_names] = refgraph_file + kw[:module_names]
    else
      kw[:module_names] = refgraph_file
    end

    if @immediate_gc
      if kw.include? :options
        kw[:options] = kw[:options] + ' --expose-gc'
      end
    end

    Jscall.config(**kw)
  end

  def self.use_bloomfilter(yes=true)
    @bloomfilter = yes
  end

  def self.force_immediate_gc(yes=true)
    @immediate_gc = yes
    Jscall.config(options: ' --expose-gc')
  end

  # Gets the sizes of the refgraphs that have been sent to JavaScript before.
  # This returns an array, and each array element represents the size of a refgraph.
  # Each array element is another array.  Its first element is the number of the remote
  # references reachable from Ruby's root set.  The second element is the sum of the
  # number of the edges from an object in the export table.
  def self.get_log
    log = @size_log
    @size_log = []
    return log
  end

  def self.gc
    exported, imported = Jscall.__getpipe__.get_exported_imported
    if @bloomfilter
      json = Refgraph.make_by_batch_propagation(exported.objects, imported.objects, Jscall::HiddenRef)
    else
      json = Refgraph.simply_make(exported.objects, imported.objects, Jscall::HiddenRef)
    end
    if @immediate_gc
      Jscall.funcall("Refgraph.eager_gc", json)
    else
      Jscall.funcall("Refgraph.gc", json)
    end
    @size_log << [Refgraph.get_root_set_count, Refgraph.get_refgraph_edges_count]
  end
end

Refgraph.config
