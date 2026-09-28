# ROOM in-process integration for Xschem (roomtcl.so + ROOM API).
# Xschem owns schematic/symbol views: cell.schematic.room, cell.symbol.room

set ::ROOM_SCRIPT_DIR [file normalize [file dirname [info script]]]

foreach {oldName newName} {
  CORE_PRIMITIVE_LIBS_FILE ROOM_PRIMITIVE_LIBS_FILE
  CORE_PRIMITIVE_LIBS ROOM_PRIMITIVE_LIBS
  CORE_PRIMITIVE_LIB ROOM_PRIMITIVE_LIB
  XSCHEM_OPEN_CORE XSCHEM_OPEN_ROOM
} {
  if {(![info exists ::env($newName)] || $::env($newName) eq "")
      && [info exists ::env($oldName)] && $::env($oldName) ne ""} {
    set ::env($newName) $::env($oldName)
  }
}

if {![info exists ::XSCHEM_ROOT]} {
  set ::XSCHEM_ROOT [file normalize [file dirname $::ROOM_SCRIPT_DIR]]
}

if {![info exists ::ROOM_ROOT]} {
  if {[info exists ::env(COMMONDB_ROOT)] && $::env(COMMONDB_ROOT) ne ""} {
    set ::ROOM_ROOT [file normalize $::env(COMMONDB_ROOT)]
  } elseif {[info exists ::env(ROOM_ROOT)] && $::env(ROOM_ROOT) ne ""} {
    set ::ROOM_ROOT [file normalize $::env(ROOM_ROOT)]
  } elseif {[info exists ::env(CORE_ROOT)] && $::env(CORE_ROOT) ne ""} {
    set ::ROOM_ROOT [file normalize $::env(CORE_ROOT)]
  } else {
    set ::ROOM_ROOT [file normalize [file join $::XSCHEM_ROOT .. CommonDB]]
  }
}

set ::ROOM_LIB [file join $::ROOM_ROOT designs xschem test.schematic.room]
set ::ROOM_PAYLOAD [file join $::ROOM_ROOT designs xschem payload]

# sch/sym path -> backing .room file (keys are normalized absolute paths)
array set ::room_binding {}

proc room_norm_path {path} {
  if {$path eq ""} {
    return ""
  }
  return [file normalize $path]
}

proc room_set_binding {sch roompath} {
  set ::room_binding([room_norm_path $sch]) [room_norm_path $roompath]
}

proc room_get_binding {sch} {
  set key [room_norm_path $sch]
  if {$key ne "" && [info exists ::room_binding($key)]} {
    return $::room_binding($key)
  }
  return ""
}

proc room_clear_binding {sch} {
  set key [room_norm_path $sch]
  if {$key ne "" && [info exists ::room_binding($key)]} {
    unset ::room_binding($key)
  }
}

source [file join $::ROOM_SCRIPT_DIR room_lock.tcl]

# payload/cell.sym opened directly -> bind parent cell.symbol.room for title/save.
proc room_try_bind_payload_sch {sch} {
  set sch [room_norm_path $sch]
  if {$sch eq "" || [room_get_binding $sch] ne ""} {
    return 0
  }
  if {![string equal -nocase [file tail [file dirname $sch]] payload]} {
    return 0
  }
  set parent [file dirname [file dirname $sch]]
  set cell [file rootname [file tail $sch]]
  foreach suffix {symbol.room schematic.room symbol.core schematic.core} {
    set roompath [file join $parent ${cell}.${suffix}]
    if {[file exists $roompath]} {
      room_set_binding $sch $roompath
      return 1
    }
  }
  return 0
}

proc room_schedule_title_refresh {} {
  foreach delay {0 100 400} {
    after $delay room_refresh_window_title
  }
}

proc room_find_tcl_lib {} {
  set candidates [list \
    [file join $::ROOM_SCRIPT_DIR roomtcl.so] \
    [file join $::ROOM_ROOT build-wsl integrations xschem_tcl roomtcl.so] \
    [file join $::ROOM_ROOT build integrations xschem_tcl roomtcl.so]]
  foreach path $candidates {
    if {[file exists $path]} {
      return $path
    }
  }
  return ""
}

proc room_ensure_loaded {} {
  if {[namespace which -command coreapi_list_cells] ne ""} {
    return
  }
  set lib [room_find_tcl_lib]
  if {$lib eq ""} {
    set build_script [file join $::XSCHEM_ROOT build-room-tcl.sh]
    error "roomtcl.so not found. Run: bash $build_script"
  }
  load $lib Core
}

proc room_view_for_sch {schpath} {
  set ext [string tolower [file extension $schpath]]
  if {$ext eq ".sym"} {
    return symbol
  }
  return schematic
}

proc room_ext_for_view {view} {
  if {$view eq "symbol"} {
    return .sym
  }
  return .sch
}

proc room_is_room_path {path} {
  foreach view {schematic symbol} {
    if {[string match -nocase *.$view.room $path] || [string match -nocase *.$view.core $path]} {
      return 1
    }
  }
  return 0
}

proc room_cell_from_path {path} {
  room_ensure_loaded
  return [lindex [coreapi_parse_core_path $path] 0]
}

proc room_view_from_path {path} {
  room_ensure_loaded
  return [lindex [coreapi_parse_core_path $path] 1]
}

proc room_path_for_cell {cell view {dir ""}} {
  room_ensure_loaded
  set name [coreapi_core_file_name $cell $view]
  if {$dir ne ""} {
    return [file join $dir $name]
  }
  return $name
}

proc room_default_room_path {sch} {
  set cell [file rootname [file tail $sch]]
  set view [room_view_for_sch $sch]
  set dir [file dirname $sch]
  if {[string equal -nocase [file tail $dir] payload]} {
    set dir [file dirname $dir]
  }
  return [room_path_for_cell $cell $view $dir]
}

proc room_save_defaultextension {} {
  set sch [xschem get schname]
  if {$sch ne "" && [string match -nocase *.sym $sch]} {
    return .symbol.room
  }
  return .schematic.room
}

proc room_payload_dir {roompath} {
  return [file join [file dirname $roompath] payload]
}

proc room_list_cells {roompath} {
  room_ensure_loaded
  return [coreapi_list_cells $roompath]
}

proc room_pick_cell {cells {title "Select cell"}} {
  set top .room_pick_cell
  if {[winfo exists $top]} {
    destroy $top
  }
  set ::room_pick_cell_answer ""
  toplevel $top
  wm title $top $title
  wm transient $top [xschem get topwindow]
  label $top.lbl -text "ROOM file contains multiple cells:"
  listbox $top.lb -listvariable ::room_pick_cell_list -height 10 -width 40 \
    -exportselection 0 -selectmode browse
  set ::room_pick_cell_list $cells
  $top.lb selection set 0
  frame $top.btns
  button $top.btns.ok -text OK -command {
    set sel [.room_pick_cell.lb curselection]
    if {$sel ne {}} {
      set ::room_pick_cell_answer [lindex $::room_pick_cell_list $sel]
    }
    destroy .room_pick_cell
  }
  button $top.btns.cancel -text Cancel -command {destroy .room_pick_cell}
  pack $top.lbl -padx 8 -pady 4
  pack $top.lb -padx 8 -pady 4 -fill both -expand 1
  pack $top.btns.ok $top.btns.cancel -side left -padx 8 -pady 8
  pack $top.btns
  bind $top.lb <Double-Button-1> "$top.btns.ok invoke"
  tkwait window $top
  return $::room_pick_cell_answer
}

proc room_temp_sch_path {cell ext} {
  if {[catch {set fh [file tempfile -prefix "xschem_room_${cell}_" -suffix $ext]} err]} {
    set dir "/tmp"
    if {[info exists ::env(TEMP)] && $::env(TEMP) ne ""} {
      set dir $::env(TEMP)
    }
    return [file join $dir xschem_room_[pid]_[clock clicks]$ext]
  }
  close $fh
  return $fh
}

proc room_write_sch_data {sch data} {
  set fh [open $sch w]
  fconfigure $fh -translation binary
  puts -nonewline $fh $data
  close $fh
}

proc room_export_cell_to_sch {roompath cell sch} {
  if {[info commands coreapi_export_cell_data] ne ""} {
    set data [coreapi_export_cell_data $roompath $cell]
    room_write_sch_data $sch $data
    return
  }
  coreapi_export_cell $roompath $cell $sch
}

proc room_has_native_bridge {} {
  if {[info commands xschem] eq ""} {
    return 0
  }
  if {[catch {xschem load_data} err]} {
    return [expr {[string match {*load_data needs*} $err]}]
  }
  return 0
}

proc room_guess_cell_name {roompath} {
  set base [file rootname [file tail $roompath]]
  if {[regexp {^(.+)\.(schematic|symbol)$} $base -> cell]} {
    return $cell
  }
  return $base
}

proc room_logical_schname {roompath {cell ""}} {
  if {$cell eq ""} {
    set cell [room_guess_cell_name $roompath]
  }
  if {$cell eq ""} {
    return $roompath
  }
  if {[info exists ::env(XSCHEM_NETLIST_DIR)] && $::env(XSCHEM_NETLIST_DIR) ne ""} {
    catch {file mkdir $::env(XSCHEM_NETLIST_DIR)}
    set ext ".sch"
    if {[string match *.symbol.room $roompath]} {
      set ext ".sym"
    }
    return [file join $::env(XSCHEM_NETLIST_DIR) ${cell}${ext}]
  }
  return $roompath
}

proc room_apply_cell_names {roompath {cell ""}} {
  if {$cell eq ""} {
    set cell [room_guess_cell_name $roompath]
  }
  if {$cell eq ""} {
    return
  }
  catch {xschem set netlist_name ${cell}.spice}
}

# Add sibling design dirs (e.g. ../inverter/inverter.sym) for hierarchical blocks.
proc room_add_hierarchy_search_paths {roompath} {
  global pathlist
  if {$roompath eq ""} {
    return
  }
  set dir [file normalize [file dirname [room_norm_path $roompath]]]
  set parent [file dirname $dir]
  set extra [list $dir $parent]
  if {[file isdirectory $parent]} {
    foreach sub [glob -nocomplain -directory $parent *] {
      if {[file isdirectory $sub]} {
        lappend extra [file normalize $sub]
      }
    }
  }
  foreach d [lsort -unique $extra] {
    if {$d ne "" && [file isdirectory $d] && [lsearch -exact $pathlist $d] < 0} {
      lappend pathlist $d
    }
  }
}

proc room_preload_primitives {} {
  # Build lookup index only; materialize symbols on demand (room_materialize_symbol).
  # Pre-exporting every primitive from /mnt/c blocks WSL on p9_client_rpc for minutes.
  room_build_symbol_index
  room_refresh_pathlist
}

proc room_load_room_data {data roompath cell} {
  set logical [room_logical_schname $roompath $cell]
  catch {file mkdir [file dirname $logical]}
  set load_args [list $data -schname $logical]
  if {[llength [room_primitive_lib_paths]] > 0} {
    lappend load_args -nosymbols
  }
  if {[catch {eval xschem load_data $load_args} err]} {
    error $err
  }
  set schname [xschem get schname]
  if {[string match *untitled* $schname]} {
    room_write_sch_data $logical $data
    xschem load $logical
    set schname [xschem get schname]
  }
  room_set_binding $schname $roompath
  set ::room_active_roompath [room_norm_path $roompath]
  set ::room_active_cell $cell
  return $schname
}

proc room_netlist_when_ready {{tries 0} {expected_cell ""}} {
  set sch [xschem get schname]
  if {$expected_cell ne "" && [string match *untitled* $sch] && $tries < 12} {
    after 250 [list room_netlist_when_ready [expr {$tries + 1}] $expected_cell]
    return
  }
  room_finish_primitive_setup
  catch {xschem reload_symbols}
  catch {xschem redraw}
  catch {xschem netlist}
}

proc room_sym_file_looks_valid {path} {
  if {$path eq "" || ![file exists $path]} {
    return 0
  }
  if {[catch {set fh [open $path r]}]} {
    return 0
  }
  set buf [read $fh 8192]
  close $fh
  if {![regexp {K \{type=} $buf] && ![regexp {G \{type=netlist_commands} $buf]} {
    return 0
  }
  # Broken ROOM exports often mash format= and template= on one line.
  if {[regexp {format="@name template=} $buf]} {
    return 0
  }
  return 1
}

proc room_find_hierarchy_sym {lookup} {
  global pathlist
  if {![info exists pathlist]} {
    return ""
  }
  set tail [file tail $lookup]
  foreach dir $pathlist {
    if {$dir eq "" || ![file isdirectory $dir]} {
      continue
    }
    foreach candidate [list \
      [file join $dir $lookup] \
      [file join $dir $tail]] {
      if {$candidate ne "" && [file exists $candidate] && [room_sym_file_looks_valid $candidate]} {
        return $candidate
      }
    }
  }
  return ""
}

proc room_pick_symbol_file {lookup {paths {}} {maxdepth -1}} {
  set stock ""
  if {[info commands find_file_first_orig] ne ""} {
    set stock [find_file_first_orig $lookup $paths $maxdepth]
  }
  if {$stock ne "" && [room_sym_file_looks_valid $stock]} {
    return $stock
  }
  set hierSym [room_find_hierarchy_sym $lookup]
  if {$hierSym ne ""} {
    return $hierSym
  }
  set coreSym [room_resolve_symbol_file $lookup]
  if {$coreSym ne "" && [file exists $coreSym] && [room_sym_file_looks_valid $coreSym]} {
    return $coreSym
  }
  if {$stock ne "" && [file exists $stock] && [room_sym_file_looks_valid $stock]} {
    return $stock
  }
  return ""
}

proc room_copy_sch_syms {srcdir outdir {protect_sch ""}} {
  if {$srcdir eq "" || ![file isdirectory $srcdir]} {
    return
  }
  foreach pattern {*.sym *.sch} {
    if {[catch {set files [glob -nocomplain -directory $srcdir $pattern]}]} {
      continue
    }
    foreach f $files {
      set tail [file tail $f]
      if {$pattern eq "*.sch" && $protect_sch ne "" && $tail eq $protect_sch} {
        continue
      }
      set dst [file join $outdir $tail]
      if {$pattern eq "*.sym"} {
        catch {file copy -force $f $dst}
      } elseif {![file exists $dst]} {
        catch {file copy -force $f $dst}
      }
    }
  }
}

proc room_safe_subdirs {parent} {
  if {$parent eq "" || ![file isdirectory $parent]} {
    return {}
  }
  if {[catch {set subs [glob -nocomplain -directory $parent *]}]} {
    return {}
  }
  set result {}
  foreach sub $subs {
    if {[file isdirectory $sub]} {
      lappend result $sub
    }
  }
  return $result
}

proc room_stage_hierarchy_syms {sch outdir} {
  set protect [file tail $sch]
  set roompath [room_get_binding $sch]
  if {$roompath ne "" && [file exists $roompath]} {
    set coredir [file dirname [file normalize $roompath]]
    set parent [file dirname $coredir]
    foreach sub [room_safe_subdirs $parent] {
      room_copy_sch_syms $sub $outdir $protect
    }
  }
  room_copy_sch_syms [file dirname [file normalize $sch]] $outdir $protect
}

proc room_refresh_sch_on_disk {sch} {
  if {$sch eq "" || ![file exists $sch]} {
    return
  }
  if {[catch {set data [xschem get_data]} err]} {
    return
  }
  catch {room_write_sch_data $sch $data}
}

proc room_batch_netlist_rc {} {
  set batch [file join $::ROOM_SCRIPT_DIR xschem-batch.rc]
  if {[file exists $batch]} {
    return $batch
  }
  foreach candidate [list \
    [file join $::env(HOME) .local share xschem xschemrc]] {
    if {[file exists $candidate]} {
      return $candidate
    }
  }
  return ""
}

proc room_ensure_pdk_env {} {
  if {![info exists ::env(PDK_ROOT)] || $::env(PDK_ROOT) eq ""} {
    foreach pdk [list \
      /mnt/c/Work/IHP \
      [file join $::env(HOME) IHP-Open-PDK] \
      /mnt/c/Users/anton/Documents/IHP-Open-PDK] {
      if {[file isdirectory [file join $pdk ihp-sg13g2]]} {
        set ::env(PDK_ROOT) $pdk
        break
      }
    }
  }
  if {![info exists ::env(PDK)] || $::env(PDK) eq ""} {
    set ::env(PDK) ihp-sg13g2
  }
}

proc room_simulation_succeeded {code msg simdir} {
  if {$code == 0} {
    return 1
  }
  foreach raw [list \
    [file join $simdir test_inverter.raw] \
    [file join $simdir tran.raw]] {
    if {[file exists $raw] && [file size $raw] > 100} {
      return 1
    }
  }
  if {[regexp {No\. of Data Rows} $msg]} {
    return 1
  }
  if {[regexp -nocase {TRAN done} $msg]} {
    return 1
  }
  return 0
}

proc room_netlist_looks_valid {nf} {
  if {![file exists $nf]} {
    return 0
  }
  if {[catch {set fh [open $nf r]}]} {
    return 0
  }
  set content [read $fh]
  close $fh
  # Ignore spice_ignore lines (e.g. analogLib/launcher emits template=name=h1).
  set filtered {}
  foreach line [split $content "\n"] {
    if {[string match -nocase "*spice_ignore=true*" $line]} {
      continue
    }
    append filtered $line "\n"
  }
  if {[regexp -nocase {template=name=} $filtered]} {
    return 0
  }
  if {[regexp {IS MISSING} $filtered]} {
    return 0
  }
  return 1
}

proc room_batch_netlist {outdir sch} {
  if {![file exists $sch]} {
    error "schematic not found: $sch"
  }
  room_refresh_sch_on_disk $sch
  room_stage_hierarchy_syms $sch $outdir
  set xschem_bin xschem
  if {[info exists ::env(XSCHEM_BIN)] && $::env(XSCHEM_BIN) ne ""} {
    set xschem_bin $::env(XSCHEM_BIN)
  }
  file mkdir $outdir
  set base [file rootname [file tail $sch]]
  set nf [file join $outdir ${base}.spice]
  set rc [room_batch_netlist_rc]
  set cmd [list $xschem_bin -n -q -s -o $outdir]
  if {$rc ne ""} {
    lappend cmd --rcfile $rc
  }
  lappend cmd $sch
  set err ""
  catch {exec {*}$cmd} err
  if {![file exists $nf]} {
    error "batch netlist failed: $err"
  }
  if {![room_netlist_looks_valid $nf]} {
    error "netlist still has unresolved symbols: $nf\n$err"
  }
  return $nf
}

proc room_prepare_for_simulate {} {
  set sch [xschem get schname]
  set roompath [room_get_binding $sch]
  if {$roompath ne ""} {
    room_add_hierarchy_search_paths $roompath
  }
  # Native load_data may leave schname pointing at a path that is not on disk yet.
  # Batch netlist and hierarchy staging need a real .sch file.
  if {$sch ne "" && ![file exists $sch]} {
    if {[catch {set data [xschem get_data]}]} {
      set data ""
    }
    if {$data ne ""} {
      catch {file mkdir [file dirname $sch]}
      catch {room_write_sch_data $sch $data}
    }
  }
  if {$sch ne "" && [file exists $sch]} {
    catch {xschem load $sch}
  }
  room_preload_primitives
  room_finish_primitive_setup
  catch {xschem reload_symbols}
  catch {xschem redraw}
}

# LibMan/ROOM: same netlist path as Simulate (batch + xschem-batch.rc), not interactive netlist.
proc room_ensure_netlist {d {sch ""} {batch_err_var ""}} {
  room_prepare_for_simulate
  if {$sch eq ""} {
    set sch [xschem get schname]
  }
  set nf ""
  set batch_err_msg ""
  if {$sch ne "" && ![file exists $sch]} {
    if {![catch {set data [xschem get_data]}] && $data ne ""} {
      catch {file mkdir [file dirname $sch]}
      catch {room_write_sch_data $sch $data}
    }
  }
  if {$sch ne "" && [file exists $sch]} {
    if {[catch {set nf [room_batch_netlist $d $sch]} err]} {
      set batch_err_msg $err
      puts "batch netlist: $err"
    }
  }
  if {$nf eq "" || ![file exists $nf] || ![room_netlist_looks_valid $nf]} {
    catch {xschem netlist}
    set nf [file join $d [xschem get netlist_name fallback]]
  }
  if {$nf eq "" || ![file exists $nf]} {
    if {$sch ne ""} {
      set nf [file join $d [file rootname [file tail $sch]].spice]
    }
  }
  if {$batch_err_var ne ""} {
    upvar 1 $batch_err_var batch_err_out
    set batch_err_out $batch_err_msg
  }
  return $nf
}

proc room_report_sim_result {code msg nf d} {
  set logfile [file join $d sim.log]
  catch {
    set lf [open $logfile a]
    puts $lf "=== [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] ==="
    puts $lf "netlist: $nf"
    puts $lf $msg
    close $lf
  }
  set summary ""
  if {$code == 0} {
    set summary "Simulation completed."
    foreach raw [list \
      [file join $d test_inverter.raw] \
      [file join $d tran.raw]] {
      if {[file exists $raw]} {
        append summary "\n\nRaw file:\n$raw"
        break
      }
    }
    catch {tk_messageBox -icon info -title "Xschem simulation" -message $summary}
  } else {
    set short $msg
    if {[string length $short] > 600} {
      set short "[string range $short 0 600]..."
    }
    set summary "ngspice failed (exit $code).\n\n$short\n\nNetlist:\n$nf\nLog:\n$logfile"
    catch {tk_messageBox -icon error -title "Xschem simulation failed" -message $summary}
  }
}

proc room_install_simulate_hook {} {
  if {[info commands simulate_orig] ne ""} {
    return
  }
  if {[info commands simulate] eq ""} {
    after 200 room_install_simulate_hook
    return
  }
  rename simulate simulate_orig
  # WSL/LibMan: avoid xschem execute_fileevent (ps + Tk screen geometry breaks on WSLg).
  if {[info exists ::env(XSCHEM_NETLIST_DIR)] && $::env(XSCHEM_NETLIST_DIR) ne ""} {
    proc simulate {{callback {}}} {
      global netlist_dir
      set d $netlist_dir
      if {$d eq ""} {
        catch {set d [xschem get netlist_dir]}
      }
      set batch_err ""
      set nf [room_ensure_netlist $d "" batch_err]
      if {![file exists $nf]} {
        set msg "Netlist not found."
        if {$batch_err ne ""} { append msg "\n\nBatch netlist:\n$batch_err" }
        room_report_sim_result -1 $msg $nf $d
        return -1
      }
      if {![room_netlist_looks_valid $nf]} {
        set msg "Netlist has unresolved symbols (template=... or IS MISSING).\nCheck PDK_ROOT and that inverter.sch/sym are findable."
        if {$batch_err ne ""} { append msg "\n\nBatch netlist:\n$batch_err" }
        room_report_sim_result -1 $msg $nf $d
        return -1
      }
      set save [pwd]
      cd $d
      room_ensure_pdk_env
      puts "Running: ngspice -b $nf"
      set code [catch {exec ngspice -b $nf} msg]
      cd $save
      if {$msg ne ""} {
        puts $msg
      }
      if {[room_simulation_succeeded $code $msg $d]} {
        set code 0
      }
      room_report_sim_result $code $msg $nf $d
      if {$callback ne ""} {
        uplevel #0 $callback
      }
      return $code
    }
    return
  }
  proc simulate {{callback {}}} {
    global netlist_dir
    set d $netlist_dir
    if {$d eq ""} {
      catch {set d [xschem get netlist_dir]}
    }
    set nf [file join $d [xschem get netlist_name fallback]]
    if {![file exists $nf]} {
      xschem netlist
    }
    simulate_orig $callback
  }
}

proc room_open {roompath {cell ""}} {
  room_ensure_loaded
  if {![file exists $roompath]} {
    tk_messageBox -icon error -message "ROOM file not found:\n$roompath"
    return
  }
  if {![room_is_room_path $roompath]} {
    tk_messageBox -icon error -message "Not an Xschem ROOM file.\nExpected .schematic.room or .symbol.room:\n$roompath"
    return
  }
  if {$cell eq ""} {
    set guess [room_guess_cell_name $roompath]
    set cells [room_list_cells $roompath]
    if {[llength $cells] == 0} {
      tk_messageBox -icon error -message "No cells in:\n$roompath"
      return
    }
    if {$guess ne "" && [lsearch -exact $cells $guess] >= 0} {
      set cell $guess
    } elseif {[llength $cells] == 1} {
      set cell [lindex $cells 0]
    } else {
      set cell [room_pick_cell $cells "Open ROOM: [file tail $roompath]"]
      if {$cell eq ""} {
        return
      }
    }
  }
  set roompath [file normalize $roompath]
  set ::room_active_roompath $roompath
  set ::room_active_cell $cell
  room_add_hierarchy_search_paths $roompath
  room_preload_primitives
  if {[room_has_native_bridge]} {
    if {[catch {set data [coreapi_export_cell_data $roompath $cell]} err]} {
      tk_messageBox -icon error -message "Failed to open ROOM:\n$err"
      return
    }
    if {[catch {room_load_room_data $data $roompath $cell} err]} {
      tk_messageBox -icon error -message "Failed to load ROOM into xschem:\n$err"
      return
    }
    room_apply_cell_names $roompath $cell
    room_schedule_title_refresh
    room_schedule_primitive_reload
    after 300 [list room_netlist_when_ready 0 $cell]
    room_lock_on_open $roompath
    return
  }
  set view [room_view_from_path $roompath]
  set ext [room_ext_for_view $view]
  if {[string match *.* $cell]} {
    set sch [room_temp_sch_path [file tail $cell] $ext]
  } else {
    set sch [room_temp_sch_path $cell $ext]
  }
  if {[catch {room_export_cell_to_sch $roompath $cell $sch} err]} {
    tk_messageBox -icon error -message "Failed to open ROOM:\n$err"
    return
  }
  room_set_binding $sch $roompath
  xschem load $sch
  room_apply_cell_names $roompath $cell
  room_schedule_title_refresh
  room_schedule_primitive_reload
  after 300 [list room_netlist_when_ready 0 $cell]
  room_lock_on_open $roompath
}

proc room_refresh_window_title {{mod {}}} {
  set sch [xschem get schname]
  if {$sch eq ""} {
    return
  }
  room_try_bind_payload_sch $sch
  set roompath [room_get_binding $sch]
  if {$roompath eq ""} {
    return
  }
  set label [file tail $roompath]
  if {[room_lock_is_viewonly $roompath]} {
    set label "\[Read-only\] $label"
  }
  if {[catch {set win [xschem get top_path]}] || $win eq {}} {
    set win .
  }
  wm title $win "xschem - $label$mod"
  wm iconname $win "xschem - $label$mod"
  if {[info exists ::tabbed_interface] && $::tabbed_interface} {
    set currwin [xschem get current_win_path]
    regsub {\.drw$} $currwin {} tabname
    if {$tabname eq {}} {
      set tabname .x0
    }
    if {[winfo exists .tabs$tabname]} {
      .tabs$tabname configure -text ${label}${mod}
      catch {balloon .tabs$tabname $roompath}
    }
  }
}

proc room_install_title_hooks {} {
  if {[info commands set_tab_names_orig] ne ""} {
    return
  }
  if {[info commands set_tab_names] eq ""} {
    after 200 room_install_title_hooks
    return
  }
  rename set_tab_names set_tab_names_orig
  proc set_tab_names {{mod {}}} {
    set_tab_names_orig $mod
    room_refresh_window_title $mod
  }
}

proc room_write {sch roompath} {
  room_ensure_loaded
  room_lock_assert_writable $roompath
  if {![room_is_room_path $roompath]} {
    error "ROOM path must be .schematic.room or .symbol.room: $roompath"
  }
  if {[room_has_native_bridge] && [info commands coreapi_import_data] ne ""} {
    if {[catch {set data [xschem get_data]} err]} {
      error $err
    }
    if {[catch {coreapi_import_data $data $roompath -lib xschem} err]} {
      error $err
    }
    catch {xschem set_modify 0}
  } elseif {[catch {coreapi_import $sch $roompath -lib xschem} err]} {
    error $err
  }
  room_set_binding $sch $roompath
}

proc room_file_open {} {
  set initdir $::ROOM_ROOT/designs/xschem
  if {![file isdirectory $initdir]} {
    set initdir $::ROOM_ROOT
  }
  set f [tk_getOpenFile -initialdir $initdir \
    -title "Open schematic, symbol, or ROOM file" \
    -filetypes {
      {{ROOM schematic} {.schematic.room}}
      {{ROOM symbol} {.symbol.room}}
      {{Xschem schematic} {.sch}}
      {{Xschem symbol} {.sym}}
      {{All files} *}
    }]
  if {$f eq ""} {
    return
  }
  if {[room_is_room_path $f]} {
    room_open $f
  } else {
    xschem load $f
    room_try_bind_payload_sch [xschem get schname]
    room_schedule_title_refresh
  }
}

proc room_file_save {} {
  set sch [xschem get schname]
  if {$sch eq ""} {
    return
  }
  if {[room_lock_is_viewonly]} {
    tk_messageBox -icon warning -message "Document is read-only.\n\n[room_lock_status_text]"
    return
  }
  set roompath [room_resolve_roompath $sch]
  if {$roompath ne ""} {
    room_set_binding $sch $roompath
    if {[catch {room_write $sch $roompath} err]} {
      tk_messageBox -icon error -message "ROOM save failed:\n$err"
      room_log_launch "ROOM save FAILED: $roompath ($err)"
    } else {
      room_log_launch "ROOM saved: $roompath"
      catch {room_refresh_window_title " (saved)"}
    }
    return
  }
  xschem save
  room_log_launch "xschem save only (no ROOM binding): $sch"
}

proc room_file_saveas {} {
  if {[room_lock_is_viewonly]} {
    tk_messageBox -icon warning -message "Document is read-only.\n\n[room_lock_status_text]"
    return
  }
  set sch [xschem get schname]
  set initdir [file dirname $sch]
  if {$initdir eq "." || $initdir eq ""} {
    set initdir $::ROOM_ROOT/designs/xschem
  }
  set f [tk_getSaveFile -initialdir $initdir \
    -title "Save schematic, symbol, or ROOM file" \
    -defaultextension [room_save_defaultextension] \
    -filetypes {
      {{ROOM schematic} {.schematic.room}}
      {{ROOM symbol} {.symbol.room}}
      {{Xschem schematic} {.sch}}
      {{Xschem symbol} {.sym}}
    }]
  if {$f eq ""} {
    return
  }
  if {[room_is_room_path $f]} {
    if {[room_has_native_bridge]} {
      if {[catch {room_write [xschem get schname] $f} err]} {
        tk_messageBox -icon error -message "ROOM save failed:\n$err"
        return
      }
      room_set_binding [xschem get schname] $f
    } else {
      set cell [room_cell_from_path $f]
      set view [room_view_from_path $f]
      set schout [room_temp_sch_path $cell [room_ext_for_view $view]]
      xschem saveas $schout
      if {[catch {room_write $schout $f} err]} {
        tk_messageBox -icon error -message "ROOM save failed:\n$err"
        return
      }
    }
  } else {
    xschem saveas $f
    set newsch [xschem get schname]
    if {$newsch ne ""} {
      room_clear_binding $newsch
    }
  }
}

proc room_resolve_roompath {{sch ""}} {
  if {$sch ne ""} {
    set roompath [room_get_binding $sch]
    if {$roompath ne ""} {
      return $roompath
    }
  }
  if {[info exists ::room_active_roompath] && $::room_active_roompath ne ""} {
    return $::room_active_roompath
  }
  return ""
}

proc room_log_launch {msg} {
  if {![info exists ::env(XSCHEM_LAUNCH_LOG)] || $::env(XSCHEM_LAUNCH_LOG) eq ""} {
    return
  }
  catch {
    set lf [open $::env(XSCHEM_LAUNCH_LOG) a]
    puts $lf "[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}] $msg"
    close $lf
  }
}

proc room_install_file_hooks {} {
  if {[catch {set topwin [xschem get top_path]}]} {
    after 500 room_install_file_hooks
    return
  }
  catch {
    $topwin.menubar.file entryconfigure "Open" -command room_file_open
    $topwin.menubar.file entryconfigure "Save" -command room_file_save
    $topwin.menubar.file entryconfigure "Save as" -command room_file_saveas
  }
  catch {
    bind $topwin <Control-o> {room_file_open ;# %}
    bind $topwin <Control-s> {room_file_save ;# %}
  }
  # Toolbar still uses "xschem save" by default — only writes /tmp/*.sch, not ROOM.
  catch {
    if {[winfo exists $topwin.toolbar.bFileSave]} {
      $topwin.toolbar.bFileSave configure -command room_file_save
    }
    if {[winfo exists $topwin.toolbar.bFileSaveAs]} {
      $topwin.toolbar.bFileSaveAs configure -command room_file_saveas
    }
  }
  room_lock_sync_ui
}

proc room_save_current {} {
  if {[room_lock_is_viewonly]} {
    tk_messageBox -icon warning -message "Document is read-only.\n\n[room_lock_status_text]"
    return
  }
  room_file_save
  set sch [xschem get schname]
  if {$sch eq ""} {
    return
  }
  if {[room_get_binding $sch] eq ""} {
    set roompath [room_default_room_path $sch]
    file mkdir [file dirname $roompath]
    if {[catch {room_write $sch $roompath} err]} {
      tk_messageBox -icon error -message "ROOM save failed:\n$err"
      return
    }
    room_set_binding $sch $roompath
  }
}

proc room_open_default {} {
  if {[file exists $::ROOM_LIB]} {
    room_open $::ROOM_LIB
  } else {
    room_file_open
  }
}

proc room_sync_payload {} {
  room_ensure_loaded
  set roompath $::ROOM_LIB
  if {![file exists $roompath]} {
    tk_messageBox -icon error -message "Default ROOM file not found:\n$roompath"
    return
  }
  set payload [room_payload_dir $roompath]
  file mkdir $payload
  if {[catch {coreapi_export_all $roompath $payload} err]} {
    tk_messageBox -icon error -message "ROOM sync failed:\n$err"
    return
  }
  tk_messageBox -icon info -message "Exported all cells to:\n$payload"
}

proc room_add_menu {} {
  set topwin [xschem get top_path]
  set liblabel [file tail $::ROOM_LIB]
  catch {
    $topwin.menubar.file insert 4 cascade -label ROOM -menu $topwin.menubar.room
    menu $topwin.menubar.room -tearoff 0
    $topwin.menubar.room add command -label "Open..." -command room_file_open
    $topwin.menubar.room add command -label "Save" -command room_file_save
    $topwin.menubar.room add command -label "Save as..." -command room_file_saveas
    $topwin.menubar.room add separator
    $topwin.menubar.room add command -label "Open $liblabel" -command room_open_default
    $topwin.menubar.room add command -label "Save to $liblabel" -command room_save_current
    $topwin.menubar.room add command -label "Sync payload folder" -command room_sync_payload
  }
}

proc room_ensure_window_geometry {} {
  if {[catch {set win [xschem get topwindow]}]} {
    return
  }
  if {$win eq ""} {
    return
  }
  if {[catch {set exists [winfo exists $win]}] || !$exists} {
    return
  }
  set force 0
  if {[catch {set geom [wm geometry $win]}]} {
    set force 1
  } elseif {[regexp {^(\d+)x(\d+)} $geom -> w h]} {
    if {$w < 200 || $h < 200} {
      set force 1
    }
  } else {
    set force 1
  }
  if {$force} {
    wm geometry $win 1300x950+100+50
  }
  catch {wm deiconify $win}
  catch {wm state $win normal}
  catch {raise $win}
  catch {focus $win}
}

proc room_primitive_cache_dir {} {
  if {[info exists ::room_primitive_cache] && $::room_primitive_cache ne ""} {
    return [file normalize $::room_primitive_cache]
  }
  if {[info exists ::env(XSCHEM_PRIMITIVE_CACHE)] && $::env(XSCHEM_PRIMITIVE_CACHE) ne ""} {
    return [file normalize $::env(XSCHEM_PRIMITIVE_CACHE)]
  }
  return [file join $::ROOM_SCRIPT_DIR primitive_cache]
}

proc room_split_primitive_libs {raw} {
  set raw [string trim $raw]
  if {$raw eq ""} {
    return {}
  }
  if {[string first ";" $raw] >= 0} {
    set parts [split $raw ";"]
  } elseif {[string match *:/* $raw] || [string match *:/mnt/* $raw]} {
    set parts [split $raw ":"]
  } else {
    return [list $raw]
  }
  set normalized {}
  foreach p $parts {
    set p [room_normalize_primitive_path $p]
    if {$p ne ""} {
      lappend normalized $p
    }
  }
  return $normalized
}

# LibMan on Windows writes C:\... paths; WSL xschem needs /mnt/c/...
proc room_normalize_primitive_path {path} {
  set path [string trim $path]
  if {$path eq ""} {
    return ""
  }
  if {[string match /mnt/* $path]} {
    return $path
  }
  if {[regexp {^([A-Za-z]):[/\\](.*)$} $path -> drive rest]} {
    set rest [string map {\\ /} $rest]
    return "/mnt/[string tolower $drive]/$rest"
  }
  return $path
}

proc room_lib_prefix_from_roompath {roompath} {
  set parent [file dirname $roompath]
  set lib_dir [file tail [file dirname $parent]]
  if {$lib_dir eq "" || $lib_dir eq "."} {
    return ""
  }
  return $lib_dir
}

proc room_register_symbol_key {key roompath} {
  if {$key eq "" || $roompath eq ""} {
    return
  }
  set ::room_symbol_index($key) $roompath
}

# Xschem built-in devices (lab_pin, lab_wire, code_shown, …): referenced as
# lab_pin.sym or devices/lab_pin.sym depending on export source.
proc room_system_device_library_roots {} {
  set roots {}
  foreach lib {
    [file join $env(HOME) .local share xschem xschem_library]
    [file join $::XSCHEM_ROOT xschem-src xschem_library]
  } {
    if {[file isdirectory $lib]} {
      lappend roots [file normalize $lib]
    }
  }
  return $roots
}

proc room_register_system_devices {} {
  array unset ::room_system_device_index
  array set ::room_system_device_index {}
  foreach root [room_system_device_library_roots] {
    set devdir [file join $root devices]
    if {![file isdirectory $devdir]} {
      continue
    }
    foreach sym [glob -nocomplain -directory $devdir *.sym] {
      set name [file tail $sym]
      set norm [file normalize $sym]
      set ::room_system_device_index($name) $norm
      set ::room_system_device_index("devices/$name") $norm
    }
  }
}

proc room_resolve_system_device {symref} {
  if {$symref eq ""} {
    return ""
  }
  if {[info exists ::room_system_device_index($symref)]} {
    return $::room_system_device_index($symref)
  }
  set tail [file tail $symref]
  if {$tail ne $symref && [info exists ::room_system_device_index($tail)]} {
    return $::room_system_device_index($tail)
  }
  foreach root [room_system_device_library_roots] {
    foreach candidate [list $symref $tail "devices/$tail"] {
      set path [file join $root $candidate]
      if {[file exists $path]} {
        return [file normalize $path]
      }
      set path [file join $root devices $tail]
      if {[file exists $path]} {
        return [file normalize $path]
      }
    }
  }
  return ""
}

proc room_cell_from_symbol_room {roompath} {
  set tail [file tail $roompath]
  if {[regexp {^(.+)\.symbol\.(room|core)$} $tail -> cell]} {
    return $cell
  }
  return ""
}

proc room_primitive_lib_paths {} {
  set cores {}
  if {[info exists ::env(ROOM_PRIMITIVE_LIBS_FILE)] && $::env(ROOM_PRIMITIVE_LIBS_FILE) ne ""} {
    set listfile $::env(ROOM_PRIMITIVE_LIBS_FILE)
    if {[file exists $listfile]} {
      if {[catch {set fh [open $listfile r]} err] == 0} {
        while {[gets $fh line] >= 0} {
          set line [room_normalize_primitive_path [string trim $line]]
          if {$line ne ""} {
            lappend cores $line
          }
        }
        close $fh
      }
    }
  }
  if {[llength $cores] > 0} {
    return $cores
  }
  if {[info exists ::env(ROOM_PRIMITIVE_LIBS)] && $::env(ROOM_PRIMITIVE_LIBS) ne ""} {
    return [room_split_primitive_libs $::env(ROOM_PRIMITIVE_LIBS)]
  }
  if {[info exists ::env(ROOM_PRIMITIVE_LIB)] && $::env(ROOM_PRIMITIVE_LIB) ne ""} {
    return [list $::env(ROOM_PRIMITIVE_LIB)]
  }
  return {}
}

proc room_build_symbol_index {} {
  array unset ::room_symbol_index
  array set ::room_symbol_index {}
  array unset ::room_symbol_materialized
  array set ::room_symbol_materialized {}

  set cores [room_primitive_lib_paths]
  if {[llength $cores] == 0} {
    return
  }

  set techlib ""
  if {[info exists ::env(LIBMAN_TECH_LIBRARY)] && $::env(LIBMAN_TECH_LIBRARY) ne ""} {
    set techlib $::env(LIBMAN_TECH_LIBRARY)
  }

  foreach roompath $cores {
    set roompath [room_normalize_primitive_path [string trim $roompath]]
    if {$roompath eq "" || ![file exists $roompath]} {
      continue
    }
    set cell [room_cell_from_symbol_room $roompath]
    if {$cell eq ""} {
      continue
    }
    room_register_symbol_key "$cell.sym" $roompath
    set libpfx [room_lib_prefix_from_roompath $roompath]
    if {$libpfx ne ""} {
      room_register_symbol_key "$libpfx/$cell.sym" $roompath
    }
    if {$libpfx eq "commonLib"} {
      room_register_symbol_key "devices/$cell.sym" $roompath
    }
    # Simulation controllers / sources are analogLib; keep analogLib/ keys even if a
    # legacy ROOM still lives under commonLib (resolver remaps commonLib -> analogLib).
    foreach simcell {launcher INCLSCR TR Vdc Vac Vpulse Vexp Vrect Idc Iac Ipulse GND vdd vss} {
      if {$cell eq $simcell} {
        room_register_symbol_key "analogLib/$cell.sym" $roompath
        break
      }
    }
    if {$libpfx eq "analogLib" && $cell eq "launcher"} {
      # Bare name for older schematics that still say C {launcher.sym}
      room_register_symbol_key "launcher.sym" $roompath
    }
    if {$techlib ne ""} {
      foreach tlib [split $techlib {;}] {
        set tlib [string trim $tlib]
        if {$tlib ne ""} {
          room_register_symbol_key "$tlib/$cell.sym" $roompath
        }
      }
    }
    room_register_symbol_key [file tail $roompath] $roompath

    # Qucs Model names <-> Xschem devices/*.sym aliases (analogLib / commonLib)
    switch -exact -- $cell {
      R { set aliases [list res] }
      C { set aliases [list capa] }
      L { set aliases [list ind] }
      GND { set aliases [list gnd] }
      Vdc - Vac - Vpulse - Vexp - Vrect { set aliases [list vsource] }
      Idc - Iac - Ipulse - Iexp - Irect { set aliases [list isource] }
      Vfile - Vpwl { set aliases [list vsource_pwl] }
      Ifile - Ipwl { set aliases [list isource_pwl] }
      Varith { set aliases [list vsource_arith] }
      Iarith { set aliases [list isource_arith] }
      vdd { set aliases [list vdd] }
      vss { set aliases [list vss] }
      iopin { set aliases [list Port] }
      ipin { set aliases [list Port] }
      opin { set aliases [list Port] }
      Port { set aliases [list iopin ipin opin] }
      res { set aliases [list R] }
      capa { set aliases [list C] }
      ind { set aliases [list L] }
      gnd { set aliases [list GND] }
      vsource { set aliases [list Vdc Vac Vpulse Vexp Vrect] }
      isource { set aliases [list Idc Iac Ipulse Iexp Irect] }
      vsource_pwl { set aliases [list Vfile Vpwl] }
      isource_pwl { set aliases [list Ifile Ipwl] }
      vsource_arith { set aliases [list Varith] }
      isource_arith { set aliases [list Iarith] }
      default { set aliases {} }
    }
    foreach alias $aliases {
      room_register_symbol_key "$alias.sym" $roompath
      if {$techlib ne ""} {
        foreach tlib [split $techlib {;}] {
          set tlib [string trim $tlib]
          if {$tlib ne ""} {
            room_register_symbol_key "$tlib/$alias.sym" $roompath
          }
        }
      }
    }  }
}

proc room_materialize_symbol {symref} {
  if {![info exists ::room_symbol_index($symref)]} {
    return ""
  }
  if {[info exists ::room_symbol_materialized($symref)]} {
    return $::room_symbol_materialized($symref)
  }

  set roompath $::room_symbol_index($symref)
  room_ensure_loaded
  set parsed [coreapi_parse_core_path $roompath]
  lassign $parsed cell view
  if {$cell eq ""} {
    return ""
  }

  set cache [room_primitive_cache_dir]
  set outdir $cache
  if {[string first "/" $symref] >= 0} {
    set outdir [file join $cache [file dirname $symref]]
  } else {
    set libpfx [room_lib_prefix_from_roompath $roompath]
    if {$libpfx ne ""} {
      set outdir [file join $cache $libpfx]
    } elseif {[info exists ::env(LIBMAN_TECH_LIBRARY)] && $::env(LIBMAN_TECH_LIBRARY) ne ""} {
      foreach tlib [split $::env(LIBMAN_TECH_LIBRARY) ";"] {
        set tlib [string trim $tlib]
        if {$tlib ne ""} {
          set outdir [file join $cache $tlib]
          break
        }
      }
    }
  }
  file mkdir $outdir
  set sym [file join $outdir "$cell.sym"]
  if {[catch {coreapi_export_cell $roompath $cell $sym} err]} {
    puts stderr "Failed to materialize ROOM symbol $symref from $roompath: $err"
    return ""
  }
  set ::room_symbol_materialized($symref) $sym
  room_refresh_pathlist
  return $sym
}

proc room_schedule_primitive_reload {} {
  foreach delay {50 400 1200} {
    after $delay room_finish_primitive_setup
  }
}

proc room_finish_primitive_setup {} {
  room_build_symbol_index
  room_refresh_pathlist
  if {![info exists ::room_primitive_setup_done]} {
    set ::room_primitive_setup_done 1
  }
  catch {xschem reload_symbols}
  catch {xschem redraw}
}

proc room_resolve_symbol_file {f} {
  set sys [room_resolve_system_device $f]
  if {$sys ne ""} {
    return $sys
  }
  if {![info exists ::room_primitive_setup_done]} {
    return ""
  }
  foreach key [list $f [file tail $f]] {
    if {$key eq ""} {
      continue
    }
    if {[info exists ::room_symbol_index($key)]} {
      set sym [room_materialize_symbol $key]
      if {$sym ne "" && [file exists $sym]} {
        return $sym
      }
    }
  }
  return ""
}

proc room_install_symbol_hooks {} {
  if {[info commands find_file_first] eq ""} {
    return
  }
  if {[info commands find_file_first_orig] ne ""} {
    return
  }
  rename find_file_first find_file_first_orig
  proc find_file_first {f {paths {}} {maxdepth -1}} {
    return [room_pick_symbol_file $f $paths $maxdepth]
  }

  if {[info commands find_file] eq ""} {
    return
  }
  rename find_file find_file_orig
  proc find_file {f {paths {}} {maxdepth -1}} {
    set picked [room_pick_symbol_file $f $paths $maxdepth]
    if {$picked ne ""} {
      return [list $picked]
    }
    return [find_file_orig $f $paths $maxdepth]
  }
}

# load_sym_def() resolves symbols via Tcl abs_sym_path, not find_file.
proc room_install_abs_sym_path_hook {} {
  if {[info commands abs_sym_path] eq ""} {
    return
  }
  if {[info commands abs_sym_path_orig] ne ""} {
    return
  }
  rename abs_sym_path abs_sym_path_orig
  proc abs_sym_path {fname {ext {}} {paths {}}} {
    set lookup $fname
    if {$ext ne {}} {
      set lookup [file rootname $fname]$ext
    }
    set picked [room_pick_symbol_file $lookup $paths]
    if {$picked ne "" && [file exists $picked]} {
      return $picked
    }
    return [abs_sym_path_orig $fname $ext $paths]
  }
}

proc room_setup_primitive_library {} {
  room_build_symbol_index
  room_refresh_pathlist
  room_install_symbol_hooks
  room_install_abs_sym_path_hook
}

proc room_refresh_pathlist {} {
  global pathlist
  if {![info exists pathlist]} {
    return
  }
  set cache [room_primitive_cache_dir]
  if {$cache eq "" || ![file isdirectory $cache]} {
    return
  }
  if {[lsearch -exact $pathlist $cache] < 0} {
    lappend pathlist $cache
  }
  # Always expose tier dirs so analogLib/foo.sym and commonLib/bar.sym resolve
  # from the seeded primitive_cache even before ROOM materialization.
  foreach tier {analogLib commonLib devices} {
    set sub [file join $cache $tier]
    if {[file isdirectory $sub] && [lsearch -exact $pathlist $sub] < 0} {
      lappend pathlist $sub
    }
  }
  if {[info exists ::env(LIBMAN_TECH_LIBRARY)] && $::env(LIBMAN_TECH_LIBRARY) ne ""} {
    foreach tlib [split $::env(LIBMAN_TECH_LIBRARY) ";"] {
      set tlib [string trim $tlib]
      if {$tlib eq ""} {
        continue
      }
      set sub [file join $cache $tlib]
      if {[file isdirectory $sub] && [lsearch -exact $pathlist $sub] < 0} {
        lappend pathlist $sub
      }
    }
  }
}

proc room_open_deferred {} {
  if {[info exists ::env(XSCHEM_OPEN_ROOM)] && $::env(XSCHEM_OPEN_ROOM) ne ""} {
    set path $::env(XSCHEM_OPEN_ROOM)
    unset ::env(XSCHEM_OPEN_ROOM)
    if {[catch {room_open $path} err]} {
      tk_messageBox -icon error -message "ROOM open failed:\n$err"
    }
    return
  }

  if {[info exists ::env(XSCHEM_OPEN_FILE)] && $::env(XSCHEM_OPEN_FILE) ne ""} {
    set path $::env(XSCHEM_OPEN_FILE)
    unset ::env(XSCHEM_OPEN_FILE)
    if {[catch {xschem load $path} err]} {
      tk_messageBox -icon error -message "Failed to open:\n$path\n\n$err"
    } else {
      room_try_bind_payload_sch [xschem get schname]
      room_schedule_title_refresh
    }
  }
}

proc room_install_wsl_execute_hook {} {
  if {[info commands execute_fileevent_orig] ne ""} {
    return
  }
  if {![info exists ::env(XSCHEM_NETLIST_DIR)] || $::env(XSCHEM_NETLIST_DIR) eq ""} {
    return
  }
  if {[info commands execute_fileevent] eq ""} {
    after 200 room_install_wsl_execute_hook
    return
  }
  rename execute_fileevent execute_fileevent_orig
  # WSLg: ps polling in execute_fileevent fails ("131072x1 screen size is bogus").
  proc execute_fileevent {id} {
    global execute has_x errorCode
    append execute(data,$id) [read $execute(pipe,$id) 1024]
    if {![eof $execute(pipe,$id)]} {
      return
    }
    set report [regexp {1} $execute(status,$id)]
    fileevent $execute(pipe,$id) readable ""
    fconfigure $execute(pipe,$id) -blocking 1
    set exit_status 0
    set catch_return [eval catch [list {close $execute(pipe,$id)} err] ]
    if {$catch_return} {
      if {"NONE" == [lindex $errorCode 0]} {
        set exit_status 0
      } elseif {"CHILDSTATUS" == [lindex $errorCode 0]} {
        set exit_status [lindex $errorCode 2]
      } else {
        set exit_status $catch_return
      }
      if {$exit_status != 0 && $report} {
        catch {viewdata "Failed: $execute(cmd,$id)\nstderr:\n$err\ndata:\n$execute(data,$id)"}
      } elseif {$report} {
        catch {viewdata "Completed: $execute(cmd,$id)\nstderr:\n$err\ndata:\n$execute(data,$id)"}
      }
    } elseif {$report} {
      catch {viewdata "Completed: $execute(cmd,$id)\ndata:\n$execute(data,$id)"}
    }
    set execute(exitcode,last) $exit_status
    set execute(exitcode,$id) $exit_status
    set execute(cmd,last) $execute(cmd,$id)
    set execute(win_path,last) $execute(win_path,$id)
    set execute(data,last) $execute(data,$id)
    if {![info exists err]} { set err {} }
    set execute(error,last) $err
    set execute(status,last) $execute(status,$id)
    if {[info exists execute(callback,$id)] && $execute(callback,$id) ne {}} {
      catch {eval uplevel #0 [list $execute(callback,$id)]}
    }
    catch {unset execute(callback,$id)}
    catch {unset execute(pipe,$id)}
    catch {unset execute(data,$id)}
    catch {unset execute(status,$id)}
    catch {unset execute(cmd,$id)}
    catch {unset execute(win_path,$id)}
    if {[info exists has_x] && [winfo exists .processlist]} {
      after 250 {insert_running_cmds .processlist.f2.lb}
    }
  }

  if {[info commands edit_netlist_orig] ne ""} {
    return
  }
  if {[info commands edit_netlist] eq ""} {
    return
  }
  rename edit_netlist edit_netlist_orig
  proc edit_netlist {netlist} {
    global netlist_dir
    regsub {/$} $netlist_dir {} netlist_dir
    if {[set_netlist_dir 0] eq ""} {
      return {}
    }
    set d $netlist_dir
    set batch_err ""
    set nf [room_ensure_netlist $d "" batch_err]
    if {![file exists $nf]} {
      set msg "Netlist not found."
      if {$batch_err ne ""} { append msg "\n\nBatch netlist:\n$batch_err" }
      tk_messageBox -icon warning -message $msg
      return {}
    }
    if {![room_netlist_looks_valid $nf]} {
      set msg "Netlist has unresolved symbols (template=... or IS MISSING).\n\n$nf"
      if {$batch_err ne ""} { append msg "\n\nBatch netlist:\n$batch_err" }
      tk_messageBox -icon warning -message $msg
    }
    set fh [open $nf r]
    set body [read $fh]
    close $fh
    if {[info commands viewdata] ne ""} {
      viewdata $body 1
    } else {
      tk_messageBox -icon info -message "Netlist:\n$nf"
    }
    return {}
  }
}

# Fast filename-only index before ROOM load; reload_symbols again after open/scripts.
after idle {
  room_install_title_hooks
  room_install_file_hooks
  room_install_simulate_hook
  room_install_wsl_execute_hook
  room_add_menu
  room_install_symbol_hooks
  room_install_abs_sym_path_hook
  room_lock_install_hooks
  room_register_system_devices
  room_build_symbol_index
  room_refresh_pathlist
  set ::room_primitive_setup_done 1
  room_open_deferred
  after 50 room_ensure_window_geometry
  after 150 room_ensure_window_geometry
  after 600 room_ensure_window_geometry
  after 1500 room_ensure_window_geometry
  after 800 room_install_file_hooks
  after 2000 room_install_file_hooks
  room_schedule_primitive_reload
}
