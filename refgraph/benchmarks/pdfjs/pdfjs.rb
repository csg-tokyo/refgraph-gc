# written by people at Computing Software Group, The University of Tokyo.
# run on this directory.

require 'jscall'

URL = "/tiger-small.pdf"

def setup_pdfjs
  if File.exists? '/Applications/Google Chrome.app'
    ## Mac OS
    Jscall::FetchServer.open_command = "open -a '/Applications/Google Chrome.app' --args --js-flags='--expose-gc' "
  elsif not `which google-chrome`.empty?
    ## Ubuntu
    Jscall::FetchServer.open_command = "/bin/bash #{ File.expand_path(File.dirname(__FILE__)) }/run-bg google-chrome --js-flags='--expose-gc' "
  else
    # Jscall::FetchServer.open_command = "firefox"
    raise StandardError.new('could not find a suitable web browser executable')
  end

  Jscall.config browser: true
  # Jscall.debug = 1

  Jscall.dom.append_to_body(<<CODE)
    <h1>PDF.js 'Tiger' example</h1>
    <canvas id="the-canvas"></canvas>
CODE

  # pdfjs = Jscall.dyn_import('https://mozilla.github.io/pdf.js/build/pdf.js')  # original source
  pdfjs = Jscall.dyn_import('/pdf.js')
  pdflib = Jscall.exec 'window["pdfjs-dist/build/pdf"]'

  # pdflib.GlobalWorkerOptions.workerSrc = "https://mozilla.github.io/pdf.js/build/pdf.worker.js"  # original source
  pdflib.GlobalWorkerOptions.workerSrc = "/pdf.worker.js"
  return pdflib
end

def load_and_show(pdflib, url)
    loadingTask = pdflib.getDocument(url)
    loadingTask.async.promise.then(-> (pdf) {
        viewer = PageView.new(pdf)
        3.times do |n|
            viewer.draw(1, 0.8 + 0.2 * n)
            # sleep(0.1)
        end
    },
    -> (reason) {
        puts reason
        exit
    })
end

class PageView
    def initialize(pdf)
        @pdf = pdf
    end

    def draw(pageNumber, scale)
        # Fetch the first page
        @pdf.async.getPage(pageNumber).then(-> (page) { render(page, scale) })
    end

    def render(page, scale)
        viewport = page.getViewport({ scale: scale })
        canvas = Jscall.document.getElementById("the-canvas")
        context = canvas.getContext("2d")
        canvas.height = viewport.height
        canvas.width = viewport.width

        # Render PDF page into canvas context
        renderContext = {
            canvasContext: context,
            viewport: viewport,
        }
        renderTask = page.render(renderContext)
        renderTask.async.promise.then(-> (r) {
            # puts "Page rendered #{r}"
        })
    end
end

require_relative '../inspect'

module Refgraph
  # process.memoryUsage().heapUsed is not available on a browser.
  # So redfine the function in ../inspect.rb
  def self.define_js_mem_utils
    Jscall.exec <<CODE
      function get_heap_memory_usage() {
        return 0
      }
CODE
  end
end

def run_benchmark()
  if ARGV.length > 0 && ARGV[0] == 'true'
    require '../install_refgraph'
  end

  if ARGV.length > 1 && ARGV[1] == 'true'
    Refgraph.force_immediate_gc
  end

  pdflib = setup_pdfjs()
  GC::Profiler.enable

  10.times do
    t00 = Refgraph.clock
    5.times do
      load_and_show(pdflib, URL)
    end
    Refgraph.logging(t00)
  end
end

run_benchmark

# ruby pdfjs.rb <true if refgraph on>
