#!/usr/bin/env bash
# Bundle non-system shared libraries for one or more binaries via ldd.
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "Usage: $0 <stage_lib_dir> <binary> [binary...]" >&2
  exit 1
fi

STAGE_LIB="$1"
shift
mkdir -p "$STAGE_LIB"

bundle_skip_lib() {
  local base
  base="$(basename "$1")"
  case "$base" in
    ld-linux*|linux-vdso*|libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|libutil.so*|libresolv.so*|libnss_*|libgcc_s.so*|libstdc++.so*)
      return 0
      ;;
  esac
  return 1
}

bundle_copy_lib() {
  local lib="$1"
  [[ -n "$lib" && -f "$lib" ]] || return 0
  bundle_skip_lib "$lib" && return 0
  cp -Ln "$lib" "$STAGE_LIB/" 2>/dev/null || cp -L "$lib" "$STAGE_LIB/" || true
}

bundle_binary_libs() {
  local binary="$1"
  [[ -f "$binary" ]] || {
    echo "ERROR: binary not found: $binary" >&2
    exit 1
  }
  while IFS= read -r lib; do
    bundle_copy_lib "$lib"
  done < <(ldd "$binary" | awk '/=> \// {print $3}' | grep -v '^$' || true)
}

for binary in "$@"; do
  bundle_binary_libs "$binary"
done

echo "Bundled native libs for $# binaries into $STAGE_LIB"
