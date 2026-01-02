#!/usr/bin/env zsh
hspice tgatehspice.cir > hspice.out  && python3 hspice_to_csv.py hspice.out
mv hspice.csv tgatehspice.results.csv




