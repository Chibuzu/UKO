# LevelBook.gd
# The LEVELS campaign as pure data. ROUND 22 (Fra): campaign REBOOTED -- the ten
# combat drafts are superseded; levels are now designed ONE AT A TIME, each a
# deliberate lesson. Only level 1 exists; 2-5 arrive as Fra specs them.
#
# Map glyphs -- ROUND 25 (Fra): maps are PURE 8x8 BOARD coordinates, drawn on
# the duel's own BoardView (same art and layout as PLAY mode). No wall ring:
# the arena edge is the wall.
#   '#' interior blocker (duel blocker art)   '.' floor   '@' player spawn
#   'T' the TARGET tile (reach objectives; drawn as a gold marker)
#   'b' bat   's' slime   'x' serpent twin (boss pair)
#   'G' gemstone   'm' mushroom   'R' rest tile
#
# Per-level fields:
#   name / teach       -- the intro card
#   map                -- ASCII rows
#   objective          -- {"reach": true} | {"kills": true} | {"gems": N} | {"mushrooms": N}
#   reward             -- {"gold": N} | {"gear": id} | {"grenade": true}
#   actions            -- OPTIONAL: only these menu buttons are offered (tutor dial)
#
# LEVEL 1 DESIGN MATH (Fra spec: 8x8 arena, start top-left, target 2 right +
# 6 south, MOVE and PIVOT only, arrive without consuming ALL the energy):
# forward=15, side=20, pivot=5, pulse +30 per 6 actions, tank 100. The naive
# side-stepping route costs 130-30 = exactly 100 -> arrives at ZERO = fail.
# The pivot route (6 forward, pivot east, 2 forward) costs 125-30 = 95 ->
# arrives with 5. The two buttons on screen ARE the lesson.
class_name LevelBook
extends RefCounted

# The level being launched (set by LevelsPage, read by LevelController).
static var current: int = 1

const CONSOLATION_GOLD := 300   # gear reward already owned -> this much gold instead

const LEVELS := [
	{
		"name": "FIRST STEPS",
		"teach": "Reach the gold mark WITH ENERGY LEFT. Forward steps cost 15, side-steps 20, a pivot only 5 -- and every 6th action pulses 30 back. Face where you're going.",
		"reward": {"gold": 50},
		"objective": {"reach": true},
		"actions": ["move", "pivot"],
		"facing": "east",
		"map": [
			"@.......",
			"........",
			"........",
			"........",
			"........",
			"........",
			"..T.....",
			"........",
		],
	},
	# LEVEL 2 (Fra spec): reach the mark before the CLOCK hits zero. WAIT joins
	# the menu and earns its seat: brute-forced, the walk is IMPOSSIBLE on
	# moves+pivots alone -- breathing is mandatory. ROUND 30: waits pay the
	# ENGINE's +5 (same as duels, Fra ruling; the old +15 level breather is
	# gone), which re-solved the clock: min feasible 22 actions -> clock 24,
	# two to spare. Blockers exactly as specced.
	{
		"name": "AGAINST THE CLOCK",
		"teach": "24 actions on the clock -- every MOVE, PIVOT and WAIT spends one. Your tank alone can't make this walk: WAIT catches your breath (+5 energy, same as every duel). Breathe in bursts, then march.",
		"reward": {"gold": 75},
		"objective": {"reach": true, "clock": 24},
		"actions": ["move", "pivot", "wait"],
		"facing": "east",
		"map": [
			"@.#.....",
			"..#.....",
			"......#T",
			"........",
			"........",
			"........",
			"........",
			"........",
		],
	},
	# LEVEL 3 (Fra spec): beat a bat -- ATTACK and GUARD unlock. Player top-left
	# FACING WEST (into the wall: turn one, facing is already the lesson); the
	# bat two tiles right, facing you. Its brain kites by nature: backpedal when
	# hugged, sting from range 2. Round-24 rules make it beatable by patience:
	# it pays energy like you (watch its tank in the HUD), so drive it into the
	# walls and strike when it's winded. Guard its sting -- with your FACE.
	{
		"name": "THE KITER",
		"teach": "You stand at 30 HP: three stings end you. The bat pokes from TWO tiles and backpedals when you close in -- but it pays energy like you, and it tires (watch its tank, top right). GUARD facing it, corner it, strike when it's winded.",
		"reward": {"gear": "discount_charm"},   # ROUND 26 (Fra): the HEAD piece -- the
		"objective": {"kills": true},           # Sage Helm, granting the DISCOUNT buff
		"actions": ["move", "pivot", "wait", "attack", "guard"],
		"player_hp": 30,                        # ROUND 28 (Fra): guard or die
		"facing": "west",
		"map": [
			"@.b.....",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
		],
	},
	# LEVEL 4 (Fra spec): TWO bats in a pincer -- one two under you, one two
	# right, both facing you; you face right. A 2x2 lattice of pillars at
	# (1,2)(3,2)(1,4)(3,4) breaks their range-2 firing lines. New buttons: REST
	# (heals HP/MP -- pays more the safer your timing) and the BUFF slot (the
	# helm's DISCOUNT makes every action cheaper while it holds).
	{
		"name": "THE PINCER",
		"teach": "Two stings, two directions -- you cannot face both. Break their lines behind the pillars, cast your new DISCOUNT before the brawl, and REST behind cover to mend. One bat at a time.",
		"reward": {"gold": 150},
		"objective": {"kills": true},
		"actions": ["move", "pivot", "wait", "attack", "guard", "rest", "spell:buff"],
		"facing": "east",
		"map": [
			"@.b.....",
			"........",
			"b#.#....",
			"........",
			".#.#....",
			"........",
			"........",
			"........",
		],
	},
]

static func count() -> int:
	return LEVELS.size()

# 1-based level access (levels are numbered 1..N everywhere the player sees them).
static func level(n: int) -> Dictionary:
	return LEVELS[clampi(n, 1, LEVELS.size()) - 1]

# The reward line shown on the select page and the level intro ("50 GOLD" / "SAGE HELM").
static func reward_label(n: int) -> String:
	var r: Dictionary = level(n).get("reward", {})
	if r.has("gear"):
		return String(GearBook.gear_def(String(r["gear"])).get("name", "?")).to_upper()
	if r.has("grenade"):
		return "THE GRENADE"
	return "%d GOLD" % int(r.get("gold", 0))

# One line describing the objective, for the intro card and the select page.
static func objective_label(n: int) -> String:
	var o: Dictionary = level(n).get("objective", {})
	var parts: Array = []
	if bool(o.get("reach", false)):
		parts.append("reach the gold mark with energy to spare")
	if int(o.get("gems", 0)) > 0:
		parts.append("mine %d gem%s" % [int(o["gems"]), "s" if int(o["gems"]) > 1 else ""])
	if int(o.get("mushrooms", 0)) > 0:
		parts.append("harvest the mushroom")
	if bool(o.get("kills", false)):
		parts.append("slay every monster")
	return " + ".join(parts) if not parts.is_empty() else "slay every monster"
