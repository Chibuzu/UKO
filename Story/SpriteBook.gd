# SpriteBook.gd
# View-side registry of named SPRITE SETS for animated actors (story mobs for now). Each set
# is a folder of PNG frames plus an animation table; a mob PROFILE names its set via "art"
# (see MobBrain.PROFILES) and UnitView builds an AnimatedSprite2D from it instead of drawing
# the fallback colored disc. Adding a creature's art is ONE entry here + dropping its PNGs in
# the folder -- no engine change, no UnitView change, no per-mob code.
#
# Per animation: an explicit list of frame FILENAMES (exact case), the fps, and whether it
# loops. Explicit files rather than a "1..N" range on purpose -- real art has gaps and mixed
# case (the ooze walk has no frame 4, some frames are capitalised), and a missing file is
# simply skipped at load. Animation names are the SHARED vocabulary UnitView triggers:
# "idle" (loops), "move", "attack", and "summon" (the slime's split). A set that lacks one
# just never plays it.
#
# "directional": monster art is drawn facing its own way and we only ever flip_h it for
# left/right -- we never rotate it to the travel vector the way the up-pointing player art is
# rotated. So mob move/attack play upright; horizontal facing comes from the mob's facing.
class_name SpriteBook
extends RefCounted

const SETS := {
	"bat": {
		"dir": "res://Assets/Sprites/Mobs Animation/Bat Anims/",
		"directional": false,
		"offset_y": 0.0,
		"anims": {
			# "points" = the direction each art set is DRAWN. The bat's sets are MIXED:
			# the IDLE is drawn facing NORTH, while the MOVE and ATTACK figures are drawn
			# facing EAST. The view rotates from "points" onto whatever the art should aim
			# at, so no single "the bat faces X" rule is needed and re-drawing a sprite
			# only ever means editing its "points" here.
			"idle":   { "fps": 3.0, "loop": true,  "points": "up",    "files": ["Bat_Idle_1.png", "Bat_idle_2.png", "Bat_idle_3.png", "Bat_idle_4.png"] },
			"move":   { "fps": 5.0, "loop": false, "points": "right", "files": ["Bat_Move_1.png", "Bat_move_2.png", "Bat_move_3.png"] },
			"attack": { "fps": 5.0, "loop": false, "points": "right", "files": ["Bat_Attack_1.png", "Bat_Attack_2.png", "Bat_attack_3.png", "Bat_attack_4.png", "Bat_attack_5.png", "Bat_Attack_6.png", "Bat_Attack_7.png"] },
		},
	},
	"ooze": {
		"dir": "res://Assets/Sprites/Mobs Animation/Ooze Anims/",
		"directional": false,
		"offset_y": 0.0,
		"anims": {
			"idle":   { "fps": 2.0, "loop": true,  "files": ["Ooze_idle_1.png", "Ooze_Idle_2.png"] },
			"move":   { "fps": 4.0, "loop": false, "files": ["Ooze_move_1.png", "Ooze_Move_2.png", "Ooze_Move_3.png", "Ooze_move_5.png", "Ooze_move_6.png"] },
			# Body wind-up for the attack (the four directional SPITS are placed on the
			# neighbor tiles by StoryController._ooze_spit_burst). Slowed to 4 fps.
			"attack": { "fps": 4.0, "loop": false, "files": ["Ooze_Attack_1.png", "Ooze_Attack_2.png", "Ooze_Attack_3.png"] },
			"summon": { "fps": 4.0, "loop": false, "files": ["Ooze_summon_1.png", "Ooze_summon_2.png", "Ooze_Summon_3.png", "Ooze_summon_4.png", "Ooze_summon_5.png"] },
		},
	},
	# The cave boss: a PAIR of identical single-tile twins (Fra). Art measured, not
	# guessed -- every frame is exactly tile-aligned:
	#   idle       32x32 = ONE tile, creature centred
	#   move/melee 64x32 = TWO tiles, creature drawn in the RIGHT tile with its action
	#                      reaching into the LEFT one (i.e. drawn acting WEST).
	# "reach" marks those 2-tile clips: "step" = it ENDS in the next tile (a move),
	# "strike" = it stays put and only the blow reaches (a bite). UnitView centres such
	# a clip on the two tiles and rotates its west-drawn action onto the real direction.
	"twin": {
		"dir": "res://Assets/Sprites/Twin Boss/",
		"directional": false,
		"offset_y": 0.0,
		"anims": {
			"idle":   { "fps": 3.0, "loop": true, "points": "down", "files": ["Twin_Idle_1.png", "Twin_Idle_2.png", "Twin_Idle_3.png", "Twin_Idle_4.png"] },
			"move":   { "fps": 8.0, "loop": false, "points": "left", "reach": "step",
					"files": ["Twin_Move_1.png", "Twin_Move_2.png", "Twin_Move_3.png", "Twin_Move_4.png", "Twin_Move_5.png"] },
			"attack": { "fps": 10.0, "loop": false, "points": "left", "reach": "strike",
					"files": ["Twin_Melee_1.png", "Twin_Melee_2.png", "Twin_Melee_3.png", "Twin_Melee_4.png", "Twin_Melee_5.png", "Twin_Melee_6.png", "Twin_Melee_7.png"] },
		},
	},
}

static func has(key: String) -> bool:
	return SETS.has(key)

static func set_of(key: String) -> Dictionary:
	return SETS.get(key, {})
