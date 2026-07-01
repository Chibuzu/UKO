# QuestDialog.gd
# The NPC quest overlay. Hand-drawn Node2D in the pause menu's style: a centered panel with
# the NPC name, the quest title + description, a progress line, and one contextual primary
# button (ACCEPT / TURN IN) plus CLOSE. Pure view -- it emits `quest_action(quest_id, action)`
# and `closed`; the controller does the accepting / handing-in and re-opens with fresh data.
# Input is consumed BEFORE any emit (the controller may change state / free focus), matching
# the pause menu's crash-safe pattern.
class_name QuestDialog
extends Node2D

signal quest_action(quest_id: String, action: String)
signal closed

const PANEL_W := 520.0
const PANEL_H := 320.0

var _open := false
var _npc := ""
var _color := Color.WHITE
var _qid := ""
var _title := ""
var _desc := ""
var _progress := ""
var _mode := "accept"     # accept | progress | turn_in | done
var _hover := -1

# `data`: {npc, color, qid, title, desc, progress, mode}
func open_for(data: Dictionary) -> void:
	_npc = String(data.get("npc", ""))
	_color = data.get("color", Color.WHITE)
	_qid = String(data.get("qid", ""))
	_title = String(data.get("title", ""))
	_desc = String(data.get("desc", ""))
	_progress = String(data.get("progress", ""))
	_mode = String(data.get("mode", "accept"))
	_open = true
	visible = true
	_hover = -1
	queue_redraw()

func close() -> void:
	_open = false
	visible = false
	queue_redraw()

func is_open() -> bool:
	return _open

# ── layout ────────────────────────────────────────────────────────────────────
func _panel() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2((vp.x - PANEL_W) * 0.5, (vp.y - PANEL_H) * 0.5, PANEL_W, PANEL_H)

# The primary action (if any) sits left, CLOSE right, along the panel bottom.
func _buttons() -> Array:
	var b: Array = []
	if _mode == "accept":
		b.append({"id": "accept", "label": "ACCEPT"})
	elif _mode == "turn_in":
		b.append({"id": "turn_in", "label": "TURN IN"})
	b.append({"id": "close", "label": "CLOSE"})
	return b

func _btn_rect(i: int) -> Rect2:
	var p := _panel()
	var bw := 150.0
	var bh := 40.0
	var gap := 16.0
	var n := _buttons().size()
	var total := n * bw + (n - 1) * gap
	var x0 := p.position.x + (PANEL_W - total) * 0.5
	var y := p.position.y + PANEL_H - 56.0
	return Rect2(x0 + i * (bw + gap), y, bw, bh)

func _hit_button(m: Vector2) -> int:
	for i in range(_buttons().size()):
		if _btn_rect(i).has_point(m):
			return i
	return -1

# ── input (consume before emit, like the pause menu) ──────────────────────────
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			closed.emit()
		return
	if event is InputEventMouseMotion:
		var old := _hover
		_hover = _hit_button(get_local_mouse_position())
		if old != _hover:
			queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _hit_button(get_local_mouse_position())
		if i < 0:
			return
		get_viewport().set_input_as_handled()   # consume BEFORE any emit that may change state
		var id: String = _buttons()[i]["id"]
		if id == "close":
			closed.emit()
		else:
			quest_action.emit(_qid, id)

# ── draw ──────────────────────────────────────────────────────────────────────
func _draw() -> void:
	if not _open:
		return
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))    # dim the world behind
	var p := _panel()
	draw_rect(p, ViewConfig.COL_LOG_BG)
	draw_rect(p, ViewConfig.COL_BOARD_EDGE, false, 2.0)

	var x := p.position.x + 24.0
	var y := p.position.y + 20.0
	# NPC marker + name
	draw_circle(Vector2(x + 8.0, y + 6.0), 8.0, _color)
	draw_string(font, Vector2(x + 24.0, y + 12.0), _npc,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ViewConfig.COL_TEXT)
	y += 40.0
	draw_string(font, Vector2(x, y), _title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ViewConfig.COL_GOLD)
	y += 30.0
	draw_multiline_string(font, Vector2(x, y), _desc,
		HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 48.0, 15, -1, ViewConfig.COL_TEXT)
	y += 96.0
	if _mode == "done":
		draw_string(font, Vector2(x, y), "Completed.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ViewConfig.COL_HEAL)
	elif _progress != "":
		var pcol := ViewConfig.COL_HEAL if _mode == "turn_in" else ViewConfig.COL_TEXT
		var tail := "  (ready to turn in)" if _mode == "turn_in" else "  (in progress)"
		draw_string(font, Vector2(x, y), "Progress: " + _progress + tail,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, pcol)

	for i in range(_buttons().size()):
		var rect := _btn_rect(i)
		var col := ViewConfig.COL_BTN_HOVER if _hover == i else ViewConfig.COL_BTN
		draw_rect(rect, col)
		draw_rect(rect, ViewConfig.COL_BOARD_EDGE, false, 1.0)
		draw_string(font, rect.position + Vector2(0, 26), _buttons()[i]["label"],
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 15, ViewConfig.COL_TEXT)
