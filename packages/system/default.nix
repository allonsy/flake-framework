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
  utils = if hasUtils then (import utilsDir) (baseInputs // { vars = vars; }) else { };

  packageInputs =
    baseInputs
    // {
      vars = vars;
      utils = utils;
    }
    // packages;

  packages = lib.genAttrs packageNames (name: import (packageDir + "/${name}") packageInputs);
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
