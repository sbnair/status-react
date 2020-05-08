#!/usr/bin/env bash

# This file defines URLs of Maven repos we know about

declare -A REPOS=(
  [apache]="https://repo.maven.apache.org/maven2"
  [clojars]="https://repo.clojars.org"
  [fabric-io]="https://maven.fabric.io/public"
  [google]="https://dl.google.com/dl/android/maven2"
  [java]="https://maven.java.net/content/repositories/releases"
  [jcenter]="https://jcenter.bintray.com"
  [jitpack]="https://jitpack.io"
  [maven]="https://repo1.maven.org/maven2"
  [gradle]="http://repo.gradle.org/gradle/libs-releases-local"
  [gradlePlugins]="https://plugins.gradle.org/m2"
)
