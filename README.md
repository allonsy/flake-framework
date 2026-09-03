# Nix Flake Framework
A semi-opinionated nix flake framework

You lay out packages, apps, vars and utils as directories, and the framework
turns them into flake outputs for every supported system, wiring each one up
with `pkgs`, your flake inputs, your vars, the utils and each other.

## Getting started

Add the framework as an input and hand your outputs over to `mkFlake`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    framework.url = "github:allonsy/flake-framework";
  };

  outputs =
    { nixpkgs, framework, ... }:
    framework.mkFlake {
      nixpkgs = nixpkgs;
      frameworkDir = ./src;
    };
}
```

`mkFlake` takes:

| Argument       | Required | Description                                                         |
| -------------- | -------- | ------------------------------------------------------------------- |
| `nixpkgs`      | yes      | The nixpkgs flake to build `pkgs` from.                             |
| `frameworkDir` | yes      | The directory holding your packages, apps, vars and utils.          |
| `inputs`       | no       | Extra arguments for every package, app, vars and utils file. Meant mostly for other flakes you depend on, but any value works. See [Inputs](#inputs). |

and produces `packages`, `apps` and `formatter` outputs for `x86_64-linux`,
`aarch64-linux` and `aarch64-darwin`.

## The framework directory

`frameworkDir` is a path, relative to your `flake.nix`, laid out like this:

```
src/
├── packages/        required
│   ├── hello/
│   │   └── default.nix
│   └── home/
│       └── default.nix
├── apps/            optional
│   └── greet/
│       └── default.nix
├── vars/            optional
│   └── default.nix
└── utils/           optional
    └── default.nix
```

Use `./.` to keep these directories next to `flake.nix`, or point at a
subdirectory such as `./src` or `./nix` to keep them apart from the rest of
your repository. As with any flake, files have to be tracked by git to be
seen.

Every `default.nix` in it is a function taking an attribute set of arguments.
Take the ones you need and end the argument list with `...`, since the set
holds more than any one file uses.

## Arguments

Everything the framework evaluates for a system is called with:

| Argument | Description                                                      |
| -------- | ---------------------------------------------------------------- |
| `pkgs`   | nixpkgs for the current system, with `allowUnfree` enabled.      |
| `lib`    | `pkgs.lib`.                                                      |
| `stdenv` | `pkgs.stdenv`.                                                   |
| `system` | The system being built, such as `"x86_64-linux"`.                |
| ...      | Every attribute of the `inputs` given to `mkFlake`.              |

On top of those, utils also get `vars` and the framework's default `utils`,
and packages and apps get `vars`, the final `utils`, and every package by
name. The table below sums it up:

| File                  | Base arguments | `vars` | `utils`  | Packages |
| --------------------- | -------------- | ------ | -------- | -------- |
| `vars/default.nix`    | yes            |        |          |          |
| `utils/default.nix`   | yes            | yes    | defaults |          |
| `packages/*/...`      | yes            | yes    | merged   | yes      |
| `apps/*/...`          | yes            | yes    | merged   | yes      |

Arguments are merged in that order, so a later one shadows an earlier one with
the same name: an input called `system` replaces the real `system`, and a
package called `utils` replaces the utils. Avoid those names.

## Inputs

`inputs` is how things from outside your flake reach your packages. It is
mainly meant for the other flakes you depend on. Each attribute becomes an
argument of its own:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    framework.url = "github:allonsy/flake-framework";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, framework, home-manager, ... }:
    framework.mkFlake {
      nixpkgs = nixpkgs;
      frameworkDir = ./src;
      inputs = {
        home-manager = home-manager;
      };
    };
}
```

```nix
# src/packages/tools/default.nix
{ pkgs, system, home-manager, ... }:
pkgs.buildEnv {
  name = "tools";
  paths = [
    pkgs.git
    home-manager.packages.${system}.home-manager
  ];
}
```

To pass all of your flake's inputs at once, write
`outputs = { nixpkgs, framework, ... }@inputs:` and `inputs = inputs;`.

Any value works as an input, not just a flake. That includes non-flake
sources (`flake = false`), paths, strings and functions. Non-flake sources are
a good use for this, such as a file outside the repository that differs per
machine:

```nix
# flake.nix
inputs.hostname = {
  url = "path:/etc/nix-hostname";
  flake = false;
};
# ...
inputs = {
  hostInput = hostname;
};
```

```nix
# src/packages/shell/default.nix
{ pkgs, hostInput, ... }:
if import hostInput == "nyx" then pkgs.zsh else pkgs.fish
```

Fixed values, such as names, ports and flags, usually belong in
[vars](#vars) instead. Vars live in the framework directory next to the code
that uses them, can be computed per system, and keep `flake.nix` down to
wiring. None of this is enforced, so organize things however suits your flake.

## Packages

Every directory under `packages/` becomes a package named after it, so
`packages/hello/default.nix` is `packages.<system>.hello`. Files directly in
`packages/` are ignored.

A package returns a derivation:

```nix
# src/packages/hello/default.nix
{ pkgs, ... }:
pkgs.hello
```

Packages can depend on each other by taking one another as arguments:

```nix
# src/packages/home/default.nix
{ pkgs, hello, ... }:
pkgs.buildEnv {
  name = "home";
  paths = [
    hello
    pkgs.coreutils
  ];
}
```

Build them with `nix build .#home`.

## Apps

Every directory under `apps/` becomes an app named after it. An app gets the
same arguments as a package and returns an app definition:

```nix
# src/apps/greet/default.nix
{ pkgs, hello, ... }:
{
  type = "app";
  program = "${hello}/bin/hello";
}
```

Run it with `nix run .#greet`.

The framework adds a `new` app of its own, which takes precedence over one of
yours with the same name. It is currently a placeholder.

## Vars

`vars/default.nix` returns an attribute set of values to share across your
packages, apps and utils as `vars`. It is evaluated once per system and gets
the base arguments, so a var can depend on the system or on an input:

```nix
# src/vars/default.nix
{ system, ... }:
{
  isLinux = system == "x86_64-linux" || system == "aarch64-linux";
  serviceName = "my-service";
}
```

```nix
# src/packages/debug-tools/default.nix
{ pkgs, vars, ... }:
pkgs.buildEnv {
  name = "debug-tools";
  paths = [ pkgs.git ] ++ (if vars.isLinux then [ pkgs.strace ] else [ ]);
}
```

Without a `vars/` directory, `vars` is an empty set.

## Utils

Every package and app is called with a `utils` argument. It holds the utils the
framework provides by default, with your flake's own `utils/` directory merged
over them, so you can add your own utils or replace a default one. Your
`utils/` directory is itself called with `utils` bound to the framework
defaults, so your utils can build on them:

```nix
# src/utils/default.nix
{ utils, vars, ... }:
{
  writeServiceConfig = file: utils.writeTemplate file { NAME = vars.serviceName; };
}
```

### Templating

`utils.writeTemplate` renders a template file into the store, and
`utils.renderTemplate` renders a template string into a string:

```nix
{ utils, vars, ... }:
utils.writeTemplate ./service.conf {
  NAME = vars.serviceName;
  PORT = 9090;
}
```

With `service.conf`:

```
name = {{ NAME }}
port = {{PORT}}
literal = \{{ NAME }}
```

rendering to a `service.conf` in the store:

```
name = my-service
port = 9090
literal = {{ NAME }}
```

The rules are the same for both functions:

- `{{ KEY }}` and `{{KEY}}` are the same placeholder; whitespace inside the
  braces is ignored.
- A `\` before a placeholder escapes it, leaving `{{ KEY }}` in the output
  verbatim.
- Values may be strings, integers, paths or derivations. Other types have no
  unambiguous string form, so convert them yourself.
- A key that is missing from the context is an error, as is a placeholder that
  does not contain exactly one key (`{{}}` or `{{ A B }}`). Nothing is
  silently passed through, so a typo fails the build instead of shipping.
- Interpolated values are not rescanned, so a value containing `{{ ... }}`
  stays as it is.

## Formatter

`formatter` is set to `nixfmt-tree` for every system, so `nix fmt` formats
your flake.

## Tests

`./test` checks the framework's default utils. `./fmt` formats the repository.
