#!/usr/bin/env bash

function join_by { local IFS="$1"; shift; echo "$*"; }

mavenSources=( \
  https://dl.google.com/dl/android/maven2 \
  https://jcenter.bintray.com \
  https://plugins.gradle.org/m2 \
  https://repo.maven.apache.org/maven2 \
  https://maven.fabric.io/public \
  https://jitpack.io \
)
mavenSourcesSedFilter=$(join_by '|' ${mavenSources[@]})

# Converts a URL to a Maven package ID (e.g. https://dl.google.com/dl/android/maven2/android/arch/core/common/1.0.0/common-1.0.0 -> android.arch.core:common:1.0.0)
function getPackageIdFromURL() {
  local url="$1"
  local path=$(echo $url | sed -E "s;($mavenSourcesSedFilter)/(.+);\2;")

  IFS='/' read -ra tokens <<< "$path"
  local groupLength=$(( ${#tokens[@]} - 3 ))
  local groupId=''
  for ((i=0;i<$groupLength;i++)); do
    if [ $i -eq 0 ]; then
      groupId=${tokens[i]}
    else
      groupId="${groupId}.${tokens[i]}"
    fi
  done
  artifactId=${tokens[-3]}
  version="${tokens[-2]}"
  echo "$groupId:$artifactId:$version"
}

# Formats the components of a Maven package ID as a URL path component (e.g. android/arch/core/common/1.0.0/common-1.0.0)
function getPath() {
  local tokens=("$@")
  local groupId=${tokens[0]}
  local artifactId=${tokens[1]}
  local version=${tokens[2]}

  groupId=$(echo $groupId | tr '.' '/')
  echo "$groupId/$artifactId/$version/$artifactId-$version"
}

# Tries to download a POM to $tmp_pom_filename given a base URL (also checks for empty files)
function tryGetPOMFromURL() {
  local url="$1"

  rm -f ${tmp_pom_filename}
  curl --output ${tmp_pom_filename} --silent --fail --location "$url.pom" && test -s ${tmp_pom_filename}
}

# Given the components of a package ID, will loop through known repositories to figure out a source for the package
function determineArtifactUrl() {
  # Parse dependency ID into components (group ID, artifact ID, version)
  IFS=':' read -ra tokens <<< "$1"
  local groupId=${tokens[0]}
  [ -z "$groupId" ] && return
  local artifactId=${tokens[1]}
  local version=$(echo "${tokens[2]}" | cut -d'@' -f1)

  local path=$(getPath "${tokens[@]}")
  for mavenSourceUrl in ${mavenSources[@]}; do
    if tryGetPOMFromURL "$mavenSourceUrl/$path"; then
      echo "$mavenSourceUrl/$path"
      return
    fi
  done
  echo "<NOTFOUND>"
}

function retrieveAdditionalDependencies() {
  # It is not enough to output the dependencies in deps, we must also ask maven to report
  # the dependencies for each individual POM file. Instead of parsing the dependency tree itself though,
  # we look at what packages maven downloads from the internet into the local repo,
  # which avoids us having to do a deep search, and does not report duplicates
  echo -n > ${tmp_mvn_dep_tree_filename}
  mvn dependency:tree -B -Dmaven.repo.local=${mvn_tmp_repo} -f "$1" > ${tmp_mvn_dep_tree_filename} 2>&1 || echo -n
  local additional_deps=( $(cat ${tmp_mvn_dep_tree_filename} \
    | grep -E 'Downloaded from [^:]+: [^ ]+\.(pom|jar|aar)' \
    | sed -E "s;^\[INFO\] Downloaded from [^:]+: ([^ ]+)\.(pom|jar|aar) .*$;\1;") )
  local missing_additional_deps=( $(cat ${tmp_mvn_dep_tree_filename} \
    | grep -E "The POM for .+:.+:(pom|jar):.+ is missing" \
    | sed -E "s;^.*The POM for (.+:.+:(pom|jar):.+) is missing.*$;\1;") )

  for additional_dep_url in ${additional_deps[@]}; do
    local additional_dep_id=$(getPackageIdFromURL $additional_dep_url)

    # See if we already have this dependency in $deps
    local alreadyExists=0
    for _dep in ${deps[@]}; do
      if [ "$additional_dep_id" = "$_dep" ]; then
        alreadyExists=1
        break
      fi
    done
    [ $alreadyExists -eq 0 ] && echo "$additional_dep_url" || continue
  done

  for additional_dep_id in ${missing_additional_deps[@]}; do
    # See if we already have this dependency in $deps
    local alreadyExists=0
    for _dep in ${deps[@]}; do
      if [ "$additional_dep_id" = "$_dep" ]; then
        alreadyExists=1
        break
      fi
    done

    if [ $alreadyExists -eq 0 ]; then
      artifactUrl=$(determineArtifactUrl $additional_dep_id)
      if [ -z "$artifactUrl" ]; then
        continue
      elif [ "$artifactUrl" = "<NOTFOUND>" ]; then
        # Some dependencies don't contain a normal format, so we ignore them (e.g. `com.squareup.okhttp:okhttp:{strictly`)
        echo " ! Failed to find URL: $DEP" >&2
        continue
      fi

      echo "$artifactUrl"
    fi
  done
}

# The only argument is the file with the deps list
DEP="${1}"
if [[ -z "${DEP}" ]]; then
    echo "No argument given!" >&2
    exit 1
fi

mvn_tmp_repo=$(mktemp -d)
tmp_pom_filename=$(mktemp --tmpdir fetch-maven-deps-XXXX.pom)
tmp_mvn_dep_tree_filename=$(mktemp --tmpdir mvn-dep-tree-XXXX.txt)

trap "rm -rf ${mvn_tmp_repo} ${tmp_pom_filename} $deps_file_path ${tmp_mvn_dep_tree_filename}" ERR EXIT HUP INT

echo -en "\033[2K  - Finding URL: ${DEP}\r" >&2

FOUND_URL=$(determineArtifactUrl $DEP)

if [ -z "${FOUND_URL}" ]; then
    echo " ! No URL found: ${DEP}" >&2
    exit
elif [ "${FOUND_URL}" = "<NOTFOUND>" ]; then
    # Some dependencies don't contain a normal format, so we ignore them (e.g. `com.squareup.okhttp:okhttp:{strictly`)
    echo " ! Failed to find URL: $DEP" >&2
    exit
fi

echo "${FOUND_URL}"

retrieveAdditionalDependencies ${tmp_pom_filename}
