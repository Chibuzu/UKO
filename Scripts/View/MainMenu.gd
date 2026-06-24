# MainMenu.gd
# Title screen + difficulty selector, and the project's MAIN SCENE. PLAY opens
# the difficulty page; choosing a difficulty stores it (AI.selected_difficulty)
# and swaps to the game scene. MULTIPLAYER and GEAR stay placeholders.
# Pure view, drawn by hand like the rest of the UI.
class_name MainMenu
extends Node2D

const GAME_SCENE := "res://Game.tscn"   # adjust if your game scene lives elsewhere

const BTN_W := 300

var _mode := "main"        # "main" | "difficulty"
var _hover := -1

var _buttons := [
	{"id": "play", "label": "PLAY", "on": true},
	{"id": "multiplayer", "label": "MULTIPLAYER", "on": false},
	{"id": "gear", "label": "GEAR", "on": true},
]

# Difficulty page. All four brains are built: EASY (Stub ladder), CHALLENGING
# (shallow best-response), HARD (robust threat/resource strategist), EXTREME
# (game-theoretic equilibrium).
var _diff_buttons := [
	{"diff": AI.Difficulty.EASY,        "label": "EASY",        "on": true},
	{"diff": AI.Difficulty.CHALLENGING, "label": "CHALLENGING", "on": true},
	{"diff": AI.Difficulty.HARD,        "label": "HARD",        "on": true},
	{"diff": AI.Difficulty.EXTREME,     "label": "EXTREME",     "on": true},
	{"diff": -1,                        "label": "BACK",        "on": true},
]

func _active() -> Array:
	return _buttons if _mode == "main" else _diff_buttons

func _btn_h() -> float:
	return 58.0 if _mode == "main" else 50.0

func _gap() -> float:
	return 18.0 if _mode == "main" else 14.0

func _top(vp: Vector2) -> float:
	return vp.y * (0.40 if _mode == "main" else 0.32)

func _btn_rect(i: int, vp: Vector2) -> Rect2:
	var x := vp.x * 0.5 - BTN_W * 0.5
	return Rect2(x, _top(vp) + i * (_btn_h() + _gap()), BTN_W, _btn_h())

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), ViewConfig.COL_LOG_BG)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, vp.y * 0.20), "UKO DUEL",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 64, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(vp.x - 220, 38), "GOLD  %d" % PlayerProfile.gold(),
		HORIZONTAL_ALIGNMENT_RIGHT, 200, 24, ViewConfig.COL_GOLD)
	if _mode == "difficulty":
		draw_string(font, Vector2(0, vp.y * 0.27), "SELECT DIFFICULTY",
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, ViewConfig.COL_TEXT_OFF)

	if _mode == "gear":
		_draw_gear(vp, font)
		return

	var items := _active()
	var bh := _btn_h()
	for i in range(items.size()):
		var b: Dictionary = items[i]
		var on: bool = b["on"]
		var r := _btn_rect(i, vp)
		var col := ViewConfig.COL_BTN
		if not on:
			col = ViewConfig.COL_BTN_OFF
		elif _hover == i:
			col = ViewConfig.COL_BTN_HOVER
		draw_rect(r, col)
		draw_rect(r, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		var label: String = b["label"]
		if _mode == "difficulty" and int(b.get("diff", -1)) >= 0:
			label += "   (%dg)" % Config.gold_reward(int(b["diff"]))   # purse for this tier
		if not on:
			label += "   (soon)"
		var tcol := ViewConfig.COL_TEXT if on else ViewConfig.COL_TEXT_OFF
		draw_string(font, Vector2(r.position.x, r.position.y + bh * 0.64), label,
			HORIZONTAL_ALIGNMENT_CENTER, BTN_W, 22, tcol)

func _input(event: InputEvent) -> void:
	var vp := get_viewport_rect().size
	if event is InputEventMouseMotion:
		var m := get_local_mouse_position()
		if _mode == "gear":
			var old_g := _hover
			_hover = -1
			if _gear_back_rect(vp).has_point(m):
				_hover = 100                              # 100 = BACK
			else:
				for i in range(GearBook.SLOT_ORDER.size()):
					if _gear_action_rect(i, vp).has_point(m):
						_hover = 200 + i                  # 200+i = row i action button
						break
			if old_g != _hover:
				queue_redraw()
			return
		var old := _hover
		_hover = -1
		var items := _active()
		for i in range(items.size()):
			if items[i]["on"] and _btn_rect(i, vp).has_point(m):
				_hover = i
				break
		if old != _hover:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_local_mouse_position()
		if _mode == "gear":
			if _gear_back_rect(vp).has_point(m):
				_mode = "main"
				_hover = -1
				queue_redraw()
				return
			for i in range(GearBook.SLOT_ORDER.size()):
				if _gear_action_rect(i, vp).has_point(m):
					_gear_click(i)
					queue_redraw()
					return
			return
		var items := _active()
		for i in range(items.size()):
			if not items[i]["on"] or not _btn_rect(i, vp).has_point(m):
				continue
			if _mode == "main":
				if items[i]["id"] == "play":
					_mode = "difficulty"          # PLAY opens the difficulty page
					_hover = -1
					queue_redraw()
				elif items[i]["id"] == "gear":
					_mode = "gear"                 # GEAR opens the loadout page
					_hover = -1
					queue_redraw()
			else:
				var diff: int = items[i]["diff"]
				if diff == -1:
					_mode = "main"                 # BACK
					_hover = -1
					queue_redraw()
				else:
					AI.selected_difficulty = diff  # carry the choice into the game
					get_tree().change_scene_to_file(GAME_SCENE)
			return

# ── Gear page ───────────────────────────────────────────────────────────
# One row per slot: a colored square (the gear's block colour, a placeholder
# for an icon) beside a box describing its spell. All data is pulled live from
# GearBook / SpellBook, so adding gear or retuning a spell updates this for free.
func _draw_gear(vp: Vector2, font) -> void:
	draw_string(font, Vector2(0, vp.y * 0.26), "GEAR SHOP",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, ViewConfig.COL_TEXT_OFF)
	var L := _gear_layout(vp)
	for i in range(GearBook.SLOT_ORDER.size()):
		var slot: String = GearBook.SLOT_ORDER[i]
		var gid: String = GearBook.gear_in_slot(slot)
		var y: float = L.top + i * L.pitch
		draw_string(font, Vector2(L.x0, y - 6), GearBook.SLOT_LABEL[slot],
			HORIZONTAL_ALIGNMENT_LEFT, L.total, 13, ViewConfig.COL_TEXT_OFF)
		# Gear block (icon placeholder = the block colour); dimmed when not owned.
		var col: Color = GearBook.block_color(gid)
		if not PlayerProfile.is_owned(gid):
			col = Color(col.r, col.g, col.b, 0.30)
		var gr := Rect2(L.x0, y, L.box, L.box)
		draw_rect(gr, col)
		draw_rect(gr, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		# Spell description.
		var sr := Rect2(L.x0 + L.box + L.gap, y, L.spell_w, L.box)
		draw_rect(sr, ViewConfig.COL_LOG_BG)
		draw_rect(sr, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		var sm := GearBook.spell_summary(gid)
		var gname := String(GearBook.gear_def(gid).get("name", "(empty)"))
		draw_string(font, Vector2(sr.position.x + 10, sr.position.y + 20),
			"%s  -  %s" % [gname, sm["spell"]], HORIZONTAL_ALIGNMENT_LEFT, L.spell_w - 20, 17, ViewConfig.COL_TEXT)
		draw_string(font, Vector2(sr.position.x + 10, sr.position.y + 40),
			"Tiles: %s" % sm["tiles"], HORIZONTAL_ALIGNMENT_LEFT, L.spell_w - 20, 13, ViewConfig.COL_TEXT_OFF)
		draw_string(font, Vector2(sr.position.x + 10, sr.position.y + 58),
			"DMG %s    CD %s    MP %s" % [sm["damage"], sm["cooldown"], sm["mp"]],
			HORIZONTAL_ALIGNMENT_LEFT, L.spell_w - 20, 13, ViewConfig.COL_TEXT_OFF)
		# Action button: BUY / EQUIP / EQUIPPED / unaffordable.
		var st := _gear_state(gid)
		var ar := _gear_action_rect(i, vp)
		var bcol := ViewConfig.COL_BTN
		var tcol := ViewConfig.COL_TEXT
		var label := ""
		match st:
			"equipped": label = "EQUIPPED"; tcol = ViewConfig.COL_HEAL
			"equip":    label = "EQUIP"
			"buy":      label = "BUY  %dg" % GearBook.cost_of(gid)
			_:          label = "%dg" % GearBook.cost_of(gid); bcol = ViewConfig.COL_HP_BG   # can't afford
		if _hover == 200 + i and st != "locked":
			bcol = ViewConfig.COL_BTN_HOVER
		draw_rect(ar, bcol)
		draw_rect(ar, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		draw_string(font, Vector2(ar.position.x, ar.position.y + 26), label,
			HORIZONTAL_ALIGNMENT_CENTER, ar.size.x, 15, tcol)
	# BACK button.
	var br := _gear_back_rect(vp)
	draw_rect(br, ViewConfig.COL_BTN_HOVER if _hover == 100 else ViewConfig.COL_BTN)
	draw_rect(br, ViewConfig.COL_BOARD_EDGE, false, 2.0)
	draw_string(font, Vector2(br.position.x, br.position.y + 24), "BACK",
		HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 18, ViewConfig.COL_TEXT)

# Shared layout for the shop rows + their action buttons (draw and hit-test agree).
func _gear_layout(vp: Vector2) -> Dictionary:
	var box := 72.0
	var gap := 14.0
	var spell_w := 300.0
	var btn_w := 130.0
	var total := box + gap + spell_w + gap + btn_w
	return {
		"box": box, "gap": gap, "spell_w": spell_w, "btn_w": btn_w,
		"total": total, "x0": vp.x * 0.5 - total * 0.5,
		"top": vp.y * 0.30, "pitch": box + 16.0,
	}

func _gear_action_rect(i: int, vp: Vector2) -> Rect2:
	var L := _gear_layout(vp)
	var x: float = L.x0 + L.box + L.gap + L.spell_w + L.gap
	var y: float = L.top + i * L.pitch + (L.box - 40.0) * 0.5
	return Rect2(x, y, L.btn_w, 40.0)

# Shop state for a piece: equipped / owned-not-equipped / buyable / unaffordable.
func _gear_state(gid: String) -> String:
	if gid == "":
		return "locked"
	if PlayerProfile.is_equipped(gid):
		return "equipped"
	if PlayerProfile.is_owned(gid):
		return "equip"
	if PlayerProfile.gold() >= GearBook.cost_of(gid):
		return "buy"
	return "locked"

func _gear_click(i: int) -> void:
	var slot: String = GearBook.SLOT_ORDER[i]
	var gid: String = GearBook.gear_in_slot(slot)
	if gid == "":
		return
	match _gear_state(gid):
		"buy":      PlayerProfile.buy(gid)        # deducts gold, owns, equips
		"equip":    PlayerProfile.equip(gid)
		"equipped": PlayerProfile.unequip(slot)   # tap again to go back to white
		_:          pass                          # unaffordable

func _gear_back_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x * 0.5 - 90, vp.y * 0.90, 180, 40)
