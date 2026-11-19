#!/bin/sh
set -e
pip install hypothesis
./yard-test.py -v
