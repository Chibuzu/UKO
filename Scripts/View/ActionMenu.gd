# ActionMenu.gd
# On-screen buttons for every action you can take this turn — basic actions
# plus three spell-category slots (Buff / AoE / Sp. Atk.) that load whatever
# spell your gear grants for that role — and a readout of both fighters'
# resources. Pure view: it emits the chosen id; the controller decides what it
# means. Buttons grey out when unaffordable, on cooldown, or unfilled by gear.
class_name ActionMenu
extends Node2D

signal action_chosen(id: String)

const BTN_W := 188
const BTN_H := 34
const GAP := 6
const HUD_H := 0     # no header; buttons start at the top of the panel

const BASIC := ["move", "attack", "pivot", "guard", "rest", "wait"]
const BASIC_LABELS := {
	"move": "MOVE", "attack": "ATTACK", "pivot": "PIVOT",
	"guard": "GUARD", "rest": "REST", "wait": "WAIT",
}

# Fixed spell-category buttons (always shown, in this order). Each maps to a
# spell ROLE: the button displays the name of the equipped spell that fills that
# role, and is unpressable when no gear fills it. Add a category here if a new
# spell role appears.
const SPELL_SLOTS := [
	{ "role": "buff", "label": "Buff" },
	{ "role": "aoe",  "label": "AoE" },
	{ "role": "poke", "label": "Sp. Atk." },
	{ "role": "blink", "label": "Mobility" },
	{ "role": "item", "label": "Item" },
]

var player: Combatant = null
var enemy: Combatant = null
var enabled := false
var spells: Array = []          # spell ids available to the player
var planned: Array = []         # short labels of actions chosen so far
var confirming := false         # both actions chosen; awaiting confirm
var waiting := false            # confirmed; the opponent is taking its turn
var rest_prompt := false        # roam sanctuary tile: REST is pressable even while disabled
var roam_extras: Array = []     # roam-only contextual buttons, e.g. [{"id":"gather","label":"GATHER"}]
var hover := ""

func _ready() -> void:
	position = ViewConfig.MENU_ORIGIN

# Story roam only: light up REST (a golden-tile full rest) while the rest of the menu stays
# disabled. Cleared automatically whenever combat calls set_state.
func set_rest_prompt(active: bool) -> void:
	if rest_prompt == active:
		return
	rest_prompt = active
	queue_redraw()

# Story roam only: contextual buttons for things you can do standing in the world (GATHER a
# gemstone, TALK to an NPC). Each is {"id","label"}; they're pressable while the combat menu
# is disabled and cleared automatically whenever combat calls set_state.
func set_roam_extras(list: Array) -> void:
	if _same_extras(list):
		return
	roam_extras = list
	queue_redraw()

func _same_extras(list: Array) -> bool:
	if list.size() != roam_extras.size():
		return false
	for i in range(list.size()):
		if String(list[i].get("id", "")) != String(roam_extras[i].get("id", "")):
			return false
	return true

func _roam_extra_label(id: String) -> String:
	for e in roam_extras:
		if String(e.get("id", "")) == id:
			return String(e.get("label", id))
	return ""

func _is_roam_extra(id: String) -> bool:
	for e in roam_extras:
		if String(e.get("id", "")) == id:
			return true
	return false

func set_state(p: Combatant, e: Combatant, is_enabled: bool, spell_ids: Array,
		p_planned: Array = [], p_confirming: bool = false, p_waiting: bool = false) -> void:
	player = p
	enemy = e
	enabled = is_enabled
	spells = spell_ids
	planned = p_planned
	confirming = p_confirming
	waiting = p_waiting
	rest_prompt = false            # combat drives the menu; drop any roam rest prompt
	roam_extras = []               # ...and any roam contextual buttons
	queue_redraw()

func _entries() -> Array:
	var list: Array = BASIC.duplicate()
	for slot in SPELL_SLOTS:
		list.append("spell:" + String(slot["role"]))   # fixed category buttons
	if confirming:
		list.append("confirm")
	for e in roam_extras:
		list.append(String(e.get("id", "")))   # roam contextual buttons (gather / talk)
	return list

# The equipped spell id whose ai_role matches this slot ("" if no gear fills it).
func _spell_for_role(role: String) -> String:
	for sid in spells:
		if String(Config.def(sid).get("ai_role", "")) == role:
			return sid
	return ""

func _slot_label(role: String) -> String:
	for slot in SPELL_SLOTS:
		if String(slot["role"]) == role:
			return String(slot["label"])
	return role

func _btn_rect(i: int) -> Rect2:
	return Rect2(0, HUD_H + i * (BTN_H + GAP), BTN_W, BTN_H)

func _usable(id: String) -> bool:
	if player == null:
		return false
	if _is_roam_extra(id):
		return true                 # roam contextual button (gather / talk) -> always pressable
	if rest_prompt and id == "rest":
		return true                 # golden sanctuary tile -> REST is pressable outside combat
	if not enabled:
		return false
	if id == "confirm":
		return true                 # not a costed action; always clickable
	if id.begins_with("spell:"):
		var sid := _spell_for_role(id.substr(6))
		if sid == "":
			return false            # no gear fills this slot -> can't press
		if Config.def(sid).get("once_per_match", false) and player.spent_once.has(sid):
			return false   # once-per-match and already used
		if int(player.cooldowns.get(sid, 0)) > 0:
			return false
		if Config.def(sid).get("once_per_match", false) and player.spent_once.has(sid):
			return false        # single-use item already spent this match
		return Config.can_afford(player.energy, player.mp, player.statuses, sid)
	if id == "rest" and not player.rest_ready:
		return false                # locked until a full turn passes without damage
	if Config.def(id).get("once_per_match", false) and player.spent_once.has(id):
		return false            # single-use item already spent this match
	return Config.can_afford(player.energy, player.mp, player.statuses, id)

func _label(id: String) -> String:
	if _is_roam_extra(id):
		return _roam_extra_label(id)
	if id == "confirm":
		return "CONFIRM \u2713"
	if id.begins_with("spell:"):
		var role := id.substr(6)
		var cat := _slot_label(role)
		var sid := _spell_for_role(role)
		if sid == "":
			return "%s: (none)" % cat               # no gear -> shown, disabled
		var d := Config.def(sid)
		var s := "%s: %s (%dmp)" % [cat, d.get("name", sid), int(d.get("mp_cost", 0))]
		var cd := int(player.cooldowns.get(sid, 0))
		if cd > 0:
			s += "  CD%d" % cd
		return s
	var ecost := Config.effective_energy_cost(id, player.statuses)
	var nm: String = BASIC_LABELS.get(id, id)
	return "%s (%de)" % [nm, ecost] if ecost > 0 else nm

func _draw() -> void:
	var font := ThemeDB.fallback_font
	# No header text: resources are in the ResourceHUD and the buttons start at the top.

	var entries := _entries()
	for i in range(entries.size()):
		var id: String = entries[i]
		var rect := _btn_rect(i)
		var usable := _usable(id)
		var col := ViewConfig.COL_BTN
		if not usable:
			col = ViewConfig.COL_BTN_OFF
		elif hover == id:
			col = ViewConfig.COL_BTN_HOVER
		draw_rect(rect, col)
		draw_rect(rect, ViewConfig.COL_BOARD_EDGE, false, 1.0)
		var tcol := ViewConfig.COL_TEXT if usable else ViewConfig.COL_TEXT_OFF
		draw_string(font, rect.position + Vector2(10, 23), _label(id),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tcol)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := get_local_mouse_position()
		var old := hover
		hover = ""
		var entries := _entries()
		for i in range(entries.size()):
			if _btn_rect(i).has_point(local):
				hover = entries[i]
				break
		if old != hover:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not enabled and not rest_prompt and roam_extras.is_empty():
			return
		var local := get_local_mouse_position()
		var entries := _entries()
		for i in range(entries.size()):
			if _btn_rect(i).has_point(local) and _usable(entries[i]):
				var id: String = entries[i]
				if id.begins_with("spell:"):
					id = _spell_for_role(id.substr(6))   # emit the real spell id
				action_chosen.emit(id)
				return
