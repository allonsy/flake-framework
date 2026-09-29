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

`utils.writeTemplate` renders a template file into the store. It is a thin
wrapper around nixpkgs' [`pkgs.replaceVars`](https://nixos.org/manual/nixpkgs/stable/#fun-replaceVars):

```nix
{ utils, vars, ... }:
utils.writeTemplate ./service.conf {
  NAME = vars.serviceName;
  PORT = "9090";
}
```

With `service.conf`:

```
name = @NAME@
port = @PORT@
```

rendering to a `service.conf` in the store:

```
name = my-service
port = 9090
```

The rules are `replaceVars`':

- A placeholder is `@KEY@`, where the key starts with a letter or `_` and
  continues with letters, digits, `_`, `'` or `-`.
- Values are strings, paths or derivations; convert anything else yourself.
- A placeholder in the file with no value, or a value that matches no
  placeholder, fails the build. Nothing is silently passed through, so a typo
  does not ship.
- There is no escape syntax. To keep a literal `@KEY@` in the output, pass
  `null` as that key's value.

## Profile manager

The framework can add a `profileManager` package that installs `bin/nprofile`,
a script for managing your flake as a single Nix "monoprofile". Build the flake
into one package (say `default`), and `nprofile` keeps a `current` link to the
latest build, keeps older builds around to roll back to, and roots them all so
garbage collection leaves them alone.

It is optional. Set both of these in your [vars](#vars) to turn it on:

```nix
# src/vars/default.nix
_: {
  FRAMEWORK_BUILD_DIR = "/home/me/nix";
  FRAMEWORK_PROFILE_DIR = "/system";
}
```

| Var                     | Description                                                       |
| ----------------------- | ----------------------------------------------------------------- |
| `FRAMEWORK_BUILD_DIR`   | The directory holding your flake. `nprofile update` builds `.` there. |
| `FRAMEWORK_PROFILE_DIR` | Where profile links are kept, such as `/system`.                  |

If either is missing, no package is added. Once on, `profileManager` is
`packages.<system>.profileManager` and is also passed to your other packages
and apps by name, so it can be included in your profile like any other
package. A package of your own called `profileManager` is replaced by it.

### Usage

```
nprofile <command> [args]

Commands:
  provision           Create /nix/var/nix/gcroots/auto/system (needs root),
                      where update registers a GC root for each previous profile
  update              Build the flake and point $FRAMEWORK_PROFILE_DIR/current
                      at the result
  clean               Remove every link in $FRAMEWORK_PROFILE_DIR except current
  rollback [name]     Replace current with the newest other link, or with the
                      link called <name> (e.g. 2026_09_09_12_12_12)
```

Running it with no command prints the usage.

- **`provision`** creates `/nix/var/nix/gcroots/auto/system`. Run it once per
  machine, before the first `update`. `update` and `rollback` refuse to run
  until it exists.
- **`update`** runs `nix build .` in `FRAMEWORK_BUILD_DIR` and points
  `current` at the result. If there was already a `current`, it is first copied
  to a link named after the time, such as `2026_09_09_12_12_12`, so that build
  stays available.
- **`clean`** deletes every link directly inside `FRAMEWORK_PROFILE_DIR` except
  `current`. It does not recurse, and anything that is not a link is skipped
  with a warning.
- **`rollback`** copies the newest link (by creation time) other than
  `current` over `current`. Give it a name to pick a specific link instead. The
  link it copies from is kept, so running it again picks the same one; pass
  a name to go further back. The build that was `current` is not kept.

Every link is registered as a GC root under
`/nix/var/nix/gcroots/auto/system`, along with `current` itself, so
`nix store gc` keeps what they point to. Nix drops a root once its link is
gone, which is how `clean` frees old builds: there is nothing to prune by hand.

`nprofile` only asks for `sudo` when the directory it writes to is not
writable by you: `FRAMEWORK_PROFILE_DIR`, or the GC root directory for
`provision`. The GC root directory is normally root-owned, so in practice
`update` and `rollback` will need `sudo` unless you have changed its ownership.

## Formatter

`formatter` is set to `nixfmt-tree` for every system, so `nix fmt` formats
your flake.

## Development

`./fmt` formats the repository.
