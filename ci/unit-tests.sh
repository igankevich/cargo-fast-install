#!/bin/sh
set -e
pip install hypothesis
./tests/yard.py -v
