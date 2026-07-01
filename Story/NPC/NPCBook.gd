# NPCBook.gd
# DATA registry for village NPCs (quest-givers). Each is pure data: a display name, a marker
# color (they render as colored discs for now, like mobs), a tile OFFSET from the village
# center, and the quest they hand out. Adding an NPC is one entry here; the controller spawns
# a disc per entry and opens that NPC's quest when you TALK next to it. Kept a single "quest"
# per NPC for now -- widen to a list here + in the talk flow when an NPC should offer several.
class_name NPCBook
extends RefCounted

const NPCS := {
	"warden": { "name": "Warden", "color": Color(0.45, 0.62, 0.95), "offset": Vector2i(-3, -2), "quest": "cull_bats" },
	"scout":  { "name": "Scout",  "color": Color(0.50, 0.85, 0.55), "offset": Vector2i( 3, -2), "quest": "find_shrines" },
	"trader": { "name": "Trader", "color": Color(0.95, 0.80, 0.35), "offset": Vector2i(-3,  3), "quest": "gel_delivery" },
	"miner":  { "name": "Miner",  "color": Color(0.60, 0.45, 0.80), "offset": Vector2i( 3,  3), "quest": "gem_haul" },
}

static func ids() -> Array:
	return NPCS.keys()

static func npc_def(npc_id: String) -> Dictionary:
	return NPCS.get(npc_id, {})

# Absolute world tile for an NPC = village center + its offset.
static func tile_of(npc_id: String) -> Vector2i:
	var off: Vector2i = NPCS.get(npc_id, {}).get("offset", Vector2i.ZERO)
	return OverworldMap.village_center() + off

static func quest_of(npc_id: String) -> String:
	return String(NPCS.get(npc_id, {}).get("quest", ""))
