# NPCBook.gd
# DATA registry for village NPCs (quest-givers). Each is pure data: a display name, a marker
# color (they render as colored discs for now, like mobs), a tile OFFSET from the village
# center, and the quest they hand out. Adding an NPC is one entry here; the controller spawns
# a disc per entry and opens that NPC's quest when you TALK next to it. Kept a single "quest"
# per NPC for now -- widen to a list here + in the talk flow when an NPC should offer several.
class_name NPCBook
extends RefCounted

# IDs are STABLE (quests + saves reference them); only display names and art change.
# "art": idle frames from Assets/Sprites/Village Characters/ (1 frame = still, 2 = sway).
const NPCS := {
	"warden": { "name": "Ancient",  "color": Color(0.45, 0.62, 0.95), "offset": Vector2i(-3, -2), "quest": "cull_bats",   "art": ["Ancient.png"] },
	"scout":  { "name": "Cowboy",   "color": Color(0.50, 0.85, 0.55), "offset": Vector2i( 3, -2), "quest": "find_shrines", "art": ["Cowboy_1.png", "Cowboy_2.png"] },
	"trader": { "name": "Chief",    "color": Color(0.95, 0.80, 0.35), "offset": Vector2i(-3,  3), "quest": "gel_delivery", "art": ["Chief_1.png", "Chief_2.png"] },
	"miner":  { "name": "Miner",    "color": Color(0.60, 0.45, 0.80), "offset": Vector2i( 3,  3), "quest": "gem_haul",    "art": ["Miner_1.png", "Miner_2.png"] },
	# The Merchant: no quest yet -- talking gives a flavor line until the shop role lands.
	"merchant": { "name": "Merchant", "color": Color(0.90, 0.55, 0.30), "offset": Vector2i(0, 3), "quest": "", "art": ["Merchant.png"] },
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
