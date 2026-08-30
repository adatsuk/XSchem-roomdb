# Export inverter_tb CORE and print snippet (xschem -q -x --pipe --script test_inverter_export.tcl)
set ::CORE_SCRIPT_DIR [file normalize [file dirname [info script]]]
set ::XSCHEM_ROOT [file normalize [file dirname $::CORE_SCRIPT_DIR]]
source [file join $::CORE_SCRIPT_DIR core.tcl]
core_ensure_loaded

set corepath "/mnt/c/Users/anton/Documents/IHP-AnalogAcademy/modules/module_0_foundations/inverter_tb/inverter_tb.schematic.core"
if {![file exists $corepath]} {
  puts stderr "missing: $corepath"
  exit 1
}

if {[catch {set data [coreapi_export_cell_data $corepath inverter_tb]} err]} {
  puts stderr "export failed: $err"
  exit 1
}
puts "export bytes: [string length $data]"
puts "--- head ---"
puts [string range $data 0 1200]
exit 0
