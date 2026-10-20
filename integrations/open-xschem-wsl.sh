#!/bin/bash
# Open a schematic/symbol view in Xschem (WSL).
# Called from Windows LibMan via open-xschem-wsl.bat
#
# Usage:
#   open-xschem-wsl.sh <windows-or-wsl-path>
#
# Paths: derived from this script's location (parent dir = Xschem repo root).
# Optional overrides: XSCHEM_ROOT, XSCHEM_HOME, XSCHEM_RC, COMMONDB_ROOT
#
# Tiny window (1x1 title bar only): corrupted ~/.xschem/geometry — remove
# lines with "1x1+" or set initial_geometry in xschemrc (already set in repo).

set -euo pipefail

export HOME="${HOME:-/home/$(whoami)}"
export PATH="$HOME/.local/bin:$PATH"

# Earliest wall-clock mark (before any /mnt/c probe).
_LAUNCH_T0="$(date +%s%3N 2>/dev/null || date +%s)"
LAUNCH_LOG="${XSCHEM_LAUNCH_LOG:-${TMPDIR:-/tmp}/xschem-libman-launch.log}"
export XSCHEM_LAUNCH_LOG="$LAUNCH_LOG"
log_launch() {
  printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >>"$LAUNCH_LOG"
}
log_timing() {
  local now label="$1"
  now="$(date +%s%3N 2>/dev/null || date +%s)"
  if [[ "$now" =~ ^[0-9]+$ && "${_LAUNCH_T0:-}" =~ ^[0-9]+$ ]]; then
    log_launch "timing ${label}: $((now - _LAUNCH_T0))ms"
  else
    log_launch "timing ${label}"
  fi
}
log_launch "script enter pid=$$"

# LibMan still exports the older CORE_* names.
if [[ -z "${ROOM_ROOT:-}" && -n "${CORE_ROOT:-}" ]]; then
  export ROOM_ROOT="$CORE_ROOT"
fi
if [[ -z "${ROOM_PRIMITIVE_LIBS_FILE:-}" && -n "${CORE_PRIMITIVE_LIBS_FILE:-}" ]]; then
  export ROOM_PRIMITIVE_LIBS_FILE="$CORE_PRIMITIVE_LIBS_FILE"
fi
if [[ -z "${ROOM_PRIMITIVE_LIBS:-}" && -n "${CORE_PRIMITIVE_LIBS:-}" ]]; then
  export ROOM_PRIMITIVE_LIBS="$CORE_PRIMITIVE_LIBS"
fi
if [[ -z "${ROOM_PRIMITIVE_LIB:-}" && -n "${CORE_PRIMITIVE_LIB:-}" ]]; then
  export ROOM_PRIMITIVE_LIB="$CORE_PRIMITIVE_LIB"
fi
if [[ -z "${XSCHEM_OPEN_ROOM:-}" && -n "${XSCHEM_OPEN_CORE:-}" ]]; then
  export XSCHEM_OPEN_ROOM="$XSCHEM_OPEN_CORE"
fi

export PDK="${PDK:-ihp-sg13g2}"

# Mirror tiny PDK tree into native WSL ext4. Never probe /mnt/c when cache is warm
# (each failed -d on 9p costs hundreds of ms).
sync_ihp_pdk_native_cache() {
  local cache="${IH_PDK_NATIVE_CACHE:-$HOME/.cache/ihp-pdk-wsl}"
  local models_dst="$cache/ihp-sg13g2/libs.tech/ngspice/models"
  local osdi_dst="$cache/ihp-sg13g2/libs.tech/ngspice/osdi"
  local force="${FORCE_PDK_SYNC:-0}"

  if [[ "$force" != "1" \
      && -d "$models_dst" && -n "$(ls -A "$models_dst" 2>/dev/null || true)" \
      && -d "$osdi_dst" && -n "$(ls -A "$osdi_dst" 2>/dev/null || true)" ]]; then
    export PDK_ROOT="$cache"
    export PDK=ihp-sg13g2
    return 0
  fi

  local models_src="" osdi_src="" xschem_src=""
  for _root in "/mnt/c/Work/IHP" "$HOME/IHP-Open-PDK" "/mnt/c/Users/anton/Documents/IHP-Open-PDK"; do
    if [[ -z "$models_src" && -d "${_root}/ihp-sg13g2/libs.tech/ngspice/models" ]]; then
      models_src="${_root}/ihp-sg13g2/libs.tech/ngspice/models"
    fi
    if [[ -z "$osdi_src" && -d "${_root}/ihp-sg13g2/libs.tech/ngspice/osdi" ]]; then
      osdi_src="${_root}/ihp-sg13g2/libs.tech/ngspice/osdi"
    fi
    if [[ -z "$xschem_src" && -d "${_root}/ihp-sg13g2/libs.tech/xschem" ]]; then
      xschem_src="${_root}/ihp-sg13g2/libs.tech/xschem"
    fi
  done

  if [[ -z "$models_src" && -z "$osdi_src" ]]; then
    return 0
  fi

  mkdir -p "$models_dst" "$osdi_dst" "$cache/ihp-sg13g2/libs.tech/xschem"
  if [[ -n "$models_src" && ( "$force" == "1" || -z "$(ls -A "$models_dst" 2>/dev/null || true)" ) ]]; then
    rsync -a --size-only "$models_src/" "$models_dst/"
  fi
  if [[ -n "$osdi_src" && ( "$force" == "1" || -z "$(ls -A "$osdi_dst" 2>/dev/null || true)" ) ]]; then
    rsync -a --size-only "$osdi_src/" "$osdi_dst/"
  fi
  if [[ -n "$xschem_src" ]]; then
    local xschem_dst="$cache/ihp-sg13g2/libs.tech/xschem"
    if [[ "$force" == "1" || -z "$(ls -A "$xschem_dst" 2>/dev/null || true)" ]]; then
      rsync -a --size-only "$xschem_src/" "$xschem_dst/"
    fi
  fi

  export PDK_ROOT="$cache"
  export PDK=ihp-sg13g2
}

write_netlist_spiceinit() {
  local dir="$1"
  [[ -n "${PDK_ROOT:-}" && -d "$PDK_ROOT/$PDK/libs.tech/ngspice/models" ]] || return 0
  cat >"$dir/.spiceinit" <<EOF
* LibMan WSL — native PDK cache (fast ext4, not /mnt/c)
setcs sourcepath = ( $PDK_ROOT/$PDK/libs.tech/ngspice/models )
osdi '$PDK_ROOT/$PDK/libs.tech/ngspice/osdi/psp103.osdi'
osdi '$PDK_ROOT/$PDK/libs.tech/ngspice/osdi/psp103_nqs.osdi'
osdi '$PDK_ROOT/$PDK/libs.tech/ngspice/osdi/r3_cmc.osdi'
osdi '$PDK_ROOT/$PDK/libs.tech/ngspice/osdi/mosvar.osdi'
EOF
}

sync_ihp_pdk_native_cache

# Keep netlists/raw files out of CommonDB payload; one dir per LibMan launch.
export XSCHEM_NETLIST_DIR="${XSCHEM_NETLIST_DIR:-${TMPDIR:-/tmp}/libman-xschem-sim-$$}"
mkdir -p "$XSCHEM_NETLIST_DIR"
write_netlist_spiceinit "$XSCHEM_NETLIST_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XSCHEM_ROOT="${XSCHEM_ROOT:-${XSCHEM_HOME:-$(cd "$SCRIPT_DIR/.." && pwd)}}"
XSCHEM_RC="${XSCHEM_RC:-$XSCHEM_ROOT/xschemrc}"

LAUNCH_LOG="${XSCHEM_LAUNCH_LOG:-${TMPDIR:-/tmp}/xschem-libman-launch.log}"
export XSCHEM_LAUNCH_LOG="$LAUNCH_LOG"
log_launch() {
  printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >>"$LAUNCH_LOG"
}

# Mirror xschemrc + integrations onto native WSL ext4. Sourcing Tcl and loading
# roomtcl.so from /mnt/c (9p) is a large part of the 20–40s LibMan open time.
sync_xschem_native_tree() {
  case "$XSCHEM_ROOT" in
    /mnt/*) ;;
    *) return 0 ;;
  esac

  local cache="${XSCHEM_NATIVE_CACHE:-$HOME/.cache/libman-xschem/tree}"
  mkdir -p "$cache/integrations"

  # Prefer cheap updates of the hot path (room.tcl / roomtcl.so / xschemrc).
  # Text files: strip CR only (never delete letter "r" — bash tr -d "\r" is unsafe).
  sync_file_if_newer() {
    local src="$1" dst="$2"
    [[ -f "$src" ]] || return 0
    case "$src" in
      *.so|*.dll|*.dylib)
        if [[ -f "$dst" ]]; then
          local ss sd
          ss="$(stat -c '%s' "$src" 2>/dev/null || echo 0)"
          sd="$(stat -c '%s' "$dst" 2>/dev/null || echo 1)"
          if [[ "$ss" == "$sd" && ! "$src" -nt "$dst" ]]; then
            return 0
          fi
        fi
        cp -f "$src" "$dst"
        return 0
        ;;
    esac
    # Warm path: do NOT read src from /mnt/c (9p) every launch — that alone was ~5s.
    # Only refresh when forced, missing, has CR, or missing critical tokens.
    if [[ -f "$dst" && "${FORCE_XSCHEM_TREE_SYNC:-0}" != "1" ]]; then
      if ! grep -q $'\r' "$dst" 2>/dev/null; then
        case "$(basename "$dst")" in
          xschemrc)
            grep -q 'room_payload_dir' "$dst" 2>/dev/null && return 0
            ;;
          room.tcl)
            grep -q 'proc room_materialize_symbol' "$dst" 2>/dev/null && return 0
            ;;
          *.sh|*.tcl|*.rc) return 0 ;;
        esac
      fi
    fi
    # Tcl text: strip CR only (never `tr -d "\r"` — that deletes letter r in bash).
    python3 - "$src" "$dst" <<'PY'
import pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
data = src.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
if dst.is_file() and dst.read_bytes() == data:
    raise SystemExit(0)
dst.write_bytes(data)
PY
  }
  sync_file_if_newer "$XSCHEM_ROOT/xschemrc" "$cache/xschemrc"
  sync_file_if_newer "$XSCHEM_ROOT/integrations/room.tcl" "$cache/integrations/room.tcl"
  sync_file_if_newer "$XSCHEM_ROOT/integrations/room_lock.tcl" "$cache/integrations/room_lock.tcl"
  sync_file_if_newer "$XSCHEM_ROOT/integrations/roomtcl.so" "$cache/integrations/roomtcl.so"
  sync_file_if_newer "$XSCHEM_ROOT/integrations/coretcl.so" "$cache/integrations/coretcl.so"

  if [[ -f "$cache/xschemrc" && -f "$cache/integrations/room.tcl" ]]; then
    XSCHEM_ROOT="$cache"
    XSCHEM_RC="$cache/xschemrc"
  fi
}

_t0="$(date +%s%3N 2>/dev/null || date +%s)"
log_timing() {
  local now label="$1"
  now="$(date +%s%3N 2>/dev/null || date +%s)"
  if [[ "$now" =~ ^[0-9]+$ && "$_t0" =~ ^[0-9]+$ ]]; then
    log_launch "timing ${label}: $((now - _t0))ms"
  else
    log_launch "timing ${label}"
  fi
}

export XSCHEM_ROOT
if [[ -n "${COMMONDB_ROOT:-}" ]]; then
  export COMMONDB_ROOT
fi

wsl_path_if_windows() {
  local p="$1"
  if [[ "$p" =~ ^[A-Za-z]:[/\\] ]]; then
    if command -v wslpath >/dev/null 2>&1; then
      wslpath -u "$p"
      return
    fi
  fi
  printf '%s' "$p"
}

normalize_primitive_path() {
  local _p="$1"
  _p="$(echo "$_p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$_p" ]] && return 1
  if [[ "$_p" =~ ^[A-Za-z]:[/\\] ]]; then
    _p="$(wsl_path_if_windows "$_p")"
  fi
  printf '%s' "$_p"
}

split_primitive_libs() {
  local raw="$1"
  local -a ar
  if [[ "$raw" == *";"* ]]; then
    IFS=';' read -r -a arr <<< "$raw"
  else
    IFS=':' read -r -a arr <<< "$raw"
  fi
  printf '%s\n' "${arr[@]}"
}

# Copy .symbol.room (+ sibling .emmodel.room) onto ext4 so Tcl index / Cap'n Proto
# loads do not walk 100+ files over 9p on every open.
stage_primitive_room_list() {
  local -a srcs=("$@")
  local cache="${XSCHEM_ROOM_SOURCE_CACHE:-$HOME/.cache/libman-xschem/room_sources}"
  mkdir -p "$cache"
  local -a staged=()
  local src dst rel em
  local copied=0 skipped=0
  for src in "${srcs[@]}"; do
    [[ -f "$src" ]] || continue
    rel="${src#/mnt/}"
    if [[ "$rel" == "$src" ]]; then
      rel="local/$(basename "$(dirname "$src")")/$(basename "$src")"
    fi
    dst="$cache/$rel"
    mkdir -p "$(dirname "$dst")"
    # Warm path: trust ext4 cache — do NOT stat src on /mnt/c (9p) every launch.
    # Refresh only when forced or destination missing.
    if [[ -f "$dst" && "${FORCE_ROOM_SOURCE_SYNC:-0}" != "1" ]]; then
      skipped=$((skipped + 1))
    else
      if cp -f "$src" "$dst" 2>/dev/null; then
        copied=$((copied + 1))
        em="${src%.symbol.room}.emmodel.room"
        if [[ -f "$em" ]]; then
          cp -f "$em" "${dst%.symbol.room}.emmodel.room" 2>/dev/null || true
        fi
        em="${src%.symbol.core}.emmodel.core"
        if [[ -f "$em" ]]; then
          cp -f "$em" "${dst%.symbol.core}.emmodel.core" 2>/dev/null || true
        fi
      else
        staged+=("$src")
        continue
      fi
    fi
    staged+=("$dst")
  done
  if [[ ${#staged[@]} -gt 0 ]]; then
    log_launch "staged primitive ROOMs: ${#staged[@]} (copied=$copied skipped=$skipped) -> $cache"
    printf '%s\n' "${staged[@]}"
  fi
}

_ROOM_LIBS_STAGED=0
if [[ -n "${ROOM_PRIMITIVE_LIBS_FILE:-}" ]]; then
  _list_file="$(wsl_path_if_windows "$ROOM_PRIMITIVE_LIBS_FILE")"
  if [[ -f "$_list_file" ]]; then
    _converted=()
    while IFS= read -r _p || [[ -n "$_p" ]]; do
      _p="$(normalize_primitive_path "$_p" || true)"
      [[ -z "$_p" ]] && continue
      _converted+=("$_p")
    done < "$_list_file"
    if [[ ${#_converted[@]} -gt 0 ]]; then
      # log_launch not defined yet on --warm early path; define a no-op fallback.
      if ! declare -F log_launch >/dev/null 2>&1; then
        log_launch() { :; }
      fi
      mapfile -t _converted < <(stage_primitive_room_list "${_converted[@]}")
      ROOM_PRIMITIVE_LIBS="$(IFS=':'; echo "${_converted[*]}")"
      export ROOM_PRIMITIVE_LIBS
      export ROOM_PRIMITIVE_LIB="${_converted[0]}"
      unset ROOM_PRIMITIVE_LIBS_FILE
      _ROOM_LIBS_STAGED=1
    fi
  fi
fi

# Skip re-stage when FILE path already produced ROOM_PRIMITIVE_LIBS (was ~2s twice).
if [[ "$_ROOM_LIBS_STAGED" -eq 0 && -n "${ROOM_PRIMITIVE_LIBS:-}" ]]; then
  _converted=()
  while IFS= read -r _p; do
    _p="$(normalize_primitive_path "$_p" || true)"
    [[ -z "$_p" ]] && continue
    _converted+=("$_p")
  done < <(split_primitive_libs "$ROOM_PRIMITIVE_LIBS")
  if ! declare -F log_launch >/dev/null 2>&1; then
    log_launch() { :; }
  fi
  if [[ ${#_converted[@]} -gt 0 ]]; then
    mapfile -t _converted < <(stage_primitive_room_list "${_converted[@]}")
  fi
  ROOM_PRIMITIVE_LIBS="$(IFS=':'; echo "${_converted[*]}")"
  export ROOM_PRIMITIVE_LIBS
  if [[ ${#_converted[@]} -gt 0 ]]; then
    export ROOM_PRIMITIVE_LIB="${_converted[0]}"
  fi
elif [[ "$_ROOM_LIBS_STAGED" -eq 0 && -n "${ROOM_PRIMITIVE_LIB:-}" ]]; then
  export ROOM_PRIMITIVE_LIB="$(wsl_path_if_windows "$ROOM_PRIMITIVE_LIB")"
fi

if [[ -n "${ROOM_PRIMITIVE_LIB:-}" || -n "${ROOM_PRIMITIVE_LIBS:-}" ]]; then
  export XSCHEM_PRIMITIVE_CACHE="${XSCHEM_PRIMITIVE_CACHE:-$HOME/.cache/libman-xschem/primitives}"
  mkdir -p "$XSCHEM_PRIMITIVE_CACHE"
fi

# Warm-only path: bring the WSL2 VM up and refresh native caches without opening Xschem.
if [[ "${1:-}" == "--warm" ]]; then
  LAUNCH_LOG="${XSCHEM_LAUNCH_LOG:-${TMPDIR:-/tmp}/xschem-libman-launch.log}"
  log_launch() {
    printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >>"$LAUNCH_LOG"
  }
  log_launch "warm start"
  sync_xschem_native_tree
  export XSCHEM_ROOT
  log_launch "warm tree XSCHEM_ROOT=$XSCHEM_ROOT PDK_ROOT=${PDK_ROOT:-}"

  # Also prime WSLg + xschem process path so the first interactive open is shorter.
  export DISPLAY="${DISPLAY:-:0}"
  export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}"
  export GDK_BACKEND="${GDK_BACKEND:-x11}"
  XSCHEM_BIN=""
  if command -v xschem >/dev/null 2>&1; then
    XSCHEM_BIN="$(command -v xschem)"
  elif [[ -x "$HOME/.local/bin/xschem" ]]; then
    XSCHEM_BIN="$HOME/.local/bin/xschem"
  fi
  if [[ -n "$XSCHEM_BIN" && -f "${XSCHEM_RC:-}" ]]; then
    log_launch "warm xschem -q via $XSCHEM_BIN"
    timeout 15s "$XSCHEM_BIN" --rcfile "$XSCHEM_RC" -q >>"$LAUNCH_LOG" 2>&1 || true
  else
    log_launch "warm skip xschem (bin='${XSCHEM_BIN:-}' rc='${XSCHEM_RC:-}')"
  fi
  log_launch "warm done"
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <sch|sym|schematic.room|symbol.room>|--warm" >&2
  exit 1
fi

INPUT="$1"

LAUNCH_LOG="${XSCHEM_LAUNCH_LOG:-${TMPDIR:-/tmp}/xschem-libman-launch.log}"
log_launch() {
  printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >>"$LAUNCH_LOG"
}
log_launch "argv: $*"
sync_xschem_native_tree
export XSCHEM_ROOT
log_launch "XSCHEM_ROOT=$XSCHEM_ROOT XSCHEM_RC=$XSCHEM_RC"
log_timing "after native tree sync"

if [[ ! -f "$XSCHEM_RC" ]]; then
  echo "xschemrc not found: $XSCHEM_RC" >&2
  echo "Set XSCHEM_ROOT or XSCHEM_RC if the repo is not next to this script." >&2
  exit 1
fi

# If LibMan passed a Windows path, normalize to WSL (/mnt/c/...).
if [[ "$INPUT" =~ ^/mnt/ ]]; then
  :
elif [[ "$INPUT" =~ ^[A-Za-z]:[/\\] ]]; then
  if command -v wslpath >/dev/null 2>&1; then
    INPUT="$(wslpath -u "$INPUT")"
  else
    drive="${INPUT:0:1}"
    rest="${INPUT:2}"
    rest="${rest//\\//}"
    INPUT="/mnt/${drive,,}/${rest}"
  fi
elif [[ "$INPUT" =~ ^[A-Za-z]: ]]; then
  # Backslashes are often stripped when argv crosses wsl.exe from Windows Qt.
  drive="${INPUT:0:1}"
  rest="${INPUT:2}"
  rest="${rest//\\//}"
  INPUT="/mnt/${drive,,}/${rest}"
fi

INPUT="$(readlink -f "$INPUT" 2>/dev/null || realpath "$INPUT" 2>/dev/null || echo "$INPUT")"

if [[ ! -f "$INPUT" ]]; then
  echo "file not found: $INPUT" >&2
  log_launch "ERROR: file not found: $INPUT (raw argv: $1)"
  exit 1
fi

# Corrupted ~/.xschem/geometry hides the window (1x1, 0x0, off-screen coords).
# Also drop saved geometry for this file and ephemeral ROOM temp paths so
# xschemrc initial_geometry {1300x950} applies on launch.
scrub_geometry_file() {
  local geom="${HOME}/.xschem/geometry"
  local target="${1:-}"
  [[ -f "$geom" ]] || return 0

  local tmp="${geom}.tmp"
  awk -v target="$target" '
    function bad_size(w, h) {
      return (w < 200 || h < 200)
    }
    function bad_position(pos) {
      return (pos ~ /\+-[0-9]+/ || pos ~ /\+[0-9]+\+-[0-9]+/)
    }
    {
      line = $0
      if (line ~ /1x1\+|0x0\+/) next
      if (index(line, "untitled") > 0) next
      if (target != "" && index(line, target) > 0) next
      if (index(line, "/tmp/xschem_room_") > 0) next
      if (match(line, /\{([0-9]+)x([0-9]+)([^}]*)\}/, sz)) {
        if (bad_size(sz[1], sz[2])) next
        if (bad_position(sz[3])) next
      }
      print line
    }
  ' "$geom" >"$tmp" && mv "$tmp" "$geom" || rm -f "$tmp"
}
scrub_geometry_file "$INPUT"

# WSLg: ensure GUI vars when launched from a GUI app (LibMan) without a login shell.
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}"
# X11 is typically snappier than Wayland under WSLg for Xschem.
export GDK_BACKEND="${GDK_BACKEND:-x11}"

ensure_wslg_display() {
  local disp="${DISPLAY#:}"
  if [[ -S "/tmp/.X11-unix/X${disp}" ]]; then
    return 0
  fi
  if [[ -S "/mnt/wslg/.X11-unix/X${disp}" ]]; then
    mkdir -p /tmp/.X11-unix
    ln -sf "/mnt/wslg/.X11-unix/X${disp}" "/tmp/.X11-unix/X${disp}" 2>/dev/null || true
    return 0
  fi
  if command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    return 0
  fi
  msg="WSLg/X11 display unavailable (DISPLAY=$DISPLAY, no X socket). Restart WSL: wsl --shutdown, then reopen LibMan."
  echo "$msg" >&2
  log_launch "ERROR: $msg"
  exit 125
}
ensure_wslg_display

resolve_xschem_bin() {
  if [[ -n "${XSCHEM_BIN:-}" && -x "$XSCHEM_BIN" ]]; then
    printf '%s' "$XSCHEM_BIN"
    return 0
  fi
  if command -v xschem >/dev/null 2>&1; then
    command -v xschem
    return 0
  fi
  if [[ -x "$HOME/.local/bin/xschem" ]]; then
    printf '%s' "$HOME/.local/bin/xschem"
    return 0
  fi
  return 1
}

XSCHEM_BIN="$(resolve_xschem_bin || true)"
if [[ -z "$XSCHEM_BIN" ]]; then
  msg="xschem not found in PATH or ~/.local/bin. Run: bash $XSCHEM_ROOT/build-xschem.sh"
  echo "$msg" >&2
  log_launch "ERROR: $msg"
  exit 127
fi
log_launch "starting $XSCHEM_BIN for $INPUT"
log_launch "DISPLAY=${DISPLAY:-} WAYLAND=${WAYLAND_DISPLAY:-} XDG=${XDG_RUNTIME_DIR:-}"
log_launch "PDK_ROOT=${PDK_ROOT:-} PDK=${PDK:-} netlist_dir=${XSCHEM_NETLIST_DIR:-}"
log_timing "before xschem exec"

case "$(basename "$INPUT")" in
  *.schematic.room|*.symbol.room|*.schematic.core|*.symbol.core)
    export XSCHEM_OPEN_ROOM="$INPUT"
    ;;
  *.sch|*.sym)
    export XSCHEM_OPEN_FILE="$INPUT"
    ;;
  *)
    echo "unsupported schematic view: $INPUT" >&2
    log_launch "ERROR: unsupported view $INPUT"
    exit 2
    ;;
esac

# LibMan always starts a fresh process. A previous LibMan xschem left running still
# holds the ROOM .lck → next open is read-only. Take over same-view sessions.
release_previous_libman_room_lock() {
  local room="$1"
  case "$(basename "$room")" in
    *.schematic.room|*.symbol.room|*.schematic.core|*.symbol.core) ;;
    *) return 0 ;;
  esac
  local lck="${room}.lck"
  [[ -f "$lck" ]] || return 0

  local pid=""
  pid="$(grep -oE '"pid"[[:space:]]*:[[:space:]]*[0-9]+' "$lck" 2>/dev/null | head -1 | grep -oE '[0-9]+$' || true)"
  if [[ -z "$pid" ]]; then
    rm -f "$lck"
    log_launch "removed unreadable ROOM lock: $lck"
    return 0
  fi

  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$lck"
    log_launch "removed stale ROOM lock (dead pid $pid)"
    return 0
  fi

  local cmd=""
  if [[ -r "/proc/$pid/cmdline" ]]; then
    cmd="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
  fi
  if [[ "$cmd" == *xschem* && ( "$cmd" == *libman-xschem* || "$cmd" == *XSchem-roomdb* || "$cmd" == *xschemrc* ) ]]; then
    log_launch "replacing previous LibMan xschem pid=$pid for $room"
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$lck"
    return 0
  fi

  log_launch "ROOM locked by live pid=$pid ($cmd); new session will be read-only"
}

release_previous_libman_room_lock "$INPUT"

# Must exec (foreground): if we background and exit, WSL tears down the session and
# kills xschem before the window appears. open-xschem-wsl.bat uses "start /b wsl"
# so this process stays detached from LibMan while wsl remains alive.
cd "$XSCHEM_NETLIST_DIR"
exec "$XSCHEM_BIN" --rcfile "$XSCHEM_RC" >>"$LAUNCH_LOG" 2>&1
