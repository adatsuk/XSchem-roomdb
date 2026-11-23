#!/usr/bin/env python3
"""Independent reviewer entry point: direct ROOM open/netlist/edit/save/reopen.

Inputs and all generated files stay under the prototype workspace. Native .sch
and normal library .sym inputs are allowed; no working .sch/.sym may be created.
"""
import argparse
import ctypes
import json
import difflib
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def run(args, *, cwd, env):
    print('+', ' '.join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), cwd=cwd, env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    print(result.stdout, end='', flush=True)
    if result.returncode:
        raise RuntimeError(f'Command exited {result.returncode}')


def listing(roots):
    paths = set()
    for root in roots:
        if root.exists():
            for current, dirs, files in os.walk(root):
                for name in files:
                    if name.endswith(('.sch', '.sym')):
                        paths.add(str(Path(current) / name))
    return paths


def canonical(path):
    # Xschem includes the physical input path in this comment; all circuit lines remain exact.
    lines = [line for line in path.read_text().splitlines() if not line.lower().startswith('** sch_path:')]
    # Only anonymous netN tokens may be renamed, with one global bijection.
    names = {}
    def rename(match):
        token = match.group()
        if token not in names:
            names[token] = f'net{len(names) + 1}'
        return names[token]
    normalized = []
    for line in lines:
        tokens = list(re.finditer(r'\S+', line))
        # This fixed CMOS fixture uses MOSFETs (four nodes), resistors and sources
        # (two nodes). Never rename directive, model or parameter tokens.
        count = {'M': 4, 'R': 2, 'V': 2}.get(tokens[0].group()[0].upper(), 0) if tokens else 0
        for token in reversed(tokens[1:count + 1]):
            if re.fullmatch(r'net[0-9]+', token.group()):
                replacement = rename(token)
                line = line[:token.start()] + replacement + line[token.end():]
        normalized.append(line)
    return normalized


def snapshot(library, path):
    class String(ctypes.Structure):
        _fields_ = [('data', ctypes.c_void_p), ('size', ctypes.c_size_t)]
    class Record(ctypes.Structure):
        _fields_ = [('kind', ctypes.c_char), ('layer', ctypes.c_int),
                    ('rotation', ctypes.c_int), ('flip', ctypes.c_int),
                    ('values', ctypes.POINTER(ctypes.c_double)), ('count', ctypes.c_size_t),
                    ('text', String), ('attributes', String)]
    def text(value):
        return ctypes.string_at(value.data, value.size).decode()
    callback_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.POINTER(Record))
    library.rx_open.argtypes = [String, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_void_p)]
    library.rx_read.argtypes = [ctypes.c_void_p, callback_type, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
    library.rx_error_message.argtypes = [ctypes.c_void_p]
    library.rx_error_message.restype = String
    library.rx_error_free.argtypes = [ctypes.c_void_p]
    library.rx_close.argtypes = [ctypes.c_void_p]
    records = []
    @callback_type
    def receive(user, ptr):
        r = ptr.contents
        kind, attrs = r.kind.decode(), text(r.attributes)
        if kind in 'GKVSEF' and not attrs:
            return 1  # Optional empty globals have identical editor meaning.
        values = [round(r.values[i], 9) for i in range(r.count)]
        if kind in 'NL' and values[:2] > values[2:]:
            values = values[2:] + values[:2]
        if kind == 'v':
            attrs = attrs.rstrip()
        records.append(dict(kind=kind, layer=r.layer, rotation=r.rotation, flip=r.flip,
                            values=values, text=text(r.text), attributes=attrs))
        return 1
    def check(ok, error):
        if not ok:
            message = text(library.rx_error_message(error))
            library.rx_error_free(error)
            raise RuntimeError(message)
    encoded = str(path).encode()
    doc, error = ctypes.c_void_p(), ctypes.c_void_p()
    check(library.rx_open(String(ctypes.cast(ctypes.c_char_p(encoded), ctypes.c_void_p), len(encoded)),
                          ctypes.byref(doc), ctypes.byref(error)), error)
    try:
        check(library.rx_read(doc, receive, None, ctypes.byref(error)), error)
    finally:
        library.rx_close(doc)
    return sorted(records, key=lambda r: json.dumps(r, sort_keys=True))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--room-prefix', type=Path, required=True)
    p.add_argument('--xschem-prefix', type=Path, required=True)
    p.add_argument('--user-conf', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    room = args.room_prefix.resolve()
    xschem = args.xschem_prefix.resolve()
    binary = xschem / 'bin/xschem'
    converter = room / 'bin/xschem_to_room'
    source = Path(__file__).resolve().parents[2] / 'xschem-src/xschem_library/examples/cmos_inv.sch'
    work = args.output.resolve() / ('demo-' + str(time.time_ns()))
    work.mkdir()
    for name in ('native', 'room', 'tmp'):
        (work / name).mkdir()
    # No copied schematic is used by either editor invocation.
    env = dict(os.environ, TMPDIR=str(work / 'tmp'), PROTO_DEMO=str(work))
    env['PROTO_ROOM_FILE'] = str(work / 'cmos_inv.room')
    rc = work / 'prototype.rc'
    rc.write_text(f'''set XSCHEM_LIBRARY_PATH {{{xschem}/share/xschem/xschem_library/devices}}
set XSCHEM_TMP_DIR {{{work}/tmp}}
set xschem_execute_scripts no
set autotrim_wires 0
set keep_symbols 1
''')
    script = work / 'edit.tcl'
    script.write_text('''if {[catch {
  if {[info exists ::room_native_error]} { error $::room_native_error }
  set channel [open $::env(PROTO_ROOM_FILE) rb]
  set original [read $channel]
  close $channel
  xschem setprop instance R1 name FORBIDDEN
  set refused [catch {xschem save} diagnostic]
  set channel [open $::env(PROTO_ROOM_FILE) rb]
  set unchanged [read $channel]
  close $channel
  if {!$refused || $unchanged ne $original || ![xschem get modified] ||
      [xschem getprop instance FORBIDDEN name] ne "FORBIDDEN"} {
    error "forbidden rename did not retain original bytes and dirty editor edits"
  }
  puts "PASS forbidden rename refused; original byte-identical; editor edits retained"
  xschem load -force $::env(PROTO_ROOM_FILE)
  set before [xschem getprop instance R1 value]
  xschem setprop instance R1 value 12345
  xschem save
  if {[info exists ::room_native_error]} { error $::room_native_error }
  xschem load -force $::env(PROTO_ROOM_FILE)
  if {[info exists ::room_native_error]} { error $::room_native_error }
  set actual [xschem getprop instance R1 value]
  if {$actual ne "12345"} { error "reopened R1 value is $actual" }
  puts "PASS edit/save/reopen: R1 value $before -> $actual"
} message options]} {
  puts stderr $message
  puts stderr [dict get $options -errorinfo]
  exit 1
}
exit 0
''')
    run([converter, source, work / 'cmos_inv.room'], cwd=work, env=env)
    # Observe only this run and its configured editor locations: the corpus runs concurrently.
    watch = [work, args.user_conf.resolve()]
    before = listing(watch)
    library = ctypes.CDLL(str(room / 'lib/libroom_xschem.so'))
    original_objects = snapshot(library, work / 'cmos_inv.room')
    common = ['xvfb-run', '-a', binary, '-r', '--rcfile', rc, '--preinit', 'set xschem_execute_scripts no']
    run(common + ['-n', '-s', '-q', '-o', work / 'native', source], cwd=work, env=env)
    run(common + ['-n', '-s', '-q', '-o', work / 'room', work / 'cmos_inv.room'], cwd=work, env=env)
    a, b = canonical(work / 'native/cmos_inv.spice'), canonical(work / 'room/cmos_inv.spice')
    if a != b:
        print('\n'.join(difflib.unified_diff(a, b, fromfile='original.sch', tofile='direct.room')))
        raise RuntimeError('Native and ROOM SPICE differ')
    print('PASS original/direct ROOM SPICE equivalence (sch_path excluded; anonymous nets bijectively renamed)')
    run(common + ['--script', script, work / 'cmos_inv.room'], cwd=work, env=env)
    run(common + ['-n', '-s', '-q', '-o', work / 'room', work / 'cmos_inv.room'], cwd=work, env=env)
    spice = (work / 'room/cmos_inv.spice').read_text()
    resistor = [line for line in spice.splitlines() if re.match(r'^R1\s', line, re.I)]
    if len(resistor) != 1 or resistor[0].split()[-1] != '12345':
        raise RuntimeError('Reopened netlist does not contain R1 value 12345')
    print('PASS reopened netlist:', resistor[0])
    expected = []
    edited = 0
    for original in original_objects:
        record = dict(original)
        if record['kind'] == 'C' and re.search(r'(?:^|\s)name=R1(?:\s|$)', record['attributes']):
            record['attributes'], count = re.subn(r'(?<!\S)value=(?:"[^"]*"|[^\s]+)', 'value=12345', record['attributes'])
            if count != 1:
                raise RuntimeError('Expected exactly one R1 value attribute')
            edited += 1
        expected.append(record)
    if edited != 1:
        raise RuntimeError('Expected exactly one R1 instance')
    actual_objects = snapshot(library, work / 'cmos_inv.room')
    expected.sort(key=lambda r: json.dumps(r, sort_keys=True))
    (work / 'before.json').write_text(json.dumps(original_objects, indent=2))
    (work / 'after.json').write_text(json.dumps(actual_objects, indent=2))
    if expected != actual_objects:
        raise RuntimeError('Reopened typed objects differ beyond R1.value; inspect before.json and after.json')
    print('PASS exactly one object change: R1.value; optional empty globals and endpoint order normalized')
    created = listing(watch) - before
    if created:
        raise RuntimeError('New .sch/.sym files detected:\n' + '\n'.join(sorted(created)))
    print('PASS no .sch/.sym files created in demo or configured editor directories')
    print('Artifacts:', work)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('FAIL:', error, file=sys.stderr)
        sys.exit(1)
