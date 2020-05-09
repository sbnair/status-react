#!/usr/bin/env bash

set -Eeu

echo -en "\033[2K - Checking deps: $1\r" >&2

GIT_ROOT=$(cd "${BASH_SOURCE%/*}" && git rev-parse --show-toplevel)
# Gradle needs to be run in 'android' subfolder
cd $GIT_ROOT/android

# Run the gradle command for a project:
# - ':buildEnvironment' to get build tools
# - ':dependencies' to get direct deps limited those by
#   implementation config to avoid test dependencies
#
# And clean up the output by:
# - remove lines that end with (*) or (n) but don't start with (+)
# - keep only lines that start with \--- or +---
# - remove lines that refer to a project
# - extract the package name and version, ignoring version range indications,
#   such as in `com.google.android.gms:play-services-ads:[15.0.1,16.0.0) -> 15.0.1`
# - drop entries that aren't just the name of the dependency
# - drop entries starting with `status-im:` like `status-go`

TMPOUT="/tmp/gradle-${1}.out"

gradle --no-daemon --console plain \
    "${1}:buildEnvironment" \
    "${1}:dependencies" \
    > ${TMPOUT}

cat ${TMPOUT} \
    | grep --invert-match -E "^[^+].+ \([\*n]\)$" \
    | grep -e "[\\\+]---" \
    | grep --invert-match -e "--- project :" \
    | sed -E "s;.*[\\\+]--- ([^ ]+:)(.+ -> )?([^ ]+).*$;\1\3;" \
    | grep -vE -e '^#.*$' -e '^[a-z]+$' -e '^:?[^:]+$' \
    | grep -v '^status-im:'
