{ pkgs, ... }:
{
  writeTemplate = file: context: pkgs.replaceVars file context;
}
