# Native ROOM bridge smoke test (run: xschem -q -x --pipe --script test_native_bridge.tcl)
set ::ROOM_SCRIPT_DIR [file normalize [file dirname [info script]]]
set ::XSCHEM_ROOT [file normalize [file dirname $::ROOM_SCRIPT_DIR]]
source [file join $::ROOM_SCRIPT_DIR room.tcl]

room_ensure_loaded

if {[catch {xschem load_data} e]} {
  if {![string match {*load_data needs*} $e]} {
    puts stderr "FAIL: load_data missing: $e"
    exit 1
  }
}
puts "OK: load_data exists"

set roompath "/mnt/c/Users/anton/Documents/LibMan/tests/data/OTA1336/schematic/dc_isolbox/dc_isolbox.schematic.room"
if {![file exists $roompath]} {
  puts stderr "SKIP: test core missing: $roompath"
  exit 0
}

set data [coreapi_export_cell_data $roompath dc_isolbox]
puts "OK: export [string length $data] bytes"

if {[catch {xschem load_data $data -schname $roompath} err]} {
  puts stderr "FAIL: load_data: $err"
  exit 1
}
puts "OK: loaded schematic in memory"

set out [xschem get_data]
puts "OK: get_data [string length $out] bytes"
exit 0
