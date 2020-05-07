#!/usr/bin/env bash

set -Eeu

# This script takes care of generating/updating the maven-inputs.txt file.
# For this, we:
#  1. query the projects in the main gradle project
#  2. loop through each of the projects, querying its dependencies
#  3. add each one to maven-inputs.txt

GIT_ROOT=$(cd "${BASH_SOURCE%/*}" && git rev-parse --show-toplevel)
current_dir=$(cd "${BASH_SOURCE%/*}" && pwd)
gradle_opts="--console plain"
tmp_pom_filename=$(mktemp --tmpdir fetch-maven-deps-XXXX.pom)
tmp_mvn_dep_tree_filename=$(mktemp --tmpdir mvn-dep-tree-XXXX.txt)
deps_file_path=$(mktemp --tmpdir fetch-maven-deps-XXXX-deps.txt)

# Executes a gradle dependencies command and returns the output package IDs
function runGradleDepsCommand() {
  echo "Computing maven dependencies with \`gradle $1 $gradle_opts\`..." > /dev/stderr
  # Add a comment header with the command we're running (useful for debugging)
  echo "# $1"

  # Run the gradle command and:
  # - remove lines that end with (*) or (n) but don't start with (+)
  # - keep only lines that start with \--- or +---
  # - remove lines that refer to a project
  # - extract the package name and version, ignoring version range indications, such as in `com.google.android.gms:play-services-ads:[15.0.1,16.0.0) -> 15.0.1`
  gradle $1 $gradle_opts \
    | grep --invert-match -E "^[^+].+ \([\*n]\)$" \
    | grep -e "[\\\+]---" \
    | grep --invert-match -e "--- project :" \
    | sed -E "s;.*[\\\+]--- ([^ ]+:)(.+ -> )?([^ ]+).*$;\1\3;"
}

mvn_tmp_repo=$(mktemp -d)
trap "rm -rf $mvn_tmp_repo $tmp_pom_filename $deps_file_path $tmp_mvn_dep_tree_filename" ERR EXIT HUP INT

rnModules=$(node ./node_modules/react-native/cli.js config | jq -r '.dependencies | keys | .[]')

pushd $GIT_ROOT/android > /dev/null

gradleProjects=$(gradle projects $gradle_opts 2>&1 \
                | grep "Project ':" \
                | sed -E "s;^.--- Project '\:([@_a-zA-Z0-9\-]+)';\1;")
projects=( ${gradleProjects[@]} ${rnModules[@]} )
IFS=$'\n' sortedProjects=($(sort -u <<<"${projects[*]}"))
unset IFS

echo -n > $deps_file_path
# TODO: try to limit unnecessary dependencies brought in by passing
# e.g. `--configuration releaseCompileClasspath`
# to the `gradle *:dependencies` command
runGradleDepsCommand 'buildEnvironment' >> $deps_file_path
for project in ${sortedProjects[@]}; do
  runGradleDepsCommand ${project}:buildEnvironment >> $deps_file_path
  runGradleDepsCommand ${project}:dependencies >> $deps_file_path
done

popd > /dev/null

# Read the deps file into memory, sorting and 
# getting rid of comments, project names and duplicates
IFS=$'\n'
cat $deps_file_path \
   | grep --invert-match -E '^#.*$' \
   | grep --invert-match -E '^[a-z]+$' \
   | grep --invert-match -E '^:?[^:]+$' \
   | sort -uV
unset IFS
