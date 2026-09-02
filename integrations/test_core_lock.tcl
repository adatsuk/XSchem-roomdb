proc core_norm_path {p} {
  if {$p eq ""} { return "" }
  return [file normalize $p]
}
proc core_resolve_corepath {} { return "" }
proc core_schedule_title_refresh {} {}

source [file join [file dirname [info script]] core_lock.tcl]

set core /tmp/xschem_lock_test.schematic.core
set r [core_lock_try_acquire $core err]
puts "acquire=$r"
if {[info exists err]} { puts "err=$err" }
puts "lck_exists=[file exists ${core}.lck]"
core_lock_release_owned $core
puts "after_release=[file exists ${core}.lck]"
