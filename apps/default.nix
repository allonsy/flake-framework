{
  system,
  frameworkDir,
  pkgs,
}:
let
  newApp = import ./new {
    stdenv = pkgs.stdenv;
    frameworkDir = frameworkDir;
    system = system;
  };
in
{
  new = newApp;
}
