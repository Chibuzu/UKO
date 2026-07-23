# LEVELS — the campaign (ROUND 22 REBOOT, Fra-directed)

Round 20's ten-level draft is superseded: levels are now designed ONE AT A
TIME, each a deliberate lesson, specced by Fra and built to measure. The
runner, ladder save, select page and reward machinery all stay; only the
level list was reset. Combat levels return when Fra specs them (2–5 next).

## Level 1 — FIRST STEPS (built)

Fra's spec, verbatim intent: an 8×8 arena; player starts in the top-left
corner; a marked tile sits 2 right + 6 south; the ONLY buttons are MOVE and
PIVOT; reach the mark **without consuming all the energy**.

Why this is a real puzzle and not a walk (engine numbers, ruleset 4):
forward step 15 · side-step 20 · pivot 5 · +30 pulse every 6th action · tank
100. The obvious route (side-step twice, walk down) costs 130 − 30 pulse =
**exactly 100: you arrive at zero and fail by the level's own rule.** The
lesson route — walk your facing 6 south, pivot east for 5, walk 2 — costs
125 − 30 = 95 and **arrives with 5 to spare**. The two buttons on screen are
the entire lesson: facing is money.

Mechanics used (all reusable for future levels):

- **Tutorial turn loop**: no monsters, but the REAL planning menu and the REAL
  resolver — energy costs, pulse and facing are engine truth, not scripted.
  (Turns resolve against an invisible waiting dummy in a sealed cell far off
  the board.)
- **`actions` tutor dial**: a level may offer only some buttons (here MOVE +
  PIVOT — no spells, no wait-stalling). Since round 26 the list may also
  unlock a spell slot by role, e.g. `"spell:buff"`.
- **Mid-turn arrival (round 27)**: CONFIRM always requires both actions (Fra);
  a turn that lands on the mark with slot 1 clears the level even if slot 2
  spends the rest — the walk is judged by the energy AT ARRIVAL.
- **'T' map glyph**: the reach target, drawn as a gold marker.
- Fail states: arriving with 0 energy, or dropping below the cheapest move
  before arriving → banner + free instant retry (ladder never regresses).

Reward: 50 gold (placeholder until Fra sets the ladder for the new 1–5).

## Level 2 — AGAINST THE CLOCK (built)

Fra's spec: reach a marked tile before a 16-action clock hits zero; WAIT joins
MOVE and PIVOT. Board: two-tall wall two tiles right of spawn (2,0)+(2,1), a
third wall one row under and four right (6,2), target immediately right of it
(7,2). Player starts top-left, facing south.

**The discovery (brute-forced over every legal sequence):** within 16 actions
the walk is IMPOSSIBLE on moves and pivots alone — minimum 11 moves plus two
turns costs 175 energy, and the tank plus every reachable pulse tops out
below that in time. Fra's added WAIT button is therefore load-bearing, and it
proved breathing mandatory. ROUND 30 (Fra): waits pay the ENGINE's own +5
everywhere — duels and levels alike (the +15 level breather is retired; it
had also been silently stacking on the engine's old +10). Re-solved at +5:
minimum feasible line is 22 actions, so the clock is **24** — two to spare.
The lesson is unchanged, the rhythm is burstier: breathe in clusters, then
march. The clock is the executioner; energy can no longer strand you.

Mechanics: `objective.clock` (action countdown, logged + floated every turn,
red when ≤4). Wait energy is engine-global (Config.WAIT_ENERGY = 5).

## Global rules of the mode (round 24, Fra)

- Every level is drawn on **the duel's own 8×8 board** (round 25): same art,
  origin and scale as PLAY mode; maps are pure board coordinates with no wall
  ring — the arena edge is the wall. Levels 1–2 start facing **east**, level 3
  west.
- **Mob resources are public**: an HP/MP/EP HUD sits top-right over the combat
  log (the log slides down); with several mobs, **click one to inspect it**.
- **Every mob shows its facing bar** and **spawns facing the player**.
- **Mobs pay energy like the player**: the free full-tank-per-turn refill is
  OFF in levels (flag-gated; story mode unchanged). They live on the engine's
  own pulse — +30 per 6 planned actions — so they press, tire, and recover in
  waves. Exhaustion is readable in their HUD and punishable.
- **No aggro radius**: every mob fights from turn one.

## Level 3 — THE KITER (built)

Fra's spec: beat a bat; ATTACK and GUARD unlock. Player top-left **facing
west** — into the wall, so the very first decision is a facing decision — the
bat two tiles east, facing you. Its stock brain already kites exactly as
specced: backpedal when hugged, sting from range 2, sidestep to firing lines.

Why it's now beatable and what it teaches: under the new energy rule the
bat's retreat-and-sting cycle burns ~45 energy a turn against a +10/turn
average income — it tires fast. The player learns to read the foe HUD (press
when its tank is low), to guard the sting *facing it* (guard covers front and
side only), and to use the arena's own walls as the corner that ends a kiter.
Five buttons: MOVE, PIVOT, WAIT, ATTACK, GUARD. Full 2-action turns (the real
duel rhythm starts here). **Reward (round 26, Fra): the HEAD piece — the Sage
Helm, whose spell is the DISCOUNT energy buff.** The new-ladder rewards begin.

## Level 4 — THE PINCER (built)

Fra's spec: two bats — one two tiles under you, one two to your right, both
facing you; you start top-left facing east. Pillars at (1,2), (3,2), (1,4),
(3,4) form a lattice that breaks range-2 firing lines. New unlocks: **REST**
(heals HP and MP — the engine pays more the later your enemy acts, so resting
behind cover when they're far pays best) and the **BUFF slot**, lit by the helm
earned one level ago: DISCOUNT (10mp, cd 3) cuts every action's energy cost
while it holds.

The lesson stack: you cannot face both stings — break line of sight with the
pillars, buff before the brawl so the chase is affordable, isolate one bat,
and mend behind cover while they reposition. The round-24 economy makes both
bats tire; the foe HUD (click either bat) tells you which one is winded.
Reward: 150g placeholder — Fra to place the chest piece on the new ladder.

## Level 5 — awaiting Fra's spec

The round-20 draft curve (flanks → guard → burst → doors) is parked as
reference in git history; nothing of it is live.

## Standing notes

- The gear ladder (helmet/chest/legs/grenade/jewellery every 2 levels) and the
  grenade gate machinery remain implemented and dormant — future levels just
  declare the rewards.
- Starting gold is still 2000 (buys the whole set day one) — open dial from
  round 20, Fra to ratify a lower start when the ladder matters.
- **Wait pays +5 everywhere (round 30, engine, both twins)**: halved from 10 —
  double-waiting no longer out-earns the activity pulse; the stall subsidy dies.
- **Directional attack pricing (round 30, engine, both twins)**: attacks cost
  front 20 / side 25 / back 30, statuses discount as usual, AI projections and
  candidate affordability updated to match. Your facing is your cheap arc —
  for every action in the game.
- **Ranged line-track rule (round 27, engine, both twins)**: a range-2+ attack
  flies down its firing line — a defender who steps onto a NEARER tile of the
  same line is hit anyway. Melee keeps the classic dodge; duels untouched
  (every duelist is range 1).
- Levels have no mob roaming: combat starts instantly from authored tiles
  (the free pre-combat approach step was the "bat starts adjacent" bug).
