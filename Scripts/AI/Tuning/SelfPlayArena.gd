# SelfPlayArena.gd
# Headless duel between two EXTREME brains with different Eval weight sets -- the
# engine under the tuner and the position suite. Mirrors GameController's turn loop
# exactly (rotation cadence, crush, resolve, adopt-clones) with no rendering.
class_name SelfPlayArena
extends RefCounted

const DEFAULT_KIT := ["dark_bolt", "aoe_burst", "energy_discount", "blink_step"]

# Fixed mirror kit. Deliberately NOT PlayerProfile.loadout(): autoloads don't exist
# yet when a --script run boots (touching one hangs the whole run), and a fixed kit
# makes tuning reproducible instead of dependent on whatever the save file holds.
static func kit() -> Array:
	return DEFAULT_KIT

# Play one match: w1 vs w2 (Eval weight dicts), w1 seated as A when w1_is_a.
# Returns {"result": "w1"|"w2"|"draw", "turns": int, "hp_margin": int (w1 - w2)}.
static func play_match(w1: Dictionary, w2: Dictionary, seed_value: int,
		w1_is_a: bool, max_turns := 50) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid := Grid.new()
	grid.generate(rng)
	var a := Combatant.new("A", grid.spawn_a, Config.Facing.EAST)
	var b := Combatant.new("B", grid.spawn_b, Config.Facing.WEST)
	a.equip(kit())
	b.equip(kit())
	var turn := 0
	while turn < max_turns:
		turn += 1
		if turn > 1 and (turn - 1) % Config.MAP_ROTATE_EVERY == 0:
			var rr := grid.rotate_blockers([a.pos, b.pos])
			a.pos = rr["positions"][0]
			b.pos = rr["positions"][1]
			for idx in rr["crushed_idx"]:
				var who: Combatant = a if int(idx) == 0 else b
				who.hp = maxi(1, who.hp - Config.MAP_CRUSH_DAMAGE)
				who.rest_ready = false
		Eval.set_weights(w1 if w1_is_a else w2)
		var seq_a := ExtremeAI.choose_sequence(a, b, grid, a.spell_ids())
		Eval.set_weights(w2 if w1_is_a else w1)
		var seq_b := ExtremeAI.choose_sequence(b, a, grid, b.spell_ids())
		var out := Resolver.resolve(grid, a, b, seq_a, seq_b, turn)
		a = out["a"]
		b = out["b"]
		var res := String(out["result"])
		if res == "a_wins" or res == "b_wins":
			var w1_won := (res == "a_wins") == w1_is_a
			return {"result": "w1" if w1_won else "w2", "turns": turn,
				"hp_margin": (a.hp - b.hp) if w1_is_a else (b.hp - a.hp)}
		elif res == "draw":
			return {"result": "draw", "turns": turn, "hp_margin": 0}
	var margin := (a.hp - b.hp) if w1_is_a else (b.hp - a.hp)   # turn cap: hp decides
	if margin > 0:
		return {"result": "w1", "turns": turn, "hp_margin": margin}
	elif margin < 0:
		return {"result": "w2", "turns": turn, "hp_margin": margin}
	return {"result": "draw", "turns": turn, "hp_margin": 0}
