#!/bin/bash
set -eu

# list of benchmarks
if [[ -n ${RUBY_REFGRAPH_BENCHMARK_NO_PDFJS:-""} ]]; then
  benchmarks="chain loop cd deltablue havlak nbody richards babel/babel"
else
  benchmarks="chain loop cd deltablue havlak nbody richards babel/babel pdfjs/pdfjs"
fi

# list of gc modes
gcmodes="rggc naive-rggc no-rggc"

# number of iterations
repeat=15

# path to output directory
out=$(cd "$(dirname "$0")" && pwd)/raw

# path to temporary file
tmp=$out/.tmp

# create output directory if needed
mkdir -p "$out"

# rm temporary file on exit
trap 'rm -f $tmp' EXIT

# set ruby version
eval "$(rbenv init -)" && RBENV_VERSION="" rbenv shell 3.1.2-clang-refgraph

# cd to benchmark directory
cd "$RUBY_REFGRAPH_BENCHMARK_DIR"

# run benchmarks
for i in $(seq 1 $repeat); do  # repeat <repeat> times
  for b in $benchmarks; do     # for each benchmark
    for m in $gcmodes; do      # for each gc mode

      # print progress
      echo "$b $m (#$i)"

      # path to ruby script
      src=${b#*/}.rb

      # path to output file
      dst=$out/${b#*/}_${m}_${i}.txt

      # run script if $dst does not exists
      if [[ ! -e $dst ]]; then

        # cd to sub-directory if needed
        if [[ $b == */* ]]; then
            pushd "${b%/*}" > /dev/null
        fi

        # run script
        if [[ $m == rggc ]]; then
            ruby "$src" true > "$tmp" && mv "$tmp" "$dst"
        elif [[ $m == naive-rggc ]]; then
            ruby "$src" true true > "$tmp" && mv "$tmp" "$dst"
        elif [[ $m == no-rggc ]]; then
            ruby "$src" > "$tmp" && mv "$tmp" "$dst"
        else
            echo "unknown mode $m"
        fi

        # cd back to benchmark directory
        if [[ $b == */* ]]; then
            popd > /dev/null
        fi
      fi
    done
  done
done
