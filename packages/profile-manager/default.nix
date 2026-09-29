{
  pkgs,
  buildDir,
  profileDir,
}:
pkgs.stdenv.mkDerivation {
  pname = "profileManager";
  version = "0.1";

  dontUnpack = true;

  nprofileScript = pkgs.replaceVars ./nprofile.sh {
    buildDir = pkgs.lib.escapeShellArg buildDir;
    profileDir = pkgs.lib.escapeShellArg profileDir;
  };

  installPhase = ''
    runHook preInstall
    install -Dm755 $nprofileScript $out/bin/nprofile
    runHook postInstall
  '';
}
