#!/bin/bash
# generate GoWin compatible verilog sources from the pacman ROMs
for i in pacman.5e pacman.5f pacman.6e pacman.6f pacman.6h pacman.6j 82s123.7f 82s126.1m 82s126.3m 82s126.4a; do
    echo "Converting ROM $i"
    ./bin2v.py $i
    echo
done
