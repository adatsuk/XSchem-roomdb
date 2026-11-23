/* Native ROOM document support, compiled only for ROOM-enabled builds. */
#include <room_xschem.h>

/* Initialize editor objects directly, with the same cached flags as the text loader. */
static short room_dash(const char *attributes)
{
  int dash = atoi(get_tok_value(attributes, "dash", 0));
  return dash < 0 ? 0 : (short)dash;
}

static short room_fill(const char *attributes)
{
  const char *fill = get_tok_value(attributes, "fill", 0);
  return !strcmp(fill, "full") ? 2 : !strboolcmp(fill, "true");
}

static void append_wire(const double *v, const char *attributes)
{
  xWire *wire;
  check_wire_storage();
  wire = &xctx->wire[xctx->wires++];
  *wire = (xWire){.x1 = v[0], .y1 = v[1], .x2 = v[2], .y2 = v[3]};
  ORDER(wire->x1, wire->y1, wire->x2, wire->y2);
  my_strdup2(_ALLOC_ID_, &wire->prop_ptr, attributes);
  wire->bus = get_attr_val(get_tok_value(wire->prop_ptr, "bus", 0));
  set_wire_flags(wire);
}

static void append_line(int layer, const double *v, const char *attributes)
{
  xLine *line;
  check_line_storage(layer);
  line = &xctx->line[layer][xctx->lines[layer]++];
  *line = (xLine){.x1 = v[0], .y1 = v[1], .x2 = v[2], .y2 = v[3]};
  ORDER(line->x1, line->y1, line->x2, line->y2);
  my_strdup2(_ALLOC_ID_, &line->prop_ptr, attributes);
  line->dash = room_dash(line->prop_ptr);
  line->bus = get_attr_val(get_tok_value(line->prop_ptr, "bus", 0));
}

static void append_box(int layer, const double *v, const char *attributes)
{
  xRect *rect;
  const char *ellipse, *fill;
  check_box_storage(layer);
  rect = &xctx->rect[layer][xctx->rects[layer]++];
  *rect = (xRect){.x1 = v[0], .y1 = v[1], .x2 = v[2], .y2 = v[3], .ellipse_a = -1, .ellipse_b = -1};
  RECTORDER(rect->x1, rect->y1, rect->x2, rect->y2);
  my_strdup2(_ALLOC_ID_, &rect->prop_ptr, attributes);
  rect->dash = room_dash(rect->prop_ptr);
  rect->bus = get_attr_val(get_tok_value(rect->prop_ptr, "bus", 0));
  fill = get_tok_value(rect->prop_ptr, "fill", 0);
  rect->fill = !strcmp(fill, "full") ? 2 : strboolcmp(fill, "false") != 0;
  ellipse = get_tok_value(rect->prop_ptr, "ellipse", 0);
  if(*ellipse && sscanf(ellipse, "%d%*[ ,]%d", &rect->ellipse_a, &rect->ellipse_b) != 2) {
    rect->ellipse_a = 0;
    rect->ellipse_b = 360;
  }
  set_rect_flags(rect);
}

static void append_arc(int layer, const double *v, const char *attributes)
{
  xArc *arc;
  check_arc_storage(layer);
  arc = &xctx->arc[layer][xctx->arcs[layer]++];
  *arc = (xArc){.x = v[0], .y = v[1], .r = v[2], .a = v[3], .b = v[4]};
  my_strdup2(_ALLOC_ID_, &arc->prop_ptr, attributes);
  arc->dash = room_dash(arc->prop_ptr);
  arc->fill = room_fill(arc->prop_ptr);
  arc->bus = get_attr_val(get_tok_value(arc->prop_ptr, "bus", 0));
}

static void append_polygon(int layer, int points, const double *v, const char *attributes)
{
  int i;
  xPoly *poly;
  check_polygon_storage(layer);
  poly = &xctx->poly[layer][xctx->polygons[layer]++];
  *poly = (xPoly){.points = points};
  poly->x = my_calloc(_ALLOC_ID_, points, sizeof(double));
  poly->y = my_calloc(_ALLOC_ID_, points, sizeof(double));
  poly->selected_point = my_calloc(_ALLOC_ID_, points, sizeof(unsigned short));
  for(i = 0; i < points; ++i) {
    poly->x[i] = v[2*i];
    poly->y[i] = v[2*i+1];
  }
  my_strdup2(_ALLOC_ID_, &poly->prop_ptr, attributes);
  poly->dash = room_dash(poly->prop_ptr);
  poly->fill = room_fill(poly->prop_ptr);
  poly->bus = get_attr_val(get_tok_value(poly->prop_ptr, "bus", 0));
}

static void append_text(const double *v, int rotation, int flip, const char *text, const char *attributes)
{
  xText *item;
  check_text_storage();
  item = &xctx->text[xctx->texts++];
  *item = (xText){.x0 = v[0], .y0 = v[1], .xscale = v[2], .yscale = v[3], .rot = rotation, .flip = flip};
  my_strdup2(_ALLOC_ID_, &item->txt_ptr, text);
  my_strdup2(_ALLOC_ID_, &item->prop_ptr, attributes);
  set_text_flags(item);
}

static void append_inst(const double *v, int rotation, int flip, const char *name, const char *attributes)
{
  xInstance *inst;
  check_inst_storage();
  inst = &xctx->inst[xctx->instances++];
  *inst = (xInstance){.x0 = v[0], .y0 = v[1], .rot = rotation, .flip = flip, .color = -10000, .ptr = -1};
  my_strdup2(_ALLOC_ID_, &inst->name, name);
  my_strdup(_ALLOC_ID_, &inst->prop_ptr, attributes);
  set_inst_flags(inst);
}

/* Apply Xschem version and header fields from the typed document. */
static void set_version_string(const char *value)
{
  char *ptr = NULL, *ptr2;
  my_strdup2(_ALLOC_ID_, &xctx->version_string, value);
      if(xctx->version_string) {
        my_snprintf(xctx->file_version, S(xctx->file_version), "%s",
                    get_tok_value(xctx->version_string, "file_version", 0));


        if((ptr2 = strstr(xctx->version_string, "xschem")) && (ptr2 - xctx->version_string < 50)) {
          my_strdup2(_ALLOC_ID_, &ptr, subst_token(xctx->version_string, "xschem", NULL));
        }
        my_strdup2(_ALLOC_ID_, &ptr, subst_token(ptr, "version", NULL));
        my_strdup2(_ALLOC_ID_, &ptr, subst_token(ptr, "file_version", NULL));

        ptr2 = ptr;
        while(*ptr2 == ' ' || *ptr2 =='\t') ptr2++; /* strip leading spaces */
        if(*ptr2 == '\n') ptr2++; /* strip leading newline */
        my_strdup2(_ALLOC_ID_, &xctx->header_text, ptr2);
        my_free(_ALLOC_ID_,&ptr);
      }
}

static rx_string room_string(const char *s)
{
  rx_string value = {s ? s : "", s ? strlen(s) : 0};
  return value;
}

/* Use the same escaping as save_ascii_string, without a document text stream. */
static char *room_encode(const char *s)
{
  size_t i = 0; char *out;
  if(!s) s = "";
  out = my_malloc(_ALLOC_ID_, strlen(s) * 2 + 1);
  while(*s) {
    if(*s == '\\' || *s == '{' || *s == '}') out[i++] = '\\';
    out[i++] = *s++;
  }
  out[i] = 0; return out;
}

/* Decode counted strings exactly; save rejects CR rather than silently stripping it. */
static char *room_decode(rx_string s)
{
  size_t i, j = 0; char *out = my_malloc(_ALLOC_ID_, s.size + 1);
  for(i = 0; i < s.size; ++i) {
    if(s.data[i] == '\\' && i + 1 < s.size) ++i;
    out[j++] = s.data[i];
  }
  out[j] = 0; return out;
}

int is_room_document(const char *name)
{
  size_t n = name ? strlen(name) : 0;
  return n >= 5 && !strcmp(name + n - 5, ".room");
}

void room_close_document(void)
{
  rx_close(xctx->room_document);
  xctx->room_document = NULL;
  my_free(_ALLOC_ID_, &xctx->room_path);
}

static int room_failure(rx_error *error, const char *message)
{
  rx_string detail = rx_error_message(error);
  Tcl_Obj *text = Tcl_NewStringObj(message, -1);
  if(detail.size) { Tcl_AppendToObj(text, ": ", 2); Tcl_AppendToObj(text, detail.data, detail.size); }
  Tcl_SetVar2Ex(interp, "room_native_error", NULL, text, TCL_GLOBAL_ONLY);
  info("%s\n", Tcl_GetString(text));
  Tcl_SetObjResult(interp, text);
  rx_error_free(error);
  return 0;
}

/* First pass validates external symbols and unsupported cases before clearing the drawing. */
static int room_receive(void *user, const rx_record *r)
{
  int install = *(int *)user, ok = 1;
  char *text = room_decode(r->text), *attrs = room_decode(r->attributes);
  const double *v = r->values;
  if(!install) {
    if(strchr("LBAP", r->kind) && r->layer >= cadlayers) {
      room_failure(NULL, "ROOM object uses an unavailable Xschem layer"); ok = 0;
    } else if(r->kind == 'C') {
      struct stat st; char *type = NULL;
      if(is_generator(text) || stat(abs_sym_path(text, ""), &st) || !S_ISREG(st.st_mode)) {
        info("ROOM symbol: %s\n", text);
        room_failure(NULL, "ROOM requires an existing external .sym; generators and ROOM-only symbols are unsupported"); ok = 0;
      } else {
        const char *editable_type = rx_value_symbol_type(r->text);
        get_sym_type(text, &type, NULL, NULL, NULL);
        if(!type || !type[0] || !strcmp(type, "subcircuit")) {
          room_failure(NULL, "ROOM Phase 1 requires flat device symbols with a declared type; subcircuits are unsupported"); ok = 0;
        } else if(editable_type && strcmp(editable_type, type)) {
          room_failure(NULL, "ROOM requires the standard device type for editable symbols"); ok = 0;
        }
        my_free(_ALLOC_ID_, &type);
      }
      if(!strboolcmp(get_tok_value(attrs, "embed", 0), "true")) {
        room_failure(NULL, "Embedded symbols are unsupported for ROOM"); ok = 0;
      }
    }
  } else {
    switch(r->kind) {
    case 'v': set_version_string(attrs); break;
    case 'G': my_strdup2(_ALLOC_ID_, &xctx->schvhdlprop, attrs); break;
    case 'K': my_strdup2(_ALLOC_ID_, &xctx->schsymbolprop, attrs); break;
    case 'V': my_strdup2(_ALLOC_ID_, &xctx->schverilogprop, attrs); break;
    case 'S': my_strdup2(_ALLOC_ID_, &xctx->schprop, attrs); break;
    case 'E': my_strdup2(_ALLOC_ID_, &xctx->schtedaxprop, attrs); break;
    case 'F': my_strdup2(_ALLOC_ID_, &xctx->schspectreprop, attrs); break;
    case 'N': append_wire(v, attrs); break;
    case 'L': append_line(r->layer, v, attrs); break;
    case 'B': append_box(r->layer, v, attrs); break;
    case 'A': append_arc(r->layer, v, attrs); break;
    case 'P': append_polygon(r->layer, r->value_count / 2, v, attrs); break;
    case 'T': append_text(v, r->rotation, r->flip, text, attrs); break;
    case 'C': append_inst(v, r->rotation, r->flip, text, attrs); break;
    default: room_failure(NULL, "Unsupported ROOM object"); ok = 0;
    }
  }
  my_free(_ALLOC_ID_, &text); my_free(_ALLOC_ID_, &attrs); return ok;
}

static rx_document *room_prepare(const char *path)
{
  rx_document *doc = NULL; rx_error *error = NULL;
  int install = 0; Tcl_CmdInfo command;
  Tcl_UnsetVar(interp, "room_native_error", TCL_GLOBAL_ONLY);
  if(Tcl_GetCommandInfo(interp, "room_ensure_loaded", &command)) {
    room_failure(NULL, "Native ROOM and legacy room.tcl cannot run together; use a clean rcfile"); return NULL;
  }
  if(!rx_open(room_string(path), &doc, &error)) {
    room_failure(error, "Cannot open ROOM"); return NULL;
  }
  if(!rx_read(doc, room_receive, &install, &error)) {
    if(Tcl_GetVar2Ex(interp, "room_native_error", NULL, TCL_GLOBAL_ONLY)) rx_error_free(error);
    else room_failure(error, "Cannot load ROOM");
    rx_close(doc);
    return NULL;
  }
  return doc;
}

static void room_alert(void);

/* Preflight completes before any drawing, symbol or undo state is replaced. */
static int room_load(const char *path, int load_symbols, int reset_undo)
{
  struct stat st;
  rx_error *error = NULL;
  char filename[PATH_MAX], *separator;
  int install = 1;
  rx_document *doc = room_prepare(path);
  if(!doc) {
    if(!xctx->sch[xctx->currsch]) {
      clear_drawing();
      set_unique_sch_name(xctx, "untitled.sch");
      if(reset_undo) set_modify(0);
    }
    room_alert();
    return 0;
  }
  my_strncpy(filename, path, S(filename));
  xctx->delete_undo();
  xctx->currsch = 0;
  xctx->prep_hi_structs = xctx->prep_net_structs = 0;
  xctx->prep_hash_inst = xctx->prep_hash_wires = 0;
  remove_symbols();
  clear_drawing();
  room_close_document();
  xctx->room_document = doc;
  my_strdup2(_ALLOC_ID_, &xctx->room_path, filename);
  my_strdup2(_ALLOC_ID_, &xctx->sch[xctx->currsch], filename);
  my_strncpy(xctx->current_name, rel_sym_path(filename), S(xctx->current_name));
  xctx->time_last_modify = !stat(filename, &st) ? st.st_mtime : -1;
  separator = strrchr(filename, '/');
  if(separator) separator[separator == filename ? 1 : 0] = '\0';
  my_strncpy(xctx->current_dirname, separator ? filename : ".", S(xctx->current_dirname));
  xctx->prev_set_modify = -1;
  if(!rx_read(doc, room_receive, &install, &error))
    return room_failure(error, "Cannot install ROOM drawing");
  int_hash_free(&xctx->floater_inst_table);
  if(xctx->loaded_symbol) {
    xctx->netlist_type = xctx->save_netlist_type;
    set_tcl_netlist_type(xctx);
    xctx->loaded_symbol = 0;
  }
  set_modify(0);
  if(load_symbols) link_symbols_to_instances(-1);
  return 1;
}

/* Capture only typed objects from xctx. Errors leave the document and dirty flag intact. */
static int room_emit(char kind, int layer, int rotation, int flip, const double *v, size_t n,
                     const char *text, const char *attributes)
{
  rx_error *error = NULL;
  char *t = room_encode(text), *a = room_encode(attributes);
  rx_record r = {kind, layer, rotation, flip, v, n, room_string(t), room_string(a)};
  int ok = rx_append(xctx->room_document, &r, &error);
  my_free(_ALLOC_ID_, &t); my_free(_ALLOC_ID_, &a);
  return ok ? 1 : room_failure(error, "Cannot stage ROOM object");
}

static int room_save_checked(const char *name, int fast)
{
  int c, i, j; rx_error *error = NULL; struct stat st;
  char *header = NULL;
  const char *current = xctx->sch[xctx->currsch];
  if(!xctx->room_document || !current || strcmp(name, current) || strcmp(name, xctx->room_path))
    return room_failure(NULL, "ROOM Save As and creation are unsupported; save to the open ROOM document");
  for(i = 0; i < xctx->instances; ++i) {
    int check = 0;
    char *t = room_encode(xctx->inst[i].name), *a = room_encode(xctx->inst[i].prop_ptr);
    double v[] = {xctx->inst[i].x0, xctx->inst[i].y0};
    rx_record r = {'C', 0, xctx->inst[i].rot, xctx->inst[i].flip, v, 2, room_string(t), room_string(a)};
    int ok = room_receive(&check, &r);
    my_free(_ALLOC_ID_, &t); my_free(_ALLOC_ID_, &a);
    if(!ok) return 0;
  }
  if(!rx_begin(xctx->room_document, &error)) return room_failure(error, "Cannot stage ROOM");
  my_mstrcat(_ALLOC_ID_, &header, "xschem version=",
      get_tok_value(xctx->version_string, "version", 0), " file_version=", xctx->file_version,
      xctx->header_text && xctx->header_text[0] ? "\n" : "", xctx->header_text ? xctx->header_text : "", NULL);
  i = room_emit('v', 0, 0, 0, NULL, 0, NULL, header);
  my_free(_ALLOC_ID_, &header);
  if(!i) return 0;
  if(!room_emit('G', 0, 0, 0, NULL, 0, NULL, xctx->schvhdlprop) ||
     !room_emit('K', 0, 0, 0, NULL, 0, NULL, xctx->schsymbolprop) ||
     !room_emit('V', 0, 0, 0, NULL, 0, NULL, xctx->schverilogprop) ||
     !room_emit('S', 0, 0, 0, NULL, 0, NULL, xctx->schprop) ||
     !room_emit('F', 0, 0, 0, NULL, 0, NULL, xctx->schspectreprop) ||
     !room_emit('E', 0, 0, 0, NULL, 0, NULL, xctx->schtedaxprop)) return 0;
  for(c = 0; c < cadlayers; ++c) {
    for(i = 0; i < xctx->lines[c]; ++i) {
      xLine *p = &xctx->line[c][i]; double v[] = {p->x1,p->y1,p->x2,p->y2};
      if(!room_emit('L',c,0,0,v,4,NULL,p->prop_ptr)) return 0;
    }
    for(i = 0; i < xctx->rects[c]; ++i) {
      xRect *p = &xctx->rect[c][i]; double v[] = {p->x1,p->y1,p->x2,p->y2};
      if(!room_emit('B',c,0,0,v,4,NULL,p->prop_ptr)) return 0;
    }
    for(i = 0; i < xctx->arcs[c]; ++i) {
      xArc *p = &xctx->arc[c][i]; double v[] = {p->x,p->y,p->r,p->a,p->b};
      if(!room_emit('A',c,0,0,v,5,NULL,p->prop_ptr)) return 0;
    }
    for(i = 0; i < xctx->polygons[c]; ++i) {
      xPoly *p = &xctx->poly[c][i]; double *v = my_malloc(_ALLOC_ID_, p->points * 2 * sizeof(double));
      int ok;
      for(j = 0; j < p->points; ++j) { v[j*2] = p->x[j]; v[j*2+1] = p->y[j]; }
      ok = room_emit('P',c,0,0,v,p->points*2,NULL,p->prop_ptr);
      my_free(_ALLOC_ID_, &v); if(!ok) return 0;
    }
  }
  for(i = 0; i < xctx->wires; ++i) {
    xWire *p = &xctx->wire[i]; double v[] = {p->x1,p->y1,p->x2,p->y2};
    if(!room_emit('N',0,0,0,v,4,NULL,p->prop_ptr)) return 0;
  }
  for(i = 0; i < xctx->texts; ++i) {
    xText *p = &xctx->text[i]; double v[] = {p->x0,p->y0,p->xscale,p->yscale};
    if(!room_emit('T',0,p->rot,p->flip,v,4,p->txt_ptr,p->prop_ptr)) return 0;
  }
  for(i = 0; i < xctx->instances; ++i) {
    xInstance *p = &xctx->inst[i]; double v[] = {p->x0,p->y0};
    if(!room_emit('C',0,p->rot,p->flip,v,2,p->name,p->prop_ptr)) return 0;
  }
  if(!rx_commit(xctx->room_document, &error)) return room_failure(error, "Cannot save ROOM; editor edits retained");
  if(!stat(name, &st)) xctx->time_last_modify = st.st_mtime;
  xctx->warn_disk_file_modified = 1;
  xctx->saved_cur_undo_ptr = xctx->cur_undo_ptr;
  set_modify(fast ? 2 : 0);
  Tcl_UnsetVar(interp, "room_native_error", TCL_GLOBAL_ONLY);
  return 1;
}


/* Keep the diagnostic available to Tcl and show it without blocking the editor. */
static void room_alert(void)
{
  Tcl_Obj *message = Tcl_GetVar2Ex(interp, "room_native_error", NULL, TCL_GLOBAL_ONLY);
  if(has_x && message) {
    Tcl_Obj *args[] = {Tcl_NewStringObj("alert_", -1), message,
                      Tcl_NewStringObj("", 0), Tcl_NewIntObj(1)};
    int i;
    for(i = 0; i < 4; ++i) Tcl_IncrRefCount(args[i]);
    Tcl_EvalObjv(interp, 4, args, TCL_EVAL_GLOBAL);
    Tcl_SetObjResult(interp, message);
    for(i = 0; i < 4; ++i) Tcl_DecrRefCount(args[i]);
  }
}

int room_refuse_saveas(void)
{
  room_failure(NULL, "ROOM Save As and creation are unsupported; save to the open ROOM document");
  room_alert();
  return 0;
}

static int room_save(const char *name, int fast)
{
  int ok = room_save_checked(name, fast);
  if(!ok) room_alert();
  return ok;
}

/* A refusal cancels the operation that asked to save and retains the dirty drawing. */
int room_save_current(int fast)
{
  const char *name = xctx->sch[xctx->currsch];
  int ok = save_schematic(name, fast);
  return !ok && (xctx->room_document || is_room_document(name)) ? -1 : ok;
}
