## Artifact: Collecting cyclic garbage across foreign function interfaces

This is the artifact for our PLDI 2023 paepr:

- Tetsuro Yamazaki, Tomoki Nakamaru, Ryota Shioya, Tomoharu Ugawa, Shigeru Chiba, "Collecting Cyclic Garbage across Foreign Function Interfaces: Who Takes the Last Piece of Cake?", ACM PLDI 2023,
https://doi.org/10.1145/3591244

The doker image of this software is available from Zenodo, https://doi.org/10.5281/zenodo.7811907

### Overview

Refgraph GC is an extension to the JScall FFI library so that
cyclic garbage betwwen Ruby and JavaScript will be reclaimed.
Jscall is a foreign function interface (FFI) library to access
a JavaScript library from Ruby.

This repository includes a modified Ruby 3.1.2 VM and a Ruby library named _refgraph_.


### Installation

We below assume that `/PATH/TO/RUBY-REFGRAPH` refers to the directory
containing this source code.
We also assume that the operating system is 
Ubuntu 22.04 or macOS 13 Ventura.

Install the dependencies for `ruby 3.1.2-clang-refgraph`.

```
$ sudo apt update
$ sudo apt install autoconf bison clang libffi-dev libreadline-dev libssl-dev rbenv ruby
$ echo 'eval "$(rbenv init -)"' >> $HOME/.bashrc
```
Install `npm` and `Node.js`

```
$ sudo apt update
$ sudo apt install npm wget
$ sudo npm install --global n
$ sudo n lts
```

Build `ruby 3.1.2-clang-refgraph`

```
$ cd /PATH/TO/RUBY-REFGRAPH
$ autoconf
$ autoreconf --install
$ mkdir build
$ cd build
$ CC=clang ../configure --prefix $(rbenv root)/versions/3.1.2-clang-refgraph --disable-install-doc
$ make install
$ cd ../refgraph
$ eval "$(rbenv init -)"
$ rbenv shell 3.1.2-clang-refgraph
$ gem install bundler
$ bin/setup
$ bundle exec rake build
$ gem install pkg/refgraph-0.1.0.gem
```

Install the dependencies for benchmark programs.

```
$ cd /PATH/TO/RUBY-REFGRAPH/refgraph/benchmarks/babel
$ npm install
```

Install the dependencies for a Python script that generates figures.

```
$ sudo apt update
$ sudo apt install python3-venv
$ cd /PATH/TO/RUBY-REFGRAPH/refgraph/experiment
$ python3 -m venv venv --upgrade-deps
$ venv/bin/pip install matplotlib==3.6.1
```

Google Chrome must be also installed.

### Testing

After building and installing necessary components as instructed in the
previous section, run test cases in the same shell.

Run tests for `ruby 3.1.2-clang-refgraph`
```
$ cd /PATH/TO/RUBY-REFGRAPH/refgraph
$ bundle exec rake test
```

All tests are supposed to pass
except `test_w_shape_long_chain_looped()`
in `test_refgraph.rb`.
It may fail when only a limited amount of computing resource is available.

### How to use `ruby 3.1.2-clang-refgraph`

Switch the Ruby VM to `ruby 3.1.2-clang-refgraph`.
```
$ rbenv shell 3.1.2-clang-refgraph
```
This command sets a shell-specific Ruby version so that
the Ruby command \texttt{ruby} will be bound to that version.

Run the Ruby shell.
```
$ irb
irb> puts 'Hello, world!!'
Hello, world!!
=> nil
irb> require 'refgraph'
=> true
irb> Jscall.console.log('Hi!')  # call a JavaScript function
Hi!
=> nil
irb> Refgraph.gc                # explicitly run Refgraph GC
=> [[0, 0]]
irb> exit
```

Refgraph GC is an extension to the `jscall` library.
`jscall` is an FFI library
for running a JavaScript program from Ruby.
The document of this library is available from their github repo
https://github.com/csg-tokyo/jscall.


### Reproduce Figures

This section mentions how to reproduce the figures presented in our PLDI paper.
The outputs are pdf files
under `/PATH/TO/RUBY-REFGRAPH/refgraph/experiment/out`.

Since this section runs all the benchmark programs for generating figures,
it takes long time, probably, one day.
To reduce the execution time, you can decrease the number of iterating
the execution of the benchmark programs.
By default, it iterates 15 times.
The number of iteration is specified in `experiment/run-benchmarks.sh`:
```
# number of iterations
repeat=15
```

Change this line and set `repeat` to, for example, `2`.
Iterating 2 tiems will take about 2 hours.
If the iteration count is not 15, the shell script will produce a warning
message `"data may not be sufficient"`, but ignore this message.

To reproduce figures, execute the following commands.
Move to the benchmark directory.
```
$ cd /PATH/TO/RUBY-REFGRAPH/refgraph
```

Run benchmarks to obtain raw results.
```
$ RUBY_REFGRAPH_BENCHMARK_DIR="$(pwd)/benchmarks" experiment/run-benchmarks.sh
```
Generate figures from raw data.
```
$ cd ./experiment
$ ./generate-figures.sh
$ ls out
```

The output figures will be found under `./out`.

### Source code

The implementation of Refgraph GC consists of an extension to CRuby and
a Ruby gem library named `Refgraph`.
This Ruby gem library is an extension to another
Ruby gem library, `Jscall`.

- `refgraph-gc`

  The source code of CRuby `3.1.2-clang-refgraph`.

- `refgraph-gc/refgraph`

  The source code of the Refgraph library.
  
  - `refgraph/lib`
    - Ruby and JavaScript source.
  - `refgraph/ext`
    - C source
  - `refgraph/benchmarks`
    - benchmark programs

The main method of Refgraph GC is `Refgraph.gc`, which is in
`lib/refgraph/jscall.rb`.
It calls `Refgraph.simply_make` to construct a compressed
reference graph in the JSON format.
The `simply_make` method is implemented in the C language.
Its source code is found in `ext/refgraph/simple.c`.

The constructed graph is sent to JavaScript by calling
`Jscall.funcall("Refgraph.gc", json)` or
`Jscall.funcall("Refgraph.eager\_gc", json)`.
This executes `Refgraph.gc(json)` or
`eager_gc(json)`
in JavaScript through the Jscall library.
Those JavaScript functions are found in `lib/refgraph/refgraph.mjs`.

Note that `Refgraph.gc` calls `override_methods`,
which installs the send barrier by redefining several methods
on the export table.
The original source code for implementing the export table is included in the
Jscall library.
See https://github.com/csg-tokyo/jscall/blob/main/lib/jscall/main.mjs

### Benchmarks

The source files of the benchmark programs are in 
`refgraph/benchmarks`.
Each benchmark program is a pair of a Ruby program and a JavaScript
program.
To illustrate the common structure of benchmark programs,
let's look at the source file of the `loop` benchmark
because it is the simplest benchmark.

The `loop` benchmark is run by the following command:

```
$ ruby loop.rb true
```

This runs the benchmark with the Refgraph GC.

The main method of the `loop` benchmark is
`run_benchmark` in `loop.rb`.
When Refgraph GC is used, this method first
runs `install_refgraph.rb`.
It redefines several methods in the Jscall library so that the
Refgraph GC will be periodically executed.

Then, `run_benchmark` calls `define_js_class`
to execute a JavaScript program, which is
embedded in `loop.rb` as the source text, on `node.js`.
It defines a class and a function in JavaScript.
The JavaScript programs for some benchmarks are stored in a separate
source file.  For example, the JavaScript program for the
`deltablue` benchmark is in `deltablue.mjs`.

After executing the JavaScript program, `run_benchmark` starts
benchmark looping.
For every iteration,
it prints logged data by calling `Refgraph.logging`.
The source code of `logging` is in `inspect.rb`.
For example, it prints the following data:

```
total time: 1.013 sec.
gc time: 514.266 msec.
reclaimed=21400. Rb=19.22Mb, Js=16.05Mb
Refgraph-gc count: 1, time: 89.933 msec.
refgraph size: [[35, 21436, 21472, 21471, 333211]]
[9802, 0, 9802, "import/import-zombi/export"]
```

The first line presents the total execution time of the iteration.
The second line presents the execution time of Ruby's GC.
In the third line, `reclaimed` is the number of proxy objects
that are reclaimed in Ruby.
`Rb` presents the memory usage in Ruby,
and `Js` presents the memory usage in JavaScript.
The fourth line presents the number of occurrences of the Refgraph GC
and its total execution time during the iteration.

The fifth line presents an array of the size of a compressed reference graph
created during the execution.
The size is represented by five numbers: the number of edges
from the root, the number of edges from the other nodes,
the number of the nodes in the export table in Ruby, the number of the node
in the import table in Ruby, and the byte length of the JSON text
representing the graph.

The last line presents the number of the live proxy-objects,
the number of the dead proxy-objects, and the number of the objects
in the export table in Ruby when the iteration finishes.
