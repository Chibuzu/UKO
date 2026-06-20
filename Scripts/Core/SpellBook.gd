# SpellBook.gd
# ALL spell and status CONTENT lives here, on its own, away from the engine's
# core numbers in Config.gd. This is the file you open to add or tweak spells
# and buffs — you should rarely need to touch anything else.
#
# A spell is data: a SHAPE (which tiles it touches) + an EFFECT (what it does).
#   shape  : "self" | "around" | "line"   (+ "range" for line)
#   effect : { "type": "damage", "amount": N }
#            { "type": "apply_status", "status": "<id>", "to": "self" }
#   needs_tile : true if the player aims it (line spells)
#
# To add a spell: copy an entry, change the numbers, give it a new id, set its
# "ai_role" (how the AI uses it) and "vfx" (how the view shows it), then point a
# GearBook piece's "spell" at it and equip that gear. A fighter only ever casts
# spells granted by its equipped gear.
# New buffs go in STATUSES and are applied via an "apply_status" effect.
class_name SpellBook
extends RefCounted

const SPELLS := {
	"energy_buff": {
		"name": "DISCOUNT", "category": "spell",
		"band": Config.Band.BUFF, "base_tick": 20,
		"energy_cost": 0, "mp_cost": 10, "cooldown": 3,
		"needs_tile": false,
		"shape": "self",
		"effect": { "type": "apply_status", "status": "energy_discount", "to": "self" },
		"ai_role": "buff",                                   # how the AI uses it
		"vfx": { "style": "self_buff", "cast_anim": "buff" },# how the view shows it
	},
	"aoe_burst": {
		"name": "BURST", "category": "spell",
		"band": Config.Band.AOE, "base_tick": 40,
		"energy_cost": 0, "mp_cost": 30, "cooldown": 2,
		"needs_tile": false,
		"shape": "around",
		"effect": { "type": "damage", "amount": 15 },   # [PH] less than a basic attack
		"ai_role": "aoe",
		"vfx": { "style": "aoe", "cast_anim": "" },
	},
	"dark_bolt": {
		"name": "DARK BOLT", "category": "spell",
		"band": Config.Band.SPECIAL, "base_tick": 50,  # after Move: step off the line to dodge it
		"energy_cost": 0, "mp_cost": 40, "cooldown": 4,
		"needs_tile": true,
		"shape": "line", "range": 3,
		"effect": { "type": "damage", "amount": 25 },   # [PH] see balance note
		"no_guard_combo": true,                          # cannot share a turn with Guard
		"ai_role": "poke",
		"vfx": { "style": "projectile", "cast_anim": "bolt", "projectile": "bolt_proj" },
	},
	"blink_step": {
		"name": "BLINK", "category": "spell",
		"band": Config.Band.PIVOT, "base_tick": 0,   # fast: resolves before the ATTACK band
		"energy_cost": 0, "mp_cost": 40, "cooldown": 4,
		"needs_tile": true,                          # player aims a direction
		"shape": "blink", "range": 2,                # fixed 2-tile jump, phases through tile 1
		"effect": { "type": "blink" },               # relocate the caster (+ free reface)
		"ai_role": "blink",
		"vfx": { "style": "blink", "cast_anim": "" },
	},
}

# Timed statuses (buffs/debuffs). duration = how many of the owner's turns it
# lasts after the turn it is applied.
const STATUSES := {
	"energy_discount": { "duration": 3, "energy_cost_reduction": 5 },   # lasts 3 full turns after cast (=6 actions @ 2/turn)
}
