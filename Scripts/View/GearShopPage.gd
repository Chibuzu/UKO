# GearShopPage.gd
# The gear shop, extracted from MainMenu (which is a router again, not a mall).
# One row per slot: a colored square (the gear's block colour, a placeholder for
# an icon) beside a box describing its spell. All data is pulled live from
# GearBook / SpellBook / PlayerProfile, so adding gear or retuning a spell
# updates this page for free. Emits `closed` when BACK is pressed; MainMenu
# owns nothing about the shop but that signal.
class_name GearShopPage
extends Node2D

signal closed()

var _hover := -1        # -1 none | 100 BACK | 200+i row i's action button

func open() -> void:
	_hover = -1
	visible = true
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	if event is InputEventMouseMotion:
		var old := _hover
		var m := get_local_mouse_position()
		_hover = -1
		if _back_rect(vp).has_point(m):
			_hover = 100
		else:
			for i in range(GearBook.SLOT_ORDER.size()):
				if _action_rect(i, vp).has_point(m):
					_hover = 200 + i
					break
		if old != _hover:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_local_mouse_position()
		if _back_rect(vp).has_point(m):
			visible = false
			closed.emit()
			return
		for i in range(GearBook.SLOT_ORDER.size()):
			if _action_rect(i, vp).has_point(m):
				_click(i)
				queue_redraw()
				return

func _draw() -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, vp.y * 0.26), "GEAR SHOP",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, ViewConfig.COL_TEXT_OFF)
	var L := _layout(vp)
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
		var st := _state(gid)
		var ar := _action_rect(i, vp)
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
	var br := _back_rect(vp)
	draw_rect(br, ViewConfig.COL_BTN_HOVER if _hover == 100 else ViewConfig.COL_BTN)
	draw_rect(br, ViewConfig.COL_BOARD_EDGE, false, 2.0)
	draw_string(font, Vector2(br.position.x, br.position.y + 24), "BACK",
		HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 18, ViewConfig.COL_TEXT)

# Shared layout for the shop rows + their action buttons (draw and hit-test agree).
func _layout(vp: Vector2) -> Dictionary:
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

func _action_rect(i: int, vp: Vector2) -> Rect2:
	var L := _layout(vp)
	var x: float = L.x0 + L.box + L.gap + L.spell_w + L.gap
	var y: float = L.top + i * L.pitch + (L.box - 40.0) * 0.5
	return Rect2(x, y, L.btn_w, 40.0)

# Shop state for a piece: equipped / owned-not-equipped / buyable / unaffordable.
func _state(gid: String) -> String:
	if gid == "":
		return "locked"
	if PlayerProfile.is_equipped(gid):
		return "equipped"
	if PlayerProfile.is_owned(gid):
		return "equip"
	if PlayerProfile.gold() >= GearBook.cost_of(gid):
		return "buy"
	return "locked"

func _click(i: int) -> void:
	var slot: String = GearBook.SLOT_ORDER[i]
	var gid: String = GearBook.gear_in_slot(slot)
	if gid == "":
		return
	match _state(gid):
		"buy":      PlayerProfile.buy(gid)        # deducts gold, owns, equips
		"equip":    PlayerProfile.equip(gid)
		"equipped": PlayerProfile.unequip(slot)   # tap again to go back to white
		_:          pass                          # unaffordable

func _back_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x * 0.5 - 90, vp.y * 0.90, 180, 40)
