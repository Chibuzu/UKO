# ParityDump.gd -- C# ENGINE PORT, STAGE ZERO: the golden oracle.
#
# Emits a DETERMINISTIC file of (fully-specified input -> resolver output) cases to
#   user://parity_gd.txt
# The C# port reproduces the SAME cases in code and must emit a byte-identical file,
# stage by stage (Config.cs -> Combatant.cs -> Resolver.cs). Any divergence is a
# ported-rules bug caught before the brain ever switches forward models.
#
# Run headless:  godot --headless --path . --script "res://Scripts/Port/ParityDump.gd"
# (see run_parity.bat)
#
# DESIGN NOTES (read before editing):
#  * NO RNG. Arenas are hand-built from ASCII templates, never Grid.generate(rng) --
#    so the port only has to reproduce Resolver + Config math, not Godot's RNG stream.
#    The Resolver itself is confirmed RNG-free, so every case is reproducible.
#  * FULL GEAR, not SelfPlayArena.kit(). The tuner kit's entries are spell/status ids,
#    not GearBook ids, so spell_ids() returns only "grenade" under it (flagged to Fra).
#    A Resolver oracle must exercise EVERY branch, so fighters here equip real gear:
#    ["discount_charm","burst_node","blink_boots","dark_focus"] -> energy_buff,
#    aoe_burst, blink_step, dark_bolt (+ universal grenade).
#  * CANONICAL FINGERPRINT. _fp() mirrors Eval._c_key's FIELDS exactly, but serializes
#    the three dictionaries (cooldowns/statuses/spent_once) with SORTED "k=v" pairs
#    instead of GDScript's str(dict) pretty-printer -- so the C# side can match the
#    bytes without reproducing Godot's dictionary formatting. (Unifying this into a
#    shared Eval helper is a possible later cleanup; kept local to avoid touching the
#    shipped brain from a tooling change.)
#  * Sequences are fed RAW to the Resolver (no brain, no WAIT-pad, no sampling): the
#    dump is a pure engine oracle, so it is 100% deterministic every run.
extends SceneTree

const OUT_PATH := "user://parity_gd.txt"

# Full gear that grants all four starter spells (+ grenade is universal).
const FULL_GEAR := ["discount_charm", "burst_node", "blink_boots", "dark_focus"]

func _init() -> void:
	var cases := _build_cases()
	var lines: Array = []
	lines.append("# UKO parity oracle v1 -- %d cases -- GDScript reference" % cases.size())
	lines.append("# fmt: idx|grid|Ain|Bin|PA|PB|turn=>result|Aout|Bout|events")
	for idx in range(cases.size()):
		lines.append(_run_case(idx, cases[idx]))
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[parity] cannot open %s" % OUT_PATH)
		quit(1)
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("[parity] wrote %d cases -> %s" % [cases.size(), ProjectSettings.globalize_path(OUT_PATH)])
	print("[parity] done")
	quit(0)

# ── One case: resolve and format the golden line ─────────────────────────
func _run_case(idx: int, c: Dictionary) -> String:
	var grid: Grid = c["grid"]
	var a: Combatant = c["a"]
	var b: Combatant = c["b"]
	var out := Resolver.resolve(grid, a, b, c["sa"], c["sb"], int(c.get("turn", 1)))
	return "%d|%s|%s|%s|%s|%s|%d=>%s|%s|%s|%s" % [
		idx, _grid_sig(grid),
		_fp(a), _fp(b),
		_plan_str(c["sa"]), _plan_str(c["sb"]), int(c.get("turn", 1)),
		String(out["result"]),
		_fp(out["a"]), _fp(out["b"]),
		_events_digest(out["events"]),
	]

# ── Fingerprints (portable) ──────────────────────────────────────────────
# Mirrors Eval._c_key's fields; dicts canonicalized (sorted k=v) for cross-language parity.
func _fp(c: Combatant) -> String:
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s" % [
		c.pos.x, c.pos.y, c.facing, c.hp, c.mp, c.energy,
		c.action_count, int(c.rest_ready), int(c.speed_boost),
		_dict_str(c.cooldowns), _dict_str(c.statuses), _dict_str(c.spent_once)]

func _dict_str(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%s" % [str(k), str(d[k])])
	return "{" + ",".join(parts) + "}"

# Behavioral digest: sorted per-type event counts. Language-portable (strings + ints),
# and independent of Vector2i pretty-printing, which would otherwise break byte-parity.
func _events_digest(events: Array) -> String:
	var tally: Dictionary = {}
	for e in events:
		var t := String(e.get("type", ""))
		tally[t] = int(tally.get(t, 0)) + 1
	var keys := tally.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s:%d" % [String(k), int(tally[k])])
	return ";".join(parts)

func _plan_str(seq: Array) -> String:
	var parts: Array = []
	for act in seq:
		var s := String(act.get("id", ""))
		if act.has("tile"):
			var t: Vector2i = act["tile"]
			s += "@%d.%d" % [t.x, t.y]
		if act.has("facing"):
			s += "^%d" % int(act["facing"])
		parts.append(s)
	return "+".join(parts) if not parts.is_empty() else "-"

func _grid_sig(g: Grid) -> String:
	var s := ""
	for y in range(Grid.SIZE):
		for x in range(Grid.SIZE):
			s += "1" if g.blocked[y][x] else "0"
	return s

# ── Builders ─────────────────────────────────────────────────────────────
# 8-row ASCII arena: '#' = wall, anything else = open. base_blocked = blocked (no rotation).
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
	return _grid_from([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
	])

# Combatant with sane duel defaults; opts overrides any of the state fields.
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

func _opp(f: int) -> int:
	return (f + 2) % 4

# The action alphabet from a seat at `p` facing `f`, with the foe at `q`. Every entry
# is legal from an interior open tile, so a full A-alpha x B-alpha cross sweeps the
# simultaneous-resolution matrix (ordering, guard-drop timing, mutual moves, casts).
func _alpha(p: Vector2i, f: int, q: Vector2i) -> Array:
	var fv: Vector2i = Config.FACING_VEC[f]
	var perp := Vector2i(-fv.y, fv.x)
	var fwd: Vector2i = p + fv
	var back: Vector2i = p - fv
	var sidea: Vector2i = p + perp
	var sideb: Vector2i = p - perp
	var blink_aim: Vector2i = p + fv * 2
	return [
		{"tag": "rest", "seq": [{"id": "rest"}]},
		{"tag": "wait", "seq": [{"id": "wait"}]},
		{"tag": "guard", "seq": [{"id": "guard"}]},
		{"tag": "atk", "seq": [{"id": "attack", "tile": q}]},
		{"tag": "mv_fwd", "seq": [{"id": "move", "tile": fwd}]},
		{"tag": "mv_sa", "seq": [{"id": "move", "tile": sidea}]},
		{"tag": "mv_sb", "seq": [{"id": "move", "tile": sideb}]},
		{"tag": "mv_back", "seq": [{"id": "move", "tile": back}]},
		{"tag": "pivot", "seq": [{"id": "pivot", "facing": _opp(f)}]},
		{"tag": "bolt", "seq": [{"id": "dark_bolt", "tile": q}]},
		{"tag": "burst", "seq": [{"id": "aoe_burst"}]},
		{"tag": "buff", "seq": [{"id": "energy_buff"}]},
		{"tag": "blink", "seq": [{"id": "blink_step", "tile": blink_aim, "facing": f}]},
		{"tag": "nade", "seq": [{"id": "grenade", "tile": q}]},
		{"tag": "grd_atk", "seq": [{"id": "guard"}, {"id": "attack", "tile": q}]},
		{"tag": "wait_atk", "seq": [{"id": "wait"}, {"id": "attack", "tile": q}]},
		{"tag": "buff_mv", "seq": [{"id": "energy_buff"}, {"id": "move", "tile": fwd}]},
		{"tag": "sa_atk", "seq": [{"id": "move", "tile": sidea}, {"id": "attack", "tile": q}]},
	]

func _build_cases() -> Array:
	var cases: Array = []

	# ── Block 1: dense adjacent cross. A(3,4) EAST vs B(4,4) WEST on open board.
	# Full alphabet x alphabet -> every simultaneous interaction at contact range.
	var apos := Vector2i(3, 4)
	var bpos := Vector2i(4, 4)
	var A := _alpha(apos, Config.Facing.EAST, bpos)
	var B := _alpha(bpos, Config.Facing.WEST, apos)
	for ea in A:
		for eb in B:
			cases.append({
				"grid": _open_grid(),
				"a": _c("A", apos, Config.Facing.EAST, 100, 100, 100),
				"b": _c("B", bpos, Config.Facing.WEST, 100, 100, 100),
				"sa": ea["seq"], "sb": eb["seq"], "turn": 3,
			})

	# ── Block 2: spaced geometry (dist 3). Movement/projectile/blink travel & dodge.
	var a2 := Vector2i(2, 4)
	var b2 := Vector2i(5, 4)
	var A2 := _alpha(a2, Config.Facing.EAST, b2)
	var B2 := _alpha(b2, Config.Facing.WEST, a2)
	for ea in A2:
		for eb in B2:
			cases.append({
				"grid": _open_grid(),
				"a": _c("A", a2, Config.Facing.EAST, 100, 100, 100),
				"b": _c("B", b2, Config.Facing.WEST, 100, 100, 100),
				"sa": ea["seq"], "sb": eb["seq"], "turn": 4,
			})

	# ── Block 3: targeted fixtures for states the open crosses can't reach.
	cases.append_array(_fixtures())
	return cases

# Each fixture pins one rule the sweep can't produce on its own.
func _fixtures() -> Array:
	var out: Array = []

	# Flank: attacker behind a foe facing away -> x2 back multiplier.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.EAST, 100, 100, 100),  # B faces away from A
		"sa": [{"id": "attack", "tile": Vector2i(4, 4)}], "sb": [{"id": "wait"}], "turn": 2,
	})
	# Flank: side hit -> x1.5.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(4, 3), Config.Facing.SOUTH, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),  # A on B's side
		"sa": [{"id": "attack", "tile": Vector2i(4, 4)}], "sb": [{"id": "wait"}], "turn": 2,
	})
	# Guard vs front attack -> fully blocked + refund + speed boost.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "attack", "tile": Vector2i(4, 4)}], "sb": [{"id": "guard"}], "turn": 2,
	})
	# Guard vs back attack -> slips past, no refund.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.EAST, 100, 100, 100),
		"sa": [{"id": "attack", "tile": Vector2i(4, 4)}], "sb": [{"id": "guard"}], "turn": 2,
	})
	# Mutual move into each other's tile -> atomic swap.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "move", "tile": Vector2i(4, 4)}], "sb": [{"id": "move", "tile": Vector2i(3, 4)}], "turn": 2,
	})
	# Move fizzle into a wall -> energy refunded.
	out.append({
		"grid": _grid_from(["........", "........", "........", "........", "...#....", "........", "........", "........"]),
		"a": _c("A", Vector2i(3, 4), Config.Facing.NORTH, 100, 100, 100),
		"b": _c("B", Vector2i(6, 6), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "move", "tile": Vector2i(3, 3)}], "sb": [{"id": "wait"}], "turn": 2,  # (3,3) is a wall
	})
	# Dark bolt travels and is dodged (foe steps off the line).
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(2, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(5, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "dark_bolt", "tile": Vector2i(5, 4)}], "sb": [{"id": "move", "tile": Vector2i(5, 5)}], "turn": 3,
	})
	# Dark bolt stopped by a wall between caster and foe.
	out.append({
		"grid": _grid_from(["........", "........", "........", "........", "....#...", "........", "........", "........"]),
		"a": _c("A", Vector2i(2, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(6, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "dark_bolt", "tile": Vector2i(6, 4)}], "sb": [{"id": "wait"}], "turn": 3,
	})
	# Grenade diagonal throw -> root + energy drain.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 3), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 60),
		"sa": [{"id": "grenade", "tile": Vector2i(4, 4)}], "sb": [{"id": "wait"}], "turn": 3,
	})
	# Rooted carryover: a root from last turn cancels this turn's FIRST move.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(5, 4), Config.Facing.WEST, 100, 100, 100, {"statuses": {"rooted": 2}}),
		"sa": [{"id": "wait"}], "sb": [{"id": "move", "tile": Vector2i(4, 4)}], "turn": 4,
	})
	# Blink over a foe, settling one tile short so they never share a tile.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(2, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "blink_step", "tile": Vector2i(4, 4), "facing": Config.Facing.EAST}], "sb": [{"id": "wait"}], "turn": 3,
	})
	# Blink fizzle at the edge (no landing tile along the aim).
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(7, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(2, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "blink_step", "tile": Vector2i(9, 4), "facing": Config.Facing.EAST}], "sb": [{"id": "wait"}], "turn": 3,
	})
	# AoE burst hits an adjacent foe (flat, no flank).
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "aoe_burst"}], "sb": [{"id": "wait"}], "turn": 3,
	})
	# Rest, uninterrupted -> HP/MP regen (foe out of range).
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(1, 1), Config.Facing.EAST, 40, 40, 100),
		"b": _c("B", Vector2i(6, 6), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "rest"}], "sb": [{"id": "wait"}], "turn": 5,
	})
	# Rest interrupted by a hit -> no regen, rest_ready false next turn.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 40, 40, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "rest"}], "sb": [{"id": "attack", "tile": Vector2i(3, 4)}], "turn": 5,
	})
	# Rest illegal when not rest_ready -> nooped.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(1, 1), Config.Facing.EAST, 40, 40, 100, {"rest_ready": false}),
		"b": _c("B", Vector2i(6, 6), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "rest"}], "sb": [{"id": "wait"}], "turn": 5,
	})
	# Energy pulse: action_count 5 + one real action crosses 6 -> +30 energy.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 40, {"action_count": 5}),
		"b": _c("B", Vector2i(6, 6), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "move", "tile": Vector2i(3, 3)}], "sb": [{"id": "wait"}], "turn": 6,
	})
	# no_guard_combo: guard THEN dark_bolt -> the bolt (second) is voided.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "guard"}, {"id": "dark_bolt", "tile": Vector2i(4, 4)}], "sb": [{"id": "wait"}], "turn": 3,
	})
	# Cooldown within a sequence: cast dark_bolt twice -> second is on cooldown, nooped.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(2, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(5, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "dark_bolt", "tile": Vector2i(5, 4)}, {"id": "dark_bolt", "tile": Vector2i(5, 4)}], "sb": [{"id": "wait"}], "turn": 3,
	})
	# Grenade spent_once: already used -> second throw is illegal/nooped.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100, {"spent_once": {"grenade": true}}),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "grenade", "tile": Vector2i(4, 4)}], "sb": [{"id": "wait"}], "turn": 3,
	})
	# Lethal: low-hp foe, back attack kills -> a_wins.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.EAST, 12, 100, 100),  # faces away, back x2 = 30 dmg
		"sa": [{"id": "attack", "tile": Vector2i(4, 4)}], "sb": [{"id": "wait"}], "turn": 8,
	})
	# Double KO -> draw (both die same turn).
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 12, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 12, 100, 100),
		"sa": [{"id": "aoe_burst"}], "sb": [{"id": "aoe_burst"}], "turn": 9,
	})
	# Speed boost carried in: slot-0 action jumps to the front of its band.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100, {"speed_boost": true}),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "attack", "tile": Vector2i(4, 4)}], "sb": [{"id": "attack", "tile": Vector2i(3, 4)}], "turn": 4,
	})
	# ── TICK BUNDLE fixtures (Fra-ratified physics) ──
	# Dodge by arithmetic: A faces NORTH, aims EAST (side, 350+190=540); foe runs
	# forward (520) -> gone before the swing lands -> whiff, no damage.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.NORTH, 100, 100, 100),
		"b": _c("B", Vector2i(4, 4), Config.Facing.EAST, 100, 100, 100),
		"sa": [{"id": "attack", "tile": Vector2i(4, 4)}], "sb": [{"id": "move", "tile": Vector2i(5, 4)}], "turn": 3,
	})
	# Clash: PUSH beats PULL -> pusher takes the tile, puller chipped 10 + yanked.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(5, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "move", "tile": Vector2i(4, 4), "stance": "push"}],
		"sb": [{"id": "move", "tile": Vector2i(4, 4), "stance": "pull"}], "turn": 3,
	})
	# Clash: FEINT beats PUSH -> pusher takes the tile but is STAGGERED.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(5, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "move", "tile": Vector2i(4, 4), "stance": "push"}],
		"sb": [{"id": "move", "tile": Vector2i(4, 4), "stance": "feint"}], "turn": 3,
	})
	# Clash: same stance -> both bounce, both pay the shoulder-check 10.
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100),
		"b": _c("B", Vector2i(5, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "move", "tile": Vector2i(4, 4)}], "sb": [{"id": "move", "tile": Vector2i(4, 4)}], "turn": 3,
	})
	# Staggered carried in: a 2-action plan is capped to ONE (status consumed).
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 100, {"statuses": {"staggered": 2}}),
		"b": _c("B", Vector2i(6, 6), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "move", "tile": Vector2i(4, 4)}, {"id": "move", "tile": Vector2i(5, 4)}],
		"sb": [{"id": "wait"}], "turn": 3,
	})
	# Energy-discount status active -> a move costs less (reduction applies).
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 15, {"statuses": {"energy_discount": 3}}),
		"b": _c("B", Vector2i(6, 6), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "move", "tile": Vector2i(4, 4)}], "sb": [{"id": "wait"}], "turn": 3,
	})
	# Energy starvation: cannot afford an attack -> nooped (illegal cost).
	out.append({
		"grid": _open_grid(),
		"a": _c("A", Vector2i(3, 4), Config.Facing.EAST, 100, 100, 5),
		"b": _c("B", Vector2i(4, 4), Config.Facing.WEST, 100, 100, 100),
		"sa": [{"id": "attack", "tile": Vector2i(4, 4)}], "sb": [{"id": "wait"}], "turn": 3,
	})

	return out
