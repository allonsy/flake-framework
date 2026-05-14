{
  nixpkgs,
  frameworkDir,
  hostnames ? [ ],
  inputs ? { },
}:
let
  systems = (import ../systems).allSystems;
  forEachSystem = import ./system;
  mapAttrs = nixpkgs.lib.attrsets.mapAttrs;
  outputs = nixpkgs.lib.genAttrs systems (
    system:
    forEachSystem {
      system = system;
      nixpkgs = nixpkgs;
      frameworkDir = frameworkDir;
      inputs = inputs;
    }
  );
  promoteField = fieldName: mapAttrs (_: systemSet: systemSet.${fieldName}) outputs;
  packages = promoteField "packages";
  apps = promoteField "apps";
  formatter = mapAttrs (system: _: (import nixpkgs { system = system; }).nixfmt-tree) outputs;
  frameworkAppsGenerator = import ../apps;
  allApps = mapAttrs (
    system: systemApps:
    systemApps
    // (frameworkAppsGenerator {
      system = system;
      pkgs = import nixpkgs { system = system; };
      frameworkDir = frameworkDir;
    })
  ) apps;

in
{
  packages = packages;
  apps = allApps;
  formatter = formatter;
}
