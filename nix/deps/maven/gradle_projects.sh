#!/usr/bin/env bash

set -Eeu

# Print all our sub-projects

gradle projects --console plain 2>&1 \
    | grep "Project ':" \
    | sed -E "s;^.--- Project '\:([@_a-zA-Z0-9\-]+)';\1;"
