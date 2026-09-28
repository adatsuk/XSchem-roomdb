# Export inverter_tb ROOM and print snippet (xschem -q -x --pipe --script test_inverter_export.tcl)
set ::ROOM_SCRIPT_DIR [file normalize [file dirname [info script]]]
set ::XSCHEM_ROOT [file normalize [file dirname $::ROOM_SCRIPT_DIR]]
source [file join $::ROOM_SCRIPT_DIR room.tcl]
room_ensure_loaded

set roompath "/mnt/c/Users/anton/Documents/IHP-AnalogAcademy/modules/module_0_foundations/inverter_tb/inverter_tb.schematic.room"
if {![file exists $roompath]} {
  puts stderr "missing: $roompath"
  exit 1
}

if {[catch {set data [coreapi_export_cell_data $roompath inverter_tb]} err]} {
  puts stderr "export failed: $err"
  exit 1
}
puts "export bytes: [string length $data]"
puts "--- head ---"
puts [string range $data 0 1200]
exit 0
