proc room_norm_path {p} {
  if {$p eq ""} { return "" }
  return [file normalize $p]
}
proc room_resolve_roompath {} { return "" }
proc room_schedule_title_refresh {} {}

source [file join [file dirname [info script]] room_lock.tcl]

set core /tmp/xschem_lock_test.schematic.room
set r [room_lock_try_acquire $core err]
puts "acquire=$r"
if {[info exists err]} { puts "err=$err" }
puts "lck_exists=[file exists ${core}.lck]"
room_lock_release_owned $core
puts "after_release=[file exists ${core}.lck]"
