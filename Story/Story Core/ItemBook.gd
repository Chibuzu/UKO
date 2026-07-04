# ItemBook.gd
# Registry of DROP ITEMS -- a new item family, separate from gear. These are collectible
# monster drops (materials for now): an item is just an id + display name + color, so
# adding one is a single entry here. When items later gain behavior (crafting inputs,
# quest turn-ins, consumable effects), extend the def with fields like "use"/"value" and
# read them where needed -- nothing else has to change. Held counts live in PlayerInventory.
class_name ItemBook
extends RefCounted

const ITEMS := {
	"bat_wing":      { "name": "Bat Wing",      "color": Color(0.62, 0.80, 1.00) },
	"slime_gel":     { "name": "Slime Gel",     "color": Color(0.55, 1.00, 0.62) },
	"serpent_scale": { "name": "Serpent Scale", "color": Color(0.90, 0.52, 0.55) },
	"serpent_fang":  { "name": "Serpent Fang",  "color": Color(1.00, 0.85, 0.40) },
	"gemstone":      { "name": "Gemstone",      "color": Color(0.66, 0.36, 0.92) },   # mirrors ViewConfig.COL_GEM (temporary; gem -> sprite soon)
	"mushroom":      { "name": "Mushroom",      "color": Color(0.90, 0.30, 0.32) },   # rare gatherable
}

static func has(item_id: String) -> bool:
	return ITEMS.has(item_id)

static func item_def(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})

static func item_name(item_id: String) -> String:
	return String(ITEMS.get(item_id, {}).get("name", item_id))

static func item_color(item_id: String) -> Color:
	return ITEMS.get(item_id, {}).get("color", Color.WHITE)
