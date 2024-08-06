#!/bin/sh
nix-shell --argstr run "sh -c 'zig $*'"