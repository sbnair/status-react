#!/usr/bin/env bash

# This defines URLs of Maven repos we know about and use.
declare -A REPOS=(
  [apache]="https://repo.maven.apache.org/maven2"
  [gradle]="https://plugins.gradle.org/m2"
  [google]="https://dl.google.com/dl/android/maven2"
  [sonatype]="https://repository.sonatype.org/content/groups/sonatype-public-grid"
  [java]="https://maven.java.net/content/repositories/releases"
  [jcenter]="https://jcenter.bintray.com"
  [jitpack]="https://jitpack.io"
  [maven]="https://repo1.maven.org/maven2"
)

# I know this is dumb, but associative arrays don't have an order
# and this should be ordered to reduce number of URL checks.
# These were sorted on the frequency of different repos in deps.urls.
declare -a REPOS_SORTED=(
  "https://repo.maven.apache.org/maven2"
  "https://plugins.gradle.org/m2"
  "https://dl.google.com/dl/android/maven2"
  "https://repository.sonatype.org/content/groups/sonatype-public-grid"
  "https://maven.java.net/content/repositories/releases"
  "https://jcenter.bintray.com"
  "https://jitpack.io"
  "https://repo1.maven.org/maven2"
)
