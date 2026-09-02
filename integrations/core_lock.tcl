# CORE sidecar lock (.core.lck) for Xschem — same format as LibMan / Qucs-S.

array set ::core_lock_refs {}
array set ::core_lock_viewonly {}
array set ::core_lock_held {}
array set ::core_lock_tracked {}
set ::core_lock_tool_version "XSchem-coredb"

proc core_lock_path {corepath} {
  return "[file normalize $corepath].lck"
}

proc core_lock_current_user {} {
  if {[info exists ::env(USER)] && $::env(USER) ne ""} {
    return $::env(USER)
  }
  if {[info exists ::env(LOGNAME)] && $::env(LOGNAME) ne ""} {
    return $::env(LOGNAME)
  }
  return "unknown"
}

proc core_lock_current_host {} {
  if {[catch {set host [info hostname]}]} {
    return "localhost"
  }
  set host [string trim $host]
  if {$host eq ""} {
    return "localhost"
  }
  return $host
}

proc core_lock_current_pid {} {
  return [pid]
}

proc core_lock_unescape_json {value} {
  regsub -all {\\"} $value "\"" value
  regsub -all {\\\\} $value "\\" value
  return $value
}

proc core_lock_json_field {json key} {
  set pattern [string cat "\"$key\"" {\s*:\s*"((?:\\.|[^"])*)"}]
  if {[regexp -nocase $pattern $json -> value]} {
    return [core_lock_unescape_json $value]
  }
  set pattern2 [string cat "\"$key\"" {\s*:\s*(-?[0-9]+)}]
  if {[regexp $pattern2 $json -> value]} {
    return $value
  }
  return ""
}

proc core_lock_read {corepath} {
  set abs [file normalize $corepath]
  set info [dict create present 0 parseOk 0 corePath $abs lockPath [core_lock_path $abs] user "" host "" tool "" toolVersion "" createdAt "" pid 0 parseError ""]
  set lockPath [dict get $info lockPath]
  if {![file exists $lockPath]} {
    return $info
  }
  dict set info present 1
  if {[catch {set fh [open $lockPath r]} err]} {
    dict set info parseOk 0
    dict set info parseError "Could not read lock file."
    return $info
  }
  set json [read $fh]
  close $fh
  if {$json eq "" || [string index [string trim $json] 0] ne "\{"} {
    dict set info parseOk 0
    dict set info parseError "Lock file is not valid JSON."
    return $info
  }
  dict set info parseOk 1
  set coreStored [core_lock_json_field $json corePath]
  if {$coreStored ne ""} {
    dict set info corePath [file normalize $coreStored]
  }
  dict set info createdAt [core_lock_json_field $json createdAt]
  dict set info user [core_lock_json_field $json user]
  dict set info host [core_lock_json_field $json host]
  dict set info tool [core_lock_json_field $json tool]
  dict set info toolVersion [core_lock_json_field $json toolVersion]
  set pid [core_lock_json_field $json pid]
  if {$pid ne ""} {
    dict set info pid $pid
  }
  return $info
}

proc core_lock_process_alive {pid} {
  if {$pid eq "" || $pid <= 0} {
    return 0
  }
  if {$pid == [pid]} {
    return 1
  }
  if {[catch {exec kill -0 $pid 2>@1}]} {
    return 0
  }
  return 1
}

proc core_lock_held_by_us {info} {
  if {![dict get $info parseOk]} {
    return 0
  }
  if {[dict get $info pid] == [pid] \
      && [string equal -nocase [dict get $info user] [core_lock_current_user]] \
      && [string equal -nocase [dict get $info host] [core_lock_current_host]]} {
    return 1
  }
  return 0
}

# Returns 1=alive, 0=dead, -1=unknown (probe failed).
proc core_lock_windows_process_status {pid} {
  if {$pid eq "" || $pid <= 0} {
    return 0
  }

  set tasklist ""
  foreach cand {
    /mnt/c/Windows/System32/tasklist.exe
    /mnt/c/Windows/Sysnative/tasklist.exe
  } {
    if {[file exists $cand]} {
      set tasklist $cand
      break
    }
  }

  if {$tasklist ne ""} {
    if {![catch {set out [exec $tasklist /FI "PID eq $pid" /NH]} err]} {
      if {[regexp -- "\\m$pid\\M" $out]} {
        return 1
      }
      # tasklist ran; PID not listed → dead
      return 0
    }
  }

  set ps ""
  foreach cand {
    /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
    /mnt/c/Windows/Sysnative/WindowsPowerShell/v1.0/powershell.exe
  } {
    if {[file exists $cand]} {
      set ps $cand
      break
    }
  }
  if {$ps eq "" && ![catch {exec which powershell.exe}]} {
    set ps [exec which powershell.exe]
  }
  if {$ps eq ""} {
    return -1
  }

  set cmd "if (Get-Process -Id $pid -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
  set status [catch {exec $ps -NoProfile -NonInteractive -Command $cmd} err]
  if {$status == 0} {
    return 1
  }
  # Non-zero from powershell usually means dead; other exec failures → unknown.
  if {[string match -nocase "*exit*1*" $err] || $err eq ""} {
    return 0
  }
  return -1
}

proc core_lock_foreign_process_status {pid} {
  # Prefer Windows probe when available (WSL ↔ native Windows qucs-s).
  set st [core_lock_windows_process_status $pid]
  if {$st != -1} {
    return $st
  }
  # Visible Windows host FS ⇒ WSL. Do not use Linux kill -0 on a Windows PID
  # (PID namespaces differ; a coincidental Linux PID would look "alive").
  if {[file isdirectory /mnt/c/Windows] || [file isdirectory /mnt/c/Windows/System32]} {
    return -1
  }
  # Native Linux (both tools share one PID namespace).
  if {[core_lock_process_alive $pid]} {
    return 1
  }
  return 0
}

proc core_lock_windows_process_alive {pid} {
  return [expr {[core_lock_windows_process_status $pid] == 1}]
}

proc core_lock_is_local_tool {info} {
  set tool [string trim [dict get $info tool]]
  if {$tool eq ""} {
    return 0
  }
  return [string equal -nocase $tool "xschem"]
}

proc core_lock_is_stale {info} {
  if {![dict get $info present]} {
    return 0
  }
  if {![dict get $info parseOk]} {
    return 1
  }
  if {[dict get $info pid] <= 0} {
    return 1
  }
  if {[core_lock_held_by_us $info]} {
    return 0
  }
  # Other tools (qucs-s, …): Windows probe when present, else Linux kill -0.
  if {![core_lock_is_local_tool $info]} {
    set st [core_lock_foreign_process_status [dict get $info pid]]
    if {$st == 1} {
      return 0
    }
    if {$st == 0} {
      return 1
    }
    return 0
  }
  if {[core_lock_process_alive [dict get $info pid]]} {
    return 0
  }
  return 1
}

proc core_lock_format_status {info} {
  if {![dict get $info present]} {
    return "CORE lock: none"
  }
  if {![dict get $info parseOk]} {
    return "CORE lock: present but unreadable"
  }
  set line "Read-only"
  set user [dict get $info user]
  set host [dict get $info host]
  if {$user ne "" || $host ne ""} {
    append line " — ${user}"
    if {$host ne ""} {
      append line "@${host}"
    }
  }
  set tool [dict get $info tool]
  set toolVersion [dict get $info toolVersion]
  if {$tool ne ""} {
    append line " (${tool}"
    if {$toolVersion ne ""} {
      append line " ${toolVersion}"
    }
    append line ")"
  }
  return $line
}

proc core_lock_add_ref {corepath} {
  set key [core_norm_path $corepath]
  if {![info exists ::core_lock_refs($key)]} {
    set ::core_lock_refs($key) 0
  }
  incr ::core_lock_refs($key)
}

proc core_lock_release_ref {corepath} {
  set key [core_norm_path $corepath]
  if {![info exists ::core_lock_refs($key)]} {
    return 0
  }
  incr ::core_lock_refs($key) -1
  if {$::core_lock_refs($key) <= 0} {
    unset ::core_lock_refs($key)
    return 0
  }
  return $::core_lock_refs($key)
}

proc core_lock_ref_count {corepath} {
  set key [core_norm_path $corepath]
  if {![info exists ::core_lock_refs($key)]} {
    return 0
  }
  return $::core_lock_refs($key)
}

proc core_lock_remove_file {corepath} {
  set lockPath [core_lock_path $corepath]
  if {[file exists $lockPath]} {
    catch {file delete -force $lockPath}
  }
}

proc core_lock_try_acquire {corepath {errorVar ""}} {
  set abs [file normalize $corepath]
  set info [core_lock_read $abs]
  if {[dict get $info present]} {
    if {[core_lock_is_stale $info]} {
      core_lock_remove_file $abs
    } elseif {[core_lock_held_by_us $info]} {
      return "already"
    } else {
      if {$errorVar ne ""} {
        upvar 1 $errorVar msg
        set msg [core_lock_format_status $info]
      }
      return "foreign"
    }
  }

  set lockPath [core_lock_path $abs]
  set tmpPath "${lockPath}.tmp"
  set user [core_lock_current_user]
  set host [core_lock_current_host]
  set pid [core_lock_current_pid]
  set now [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S} -gmt 1]
  set json [format {
{
    "version": 1,
    "corePath": "%s",
    "holder": {
        "user": "%s",
        "host": "%s",
        "pid": %d,
        "tool": "xschem",
        "toolVersion": "%s"
    },
    "createdAt": "%sZ"
}
} $abs $user $host $pid $::core_lock_tool_version $now]

  if {[catch {set fh [open $tmpPath w]} err]} {
    if {$errorVar ne ""} {
      upvar 1 $errorVar msg
      set msg "Could not create lock file."
    }
    return "error"
  }
  fconfigure $fh -translation binary
  puts -nonewline $fh $json
  close $fh

  if {[file exists $lockPath] && ![core_lock_is_stale [core_lock_read $abs]]} {
    catch {file delete -force $tmpPath}
    if {$errorVar ne ""} {
      upvar 1 $errorVar msg
      set msg [core_lock_format_status [core_lock_read $abs]]
    }
    return "foreign"
  }
  if {[file exists $lockPath]} {
    catch {file delete -force $lockPath}
  }
  if {[catch {file rename -force $tmpPath $lockPath} err]} {
    catch {file delete -force $tmpPath}
    if {$errorVar ne ""} {
      upvar 1 $errorVar msg
      set msg "Could not finalize lock file."
    }
    return "error"
  }
  return "acquired"
}

proc core_lock_release_owned {corepath} {
  set abs [core_norm_path $corepath]
  if {$abs eq ""} {
    return
  }
  if {[info exists ::core_lock_held($abs)]} {
    unset ::core_lock_held($abs)
  }
  if {[core_lock_release_ref $abs] > 0} {
    return
  }
  set info [core_lock_read $abs]
  if {[dict get $info present] && [dict get $info parseOk] \
      && ![core_lock_held_by_us $info] && ![core_lock_is_stale $info]} {
    return
  }
  core_lock_remove_file $abs
}

proc core_lock_release_all {} {
  set paths {}
  foreach abs [array names ::core_lock_held] {
    lappend paths $abs
  }
  foreach abs [array names ::core_lock_tracked] {
    if {[lsearch -exact $paths $abs] < 0} {
      lappend paths $abs
    }
  }
  foreach abs $paths {
    set info [core_lock_read $abs]
    if {[dict get $info present] && [core_lock_held_by_us $info]} {
      core_lock_remove_file $abs
    } elseif {[info exists ::core_lock_held($abs)]} {
      # We think we hold it — remove even if parse is flaky.
      core_lock_remove_file $abs
    }
  }
  array unset ::core_lock_held
  array unset ::core_lock_refs
  array unset ::core_lock_viewonly
}

proc core_lock_install_exit_hook {} {
  if {[info commands __core_lock_exit_orig] ne ""} {
    return
  }
  if {[info commands exit] eq ""} {
    after 300 core_lock_install_exit_hook
    return
  }
  rename exit __core_lock_exit_orig
  proc exit {{code 0}} {
    catch {core_lock_release_all}
    return [__core_lock_exit_orig $code]
  }
}

proc core_lock_set_viewonly {corepath viewonly} {
  set key [core_norm_path $corepath]
  if {$viewonly} {
    set ::core_lock_viewonly($key) 1
  } elseif {[info exists ::core_lock_viewonly($key)]} {
    unset ::core_lock_viewonly($key)
  }
}

proc core_lock_is_viewonly { {corepath ""} } {
  if {$corepath eq ""} {
    set corepath [core_resolve_corepath]
  }
  if {$corepath eq ""} {
    return 0
  }
  set key [core_norm_path $corepath]
  return [info exists ::core_lock_viewonly($key)]
}

proc core_lock_status_text { {corepath ""} } {
  if {$corepath eq ""} {
    set corepath [core_resolve_corepath]
  }
  if {$corepath eq ""} {
    return ""
  }
  set key [core_norm_path $corepath]
  if {[info exists ::core_lock_viewonly($key)]} {
    return [core_lock_format_status [core_lock_read $corepath]]
  }
  if {[info exists ::core_lock_held($key)]} {
    return "Editing (lock held)"
  }
  return "CORE lock: none"
}

proc core_lock_track {corepath} {
  set key [core_norm_path $corepath]
  set ::core_lock_tracked($key) 1
}

proc core_lock_on_open {corepath} {
  set abs [file normalize $corepath]
  core_lock_track $abs

  set info [core_lock_read $abs]
  if {[dict get $info present] && ![core_lock_is_stale $info] \
      && ![core_lock_held_by_us $info]} {
    core_lock_set_viewonly $abs 1
    tk_messageBox -icon info -title "CORE file locked" \
      -message "This CORE view is opened read-only.\n\n[core_lock_format_status $info]"
    core_lock_sync_ui
    return
  }

  if {[dict get $info present] && [core_lock_is_stale $info]} {
    core_lock_remove_file $abs
  }

  set err ""
  set result [core_lock_try_acquire $abs err]
  if {$result eq "foreign"} {
    core_lock_set_viewonly $abs 1
    tk_messageBox -icon info -title "CORE file locked" \
      -message "This CORE view is opened read-only.\n\n$err"
    core_lock_sync_ui
    return
  }
  if {$result eq "error"} {
    core_lock_set_viewonly $abs 1
    tk_messageBox -icon warning -title "CORE lock" \
      -message "Could not acquire CORE lock.\n\n$err"
    core_lock_sync_ui
    return
  }

  core_lock_set_viewonly $abs 0
  set ::core_lock_held($abs) 1
  core_lock_add_ref $abs
  core_lock_sync_ui
}

proc core_lock_assert_writable {corepath} {
  set abs [file normalize $corepath]
  if {[core_lock_is_viewonly $abs]} {
    error "Cannot save: [core_lock_format_status [core_lock_read $abs]]"
  }
  set info [core_lock_read $abs]
  if {[dict get $info present] && ![core_lock_is_stale $info] \
      && ![core_lock_held_by_us $info] && [core_lock_ref_count $abs] == 0} {
    error "Cannot save: [core_lock_format_status $info]"
  }
  return 1
}

proc core_lock_refresh {corepath} {
  set abs [core_norm_path $corepath]
  if {$abs eq "" || ![info exists ::core_lock_tracked($abs)]} {
    return
  }

  set wasViewonly [info exists ::core_lock_viewonly($abs)]
  set wasHeld [info exists ::core_lock_held($abs)]
  set info [core_lock_read $abs]

  if {![dict get $info present] || [core_lock_is_stale $info]} {
    if {$wasViewonly} {
      set err ""
      set result [core_lock_try_acquire $abs err]
      if {$result eq "acquired" || $result eq "already"} {
        core_lock_set_viewonly $abs 0
        set ::core_lock_held($abs) 1
        core_lock_add_ref $abs
      }
    }
  } elseif {![core_lock_held_by_us $info] && [core_lock_ref_count $abs] == 0} {
    if {!$wasViewonly} {
      if {$wasHeld} {
        catch {unset ::core_lock_held($abs)}
        core_lock_release_ref $abs
      }
      core_lock_set_viewonly $abs 1
      catch {xschem set_modify 0}
      tk_messageBox -icon warning -title "CORE lock" \
        -message "This document is now read-only and cannot be saved."
    }
  } elseif {$wasViewonly && [core_lock_held_by_us $info]} {
    core_lock_set_viewonly $abs 0
    set ::core_lock_held($abs) 1
    core_lock_add_ref $abs
  }

  if {$wasViewonly != [info exists ::core_lock_viewonly($abs)] \
      || $wasHeld != [info exists ::core_lock_held($abs)]} {
    core_lock_sync_ui
    core_schedule_title_refresh
  }
}

proc core_lock_poll {} {
  foreach abs [array names ::core_lock_tracked] {
    core_lock_refresh $abs
  }
  after 2000 core_lock_poll
}

proc core_lock_blocked_xschem_subcmds {} {
  return {
    delete cut copy_objects move rotate mirror stretch paste wire line arc
    text place clear clear_drawing edit_prop change_elem_order break_wires
    add_symbol_pin add_graph add_image align undo redo save get_data
    import push pop replace
  }
}

proc core_lock_blocks_xschem {args} {
  if {![core_lock_is_viewonly]} {
    return 0
  }
  set cmd [lindex $args 0]
  if {$cmd eq ""} {
    return 0
  }
  if {[lsearch -exact [core_lock_blocked_xschem_subcmds] $cmd] >= 0} {
    return 1
  }
  return 0
}

proc core_lock_install_xschem_hook {} {
  if {[info commands xschem_orig] ne ""} {
    return
  }
  if {[info commands xschem] eq ""} {
    after 300 core_lock_install_xschem_hook
    return
  }
  rename xschem xschem_orig
  proc xschem {args} {
    if {[core_lock_blocks_xschem $args]} {
      tk_messageBox -icon warning -message "Read-only: cannot [lindex $args 0]"
      return {}
    }
    return [uplevel 1 xschem_orig $args]
  }
}

proc core_lock_install_quit_hook {} {
  if {[info commands quit_xschem_orig] ne ""} {
    return
  }
  if {[info commands quit_xschem] eq ""} {
    after 300 core_lock_install_quit_hook
    return
  }
  rename quit_xschem quit_xschem_orig
  # Do not release here: user may cancel the unsaved dialog.
  # Actual unlock happens in the Tcl exit hook / Destroy binding.
  proc quit_xschem {{force {}}} {
    return [quit_xschem_orig $force]
  }
}

proc core_lock_sync_ui {} {
  if {[catch {set topwin [xschem get top_path]}]} {
    return
  }
  set viewonly [core_lock_is_viewonly]
  set state [expr {$viewonly ? "disabled" : "normal"}]
  catch {
    $topwin.menubar.file entryconfigure "Save" -state $state
    $topwin.menubar.file entryconfigure "Save as" -state $state
  }
  catch {
    if {[winfo exists $topwin.menubar.core]} {
      $topwin.menubar.core entryconfigure "Save" -state $state
      $topwin.menubar.core entryconfigure "Save as..." -state $state
      $topwin.menubar.core entryconfigure "Save to *" -state $state
    }
  }
  catch {
    if {[winfo exists $topwin.toolbar.bFileSave]} {
      $topwin.toolbar.bFileSave configure -state $state
    }
    if {[winfo exists $topwin.toolbar.bFileSaveAs]} {
      $topwin.toolbar.bFileSaveAs configure -state $state
    }
  }
}

proc core_lock_install_delete_tab_hook {} {
  if {[info commands delete_tab_orig] ne ""} {
    return
  }
  if {[info commands delete_tab] eq ""} {
    after 300 core_lock_install_delete_tab_hook
    return
  }
  rename delete_tab delete_tab_orig
  proc delete_tab {path} {
    set sch ""
    catch {set sch [xschem get schname]}
    set corepath ""
    if {$sch ne ""} {
      set corepath [core_get_binding $sch]
    }
    set rc [delete_tab_orig $path]
    if {$corepath ne ""} {
      core_lock_release_owned $corepath
    }
    return $rc
  }
}

proc core_lock_install_hooks {} {
  core_lock_install_xschem_hook
  core_lock_install_quit_hook
  core_lock_install_delete_tab_hook
  core_lock_install_exit_hook
  after 2000 core_lock_poll
}
