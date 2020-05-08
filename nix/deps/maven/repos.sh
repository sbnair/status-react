#!/usr/bin/env bash

# This file defines URLs of Maven repos we know about

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
