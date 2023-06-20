#!/bin/bash
set -eu

# path to python virtual environment
venv=venv

# path to output directory
out=out

# cd to script dir
cd "$(dirname "$0")"

# create virtual environment if needed
if [[ ! -e $venv ]]; then
    python3 -m venv $venv --upgrade-deps
    $venv/bin/pip install matplotlib==3.6.1
    echo '*' > $venv/.gitignore
fi

# create output directory
mkdir -p $out

# delete output directory
rm $out/* || true

# run vis.py
$venv/bin/python generate-figures.py
