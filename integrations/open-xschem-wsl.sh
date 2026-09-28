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

# IHP ngspice: ~/.spiceinit uses $PDK_ROOT/$PDK for .lib and osdi paths.
if [[ -z "${PDK_ROOT:-}" ]]; then
  for _pdk_root in \
    "/mnt/c/Work/IHP" \
    "$HOME/IHP-Open-PDK" \
    "/mnt/c/Users/anton/Documents/IHP-Open-PDK"; do
    if [[ -d "${_pdk_root}/ihp-sg13g2/libs.tech/ngspice/models" ]]; then
      PDK_ROOT="$(readlink -f "$_pdk_root" 2>/dev/null || echo "$_pdk_root")"
      export PDK_ROOT
      break
    fi
  done
fi
export PDK="${PDK:-ihp-sg13g2}"

# Mirror tiny PDK tree (models + osdi + xschem) into native WSL ext4 (~6MB).
# Avoids slow /mnt/c/9p I/O during ngspice and symbol lookup.
sync_ihp_pdk_native_cache() {
  local cache="${IH_PDK_NATIVE_CACHE:-$HOME/.cache/ihp-pdk-wsl}"
  local models_src=""
  local osdi_src=""
  local xschem_src=""

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

  mkdir -p "$cache/ihp-sg13g2/libs.tech/ngspice/models" \
           "$cache/ihp-sg13g2/libs.tech/ngspice/osdi" \
           "$cache/ihp-sg13g2/libs.tech/xschem"
  if [[ -n "$models_src" ]]; then
    rsync -a --size-only "$models_src/" "$cache/ihp-sg13g2/libs.tech/ngspice/models/"
  fi
  if [[ -n "$osdi_src" ]]; then
    rsync -a --size-only "$osdi_src/" "$cache/ihp-sg13g2/libs.tech/ngspice/osdi/"
  fi
  if [[ -n "$xschem_src" ]]; then
    rsync -a --size-only "$xschem_src/" "$cache/ihp-sg13g2/libs.tech/xschem/"
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
  local -a arr
  if [[ "$raw" == *";"* ]]; then
    IFS=';' read -r -a arr <<< "$raw"
  else
    IFS=':' read -r -a arr <<< "$raw"
  fi
  printf '%s\n' "${arr[@]}"
}

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
      ROOM_PRIMITIVE_LIBS="$(IFS=':'; echo "${_converted[*]}")"
      export ROOM_PRIMITIVE_LIBS
      export ROOM_PRIMITIVE_LIB="${_converted[0]}"
      unset ROOM_PRIMITIVE_LIBS_FILE
    fi
  fi
fi

if [[ -n "${ROOM_PRIMITIVE_LIBS:-}" ]]; then
  _converted=()
  while IFS= read -r _p; do
    _p="$(normalize_primitive_path "$_p" || true)"
    [[ -z "$_p" ]] && continue
    _converted+=("$_p")
  done < <(split_primitive_libs "$ROOM_PRIMITIVE_LIBS")
  ROOM_PRIMITIVE_LIBS="$(IFS=':'; echo "${_converted[*]}")"
  export ROOM_PRIMITIVE_LIBS
  if [[ ${#_converted[@]} -gt 0 ]]; then
    export ROOM_PRIMITIVE_LIB="${_converted[0]}"
  fi
elif [[ -n "${ROOM_PRIMITIVE_LIB:-}" ]]; then
  export ROOM_PRIMITIVE_LIB="$(wsl_path_if_windows "$ROOM_PRIMITIVE_LIB")"
fi

if [[ -n "${ROOM_PRIMITIVE_LIB:-}" || -n "${ROOM_PRIMITIVE_LIBS:-}" ]]; then
  export XSCHEM_PRIMITIVE_CACHE="${XSCHEM_PRIMITIVE_CACHE:-$HOME/.cache/libman-xschem/primitives}"
  mkdir -p "$XSCHEM_PRIMITIVE_CACHE"
fi

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <sch|sym|schematic.room|symbol.room>" >&2
  exit 1
fi

if [[ ! -f "$XSCHEM_RC" ]]; then
  echo "xschemrc not found: $XSCHEM_RC" >&2
  echo "Set XSCHEM_ROOT or XSCHEM_RC if the repo is not next to this script." >&2
  exit 1
fi

INPUT="$1"

LAUNCH_LOG="${XSCHEM_LAUNCH_LOG:-${TMPDIR:-/tmp}/xschem-libman-launch.log}"
log_launch() {
  printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" >>"$LAUNCH_LOG"
}
log_launch "argv: $*"

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
export GDK_BACKEND="${GDK_BACKEND:-wayland,x11}"

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

# Must exec (foreground): if we background and exit, WSL tears down the session and
# kills xschem before the window appears. open-xschem-wsl.bat uses "start /b wsl"
# so this process stays detached from LibMan while wsl remains alive.
cd "$XSCHEM_NETLIST_DIR"
exec "$XSCHEM_BIN" --rcfile "$XSCHEM_RC" >>"$LAUNCH_LOG" 2>&1
