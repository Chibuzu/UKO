# UKO Duel — Context & Handoff

**For the next Claude:** read this whole file, then read the actual code in this
repo — **the repo is the source of truth**, not anything you think you remember.
Francesco directs all design; you write all the code. Confirm the live decisions
below before implementing anything.

---

## Working agreement (non-negotiable)
- Be brutally honest and direct. No validation-seeking, no flattery.
- Before implementing: state the **problem**, your **proposed solution**, and the
  **downsides**, then wait for his decision. Don't implement things he didn't ask for.
- **Never guess at mechanics.** Read the relevant code first. If you're unsure how
  something resolves, open the file.
- **Verify before claiming it works.** The established practice is a small Python
  mirror of the resolver logic for anything timing/rules-sensitive (see the guard
  sim from the last session).
- He owns design decisions; you own implementation.

---

## What the game is
A 1v1 **simultaneous-turn (WEGO) tactical dueler** in **Godot 4 / GDScript**.
Both fighters lock in their turn at once, then it resolves. Design pillars: skill
as the primary tiebreaker, no dominant builds, "complexity without complication."

## Architecture (how the code is organized)
- **Event-driven.** `Resolver` is near-pure: it clones its inputs, never mutates
  them, and produces an ordered **event list** plus a `result`. The view layer only
  *consumes* events (animation, combat log, fx). Don't put game logic in the view.
- **Tunables are split by concern:** `Config.gd` (engine numbers/bands/costs),
  `SpellBook.gd` (spell + status content), `GearBook.gd` (gear pieces), `ViewConfig.gd`
  (all visuals/layout).
- **Spells are data:** `shape` + `effect` + `vfx` + `ai_role`. The engine never names
  a specific spell. A fighter has **no innate magic** — spells come from equipped
  **gear** (4 slots; a gear piece grants a spell).

## File map (paths under the Godot project's script folders)
- `core/`: `Config`, `SpellBook`, `GearBook`, `Grid`, `Combatant`, `Resolver`,
  `StubOpponent`, `AI`, `ChallengingAI`, `GameController`
- `view/`: `ViewConfig`, `BoardView`, `UnitView`, `EventPlayer`, `CombatLog`, `Fx`,
  `ActionMenu`, `MainMenu`, `EndScreen`
- Scenes: `MainMenu.tscn` (**main scene**), `Game.tscn` (root has `GameController`)

## Core ruleset (locked)
- **Bands** `{BUFF 0, PIVOT 100, GUARD 200, ATTACK 300, AOE 400, MOVE 500, SPECIAL 600,
  REST 700}`, width 100. "Attack-before-Move" world (melee can't be kited; AoE is
  un-dodgeable; dark_bolt at SPECIAL is dodgeable by stepping off the line, since
  MOVE 500 < SPECIAL 600).
- **Two-action timeline.** Each player picks ≤2 ordered actions (Rest = whole turn).
  Strike times are **cumulative**, so a slot-2 action resolves much later than if it
  were alone. Both players' actions interleave on one clock, sorted by `(tick, then
  band_priority, then A-before-B)`.
- **speed_boost**: set by **Wait** and by a **successful guard**; makes next turn's
  slot-0 action front-of-its-band (never cross-band). Read for scheduling at the top
  of `resolve()` *before* it's reset.
- **Flank** (`Resolver._flank(defender, attacker_pos)`): dot of `(attacker - defender)`
  with the defender's facing vector → `dot>0` front (1.0×), `dot<0` back (2.0×),
  `dot==0` side (1.5×).
- **Cooldowns are action-based** (aged 1 per action in `_plan`, before legalize; a cast
  goes on cd immediately so it can't recast itself the same turn).
- **Economy / anti-kite**: directional move cost (fwd/side/back), a shared energy pulse
  every N non-Wait actions, hard energy lockout at 0 (only Rest/Pivot/Spells usable).
- **Gear → spells**: `GameController` equips `PLAYER_GEAR` / `AI_GEAR`; reads
  `a.spell_ids()` / `b.spell_ids()`. Number keys 1–4 are slot-indexed.

## AI (done)
- `AI.gd` is the **dispatcher**: `AI.choose_sequence(difficulty, me, foe, grid, spells)`,
  a `Difficulty` enum `{EASY, CHALLENGING, HARD, EXTREME}`, and a `static var
  selected_difficulty` that carries the menu choice across the scene change.
- **Easy** = `StubOpponent` (reactive role-based ladder + the shared toolkit the search
  brain reuses).
- **Challenging** = `ChallengingAI`, a **shallow-search brain**: it generates candidate
  1–2 action sequences, plays each through the **real Resolver** against an assumed
  Easy enemy move, and scores the outcome (weights `W_DEAL / W_TAKE / W_WIN / W_RES /
  W_DIST` at the top of the file), keeping the best with Easy's pick as a floor.
  Flanking/dodging/guarding emerge from real-rules scoring, not hardcoded heuristics.
- **Hard / Extreme** currently fall back to Challenging and are shown disabled "(soon)"
  in the menu. Roadmap: Hard models a *distribution* of the player's moves; Extreme
  solves the per-turn matrix.

## Main menu (done)
`MainMenu.gd` (hand-drawn `Node2D`, main scene). PLAY opens a **difficulty page**
(`_mode = "main" | "difficulty"`); Easy/Challenging enabled, Hard/Extreme disabled,
plus Back. Picking a difficulty sets `AI.selected_difficulty` and changes to
`Game.tscn`. `GameController._ready` reads it on its first line. **Requires Godot
4.1+** for the `static var`; on 4.0 use a small autoload instead.

## Guard rework (done last session)
- A guard's shield **drops the instant the guarder takes an offensive action** (a basic
  attack, or a damaging spell where `effect.type == "damage"`). Defensive/neutral
  actions (move/pivot/buff/rest/wait) leave it up.
- A latched `guarded[id]` flag (separate from the live `guarding[id]` shield) means you
  still earn the block-refund if you blocked **before** striking.
- The drop is a **per-tick-group pre-pass** so a foe striking on the *same* tick as your
  attack is **not** blocked (clean trade).
- **Guard + dark_bolt is forbidden** in one turn: enforced in `Resolver._plan` (the later
  pick is voided via `_noop` + an `illegal_action` event with `reason "no_guard_combo"`),
  driven by a `"no_guard_combo": true` data flag on the spell, and blocked at pick-time
  in `GameController._add_action` / `_conflicts_with_plan`.

---

## ⚠️ LIVE DECISIONS — resume here (Francesco to choose)

1. **Guard timing — the important one.** Because slot-2 actions resolve *late*
   (cumulative scheduling: a guard→attack strikes at ~t550 while a normal attack lands
   at ~t350), the current "covered until your strike tick" rule means **guard→attack
   still blocks a normal first attack** — i.e. the "won't get hit but can hit" case he
   originally flagged still happens against a single attack. The change so far only
   exposes you to offense landing *after* your strike, and bans dark_bolt.
   **Decision needed:** keep it as-is (telegraphed/punishable; only beats a naive
   attacker) OR switch to **"guard drops at the offensive BAND tick (~t300)"** so
   guard→attack becomes a genuine trade even vs a first attack. The latter is a bigger
   resolver change (a scheduled drop-event decoupled from the action's resolution) and
   would make per-spell bans unnecessary.
2. **aoe_burst:** under the current rule, guard→aoe covers to ~t640. Should it also be
   `no_guard_combo`, or does the band-drop version (decision 1) make this moot?
3. **Menu greying (polish):** the conflicting Guard/bolt button is currently *silently*
   ignored on click. Option to grey it out in `ActionMenu` instead (small change).
4. **Second-action tax (discussing, not yet built):** need the **goal** first — curb
   2-action dominance generally? nerf a specific burst (attack+attack, move+attack
   alpha strike)? give 1-action turns a niche? — and whether 2-action turns actually
   dominate in playtests. Claude's lean: a **time tax** (extra within-band delay on
   slot-2) fits the "everything is timing" philosophy; note slot-2 is *already*
   time-taxed by cumulative scheduling, so confirm the problem is real before adding one.

## Other deferred items
- **Board scaling** (he wants the board bigger, keeping 32×32 art and 12×12 grid): not
  picked yet. Route A = project settings (Stretch Mode `canvas_items`, Aspect `keep`,
  base viewport ~960×460, window-size override 2×, Texture Filter `Nearest`) — scales
  everything uniformly. Route B = code (`BOARD_SCALE` in `ViewConfig`: scale the board
  node, reflow the log right, resize the window in `_ready`) — board only; clicks stay
  correct because `BoardView` maps clicks in its own local space.
- **Hard / Extreme AI brains** (see roadmap above).
- **Layered sprite (Step 5):** blockless base figure + 4 gear-block overlays (needs art
  from Francesco).
- **ChallengingAI weight tuning** after playtest (the 5 `W_*` constants).
- **Key/menu unification:** number keys are slot-based; menu spell buttons are
  role-based — unify later.

## Verification habit
For any resolver/timing change, mirror it in Python and print the tick timeline for a
few scenarios before telling him it works. He will (rightly) not trust "it works"
without it.
