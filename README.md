# XSchem-roomdb

Xschem workspace integrated with [ROOM](https://github.com/IHP-GmbH/Room) (CommonDB): open `.schematic.room` / `.symbol.room` in the editor, round-trip through `roomtcl.so`, and Qucs symbol placeholders for cross-tool schematics.

This repository is a standalone fork of the LibMan/Xschem integration layer plus a vendored [xschem](https://github.com/StefanSchippers/xschem) tree under `xschem-src/` (upstream `master`, **3.4.8RC**).

## Layout

| Path | Purpose |
|------|---------|
| `xschemrc` | Workspace config; loads `integrations/room.tcl` |
| `integrations/` | ROOM Tcl bridge (`room.tcl`), WSL launcher, `qucs_symbols/` |
| `xschem-src/` | Xschem sources (configure + make) |
| `build-xschem.sh` | Build/install xschem into `~/.local` (WSL) |
| `build-room-tcl.sh` | Build `integrations/roomtcl.so` from sibling **CommonDB** |

## Prerequisites

- **Linux** or **WSL2** (Windows hosts use `integrations/open-xschem-wsl.bat` from LibMan)
- **CommonDB** checkout as a sibling directory, e.g. `../CommonDB`
- Build tools: `cmake`, `g++`, `make`, `tcl-dev`, Cap'n Proto (bootstrapped automatically on first `build-room-tcl.sh` run)

## Quick start (WSL)

```bash
# 1. Clone both repos side by side
git clone https://github.com/adatsuk/XSchem-roomdb.git
git clone https://github.com/IHP-GmbH/Room.git CommonDB

# 2. Build xschem
cd XSchem-roomdb
bash build-xschem.sh

# 3. Build ROOM Tcl extension
bash build-room-tcl.sh

# 4. Open a ROOM schematic
export XSCHEM_RC=$PWD/xschemrc
xschem --rcfile "$XSCHEM_RC"
# Or pass a .schematic.room path via integrations/open-xschem-wsl.sh (LibMan)
```

Set `COMMONDB_ROOT` if CommonDB is not at `../CommonDB`.

## Coordinate scale

ROOM schematic views store integer DBU with `dbuPerEditorUnit` (Qucs = 1, Xschem = 1000). See [CommonDB coord scale docs](https://github.com/IHP-GmbH/Room/blob/main/docs/html/coordscale.html).

## CI

GitHub Actions (`.github/workflows/ci.yaml`) on **Rocky Linux 8** (RHEL 8 compatible):

- builds **xschem** and **roomtcl.so** (CommonDB checkout via `GH_PAT`)
- packages a portable **`xschem-rocky8`** tar.gz (artifact), runnable via `./xschem-run.sh`

Manual run: **Actions → CI → Run workflow**.

## License

Xschem is GPL-2.0 (see `xschem-src/COPYING`). Integration scripts and ROOM bridge follow the same workflow as the parent IHP stack; refer to upstream xschem and CommonDB for license details.
