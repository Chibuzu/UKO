# BridgeBench.gd -- OPTION-1 MEASUREMENT: is a per-call GDScript->C# resolve bridge
# viable, or must the whole search loop move into C#?
#
# Runs headless (see run_bridge_bench.bat) and answers two questions:
#  1. CORRECTNESS: the bridge (marshal -> C# Resolver -> marshal back) must produce the
#     SAME end states + result as the GDScript Resolver on 648 crossed cases + fixtures.
#  2. TIMING: per-call microseconds for (a) GDScript resolve, (b) bridge resolve,
#     (c) bridge Echo (marshal only, no resolve). From these:
#        C# compute  = (b) - (c)          crossing cost = (c)
#     -> if (b) < (a): per-call swaps are a win as-is (option 3 viable everywhere).
#     -> if (b) >= (a) but C# compute << (a): the engine IS faster, the boundary eats
#        it -> the search loop must live in C# (option 2 / batched calls).
extends SceneTree

const OUT_PATH := "user://bridge_bench.txt"
const FULL_GEAR := ["discount_charm", "burst_node", "blink_boots", "dark_focus"]
const N_TIME := 2000   # timing iterations per engine

var _lines: Array = []

func _say(s: String) -> void:
	print(s)
	_lines.append(s)

func _init() -> void:
	var bridge_script := load("res://Scripts/Port/CSharp/ResolverBridge.cs")
	if bridge_script == null:
		push_error("[bench] ResolverBridge.cs failed to load -- did the C# build succeed?")
		quit(1)
		return
	var bridge = bridge_script.new()

	# ── correctness ────────────────────────────────────────────────────────
	var cases := _build_cases()
	var bad := 0
	for i in range(cases.size()):
		var c: Dictionary = cases[i]
		var gd := Resolver.resolve(c["grid"], c["a"], c["b"], c["sa"], c["sb"], c["turn"])
		var cs = bridge.Resolve(_rows_of(c["grid"]), _to_dict(c["a"]), _to_dict(c["b"]), c["sa"], c["sb"], c["turn"])
		var gd_sig := "%s|%s|%s" % [gd["result"], _fp_c(gd["a"]), _fp_c(gd["b"])]
		var cs_sig := "%s|%s|%s" % [String(cs["result"]), _fp_d(cs["a"]), _fp_d(cs["b"])]
		if gd_sig != cs_sig:
			bad += 1
			if bad <= 5:
				_say("[MISMATCH] case %d" % i)
				_say("  gd: " + gd_sig)
				_say("  cs: " + cs_sig)
	if bad == 0:
		_say("[bench] CORRECTNESS: all %d bridge cases match the GDScript resolver." % cases.size())
	else:
		_say("[bench] CORRECTNESS FAILED: %d / %d mismatches -- DO NOT trust timings below." % [bad, cases.size()])

	# ── timing ─────────────────────────────────────────────────────────────
	# Cycle a small set of representative mid-game resolves (adjacent + spaced, incl.
	# two-action sequences and a projectile) so neither engine optimizes for one shape.
	var tc := _timing_cases()
	for w in range(50):   # warmup both paths (JIT, caches)
		var c: Dictionary = tc[w % tc.size()]
		Resolver.resolve(c["grid"], c["a"], c["b"], c["sa"], c["sb"], c["turn"])
		bridge.Resolve(_rows_of(c["grid"]), _to_dict(c["a"]), _to_dict(c["b"]), c["sa"], c["sb"], c["turn"])

	var t0 := Time.get_ticks_usec()
	for i in range(N_TIME):
		var c: Dictionary = tc[i % tc.size()]
		Resolver.resolve(c["grid"], c["a"], c["b"], c["sa"], c["sb"], c["turn"])
	var gd_us := float(Time.get_ticks_usec() - t0) / float(N_TIME)

	t0 = Time.get_ticks_usec()
	for i in range(N_TIME):
		var c: Dictionary = tc[i % tc.size()]
		bridge.Resolve(_rows_of(c["grid"]), _to_dict(c["a"]), _to_dict(c["b"]), c["sa"], c["sb"], c["turn"])
	var cs_us := float(Time.get_ticks_usec() - t0) / float(N_TIME)

	t0 = Time.get_ticks_usec()
	for i in range(N_TIME):
		var c: Dictionary = tc[i % tc.size()]
		bridge.Echo(_rows_of(c["grid"]), _to_dict(c["a"]), _to_dict(c["b"]), c["sa"], c["sb"], c["turn"])
	var echo_us := float(Time.get_ticks_usec() - t0) / float(N_TIME)

	var compute_us := cs_us - echo_us
	_say("")
	_say("[bench] TIMING (avg us/call over %d calls):" % N_TIME)
	_say("  GDScript resolve        : %8.1f us" % gd_us)
	_say("  bridge resolve (total)  : %8.1f us" % cs_us)
	_say("  bridge Echo (marshal)   : %8.1f us" % echo_us)
	_say("  -> C# compute (approx)  : %8.1f us" % compute_us)
	_say("")
	var speedup := gd_us / maxf(0.001, cs_us)
	var pure := gd_us / maxf(0.001, compute_us)
	_say("  per-call speedup (bridge as-is)      : %.2fx" % speedup)
	_say("  engine speedup (if loop lived in C#) : %.2fx" % pure)
	_say("")
	# Per-turn projection at EXTREME's budget shape: ~150 resolves/decision today.
	var per_turn_gd := gd_us * 150.0 / 1000.0
	var per_turn_cs := cs_us * 150.0 / 1000.0
	var per_turn_pure := compute_us * 150.0 / 1000.0
	_say("  projected 150-resolve decision: GD %.1f ms | bridge %.1f ms | in-C# loop %.1f ms" % [per_turn_gd, per_turn_cs, per_turn_pure])
	_say("")
	if cs_us < gd_us:
		_say("[verdict] Bridge is ALREADY faster per call -> incremental swaps (option 3) are viable.")
	elif compute_us < gd_us * 0.5:
		_say("[verdict] Engine is fast but the BOUNDARY eats it -> the search loop must move into C# (option 2 / batching).")
	else:
		_say("[verdict] C# compute is not decisively faster here -> re-examine before porting more.")

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
		print("[bench] report -> " + ProjectSettings.globalize_path(OUT_PATH))
	quit(0)

# ── case builders (mirror ParityDump) ─────────────────────────────────────
func _grid_from(rows: Array) -> Grid:
	var g := Grid.new()
	var m: Array = []
	for y in range(Grid.SIZE):
		var row: Array = []
		var line: String = rows[y] if y < rows.size() else ""
		for x in range(Grid.SIZE):
			row.append(x < line.length() and line[x] == "#")
		m.append(row)
	g.blocked = m
	g.base_blocked = g.blocked.duplicate(true)
	return g

func _open_grid() -> Grid:
	return _grid_from(["........","........","........","........","........","........","........","........"])

func _rows_of(g: Grid) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in range(Grid.SIZE):
		var s := ""
		for x in range(Grid.SIZE):
			s += "#" if g.blocked[y][x] else "."
		rows.append(s)
	return rows

func _c(id: String, pos: Vector2i, facing: int, hp: int, mp: int, energy: int, opts: Dictionary = {}) -> Combatant:
	var c := Combatant.new(id, pos, facing)
	c.equip(FULL_GEAR)
	c.hp = hp
	c.mp = mp
	c.energy = energy
	c.action_count = int(opts.get("action_count", 0))
	c.rest_ready = bool(opts.get("rest_ready", true))
	c.speed_boost = bool(opts.get("speed_boost", false))
	if opts.has("statuses"):
		c.statuses = (opts["statuses"] as Dictionary).duplicate()
	if opts.has("cooldowns"):
		c.cooldowns = (opts["cooldowns"] as Dictionary).duplicate()
	if opts.has("spent_once"):
		c.spent_once = (opts["spent_once"] as Dictionary).duplicate()
	return c

func _to_dict(c: Combatant) -> Dictionary:
	return {
		"id": c.id, "x": c.pos.x, "y": c.pos.y, "facing": c.facing,
		"hp": c.hp, "mp": c.mp, "energy": c.energy,
		"action_count": c.action_count, "rest_ready": c.rest_ready, "speed_boost": c.speed_boost,
		"cooldowns": c.cooldowns.duplicate(), "statuses": c.statuses.duplicate(),
		"spent_once": c.spent_once.duplicate(), "gear": c.gear.duplicate(),
	}

func _fp_c(c: Combatant) -> String:
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s" % [
		c.pos.x, c.pos.y, c.facing, c.hp, c.mp, c.energy,
		c.action_count, int(c.rest_ready), int(c.speed_boost),
		_dict_str(c.cooldowns), _dict_str(c.statuses), _dict_str(c.spent_once)]

func _fp_d(d: Dictionary) -> String:
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s" % [
		int(d["x"]), int(d["y"]), int(d["facing"]), int(d["hp"]), int(d["mp"]), int(d["energy"]),
		int(d["action_count"]), int(d["rest_ready"]), int(d["speed_boost"]),
		_dict_str(d["cooldowns"]), _dict_str(d["statuses"]), _dict_str(d["spent_once"])]

func _dict_str(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		var v = d[k]
		if v is bool:
			parts.append("%s=%s" % [str(k), "true" if v else "false"])
		else:
			parts.append("%s=%s" % [str(k), str(v)])
	return "{" + ",".join(parts) + "}"

func _opp(f: int) -> int:
	return (f + 2) % 4

func _alpha(p: Vector2i, f: int, q: Vector2i) -> Array:
	var fv: Vector2i = Config.FACING_VEC[f]
	var perp := Vector2i(-fv.y, fv.x)
	return [
		[{"id": "rest"}], [{"id": "wait"}], [{"id": "guard"}],
		[{"id": "attack", "tile": q}],
		[{"id": "move", "tile": p + fv}], [{"id": "move", "tile": p + perp}],
		[{"id": "move", "tile": p - perp}], [{"id": "move", "tile": p - fv}],
		[{"id": "pivot", "facing": _opp(f)}],
		[{"id": "dark_bolt", "tile": q}], [{"id": "aoe_burst"}], [{"id": "energy_buff"}],
		[{"id": "blink_step", "tile": p + fv * 2, "facing": f}],
		[{"id": "grenade", "tile": q}],
		[{"id": "guard"}, {"id": "attack", "tile": q}],
		[{"id": "wait"}, {"id": "attack", "tile": q}],
		[{"id": "energy_buff"}, {"id": "move", "tile": p + fv}],
		[{"id": "move", "tile": p + perp}, {"id": "attack", "tile": q}],
	]

func _build_cases() -> Array:
	var cases: Array = []
	var apos := Vector2i(3, 4)
	var bpos := Vector2i(4, 4)
	var A := _alpha(apos, Config.Facing.EAST, bpos)
	var B := _alpha(bpos, Config.Facing.WEST, apos)
	for sa in A:
		for sb in B:
			cases.append({"grid": _open_grid(),
				"a": _c("A", apos, Config.Facing.EAST, 100, 100, 100),
				"b": _c("B", bpos, Config.Facing.WEST, 100, 100, 100),
				"sa": sa, "sb": sb, "turn": 3})
	# delicate fixtures: rooted carryover, discount, spent grenade, boost, wall
	cases.append({"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(5, 4), Config.Facing.WEST, 100, 100, 100, {"statuses": {"rooted": 2}}),
		"sa": [{"id": "wait"}], "sb": [{"id": "move", "tile": Vector2i(4, 4)}], "turn": 4})
	cases.append({"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 15, {"statuses": {"energy_discount": 3}}),
		"b": _c("B", Vector2i(6, 6), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "move", "tile": Vector2i(4, 4)}], "sb": [{"id": "wait"}], "turn": 3})
	cases.append({"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100, {"spent_once": {"grenade": true}}),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "grenade", "tile": Vector2i(4, 4)}], "sb": [{"id": "wait"}], "turn": 3})
	cases.append({"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100, {"speed_boost": true}),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "attack", "tile": Vector2i(4, 4)}], "sb": [{"id": "attack", "tile": Vector2i(3, 4)}], "turn": 4})
	cases.append({"grid": _grid_from(["........","........","........","........","....#...","........","........","........"]),
		"a": _c("A", Vector2i(2, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(6, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "dark_bolt", "tile": Vector2i(6, 4)}], "sb": [{"id": "wait"}], "turn": 3})
	return cases

# Representative shapes for timing: melee trade, move+attack combo, bolt at range,
# guard vs press, blink approach -- the payoff-matrix cells the brain actually rolls.
func _timing_cases() -> Array:
	var out: Array = []
	out.append({"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 80, 70, 60),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 75, 60, 55),
		"sa": [{"id": "attack", "tile": Vector2i(4, 4)}], "sb": [{"id": "attack", "tile": Vector2i(3, 4)}], "turn": 5})
	out.append({"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 80, 70, 60),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 75, 60, 55),
		"sa": [{"id": "move", "tile": Vector2i(3, 3)}, {"id": "attack", "tile": Vector2i(4, 4)}],
		"sb": [{"id": "guard"}, {"id": "attack", "tile": Vector2i(3, 4)}], "turn": 5})
	out.append({"grid": _open_grid(),
		"a": _c("A", Vector2i(2, 4), Config.Facing.EAST, 80, 70, 60),
		"b": _c("B", Vector2i(5, 4), Config.Facing.WEST, 75, 60, 55),
		"sa": [{"id": "dark_bolt", "tile": Vector2i(5, 4)}], "sb": [{"id": "move", "tile": Vector2i(5, 5)}], "turn": 6})
	out.append({"grid": _open_grid(),
		"a": _c("A", Vector2i(2, 4), Config.Facing.EAST, 80, 70, 60),
		"b": _c("B", Vector2i(5, 4), Config.Facing.WEST, 75, 60, 55),
		"sa": [{"id": "blink_step", "tile": Vector2i(4, 4), "facing": Config.Facing.EAST}],
		"sb": [{"id": "wait"}, {"id": "attack", "tile": Vector2i(4, 4)}], "turn": 6})
	return out
