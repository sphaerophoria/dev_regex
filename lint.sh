#!/usr/bin/env bash

set -ex

prettier -c res
jshint res
zig fmt --check src
zig build
zig build test
