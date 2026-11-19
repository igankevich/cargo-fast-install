#!/bin/sh
set -e
pip install hypothesis
python3 -m unittest discover -v tests
