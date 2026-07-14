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
			# Symmetric two-head body. "move" = vertical slither, "sidemove" = horizontal
			# (also the 90-deg turn). The view picks by axis and never flips/rotates.
			# move/sidemove play ONCE per step (loop:false) then settle to a still pose,
			# so a motionless serpent is truly still. No idle key -> never auto-idles.
			"move":     { "fps": 8.0, "loop": false, "files": ["BossMove_1.png", "BossMove_2.png", "BossMove_3.png", "BossMove_4.png", "BossMove_5.png", "BossMove_6.png", "BossMove_7.png"] },
			"sidemove": { "fps": 8.0, "loop": false, "files": ["BossSideMove_1.png", "BossSideMove_2.png", "BossSideMove_3.png", "BossSideMove_4.png", "BossSideMove_5.png", "BossSideMove_6.png", "BossSideMove_7.png"] },
			"attack":   { "fps": 8.0, "loop": false, "files": ["BossMelee_1.png", "BossMelee_2.png", "BossMelee_3.png", "BossMelee_4.png", "BossMelee_5.png", "BossMelee_6.png", "BossMelee_7.png", "BossMelee_8.png"] },
			"aoe":      { "fps": 8.0, "loop": false, "files": ["BossAoE_1.png", "BossAoE_2.png", "BossAoE_3.png", "BossAoE_4.png", "BossAoE_5.png", "BossAoE_6.png", "BossAoE_7.png", "BossAoE_8.png", "BossAoE_9.png", "BossAoE_10.png", "BossAoE_11.png"] },
		},
	},
}

static func has(key: String) -> bool:
	return SETS.has(key)

static func set_of(key: String) -> Dictionary:
	return SETS.get(key, {})
