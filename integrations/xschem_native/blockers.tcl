# Run on a disposable converter-produced ROOM fixture with scripts disabled.
if {[catch {
  foreach backend {memory disk} {
    xschem load -force $::env(REVIEW_FILE)
    xschem undo_type $backend
    xschem setprop instance R1 value 555
    xschem move_instance R1 999 - - -
    if {![catch {xschem save} msg]} {error "Moved instance was saved"}
    xschem undo
    xschem save
    xschem load -force $::env(REVIEW_FILE)
    if {[xschem getprop instance R1 value] ne "555"} {error "Undo lost parameter"}
    puts "PASS $backend undo restores drawing and permits save/reopen"
  }
  foreach {label value} [list quote {"a\"b"} backslash {"a\\b"} braces {{braces}}] {
    xschem setprop instance R1 value $value
    set expected [xschem getprop instance R1 value]
    xschem save
    xschem load -force $::env(REVIEW_FILE)
    set actual [xschem getprop instance R1 value]
    if {$actual ne $expected} {error "$label differs: [list $expected] -> [list $actual]"}
    puts "PASS $label round-trips exactly: [list $actual]"
  }
} msg options]} {
  puts stderr $msg
  puts stderr [dict get $options -errorinfo]
  exit 1
}
exit 0
