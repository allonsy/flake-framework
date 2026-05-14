{
  frameworkDir,
  stdenv,
  ...
}:
let
  appDerivation = stdenv.mkDerivation {
    name = "new-package-template";
    src = null;
    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin

      cat <<EOF > $out/bin/runner.sh
      #!/usr/bin/env bash

      echo "Hello from app"
      echo ${frameworkDir}
      EOF
      chmod +x $out/bin/runner.sh
    '';
  };
in
{
  type = "app";
  program = "${appDerivation}/bin/runner.sh";
}
