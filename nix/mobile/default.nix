{ config, lib, stdenvNoCC, callPackage, mkShell,
  status-go, xcodeWrapper }:

let
  inherit (lib) catAttrs concatStrings optional unique;

  localMavenRepoBuilder = callPackage ../tools/maven/maven-repo-builder.nix { };

  fastlane = callPackage ./fastlane { };

  android = callPackage ./android {
    inherit localMavenRepoBuilder;
    status-go = status-go.mobile.android;
  };

  ios = callPackage ./ios {
    inherit xcodeWrapper fastlane;
    status-go = status-go.mobile.ios;
  };

  selectedSources = [
    status-go.mobile.android
    status-go.mobile.ios
    fastlane
    android
    ios
  ];

in {
  shell = mkShell {
    inputsFrom = (catAttrs "shell" selectedSources);
  };

  # TARGETS
  inherit android ios fastlane;
}
