# Run in a fresh editor process on a disposable converter-produced ROOM file.
proc must {condition message} {
  if {![uplevel 1 [list expr $condition]]} {error $message}
}

proc bytes {path} {
  set file [open $path rb]
  set data [read $file]
  close $file
  return $data
}

proc must_refuse {path diagnostic} {
  set before [bytes $path]
  set failed [catch {xschem save} message]
  must {$failed && [string match $diagnostic $message]} "Unexpected save result: $failed $message"
  must {[bytes $path] eq $before && [xschem get modified]} "Refusal lost original bytes or dirty state"
}

if {[catch {
  if {[info exists ::room_native_error]} {error $::room_native_error}
  set path $::env(REVIEW_FILE)
  switch -- $::env(REVIEW_CASE) {
    scope {
      foreach {instance key original changed} {
        l6 global false true
        l6 lab D OTHER
        l6 sig_type std_logic integer
        l6 value 0 9
        R1 spice_ignore false true
      } {
        must {[xschem getprop instance $instance $key] eq $original} "Missing fixture value $instance.$key"
        xschem setprop instance $instance $key $changed
        must_refuse $path "*Instance attribute is read-only: $instance.$key*"
        must {[xschem getprop instance $instance $key] eq $changed} "Refusal lost $instance.$key"
        xschem load -force $path
      }
      xschem setprop instance R1 value 50
      set expected 50
    }
    escape {
      xschem setprop instance R1 value {a\b}
      must {[xschem getprop instance_notcl R1 value] eq "ab"} "Fixture did not reproduce the unquoted escape"
      must_refuse $path {*Unsupported unquoted attribute spelling: value*}
      must {[xschem getprop instance_notcl R1 value] eq "ab"} "Refusal lost the existing edit"
      xschem setprop instance R1 value {"a\\b"}
      set expected {a\b}
      must {[xschem getprop instance_notcl R1 value] eq $expected} "Quoted escape did not reach the editor"
    }
    precision {
      xschem undo_type $::env(REVIEW_UNDO)
      xschem setprop instance R1 value 720
      xschem move_instance R1 999 - - -
      xschem undo
      set expected 720
      must {[xschem getprop instance R1 value] eq $expected && [xschem get modified]} "Undo lost the parameter or dirty state"
    }
    default {error "Unknown regression case $::env(REVIEW_CASE)"}
  }
  xschem save
  xschem load -force $path
  must {[xschem getprop instance_notcl R1 value] eq $expected} "Saved value differs after reopen"
  puts "PASS $::env(REVIEW_CASE): R1.value reopened as [list $expected]"
} message options]} {
  puts stderr [dict get $options -errorinfo]
  exit 1
}
exit 0
