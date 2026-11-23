# Native ROOM parameters in Xschem

A ROOM-enabled editor opens a flat binary `.room` schematic directly in
memory. Open it from the file dialog, the command line or `xschem load`.
You can save an existing `value` on the standard resistor, capacitor and
inductor symbols (`res.sym`, `capa.sym`, `ind.sym`, with or without `devices/`).
Other attribute changes, structural changes, Save As and new ROOM files
are refused. Quote values with literal backslashes or double quotes and
escape those characters inside the quotes. A refused save leaves
the editor dirty and cancels the Open or Close operation that requested it.
Undo the unsupported edit to continue. Memory and disk undo are supported.
ROOM disk snapshots use 17 significant digits to preserve drawing coordinates.

Use a clean Xschem rcfile. The legacy `room.tcl` integration and this
native build are mutually exclusive. ROOM files need external flat device
symbols, using the ordinary Xschem symbol library search. JSON, hierarchy,
ROOM-local symbols, embedded and generated symbols are outside this path.

## Independent Linux review

Use a fresh directory for the builds, installed binaries and user
configuration. These commands assume both repositories are siblings.

```sh
P=/home/louis/Code/ihp-xschem-proto
V=$(mktemp -d "$P/build/parameters-review.XXXXXX")
cmake -S "$P/Room" -B "$V/room" -DCMAKE_BUILD_TYPE=Release \
  -DROOM_BOOTSTRAP_CAPNP=OFF -DCAPNP_ROOT=/usr -DROOM_BUILD_PYTHON=OFF \
  -DROOM_BUILD_XSCHEM_NATIVE=ON -DCMAKE_INSTALL_PREFIX="$V/install-room"
cmake --build "$V/room" -j8
cmake --install "$V/room"
ctest --test-dir "$V/room" -R '^xschem_native$' --output-on-failure

cp -a "$P/XSchem-roomdb/xschem-src" "$V/enabled"
(
  cd "$V/enabled"
  ./configure --prefix="$V/install-xschem" --user-conf-dir="$V/user-conf"
  make -j8 ROOM_PREFIX="$V/install-room"
  make install ROOM_PREFIX="$V/install-room"
)
python3 "$P/XSchem-roomdb/integrations/xschem_native/demo.py" \
  --room-prefix "$V/install-room" --xschem-prefix "$V/install-xschem" \
  --user-conf "$V/user-conf" --output "$V"
```

For disk and memory undo and special values, run `blockers.tcl` with
the enabled executable, the generated demo rcfile and `REVIEW_FILE`
pointing at a disposable copy of the demo's `.room` file. Review
failed Open, Save As, carriage returns and stale files with scripts
disabled. Observe filesystem writes to distinguish Xschem's undo
snapshots from a schematic working copy.

`minimal-regressions.tcl` checks the save scope, unquoted escape refusal
and high-precision arc undo. Run it in a fresh process per case with a
disposable `REVIEW_FILE`, `REVIEW_CASE` set to `scope`, `escape` or `precision`,
and `REVIEW_UNDO` set to `disk` or `memory` for `precision`. The fixture and
invocation details are in the implementation handoff `FIXES.md`.

Use a separate copy for the ordinary build and omit `ROOM_PREFIX`.
The makefile accepts `ROOM_PREFIX` only from the make command line.
Compare ordinary `.sch` behavior against `f97e81c` in both builds.
