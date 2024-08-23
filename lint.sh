#!/usr/bin/env bash

set -ex

zig fmt --check src
zig build
zig build test
