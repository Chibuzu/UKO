# LobbyPage.gd
# The multiplayer lobby, extracted from MainMenu: owns the WHOLE online session
# lifecycle up to the scene change -- creating/tearing down the GDSyncSession,
# quick match / host code / join code, the room-code LineEdit, and the handshake
# handoff into the match (MatchBootstrap.start_online + change_scene). MainMenu
# owns nothing about the network but this page's `closed` signal.
# (GD-Sync: global relay + lobbies, no NAT/port-forwarding pain.)
class_name LobbyPage
extends Node2D

signal closed()

const BTN_W := 300
const BTN_H := 50.0
const GAP := 14.0

var _buttons := [
	{"id": "quick",     "label": "QUICK MATCH",  "on": true},
	{"id": "host_code", "label": "HOST PRIVATE", "on": true},
	{"id": "join_code", "label": "JOIN PRIVATE", "on": true},
	{"id": "mp_back",   "label": "BACK",         "on": true},
]
var _hover := -1
var _status := ""               # connection status line shown on the page
var _session: GDSyncSession     # live while on the page / handed to the match on connect
var _code_edit: LineEdit        # room code: shown for HOST PRIVATE, typed for JOIN PRIVATE

func _ready() -> void:
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "room code"
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.max_length = 8
	_code_edit.visible = false
	add_child(_code_edit)

func open() -> void:
	_hover = -1
	_status = "Quick Match to find anyone, or a private code to play a friend."
	_make_session()
	var vp := get_viewport_rect().size
	var w := 220.0
	_code_edit.position = Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.43)
	_code_edit.size = Vector2(w, 34)
	_code_edit.text = ""
	_code_edit.visible = true
	visible = true
	queue_redraw()

func _leave() -> void:
	if is_instance_valid(_session):
		_session.leave()       # exit any lobby we joined while browsing
	_teardown_session()
	_code_edit.visible = false
	visible = false
	closed.emit()

# Parented to /root with a FIXED name: GD-Sync routes remote calls by node path, so
# the session must sit at the same path on both clients and survive the scene change.
func _make_session() -> void:
	_teardown_session()
	var stale := get_tree().root.get_node_or_null("GDSyncSession")
	if stale != null:
		stale.free()   # zombie from a prior match/attempt, still subscribed to GD-Sync signals
	_session = GDSyncSession.new()
	_session.name = "GDSyncSession"
	get_tree().root.add_child(_session)
	_session.match_ready.connect(_on_match_ready)
	_session.match_failed.connect(_on_match_failed)

func _teardown_session() -> void:
	if is_instance_valid(_session):
		_session.queue_free()
	_session = null

# ── layout + drawing (this page's own geometry) ─────────────────────────────
func _btn_rect(i: int, vp: Vector2) -> Rect2:
	var x := vp.x * 0.5 - BTN_W * 0.5
	return Rect2(x, vp.y * 0.52 + i * (BTN_H + GAP), BTN_W, BTN_H)

func _draw() -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, vp.y * 0.27), "MULTIPLAYER",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, ViewConfig.COL_TEXT_OFF)
	draw_string(font, Vector2(0, vp.y * 0.40), "Room code (share to HOST, type to JOIN):",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 15, ViewConfig.COL_TEXT_OFF)
	if _status != "":
		draw_string(font, Vector2(0, vp.y * 0.92), _status,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, ViewConfig.COL_TEXT)
	for i in range(_buttons.size()):
		var r := _btn_rect(i, vp)
		draw_rect(r, ViewConfig.COL_BTN_HOVER if _hover == i else ViewConfig.COL_BTN)
		draw_rect(r, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		draw_string(font, Vector2(r.position.x, r.position.y + BTN_H * 0.64), _buttons[i]["label"],
			HORIZONTAL_ALIGNMENT_CENTER, BTN_W, 22, ViewConfig.COL_TEXT)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	if event is InputEventMouseMotion:
		var old := _hover
		var m := get_local_mouse_position()
		_hover = -1
		for i in range(_buttons.size()):
			if _btn_rect(i, vp).has_point(m):
				_hover = i
				break
		if old != _hover:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_local_mouse_position()
		for i in range(_buttons.size()):
			if _btn_rect(i, vp).has_point(m):
				_click(String(_buttons[i]["id"]))
				return

func _click(id: String) -> void:
	match id:
		"quick":
			_session.quick_match(PlayerProfile.loadout())
			_status = "Searching for an opponent..."
		"host_code":
			var code := _gen_code()
			_code_edit.text = code
			_session.host_code(code, PlayerProfile.loadout())
			_status = "Share code %s -- waiting for your friend..." % code
		"join_code":
			var code := _code_edit.text.strip_edges().to_upper()
			if code.length() < 3:
				_status = "Enter the room code your friend shared."
			else:
				_session.join_code(code, PlayerProfile.loadout())
				_status = "Joining %s..." % code
		"mp_back":
			_leave()
	queue_redraw()

# Handshake done: both sides hold an identical MatchConfig. Hand the live session to
# the match via a NetworkOpponent (over GD-Sync) and switch scenes. The session stays
# in /root (null our handle so _teardown won't free it) so its relay link survives.
func _on_match_ready(config: MatchConfig) -> void:
	MatchBootstrap.start_online(config, NetworkOpponent.new(GDSyncTransport.new(_session)))
	_session = null
	get_tree().change_scene_to_file(MainMenu.GAME_SCENE)

func _on_match_failed(reason: String) -> void:
	_status = reason
	queue_redraw()

# Short, unambiguous room code (no 0/O/1/I to avoid friends mistyping).
func _gen_code() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in 4:
		code += chars[randi() % chars.length()]
	return code
