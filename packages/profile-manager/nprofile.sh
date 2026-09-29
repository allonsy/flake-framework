#!/usr/bin/env bash

set -euo pipefail

BUILD_DIR=@buildDir@
SYSTEM_DIR=@profileDir@
GC_ROOT_DIR=/nix/var/nix/gcroots/auto/system

usage() {
  cat <<USAGE
Usage: nprofile <command> [args]

Commands:
  provision           Create $GC_ROOT_DIR (needs root), where
                      update registers a GC root for each previous profile
  update              Build the flake and point $SYSTEM_DIR/current at the result
  clean               Remove every link in $SYSTEM_DIR except current
  rollback [name]     Replace current with the newest other link, or with the
                      link called <name> (e.g. 2026_09_09_12_12_12)
USAGE
}

# Only elevate when the given dir (or the nearest existing parent, since we
# create it if missing) can't be written by the current user.
require_writable() {
  local dir="$1"
  local target="$dir"
  while [ ! -e "$target" ]; do
    target=$(dirname "$target")
  done

  if [ ! -w "$target" ] && [ "$(id -u)" -ne 0 ]; then
    echo "$dir is not writable by $(id -un), please run with sudo" >&2
    exit 1
  fi
}

require_provisioned() {
  if [ ! -d "$GC_ROOT_DIR" ]; then
    echo "$GC_ROOT_DIR does not exist, please run: sudo nprofile provision" >&2
    exit 1
  fi
}

root_current() {
  ln -sfn "$SYSTEM_DIR/current" "$GC_ROOT_DIR/current"
}

cmd_provision() {
  mkdir -p "$GC_ROOT_DIR"
  echo "provisioned $GC_ROOT_DIR"
}

cmd_update() {
  require_provisioned

  mkdir -p "$SYSTEM_DIR"
  cd "$BUILD_DIR"

  nix build '.'
  local new_root
  new_root=$(readlink result)
  echo "new root is: $new_root"

  if [ -e "$SYSTEM_DIR/current" ]; then
    local timestamp
    timestamp=$(date '+%Y_%m_%d_%H_%M_%S')
    cp -d "$SYSTEM_DIR/current" "$SYSTEM_DIR/$timestamp"
    ln -s "$SYSTEM_DIR/$timestamp" "$GC_ROOT_DIR/"
  fi

  ln -sfn "$new_root" "$SYSTEM_DIR/current"
  root_current
}

cmd_clean() {
  local entry
  for entry in "$SYSTEM_DIR"/*; do
    [ "$(basename "$entry")" = current ] && continue
    if [ -L "$entry" ]; then
      rm -f "$entry"
      echo "removed $entry"
    elif [ -e "$entry" ]; then
      echo "skipping $entry: not a link" >&2
    fi
  done
}

# Newest link (by modification time of the link itself) that isn't current.
latest_link() {
  local name
  for name in $(ls -1t "$SYSTEM_DIR"); do
    [ "$name" = current ] && continue
    if [ -L "$SYSTEM_DIR/$name" ]; then
      echo "$name"
      return 0
    fi
  done
  return 1
}

cmd_rollback() {
  local name
  if [ $# -ge 1 ]; then
    name="$1"
    case "$name" in
      current | */*)
        echo "invalid link name: $name" >&2
        exit 1
        ;;
    esac
    if [ ! -L "$SYSTEM_DIR/$name" ]; then
      echo "no such link: $SYSTEM_DIR/$name" >&2
      exit 1
    fi
  else
    name=$(latest_link) || {
      echo "nothing to roll back to in $SYSTEM_DIR" >&2
      exit 1
    }
  fi

  require_provisioned

  # copy, not move, so the link (and its GC root) stays valid; rm first so cp
  # -d replaces the link itself instead of writing through it
  rm -f "$SYSTEM_DIR/current"
  cp -d "$SYSTEM_DIR/$name" "$SYSTEM_DIR/current"
  root_current
  echo "rolled back to $name"
}

if [ $# -lt 1 ]; then
  usage >&2
  exit 1
fi

command="$1"
shift

case "$command" in
  provision)
    require_writable "$GC_ROOT_DIR"
    cmd_provision
    ;;
  update)
    require_writable "$SYSTEM_DIR"
    cmd_update
    ;;
  clean)
    require_writable "$SYSTEM_DIR"
    cmd_clean
    ;;
  rollback)
    require_writable "$SYSTEM_DIR"
    cmd_rollback "$@"
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    echo "unknown command: $command" >&2
    usage >&2
    exit 1
    ;;
esac
