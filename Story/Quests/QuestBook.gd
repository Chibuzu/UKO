# QuestBook.gd
# DATA registry for story quests plus the factory that hands back the right behavior -- the
# quest analogue of MobBrain. Each entry is pure data: which "kind" drives it, who gives it
# ("npc"), display text, the target count, and a reward. Adding a quest is usually one entry
# here; a genuinely new tracking rule is one QuestKind subclass + one line in make_quest.
# This file holds no logic beyond the factory.
class_name QuestBook
extends RefCounted

const QUESTS := {
	"cull_bats": {
		"kind": "kill", "npc": "warden",
		"title": "Cull the Bats",
		"desc": "Bats have been swarming the outskirts lately. Put down three of them and the roads will be a little safer.",
		"target_type": "bat", "count": 3,
		"reward": { "gold": 150, "items": {} },
	},
	"find_shrines": {
		"kind": "find_tiles", "npc": "scout",
		"title": "Chart the Shrines",
		"desc": "Golden shrines are scattered out in the wilds. Find two of them and mark them on my map.",
		"count": 2,
		"reward": { "gold": 200, "items": {} },
	},
	"gel_delivery": {
		"kind": "fetch", "npc": "trader",
		"title": "Slime Gel Run",
		"desc": "Bring me three Slime Gel from the slimes out east and I'll pay you well for the trouble.",
		"item": "slime_gel", "count": 3,
		"reward": { "gold": 180, "items": {} },
	},
	"gem_haul": {
		"kind": "gather", "npc": "miner",
		"title": "Gem Haul",
		"desc": "There are gemstone deposits out in the world -- the purple ones. Gather four and I'll cut you in.",
		"material": "gemstone", "count": 4,
		"reward": { "gold": 250, "items": {} },
	},
}

static func has(quest_id: String) -> bool:
	return QUESTS.has(quest_id)

static func quest_def(quest_id: String) -> Dictionary:
	return QUESTS.get(quest_id, {})

# The one place mapping a quest def's "kind" to its behavior. Add a case for a new kind.
static func make_quest(quest_id: String) -> QuestKind:
	var d: Dictionary = QUESTS.get(quest_id, {})
	var q: QuestKind
	match String(d.get("kind", "")):
		"kill":       q = KillQuest.new()
		"find_tiles": q = FindTilesQuest.new()
		"fetch":      q = FetchQuest.new()
		"gather":     q = GatherQuest.new()
		_:            q = QuestKind.new()
	q.setup(quest_id, d)
	return q
