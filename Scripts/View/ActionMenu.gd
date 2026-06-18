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
const HUD_H := 96

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
]

var player: Combatant = null
var enemy: Combatant = null
var enabled := false
var spells: Array = []          # spell ids available to the player
var planned: Array = []         # short labels of actions chosen so far
var confirming := false         # both actions chosen; awaiting confirm
var hover := ""

func _ready() -> void:
	position = ViewConfig.MENU_ORIGIN

func set_state(p: Combatant, e: Combatant, is_enabled: bool, spell_ids: Array,
		p_planned: Array = [], p_confirming: bool = false) -> void:
	player = p
	enemy = e
	enabled = is_enabled
	spells = spell_ids
	planned = p_planned
	confirming = p_confirming
	queue_redraw()

func _entries() -> Array:
	var list: Array = BASIC.duplicate()
	for slot in SPELL_SLOTS:
		list.append("spell:" + String(slot["role"]))   # fixed category buttons
	if confirming:
		list.append("confirm")
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
	if player == null or not enabled:
		return false
	if id == "confirm":
		return true                 # not a costed action; always clickable
	if id.begins_with("spell:"):
		var sid := _spell_for_role(id.substr(6))
		if sid == "":
			return false            # no gear fills this slot -> can't press
		if int(player.cooldowns.get(sid, 0)) > 0:
			return false
		return Config.can_afford(player.energy, player.mp, player.statuses, sid)
	return Config.can_afford(player.energy, player.mp, player.statuses, id)

func _label(id: String) -> String:
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
	if player != null and enemy != null:
		draw_string(font, Vector2(0, 16), "A  hp %d  mp %d  en %d" % [player.hp, player.mp, player.energy],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ViewConfig.COL_WIN_A)
		draw_string(font, Vector2(0, 38), "B  hp %d  mp %d  en %d" % [enemy.hp, enemy.mp, enemy.energy],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ViewConfig.COL_WIN_B)
		draw_string(font, Vector2(0, 66), "Your move" if enabled else "...",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ViewConfig.COL_TEXT)

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
		if not enabled:
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
