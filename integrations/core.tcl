# CORE in-process integration for Xschem (coretcl.so + CORE API).
# Xschem owns schematic/symbol views: cell.schematic.core, cell.symbol.core

set ::CORE_SCRIPT_DIR [file normalize [file dirname [info script]]]

if {![info exists ::XSCHEM_ROOT]} {
  set ::XSCHEM_ROOT [file normalize [file dirname $::CORE_SCRIPT_DIR]]
}

if {![info exists ::CORE_ROOT]} {
  if {[info exists ::env(COMMONDB_ROOT)] && $::env(COMMONDB_ROOT) ne ""} {
    set ::CORE_ROOT [file normalize $::env(COMMONDB_ROOT)]
  } elseif {[info exists ::env(CORE_ROOT)] && $::env(CORE_ROOT) ne ""} {
    set ::CORE_ROOT [file normalize $::env(CORE_ROOT)]
  } else {
    set ::CORE_ROOT [file normalize [file join $::XSCHEM_ROOT .. CommonDB]]
  }
}

set ::CORE_LIB [file join $::CORE_ROOT designs xschem test.schematic.core]
set ::CORE_PAYLOAD [file join $::CORE_ROOT designs xschem payload]

# sch/sym path -> backing .core file (keys are normalized absolute paths)
array set ::core_binding {}

proc core_norm_path {path} {
  if {$path eq ""} {
    return ""
  }
  return [file normalize $path]
}

proc core_set_binding {sch corepath} {
  set ::core_binding([core_norm_path $sch]) [core_norm_path $corepath]
}

proc core_get_binding {sch} {
  set key [core_norm_path $sch]
  if {$key ne "" && [info exists ::core_binding($key)]} {
    return $::core_binding($key)
  }
  return ""
}

proc core_clear_binding {sch} {
  set key [core_norm_path $sch]
  if {$key ne "" && [info exists ::core_binding($key)]} {
    unset ::core_binding($key)
  }
}

# payload/cell.sym opened directly -> bind parent cell.symbol.core for title/save.
proc core_try_bind_payload_sch {sch} {
  set sch [core_norm_path $sch]
  if {$sch eq "" || [core_get_binding $sch] ne ""} {
    return 0
  }
  if {![string equal -nocase [file tail [file dirname $sch]] payload]} {
    return 0
  }
  set parent [file dirname [file dirname $sch]]
  set cell [file rootname [file tail $sch]]
  foreach suffix {symbol.core schematic.core} {
    set corepath [file join $parent ${cell}.${suffix}]
    if {[file exists $corepath]} {
      core_set_binding $sch $corepath
      return 1
    }
  }
  return 0
}

proc core_schedule_title_refresh {} {
  foreach delay {0 100 400} {
    after $delay core_refresh_window_title
  }
}

proc core_find_tcl_lib {} {
  set candidates [list \
    [file join $::CORE_SCRIPT_DIR coretcl.so] \
    [file join $::CORE_ROOT build-wsl integrations xschem_tcl coretcl.so] \
    [file join $::CORE_ROOT build integrations xschem_tcl coretcl.so]]
  foreach path $candidates {
    if {[file exists $path]} {
      return $path
    }
  }
  return ""
}

proc core_ensure_loaded {} {
  if {[namespace which -command coreapi_list_cells] ne ""} {
    return
  }
  set lib [core_find_tcl_lib]
  if {$lib eq ""} {
    set build_script [file join $::XSCHEM_ROOT build-core-tcl.sh]
    error "coretcl.so not found. Run: bash $build_script"
  }
  load $lib Core
}

proc core_view_for_sch {schpath} {
  set ext [string tolower [file extension $schpath]]
  if {$ext eq ".sym"} {
    return symbol
  }
  return schematic
}

proc core_ext_for_view {view} {
  if {$view eq "symbol"} {
    return .sym
  }
  return .sch
}

proc core_is_core_path {path} {
  foreach view {schematic symbol} {
    if {[string match -nocase *.$view.core $path]} {
      return 1
    }
  }
  return 0
}

proc core_cell_from_path {path} {
  core_ensure_loaded
  return [lindex [coreapi_parse_core_path $path] 0]
}

proc core_view_from_path {path} {
  core_ensure_loaded
  return [lindex [coreapi_parse_core_path $path] 1]
}

proc core_path_for_cell {cell view {dir ""}} {
  core_ensure_loaded
  set name [coreapi_core_file_name $cell $view]
  if {$dir ne ""} {
    return [file join $dir $name]
  }
  return $name
}

proc core_default_core_path {sch} {
  set cell [file rootname [file tail $sch]]
  set view [core_view_for_sch $sch]
  set dir [file dirname $sch]
  if {[string equal -nocase [file tail $dir] payload]} {
    set dir [file dirname $dir]
  }
  return [core_path_for_cell $cell $view $dir]
}

proc core_save_defaultextension {} {
  set sch [xschem get schname]
  if {$sch ne "" && [string match -nocase *.sym $sch]} {
    return .symbol.core
  }
  return .schematic.core
}

proc core_payload_dir {corepath} {
  return [file join [file dirname $corepath] payload]
}

proc core_list_cells {corepath} {
  core_ensure_loaded
  return [coreapi_list_cells $corepath]
}

proc core_pick_cell {cells {title "Select cell"}} {
  set top .core_pick_cell
  if {[winfo exists $top]} {
    destroy $top
  }
  set ::core_pick_cell_answer ""
  toplevel $top
  wm title $top $title
  wm transient $top [xschem get topwindow]
  label $top.lbl -text "CORE file contains multiple cells:"
  listbox $top.lb -listvariable ::core_pick_cell_list -height 10 -width 40 \
    -exportselection 0 -selectmode browse
  set ::core_pick_cell_list $cells
  $top.lb selection set 0
  frame $top.btns
  button $top.btns.ok -text OK -command {
    set sel [.core_pick_cell.lb curselection]
    if {$sel ne {}} {
      set ::core_pick_cell_answer [lindex $::core_pick_cell_list $sel]
    }
    destroy .core_pick_cell
  }
  button $top.btns.cancel -text Cancel -command {destroy .core_pick_cell}
  pack $top.lbl -padx 8 -pady 4
  pack $top.lb -padx 8 -pady 4 -fill both -expand 1
  pack $top.btns.ok $top.btns.cancel -side left -padx 8 -pady 8
  pack $top.btns
  bind $top.lb <Double-Button-1> "$top.btns.ok invoke"
  tkwait window $top
  return $::core_pick_cell_answer
}

proc core_temp_sch_path {cell ext} {
  if {[catch {set fh [file tempfile -prefix "xschem_core_${cell}_" -suffix $ext]} err]} {
    set dir "/tmp"
    if {[info exists ::env(TEMP)] && $::env(TEMP) ne ""} {
      set dir $::env(TEMP)
    }
    return [file join $dir xschem_core_[pid]_[clock clicks]$ext]
  }
  close $fh
  return $fh
}

proc core_write_sch_data {sch data} {
  set fh [open $sch w]
  fconfigure $fh -translation binary
  puts -nonewline $fh $data
  close $fh
}

proc core_export_cell_to_sch {corepath cell sch} {
  if {[info commands coreapi_export_cell_data] ne ""} {
    set data [coreapi_export_cell_data $corepath $cell]
    core_write_sch_data $sch $data
    return
  }
  coreapi_export_cell $corepath $cell $sch
}

proc core_has_native_bridge {} {
  if {[info commands xschem] eq ""} {
    return 0
  }
  if {[catch {xschem load_data} err]} {
    return [expr {[string match {*load_data needs*} $err]}]
  }
  return 0
}

proc core_guess_cell_name {corepath} {
  set base [file rootname [file tail $corepath]]
  if {[regexp {^(.+)\.(schematic|symbol)$} $base -> cell]} {
    return $cell
  }
  return $base
}

proc core_open {corepath {cell ""}} {
  core_ensure_loaded
  if {![file exists $corepath]} {
    tk_messageBox -icon error -message "CORE file not found:\n$corepath"
    return
  }
  if {![core_is_core_path $corepath]} {
    tk_messageBox -icon error -message "Not an Xschem CORE file.\nExpected .schematic.core or .symbol.core:\n$corepath"
    return
  }
  if {$cell eq ""} {
    set guess [core_guess_cell_name $corepath]
    set cells [core_list_cells $corepath]
    if {[llength $cells] == 0} {
      tk_messageBox -icon error -message "No cells in:\n$corepath"
      return
    }
    if {$guess ne "" && [lsearch -exact $cells $guess] >= 0} {
      set cell $guess
    } elseif {[llength $cells] == 1} {
      set cell [lindex $cells 0]
    } else {
      set cell [core_pick_cell $cells "Open CORE: [file tail $corepath]"]
      if {$cell eq ""} {
        return
      }
    }
  }
  set corepath [file normalize $corepath]
  if {[core_has_native_bridge]} {
    if {[catch {set data [coreapi_export_cell_data $corepath $cell]} err]} {
      tk_messageBox -icon error -message "Failed to open CORE:\n$err"
      return
    }
    if {[catch {xschem load_data $data -schname $corepath} err]} {
      tk_messageBox -icon error -message "Failed to load CORE into xschem:\n$err"
      return
    }
    core_set_binding [xschem get schname] $corepath
    core_schedule_title_refresh
    core_schedule_primitive_reload
    return
  }
  set view [core_view_from_path $corepath]
  set ext [core_ext_for_view $view]
  if {[string match *.* $cell]} {
    set sch [core_temp_sch_path [file tail $cell] $ext]
  } else {
    set sch [core_temp_sch_path $cell $ext]
  }
  if {[catch {core_export_cell_to_sch $corepath $cell $sch} err]} {
    tk_messageBox -icon error -message "Failed to open CORE:\n$err"
    return
  }
  core_set_binding $sch $corepath
  xschem load $sch
  core_schedule_title_refresh
}

# Show .schematic.core / .symbol.core in window and tab titles (not payload/*.sch).
proc core_refresh_window_title {{mod {}}} {
  set sch [xschem get schname]
  if {$sch eq ""} {
    return
  }
  core_try_bind_payload_sch $sch
  set corepath [core_get_binding $sch]
  if {$corepath eq ""} {
    return
  }
  set label [file tail $corepath]
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
      catch {balloon .tabs$tabname $corepath}
    }
  }
}

proc core_install_title_hooks {} {
  if {[info commands set_tab_names_orig] ne ""} {
    return
  }
  if {[info commands set_tab_names] eq ""} {
    after 200 core_install_title_hooks
    return
  }
  rename set_tab_names set_tab_names_orig
  proc set_tab_names {{mod {}}} {
    set_tab_names_orig $mod
    core_refresh_window_title $mod
  }
}

proc core_write {sch corepath} {
  core_ensure_loaded
  if {![core_is_core_path $corepath]} {
    error "CORE path must be .schematic.core or .symbol.core: $corepath"
  }
  if {[core_has_native_bridge] && [info commands coreapi_import_data] ne ""} {
    if {[catch {set data [xschem get_data]} err]} {
      error $err
    }
    if {[catch {coreapi_import_data $data $corepath -lib xschem} err]} {
      error $err
    }
    catch {xschem set_modify 0}
  } elseif {[catch {coreapi_import $sch $corepath -lib xschem} err]} {
    error $err
  }
  core_set_binding $sch $corepath
}

proc core_file_open {} {
  set initdir $::CORE_ROOT/designs/xschem
  if {![file isdirectory $initdir]} {
    set initdir $::CORE_ROOT
  }
  set f [tk_getOpenFile -initialdir $initdir \
    -title "Open schematic, symbol, or CORE file" \
    -filetypes {
      {{CORE schematic} {.schematic.core}}
      {{CORE symbol} {.symbol.core}}
      {{Xschem schematic} {.sch}}
      {{Xschem symbol} {.sym}}
      {{All files} *}
    }]
  if {$f eq ""} {
    return
  }
  if {[core_is_core_path $f]} {
    core_open $f
  } else {
    xschem load $f
    core_try_bind_payload_sch [xschem get schname]
    core_schedule_title_refresh
  }
}

proc core_file_save {} {
  set sch [xschem get schname]
  if {$sch eq ""} {
    return
  }
  set corepath [core_get_binding $sch]
  if {$corepath ne ""} {
    if {[catch {core_write $sch $corepath} err]} {
      tk_messageBox -icon error -message "CORE save failed:\n$err"
    }
    return
  }
  xschem save
}

proc core_file_saveas {} {
  set sch [xschem get schname]
  set initdir [file dirname $sch]
  if {$initdir eq "." || $initdir eq ""} {
    set initdir $::CORE_ROOT/designs/xschem
  }
  set f [tk_getSaveFile -initialdir $initdir \
    -title "Save schematic, symbol, or CORE file" \
    -defaultextension [core_save_defaultextension] \
    -filetypes {
      {{CORE schematic} {.schematic.core}}
      {{CORE symbol} {.symbol.core}}
      {{Xschem schematic} {.sch}}
      {{Xschem symbol} {.sym}}
    }]
  if {$f eq ""} {
    return
  }
  if {[core_is_core_path $f]} {
    if {[core_has_native_bridge]} {
      if {[catch {core_write [xschem get schname] $f} err]} {
        tk_messageBox -icon error -message "CORE save failed:\n$err"
        return
      }
      core_set_binding [xschem get schname] $f
    } else {
      set cell [core_cell_from_path $f]
      set view [core_view_from_path $f]
      set schout [core_temp_sch_path $cell [core_ext_for_view $view]]
      xschem saveas $schout
      if {[catch {core_write $schout $f} err]} {
        tk_messageBox -icon error -message "CORE save failed:\n$err"
        return
      }
    }
  } else {
    xschem saveas $f
    set newsch [xschem get schname]
    if {$newsch ne ""} {
      core_clear_binding $newsch
    }
  }
}

proc core_install_file_hooks {} {
  if {[catch {set topwin [xschem get top_path]}]} {
    after 500 core_install_file_hooks
    return
  }
  catch {
    $topwin.menubar.file entryconfigure "Open" -command core_file_open
    $topwin.menubar.file entryconfigure "Save" -command core_file_save
    $topwin.menubar.file entryconfigure "Save as" -command core_file_saveas
  }
  catch {
    bind $topwin <Control-o> {core_file_open ;# %}
    bind $topwin <Control-s> {core_file_save ;# %}
  }
}

proc core_save_current {} {
  core_file_save
  set sch [xschem get schname]
  if {$sch eq ""} {
    return
  }
  if {[core_get_binding $sch] eq ""} {
    set corepath [core_default_core_path $sch]
    file mkdir [file dirname $corepath]
    if {[catch {core_write $sch $corepath} err]} {
      tk_messageBox -icon error -message "CORE save failed:\n$err"
      return
    }
    core_set_binding $sch $corepath
  }
}

proc core_open_default {} {
  if {[file exists $::CORE_LIB]} {
    core_open $::CORE_LIB
  } else {
    core_file_open
  }
}

proc core_sync_payload {} {
  core_ensure_loaded
  set corepath $::CORE_LIB
  if {![file exists $corepath]} {
    tk_messageBox -icon error -message "Default CORE file not found:\n$corepath"
    return
  }
  set payload [core_payload_dir $corepath]
  file mkdir $payload
  if {[catch {coreapi_export_all $corepath $payload} err]} {
    tk_messageBox -icon error -message "CORE sync failed:\n$err"
    return
  }
  tk_messageBox -icon info -message "Exported all cells to:\n$payload"
}

proc core_add_menu {} {
  set topwin [xschem get top_path]
  set liblabel [file tail $::CORE_LIB]
  catch {
    $topwin.menubar.file insert 4 cascade -label Core -menu $topwin.menubar.core
    menu $topwin.menubar.core -tearoff 0
    $topwin.menubar.core add command -label "Open..." -command core_file_open
    $topwin.menubar.core add command -label "Save" -command core_file_save
    $topwin.menubar.core add command -label "Save as..." -command core_file_saveas
    $topwin.menubar.core add separator
    $topwin.menubar.core add command -label "Open $liblabel" -command core_open_default
    $topwin.menubar.core add command -label "Save to $liblabel" -command core_save_current
    $topwin.menubar.core add command -label "Sync payload folder" -command core_sync_payload
  }
}

proc core_ensure_window_geometry {} {
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

proc core_primitive_cache_dir {} {
  if {[info exists ::core_primitive_cache] && $::core_primitive_cache ne ""} {
    return [file normalize $::core_primitive_cache]
  }
  if {[info exists ::env(XSCHEM_PRIMITIVE_CACHE)] && $::env(XSCHEM_PRIMITIVE_CACHE) ne ""} {
    return [file normalize $::env(XSCHEM_PRIMITIVE_CACHE)]
  }
  return [file join $::CORE_SCRIPT_DIR primitive_cache]
}

proc core_split_primitive_libs {raw} {
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
    set p [core_normalize_primitive_path $p]
    if {$p ne ""} {
      lappend normalized $p
    }
  }
  return $normalized
}

# LibMan on Windows writes C:\... paths; WSL xschem needs /mnt/c/...
proc core_normalize_primitive_path {path} {
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

proc core_lib_prefix_from_corepath {corepath} {
  set parent [file dirname $corepath]
  set lib_dir [file tail [file dirname $parent]]
  if {$lib_dir eq "" || $lib_dir eq "."} {
    return ""
  }
  return $lib_dir
}

proc core_register_symbol_key {key corepath} {
  if {$key eq "" || $corepath eq ""} {
    return
  }
  set ::core_symbol_index($key) $corepath
}

# Xschem built-in devices (lab_pin, lab_wire, code_shown, …): referenced as
# lab_pin.sym or devices/lab_pin.sym depending on export source.
proc core_system_device_library_roots {} {
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

proc core_register_system_devices {} {
  array unset ::core_system_device_index
  array set ::core_system_device_index {}
  foreach root [core_system_device_library_roots] {
    set devdir [file join $root devices]
    if {![file isdirectory $devdir]} {
      continue
    }
    foreach sym [glob -nocomplain -directory $devdir *.sym] {
      set name [file tail $sym]
      set norm [file normalize $sym]
      set ::core_system_device_index($name) $norm
      set ::core_system_device_index("devices/$name") $norm
    }
  }
}

proc core_resolve_system_device {symref} {
  if {$symref eq ""} {
    return ""
  }
  if {[info exists ::core_system_device_index($symref)]} {
    return $::core_system_device_index($symref)
  }
  set tail [file tail $symref]
  if {$tail ne $symref && [info exists ::core_system_device_index($tail)]} {
    return $::core_system_device_index($tail)
  }
  foreach root [core_system_device_library_roots] {
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

proc core_cell_from_symbol_core {corepath} {
  set tail [file tail $corepath]
  if {[regexp {^(.+)\.symbol\.core$} $tail -> cell]} {
    return $cell
  }
  return ""
}

proc core_primitive_lib_paths {} {
  set cores {}
  if {[info exists ::env(CORE_PRIMITIVE_LIBS_FILE)] && $::env(CORE_PRIMITIVE_LIBS_FILE) ne ""} {
    set listfile $::env(CORE_PRIMITIVE_LIBS_FILE)
    if {[file exists $listfile]} {
      if {[catch {set fh [open $listfile r]} err] == 0} {
        while {[gets $fh line] >= 0} {
          set line [core_normalize_primitive_path [string trim $line]]
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
  if {[info exists ::env(CORE_PRIMITIVE_LIBS)] && $::env(CORE_PRIMITIVE_LIBS) ne ""} {
    return [core_split_primitive_libs $::env(CORE_PRIMITIVE_LIBS)]
  }
  if {[info exists ::env(CORE_PRIMITIVE_LIB)] && $::env(CORE_PRIMITIVE_LIB) ne ""} {
    return [list $::env(CORE_PRIMITIVE_LIB)]
  }
  return {}
}

proc core_build_symbol_index {} {
  array unset ::core_symbol_index
  array set ::core_symbol_index {}
  array unset ::core_symbol_materialized
  array set ::core_symbol_materialized {}

  set cores [core_primitive_lib_paths]
  if {[llength $cores] == 0} {
    return
  }

  set techlib ""
  if {[info exists ::env(LIBMAN_TECH_LIBRARY)] && $::env(LIBMAN_TECH_LIBRARY) ne ""} {
    set techlib $::env(LIBMAN_TECH_LIBRARY)
  }

  foreach corepath $cores {
    set corepath [core_normalize_primitive_path [string trim $corepath]]
    if {$corepath eq "" || ![file exists $corepath]} {
      continue
    }
    set cell [core_cell_from_symbol_core $corepath]
    if {$cell eq ""} {
      continue
    }
    core_register_symbol_key "$cell.sym" $corepath
    set libpfx [core_lib_prefix_from_corepath $corepath]
    if {$libpfx ne ""} {
      core_register_symbol_key "$libpfx/$cell.sym" $corepath
    }
    if {$libpfx eq "commonLib"} {
      core_register_symbol_key "devices/$cell.sym" $corepath
    }
    if {$techlib ne ""} {
      foreach tlib [split $techlib {;}] {
        set tlib [string trim $tlib]
        if {$tlib ne ""} {
          core_register_symbol_key "$tlib/$cell.sym" $corepath
        }
      }
    }
    core_register_symbol_key [file tail $corepath] $corepath

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
      core_register_symbol_key "$alias.sym" $corepath
      if {$techlib ne ""} {
        foreach tlib [split $techlib {;}] {
          set tlib [string trim $tlib]
          if {$tlib ne ""} {
            core_register_symbol_key "$tlib/$alias.sym" $corepath
          }
        }
      }
    }  }
}

proc core_materialize_symbol {symref} {
  if {![info exists ::core_symbol_index($symref)]} {
    return ""
  }
  if {[info exists ::core_symbol_materialized($symref)]} {
    return $::core_symbol_materialized($symref)
  }

  set corepath $::core_symbol_index($symref)
  core_ensure_loaded
  set parsed [coreapi_parse_core_path $corepath]
  lassign $parsed cell view
  if {$cell eq ""} {
    return ""
  }

  set cache [core_primitive_cache_dir]
  set outdir $cache
  if {[string first "/" $symref] >= 0} {
    set outdir [file join $cache [file dirname $symref]]
  } else {
    set libpfx [core_lib_prefix_from_corepath $corepath]
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
  if {[catch {coreapi_export_cell $corepath $cell $sym} err]} {
    puts stderr "Failed to materialize CORE symbol $symref from $corepath: $err"
    return ""
  }
  set ::core_symbol_materialized($symref) $sym
  core_refresh_pathlist
  return $sym
}

proc core_schedule_primitive_reload {} {
  foreach delay {50 400 1200} {
    after $delay core_finish_primitive_setup
  }
}

proc core_finish_primitive_setup {} {
  core_build_symbol_index
  core_refresh_pathlist
  if {![info exists ::core_primitive_setup_done]} {
    set ::core_primitive_setup_done 1
  }
  catch {xschem reload_symbols}
  catch {xschem redraw}
}

proc core_resolve_symbol_file {f} {
  set sys [core_resolve_system_device $f]
  if {$sys ne ""} {
    return $sys
  }
  if {![info exists ::core_primitive_setup_done]} {
    return ""
  }
  foreach key [list $f [file tail $f]] {
    if {$key eq ""} {
      continue
    }
    if {[info exists ::core_symbol_index($key)]} {
      set sym [core_materialize_symbol $key]
      if {$sym ne "" && [file exists $sym]} {
        return $sym
      }
    }
  }
  return ""
}

proc core_install_symbol_hooks {} {
  if {[info commands find_file_first] eq ""} {
    return
  }
  if {[info commands find_file_first_orig] ne ""} {
    return
  }
  rename find_file_first find_file_first_orig
  proc find_file_first {f {paths {}} {maxdepth -1}} {
    # Prefer CORE-materialized primitives (same pin centers as LibMan/Qucs CORE path).
    set coreSym [core_resolve_symbol_file $f]
    if {$coreSym ne "" && [file exists $coreSym]} {
      return $coreSym
    }
    return [find_file_first_orig $f $paths $maxdepth]
  }

  if {[info commands find_file] eq ""} {
    return
  }
  rename find_file find_file_orig
  proc find_file {f {paths {}} {maxdepth -1}} {
    set coreSym [core_resolve_symbol_file $f]
    if {$coreSym ne ""} {
      return [list $coreSym]
    }
    return [find_file_orig $f $paths $maxdepth]
  }
}

# load_sym_def() resolves symbols via Tcl abs_sym_path, not find_file.
proc core_install_abs_sym_path_hook {} {
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
    set coreSym [core_resolve_symbol_file $lookup]
    if {$coreSym ne "" && [file exists $coreSym]} {
      return $coreSym
    }
    return [abs_sym_path_orig $fname $ext $paths]
  }
}

proc core_setup_primitive_library {} {
  core_build_symbol_index
  core_refresh_pathlist
  core_install_symbol_hooks
  core_install_abs_sym_path_hook
}

proc core_refresh_pathlist {} {
  global pathlist
  if {![info exists pathlist]} {
    return
  }
  set cache [core_primitive_cache_dir]
  if {$cache eq "" || ![file isdirectory $cache]} {
    return
  }
  if {[lsearch -exact $pathlist $cache] < 0} {
    lappend pathlist $cache
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

proc core_open_deferred {} {
  if {[info exists ::env(XSCHEM_OPEN_CORE)] && $::env(XSCHEM_OPEN_CORE) ne ""} {
    set path $::env(XSCHEM_OPEN_CORE)
    unset ::env(XSCHEM_OPEN_CORE)
    if {[catch {core_open $path} err]} {
      tk_messageBox -icon error -message "CORE open failed:\n$err"
    }
    return
  }

  if {[info exists ::env(XSCHEM_OPEN_FILE)] && $::env(XSCHEM_OPEN_FILE) ne ""} {
    set path $::env(XSCHEM_OPEN_FILE)
    unset ::env(XSCHEM_OPEN_FILE)
    if {[catch {xschem load $path} err]} {
      tk_messageBox -icon error -message "Failed to open:\n$path\n\n$err"
    } else {
      core_try_bind_payload_sch [xschem get schname]
      core_schedule_title_refresh
    }
  }
}

# Fast filename-only index before CORE load; reload_symbols again after open/scripts.
after idle {
  core_install_title_hooks
  core_install_file_hooks
  core_add_menu
  core_install_symbol_hooks
  core_install_abs_sym_path_hook
  core_register_system_devices
  core_build_symbol_index
  core_refresh_pathlist
  set ::core_primitive_setup_done 1
  core_open_deferred
  after 50 core_ensure_window_geometry
  after 150 core_ensure_window_geometry
  after 600 core_ensure_window_geometry
  after 1500 core_ensure_window_geometry
  core_schedule_primitive_reload
}
