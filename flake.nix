{
  description = "A Nix Flake semi-opinionated framework";

  outputs =
    {
      ...
    }:
    {
      mkFlake = import ./packages;

    };
}
