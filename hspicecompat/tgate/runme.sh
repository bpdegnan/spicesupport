#!/usr/bin/env zsh
hspice tgatehspice.cir > hspice.out  && python3 parse_hspice.py hspice.out
mv hspice.csv tgatehspice.results.csv




