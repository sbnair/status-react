#!/usr/bin/env bash

#
# This script takes a deps.list file and builds a Nix expression
# that can be used by maven-repo-builder.nix to produce a path to
# a local Maven repository.
#

CUR_DIR=$(cd "${BASH_SOURCE%/*}" && pwd)
MAVEN_CACHE_PATH="${HOME}/.m2/repository"

function fetch_nix_sha() {
    nix-prefetch-url --type sha256 "$1" 2> /dev/null
}

function get_nix_sha() {
    nix hash-file --base32 --type sha256 "$1" 2>/dev/null
}

function maven_fetch() {
    mvn --non-recursive --batch-mode --fail-never "${1}:get" 2>&1 >/dev/null
}

function find_jar() {
    find ${MAVEN_CACHE_PATH} \
        -path "*/$(echo "${1%:*}" | tr '.:' '/')/*" \
        -name "*.jar" \
        | sort -V \
        | tail -n 1
}

function nix_entry_from_jar() {
    JAR_REL_PATH="${1}"
    JAR_REL_NAME="${JAR_REL_PATH#${MAVEN_CACHE_PATH}}"
    JAR_PATH="${MAVEN_CACHE_PATH}/${JAR_REL_PATH}"
    JAR_NAME=$(basename "${JAR_PATH}")
    JAR_DIR=$(dirname "${JAR_PATH}")
    # POM might have a slightly different name
    POM_PATH=$(echo ${JAR_DIR}/*.pom)

    REPO_NAME=$(get_repo_for_dir "${JAR_DIR}")

    JAR_SHA1=$(cat "${JAR_PATH}.sha1")
    JAR_SHA256=$(get_nix_sha "${JAR_PATH}")

    POM_SHA1=$(cat "${POM_PATH}.sha1")
    POM_SHA256=$(get_nix_sha "${POM_PATH}")
    
    # Format into a Nix attrset entry
    echo -n "
  \"${JAR_REL_NAME}\" =
  {
      host = repos.${REPO_NAME};
      path = \"${JAR_REL_NAME}\";
      type = \"jar\";
      pom = {
          sha1 = \"${POM_SHA1}\";
          sha256 = \"${POM_SHA256}\";
      };
      jar = {
          sha1 = \"${JAR_SHA1}\";
          sha256 = \"${JAR_SHA256}\";
      };
  };
"
}


DEP=${1}
echo " - Nix entry for: ${DEP}" >&2

nix_entry_from_jar ${DEP}
