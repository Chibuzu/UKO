# StoryPauseMenu.gd
# The story pause overlay (ESC). Hand-drawn Node2D in MainMenu's style, but tabbed:
#   main      -> GEAR / INVENTORY / SAVE / RESUME / EXIT buttons
#   gear      -> read-only loadout (slot, gear, spell) + BACK
#   inventory -> an RPG bag grid: fixed slots, each holding one stacked item + count, + BACK
# It changes no game state; it emits `resume`, `save`, and `exit_to_menu` for the controller.
# Tabs are just a `_tab` string + a per-tab button list + a per-tab draw call, so a future
# panel (map, quests, stats) is one entry in each of those three places.
class_name StoryPauseMenu
extends Node2D

signal resume
signal save
signal exit_to_menu

const PANEL_W := 600.0
const PANEL_H := 440.0

const BAG_COLS := 6
const BAG_ROWS := 4                    # 24 slots -- a "bag" that's mostly empty early on
const CELL := 64.0
const CELL_GAP := 8.0

var _open := false
var _tab := "main"
var _hover := -1                       # hovered button index in the current tab
var _hover_item := ""                  # item id under the cursor in the bag grid (tooltip)
var _status := ""                      # transient line (e.g. "Progress saved.")

func open() -> void:
	_open = true
	visible = true
	_tab = "main"
	_hover = -1
	_hover_item = ""
	_status = ""
	queue_redraw()

func close() -> void:
	_open = false
	visible = false
	queue_redraw()

func is_open() -> bool:
	return _open

func note_saved() -> void:
	_status = "Progress saved."
	queue_redraw()

# ── layout ────────────────────────────────────────────────────────────────────
func _panel() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2((vp.x - PANEL_W) * 0.5, (vp.y - PANEL_H) * 0.5, PANEL_W, PANEL_H)

func _tab_buttons() -> Array:
	if _tab == "gear" or _tab == "inventory":
		return [ {"id": "back", "label": "BACK"} ]
	return [
		{"id": "gear",      "label": "GEAR"},
		{"id": "inventory", "label": "INVENTORY"},
		{"id": "save",      "label": "SAVE"},
		{"id": "resume",    "label": "RESUME"},
		{"id": "exit",      "label": "EXIT TO MAIN MENU"},
	]

func _btn_rect(i: int) -> Rect2:
	var p := _panel()
	if _tab == "main":
		var bh := 46.0
		var gap := 12.0
		var n := _tab_buttons().size()
		var top := p.position.y + 96.0
		return Rect2(p.position.x + 40.0, top + i * (bh + gap), PANEL_W - 80.0, bh)
	# gear / inventory: a single BACK button centered at the bottom
	var bw := 160.0
	return Rect2(p.position.x + (PANEL_W - bw) * 0.5, p.position.y + PANEL_H - 56.0, bw, 40.0)

func _bag_origin() -> Vector2:
	var p := _panel()
	var gw := BAG_COLS * CELL + (BAG_COLS - 1) * CELL_GAP
	return Vector2(p.position.x + (PANEL_W - gw) * 0.5, p.position.y + 84.0)

func _cell_rect(idx: int) -> Rect2:
	var o := _bag_origin()
	var col := idx % BAG_COLS
	var row := idx / BAG_COLS
	return Rect2(o.x + col * (CELL + CELL_GAP), o.y + row * (CELL + CELL_GAP), CELL, CELL)

# ── input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _tab != "main":
			_tab = "main"; _hover = -1; _hover_item = ""; queue_redraw()
		else:
			resume.emit()
		return
	if event is InputEventMouseMotion:
		var m := get_local_mouse_position()
		var oh := _hover
		var oi := _hover_item
		_hover = _hit_button(m)
		_hover_item = _hit_item(m) if _tab == "inventory" else ""
		if _hover != oh or _hover_item != oi:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _hit_button(get_local_mouse_position())
		if i >= 0:
			get_viewport().set_input_as_handled()   # consume BEFORE any emit that may free us
			_click(i)

func _hit_button(m: Vector2) -> int:
	var btns := _tab_buttons()
	for i in btns.size():
		if _btn_rect(i).has_point(m):
			return i
	return -1

func _hit_item(m: Vector2) -> String:
	var ids := PlayerInventory.all().keys()
	for idx in ids.size():
		if _cell_rect(idx).has_point(m):
			return String(ids[idx])
	return ""

func _click(i: int) -> void:
	var id := String(_tab_buttons()[i]["id"])
	match id:
		"gear":
			_tab = "gear"; _hover = -1; queue_redraw()
		"inventory":
			_tab = "inventory"; _hover = -1; _hover_item = ""; queue_redraw()
		"save":
			save.emit()                              # controller writes the save, then note_saved()
		"resume":
			resume.emit()
		"exit":
			exit_to_menu.emit()                      # viewport already consumed above; no touch after
		"back":
			_tab = "main"; _hover = -1; _hover_item = ""; queue_redraw()

# ── draw ──────────────────────────────────────────────────────────────────────
func _draw() -> void:
	if not _open:
		return
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.72))
	var p := _panel()
	draw_rect(p, ViewConfig.COL_LOG_BG)
	draw_rect(p, ViewConfig.COL_BOARD_EDGE, false, 2.0)

	var title := "PAUSED"
	if _tab == "gear": title = "GEAR"
	elif _tab == "inventory": title = "INVENTORY"
	draw_string(font, Vector2(p.position.x, p.position.y + 36.0), title,
		HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 26, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(p.position.x - 24.0, p.position.y + 34.0), "GOLD %d" % PlayerProfile.gold(),
		HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W, 18, ViewConfig.COL_GOLD)

	if _tab == "gear":
		_draw_gear(font, p)
	elif _tab == "inventory":
		_draw_bag(font, p)

	if _tab == "main" and _status != "":
		draw_string(font, Vector2(p.position.x, p.position.y + PANEL_H - 22.0), _status,
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 15, ViewConfig.COL_GOLD)

	for i in _tab_buttons().size():
		var r := _btn_rect(i)
		draw_rect(r, ViewConfig.COL_BTN_HOVER if _hover == i else ViewConfig.COL_BTN)
		draw_rect(r, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.64), String(_tab_buttons()[i]["label"]),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, ViewConfig.COL_TEXT)

func _draw_gear(font: Font, p: Rect2) -> void:
	var x := p.position.x + 40.0
	var w := PANEL_W - 80.0
	var ry := p.position.y + 96.0
	for slot in GearBook.SLOT_ORDER:
		var gid := PlayerProfile.equipped_in(String(slot))
		var gname := "-- empty --"
		var gspell := ""
		var swatch: Color = Color(0.28, 0.28, 0.34)
		if gid != "":
			var d := GearBook.gear_def(gid)
			gname = String(d.get("name", gid))
			gspell = String(d.get("spell", ""))
			if d.has("block_color"):
				swatch = d["block_color"]
		draw_rect(Rect2(x, ry - 12.0, 18.0, 18.0), swatch)
		draw_rect(Rect2(x, ry - 12.0, 18.0, 18.0), ViewConfig.COL_BOARD_EDGE, false, 1.0)
		draw_string(font, Vector2(x + 28.0, ry), "%s:  %s" % [String(GearBook.SLOT_LABEL.get(slot, slot)), gname],
			HORIZONTAL_ALIGNMENT_LEFT, w - 28.0, 16, ViewConfig.COL_TEXT)
		if gspell != "":
			draw_string(font, Vector2(x + 28.0, ry + 16.0), gspell,
				HORIZONTAL_ALIGNMENT_LEFT, w - 28.0, 12, ViewConfig.COL_TEXT_OFF)
		ry += 48.0

func _draw_bag(font: Font, p: Rect2) -> void:
	var counts := PlayerInventory.all()
	var ids := counts.keys()
	var slot_bg := Color(0.11, 0.11, 0.15)
	for idx in BAG_COLS * BAG_ROWS:
		var r := _cell_rect(idx)
		draw_rect(r, slot_bg)
		draw_rect(r, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		if idx < ids.size():
			var id := String(ids[idx])
			draw_circle(r.position + r.size * 0.5 - Vector2(0.0, 6.0), CELL * 0.26, ItemBook.item_color(id))
			draw_string(font, Vector2(r.position.x, r.end.y - 6.0), "x%d" % int(counts[id]),
				HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6.0, 15, ViewConfig.COL_TEXT)
	# Tooltip: name of the item the cursor is over.
	if _hover_item != "":
		draw_string(font, Vector2(p.position.x, p.position.y + PANEL_H - 66.0), ItemBook.item_name(_hover_item),
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, 16, ViewConfig.COL_GOLD)
