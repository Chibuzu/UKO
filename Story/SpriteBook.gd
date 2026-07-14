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
			"idle":   { "fps": 3.0, "loop": true,  "files": ["Bat_Idle_1.png", "Bat_idle_2.png", "Bat_idle_3.png", "Bat_idle_4.png"] },
			"move":   { "fps": 5.0, "loop": false, "files": ["Bat_Move_1.png", "Bat_move_2.png", "Bat_move_3.png"] },
			"attack": { "fps": 5.0, "loop": false, "files": ["Bat_Attack_1.png", "Bat_Attack_2.png", "Bat_attack_3.png", "Bat_attack_4.png", "Bat_attack_5.png", "Bat_Attack_6.png", "Bat_Attack_7.png"] },
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
	"serpent": {
		# The First Boss animation set, worn by the serpent (Fra). Two-tile creature:
		# UnitView spans it across head+tail via set_span/tween_span.
		"dir": "res://Assets/Sprites/First Boss/",
		"directional": false,
		"offset_y": 0.0,
		"anims": {
			# CLEAN pre-sized art (Fra extracted to exact tile footprints, transparent bg):
			#   idle/move = 32x64 VERTICAL body   (1 tile wide, 2 tall)
			#   sidemove  = 64x32 HORIZONTAL body (2 tiles wide, 1 tall) -- the TURN
			# No scaling needed: the sprite IS the footprint. move/sidemove loop while
			# stepping, then settle to a still frame; idle plays only when motionless.
			"idle":     { "fps": 3.0, "loop": true,  "files": ["Serpent_Idle_1.png", "Serpent_Idle_2.png", "Serpent_Idle_3.png", "Serpent_Idle_4.png"] },
			"move":     { "fps": 8.0, "loop": false, "files": ["Serpent_Move_1.png", "Serpent_Move_2.png", "Serpent_Move_3.png", "Serpent_Move_4.png", "Serpent_Move_5.png", "Serpent_Move_6.png", "Serpent_Move_7.png"] },
			# The TURN sweep: 88x59 frames drawn as vertical -> horizontal(east), pivoting
			# on the bottom of the vertical body. Bigger than the footprint on purpose;
			# the view anchors + flips it per turn direction (see _play_turn).
			"sidemove": { "fps": 10.0, "loop": false, "sweep": true, "files": ["Serpent_SideMove_1.png", "Serpent_SideMove_2.png", "Serpent_SideMove_3.png", "Serpent_SideMove_4.png", "Serpent_SideMove_5.png", "Serpent_SideMove_6.png", "Serpent_SideMove_7.png"] },
		},
	},
}

static func has(key: String) -> bool:
	return SETS.has(key)

static func set_of(key: String) -> Dictionary:
	return SETS.get(key, {})
