{
  nixpkgs,
  system,
  frameworkDir,
  inputs ? { },
}:
let
  pkgs = import nixpkgs {
    system = system;
    config.allowUnfree = true;
  };
  lib = pkgs.lib;
  packageDir = frameworkDir + "/packages";
  packageNames = builtins.attrNames (
    lib.filterAttrs (_name: type: type == "directory") (builtins.readDir packageDir)
  );
  appDir = frameworkDir + "/apps";
  hasApps = builtins.pathExists appDir;
  appNames =
    if hasApps then
      builtins.attrNames (lib.filterAttrs (_name: type: type == "directory") (builtins.readDir appDir))
    else
      [ ];
  baseInputs = {
    pkgs = pkgs;
    system = system;
    lib = lib;
    stdenv = pkgs.stdenv;
  }
  // inputs;

  varsDir = frameworkDir + "/vars";
  hasVars = builtins.pathExists varsDir;
  vars = if hasVars then (import varsDir) baseInputs else { };

  utilsDir = frameworkDir + "/utils";
  hasUtils = builtins.pathExists utilsDir;
  utilInputs = baseInputs // {
    vars = vars;
  };
  defaultUtils = import ../../utils utilInputs;
  flakeUtils = if hasUtils then (import utilsDir) (utilInputs // { utils = defaultUtils; }) else { };
  utils = defaultUtils // flakeUtils;

  packageInputs =
    baseInputs
    // {
      vars = vars;
      utils = utils;
    }
    // packages;

  hasProfileManager = vars ? FRAMEWORK_BUILD_DIR && vars ? FRAMEWORK_PROFILE_DIR;
  profileManager = import ../profile-manager {
    pkgs = pkgs;
    buildDir = vars.FRAMEWORK_BUILD_DIR;
    profileDir = vars.FRAMEWORK_PROFILE_DIR;
  };

  userPackages = lib.genAttrs packageNames (name: import (packageDir + "/${name}") packageInputs);
  packages = userPackages // lib.optionalAttrs hasProfileManager { inherit profileManager; };
  apps = lib.genAttrs appNames (name: import (appDir + "/${name}") packageInputs);
  frameworkApps = import ../../apps {
    system = system;
    frameworkDir = frameworkDir;
    pkgs = pkgs;
  };
in
{
  apps = apps // frameworkApps;
  packages = packages;
}
