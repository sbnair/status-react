#!/usr/bin/env bash

if [[ -z "${IN_NIX_SHELL}" ]]; then
    echo "Remember to call 'make shell'!"
    exit 1
fi

# This script takes care of generating/updating the maven-sources.nix file
# representing the offline Maven repo containing the dependencies
# required to build the project

set -Eeu

GIT_ROOT=$(cd "${BASH_SOURCE%/*}" && git rev-parse --show-toplevel)
CUR_DIR=$(cd "${BASH_SOURCE%/*}" && pwd)
source "${GIT_ROOT}/scripts/colors.sh"

PROJ_LIST="${CUR_DIR}/proj.list"
DEPS_LIST="${CUR_DIR}/deps.list"
DEPS_URLS="${CUR_DIR}/deps.urls"
DEPS_NIX="${CUR_DIR}/deps.nix"

echo "Regenerating Nix files..."

# Gradle needs to be run in 'android' subfolder
pushd $GIT_ROOT/android > /dev/null

# Generate list of Gradle sub-projects
${CUR_DIR}/gen_gradle_projects.sh | sort -u -o ${PROJ_LIST}

echo -e "Found ${GRN}$(wc -l < ${PROJ_LIST})${RST} sub-projects..."

# check each sub-project in parallel
PROJECTS=$(cat ${PROJ_LIST})
parallel --will-cite \
    ${CUR_DIR}/gradle_deps.sh \
    ::: ${PROJECTS[@]} \
    | sort -uV -o ${DEPS_LIST}
echo -e "\033[2KFound ${GRN}$(wc -l < ${DEPS_LIST})${RST} dependencies..."

# find download URLs for each dependency
DEPENDENCIES=$(cat ${DEPS_LIST})
parallel --will-cite \
    ${CUR_DIR}/determine_url.sh \
    ::: ${DEPENDENCIES[@]} \
    | sort -uV -o ${DEPS_URLS}

echo -e "\033[2KFound ${GRN}$(wc -l < ${DEPS_URLS})${RST} URLs..."

# Format URLs into a Nix consumable file
"${CUR_DIR}/urls2nix.sh" ${DEPS_URLS} > ${DEPS_NIX}

echo "Generated Nix deps file: ${DEPS_NIX}"
echo -e "${GRN}Done${RST}"

popd > /dev/null
