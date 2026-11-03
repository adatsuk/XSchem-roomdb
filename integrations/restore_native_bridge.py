#!/usr/bin/env python3
"""Restore ROOM native load_data/get_data bridge into current xschem-src."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "xschem-src" / "src"


def patch_save_c() -> None:
    path = ROOT / "save.c"
    text = path.read_text(encoding="utf-8", errors="replace")
    if "load_schematic_from_buffer" in text:
        print("save.c: already patched")
        return

    marker = (
        "  my_free(_ALLOC_ID_, &ffname);\n"
        "  return ret;\n"
        "}\n"
        "\n"
        "void clear_undo(void)"
    )
    insert = r"""  my_free(_ALLOC_ID_, &ffname);
  return ret;
}

static char *read_fp_to_buffer(FILE *fd, size_t *out_len)
{
  long sz;
  char *buf;

  if(fseek(fd, 0, SEEK_END) != 0) return NULL;
  sz = ftell(fd);
  if(sz < 0) return NULL;
  if(fseek(fd, 0, SEEK_SET) != 0) return NULL;
  buf = (char *)my_malloc(_ALLOC_ID_, (size_t)sz + 1);
  if(!buf) return NULL;
  if(sz > 0 && fread(buf, 1, (size_t)sz, fd) != (size_t)sz) {
    my_free(_ALLOC_ID_, &buf);
    return NULL;
  }
  buf[sz] = '\0';
  if(out_len) *out_len = (size_t)sz;
  return buf;
}

static void write_current_schematic_to_fp(FILE *fd)
{
  xRect *rect;
  int rects;

  unselect_all(1);
  rects = xctx->rects[PINLAYER];
  rect = xctx->rect[PINLAYER];
  sort_symbol_pins(rect, rects, xctx->sch[xctx->currsch] ? xctx->sch[xctx->currsch] : "buffer");
  write_xschem_file(fd);
}

/* Load schematic/symbol records from memory (ROOM native bridge). */
int load_schematic_from_buffer(const char *data, size_t len, const char *logical_name,
                               int load_symbols, int reset_undo)
{
  FILE *fd;
  char msg[PATH_MAX + 100];
  int ret = 1;

  if(!xctx) return 0;
  xctx->prep_hi_structs=0;
  xctx->prep_net_structs=0;
  xctx->prep_hash_inst=0;
  xctx->prep_hash_wires=0;
  if(reset_undo) {
    xctx->delete_undo();
    xctx->prev_set_modify = -1;
  } else {
    xctx->prev_set_modify = 0;
  }
  clear_drawing();
  fd = tmpfile();
  if(!fd) return 0;
  if(len > 0) {
    if(fwrite(data, 1, len, fd) != len) {
      fclose(fd);
      return 0;
    }
  }
  fflush(fd);
  rewind(fd);
  read_xschem_file(fd);
  fclose(fd);

  if(logical_name && logical_name[0]) {
    my_strdup2(_ALLOC_ID_, &xctx->sch[xctx->currsch], logical_name);
    my_snprintf(msg, S(msg), "get_directory {%s}", logical_name);
    my_strncpy(xctx->current_dirname, tcleval(msg), S(xctx->current_dirname));
    my_strncpy(xctx->current_name, rel_sym_path(logical_name), S(xctx->current_name));
  }
  if(reset_undo) {
    xctx->time_last_modify = 0;
    set_modify(0);
  }
  if(load_symbols) link_symbols_to_instances(-1);
  tclvareval("is_xschem_file {", xctx->sch[xctx->currsch], "}", NULL);
  if(!strcmp(tclresult(), "SYMBOL") || xctx->instances == 0) {
    if(xctx->netlist_type != CAD_SYMBOL_ATTRS) xctx->save_netlist_type = xctx->netlist_type;
    xctx->netlist_type = CAD_SYMBOL_ATTRS;
    set_tcl_netlist_type(xctx);
    xctx->loaded_symbol = 1;
  } else {
    if(xctx->loaded_symbol) {
      xctx->netlist_type = xctx->save_netlist_type;
      set_tcl_netlist_type(xctx);
    }
    xctx->loaded_symbol = 0;
  }
  check_collapsing_objects();
  if(reset_undo && tclgetboolvar("autotrim_wires")) trim_wires();
  update_conn_cues(WIRELAYER, 0, 0);
  if(xctx->hilight_nets && load_symbols) {
    propagate_hilights(1, 1, XINSERT_NOREPLACE);
  }
  if(reset_undo) {
    set_netlist_dir(2, NULL);
    drc_check(-1);
    tcleval("eval_load_file_postprocess");
  }
  return ret;
}

/* Export current schematic/symbol records to a newly allocated buffer. */
char *export_schematic_to_buffer(size_t *out_len)
{
  FILE *fd;
  char *data;

  if(!xctx) return NULL;
  fd = tmpfile();
  if(!fd) return NULL;
  write_current_schematic_to_fp(fd);
  fflush(fd);
  rewind(fd);
  data = read_fp_to_buffer(fd, out_len);
  fclose(fd);
  return data;
}

void clear_undo(void)"""
    if marker not in text:
        raise SystemExit("save.c: insertion marker not found")
    path.write_text(text.replace(marker, insert, 1), encoding="utf-8")
    print("save.c: patched")


def patch_scheduler_c() -> None:
    path = ROOT / "scheduler.c"
    text = path.read_text(encoding="utf-8", errors="replace")
    if 'strcmp(argv[1], "load_data")' in text:
        print("scheduler.c: already patched")
        return

    get_data = r'''
    /* get_data
     *   Return current schematic/symbol records as a string (ROOM native bridge).
     */
    else if(!strcmp(argv[1], "get_data"))
    {
      size_t len = 0;
      char *data;

      if(!xctx) {Tcl_SetResult(interp, not_avail, TCL_STATIC); return TCL_ERROR;}
      data = export_schematic_to_buffer(&len);
      if(!data) {
        Tcl_SetResult(interp, "xschem get_data failed", TCL_STATIC);
        return TCL_ERROR;
      }
      Tcl_SetObjResult(interp, Tcl_NewStringObj(data, (int)len));
      my_free(_ALLOC_ID_, &data);
    }

'''
    load_data = r'''
    /* load_data TEXT ?-schname PATH? ?-noundoreset? ?-nosymbols? ?-nofullzoom? ?-nodraw?
     *   Load schematic/symbol records from memory (ROOM native bridge).
     */
    else if(!strcmp(argv[1], "load_data") )
    {
      int load_symbols = 1, undo_reset = 1, nofullzoom = 0, nodraw = 0;
      const char *data = NULL;
      const char *schname = NULL;
      int i;

      if(!xctx) {Tcl_SetResult(interp, not_avail, TCL_STATIC); return TCL_ERROR;}
      if(argc < 3) {
        Tcl_SetResult(interp, "xschem load_data needs at least 1 argument: data", TCL_STATIC);
        return TCL_ERROR;
      }
      for(i = 2; i < argc; i++) {
        if(argv[i][0] == '-') {
          if(!strcmp(argv[i], "-nosymbols")) {
            load_symbols = 0;
          } else if(!strcmp(argv[i], "-noundoreset")) {
            undo_reset = 0;
          } else if(!strcmp(argv[i], "-nofullzoom")) {
            nofullzoom = 1;
          } else if(!strcmp(argv[i], "-nodraw")) {
            nofullzoom = 1; nodraw = 1;
          } else if(!strcmp(argv[i], "-schname") && i + 1 < argc) {
            schname = argv[++i];
          }
        } else {
          data = argv[i];
          break;
        }
      }
      if(!data) {
        Tcl_SetResult(interp, "xschem load_data: missing data argument", TCL_STATIC);
        return TCL_ERROR;
      }
      if(load_schematic_from_buffer(data, strlen(data), schname ? schname : "", load_symbols, undo_reset)) {
        if(undo_reset) {
          my_strdup(_ALLOC_ID_, &xctx->sch_path[xctx->currsch], ".");
          if(xctx->portmap[xctx->currsch].table) str_hash_free(&xctx->portmap[xctx->currsch]);
          str_hash_init(&xctx->portmap[xctx->currsch], HASHSIZE);
          xctx->sch_path_hash[xctx->currsch] = 0;
          xctx->sch_inst_number[xctx->currsch] = 1;
        }
        if(nofullzoom) {
          if(!nodraw) draw();
        } else zoom_full(1, 0, 1 + 2 * tclgetboolvar("zoom_full_center"), 0.97);
        Tcl_SetResult(interp, xctx->sch[xctx->currsch], TCL_STATIC);
      } else {
        Tcl_SetResult(interp, "xschem load_data failed", TCL_STATIC);
        return TCL_ERROR;
      }
    }

'''

    m1 = (
        "    else if(!strcmp(argv[1], \"get_tok_size\") )\n"
        "    {\n"
        "      if(!xctx) {Tcl_SetResult(interp, not_avail, TCL_STATIC); return TCL_ERROR;}\n"
        "      Tcl_SetResult(interp, my_itoa((int)xctx->tok_size), TCL_VOLATILE);\n"
        "    }\n"
        "\n"
        "    /* globals"
    )
    if m1 not in text:
        raise SystemExit("scheduler.c: get_data marker not found")
    text = text.replace(
        m1,
        "    else if(!strcmp(argv[1], \"get_tok_size\") )\n"
        "    {\n"
        "      if(!xctx) {Tcl_SetResult(interp, not_avail, TCL_STATIC); return TCL_ERROR;}\n"
        "      Tcl_SetResult(interp, my_itoa((int)xctx->tok_size), TCL_VOLATILE);\n"
        "    }\n"
        + get_data
        + "    /* globals",
        1,
    )

    m2 = (
        "      Tcl_SetResult(interp, xctx->sch[xctx->currsch], TCL_STATIC);\n"
        "    }\n"
        "\n"
        "    /* load_new_window [-lastclosed | -lastopened] [f]\n"
    )
    # The load command ends with this pattern; ensure we match the last occurrence before load_new_window
    idx = text.find("    /* load_new_window [-lastclosed | -lastopened] [f]\n")
    if idx < 0:
        raise SystemExit("scheduler.c: load_new_window marker not found")
    # Find the Tcl_SetResult closing of the preceding load block
    precede = text.rfind("      Tcl_SetResult(interp, xctx->sch[xctx->currsch], TCL_STATIC);\n    }\n\n", 0, idx)
    if precede < 0:
        raise SystemExit("scheduler.c: end-of-load marker not found")
    end = precede + len("      Tcl_SetResult(interp, xctx->sch[xctx->currsch], TCL_STATIC);\n    }\n\n")
    text = text[:end] + load_data + text[end:]
    path.write_text(text, encoding="utf-8")
    print("scheduler.c: patched")


def patch_xschem_h() -> None:
    path = ROOT / "xschem.h"
    text = path.read_text(encoding="utf-8", errors="replace")
    if "load_schematic_from_buffer" in text:
        print("xschem.h: already patched")
        return
    marker = "extern int load_schematic(int load_symbol, const char *fname, int reset_undo, int alert);\n"
    insert = (
        marker
        + "extern int load_schematic_from_buffer(const char *data, size_t len, const char *logical_name,\n"
        + "                                      int load_symbols, int reset_undo);\n"
        + "extern char *export_schematic_to_buffer(size_t *out_len);\n"
    )
    if marker not in text:
        raise SystemExit("xschem.h: marker not found")
    path.write_text(text.replace(marker, insert, 1), encoding="utf-8")
    print("xschem.h: patched")


def main() -> None:
    patch_save_c()
    patch_scheduler_c()
    patch_xschem_h()
    print("done")


if __name__ == "__main__":
    main()
