# OverworldEntity.gd
# Any actor on the map -- the player OR a monster. It pairs the two things every
# actor needs: a Combatant (the rules-side state: pos, facing, hp, mp, energy,
# gear -- i.e. its "resources") and a UnitView (the on-map figure). All movement
# and combat-state changes go through here, so the player and mobs share ONE set
# of verbs (face / step_to / attack_toward / hurt / reset_to). Future actions
# (pivot, cast, guard) are added once here and both sides get them.
class_name OverworldEntity
extends RefCounted

var combatant: Combatant = null
var view: UnitView = null
var behavior = null              # a MobBehavior for monsters; null for the player
var tag: String = ""             # free-form (the mob's type, for duel lookup); "" for the player

# Build an actor from a loadout. The UnitView shows the real animated figure
# (or a tinted disc if the art isn't loaded), seated on its tile.
static func make(id: String, tile: Vector2i, facing: int, gear: Array, label: String) -> OverworldEntity:
	var e := OverworldEntity.new()
	e.combatant = Combatant.new(id, tile, facing)
	e.combatant.equip(gear)
	e.view = UnitView.new()
	e.view.init_state(e.combatant)
	e.view.unit_id = label
	return e

func tile() -> Vector2i:
	return combatant.pos

func world_pos() -> Vector2:
	return view.position          # the live (tweened) pixel position, for the camera

func face(f: int) -> void:
	if f != combatant.facing:
		combatant.facing = f
		view.set_facing(f)

func step_to(t: Vector2i) -> void:
	combatant.pos = t
	view.tween_to(t)              # slide + walk animation

func attack_toward(dir: Vector2i) -> void:
	view.play_anim("attack", Vector2(dir))

# Take damage; returns the new HP. Drives the figure's flash + HP bar.
func hurt(amount: int) -> int:
	combatant.hp = maxi(0, combatant.hp - amount)
	view.flash(ViewConfig.FLASH_HIT)
	view.set_display_hp(combatant.hp)
	return combatant.hp

# Snap back to a tile at a given HP (used to respawn the player).
func reset_to(t: Vector2i, hp: int) -> void:
	combatant.pos = t
	combatant.hp = hp
	view.set_state(combatant)
