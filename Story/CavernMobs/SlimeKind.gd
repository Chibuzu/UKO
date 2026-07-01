# SlimeKind.gd
# Melee splitter. Threatens its 4 adjacent tiles (base default). The first time it drops
# to <=50% HP it spawns a same-resource copy next to the player that also fights; the copy
# is flagged so it can't split again, so there's no runaway. Movement and the strike are
# the base's; only the on-committed threshold behavior is new.
class_name SlimeKind
extends MobKind

func on_committed(entry: Dictionary, player: Combatant, ctx) -> void:
	if entry.get("no_split", false):
		return
	var c: Combatant = entry["combatant"]
	if c.is_dead():
		return
	if c.hp * 2 <= int(prof.get("hp", 100)):     # crossed to 50% or below
		entry["no_split"] = true
		ctx.spawn_split(entry, player)
