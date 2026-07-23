# UKO — THE COMPLETE RULESET (physics era: rounds 27–30)

Every number below is read from the live code (Config, SpellBook, Resolver),
not from memory. Both engine twins carry identical values.

## 1. The clock

One shared tick clock per turn. Each action's strike time:

    final tick = BAND BASE + base tick (clamped 0–99) + direction tax
    slot 2 adds its own time on top of slot 1 (cumulative)
    slot 2 of a DIFFERENT id than slot 1: +80 (versatility tax)

Bands (earliest first): BUFF 0 · PIVOT 100 · GUARD 200 · ATTACK 300 ·
AOE 400 · MOVE 500 · SPECIAL 600 · REST 700. Same-tick entries resolve in two
phases: first state (pivots, moves, blink arrivals, rest, wait), then violence
(attacks, casts, projectile steps) — everyone is where they end up at T, and
every effect at T judges that board.

## 2. Basic actions

| Action | Tick (front aim) | Side aim | Back aim | Energy (front/side/back) | Notes |
|---|---|---|---|---|---|
| PIVOT  | **0** | — | — | 5 | Round 29: instant. Only pivot & blink ever change facing. Blocked while rooted. |
| GUARD  | **200** | — | — | 30 | Blocks MELEE ONLY, by attacker's flank vs you: front 100% / side 50% / back 0%. Refund 15/10/0. Success → next-turn speed boost (slot-1 action at front of its band). Drops the instant you attack. Can't share a turn with DARK BOLT. |
| ATTACK | **350** | 540 | 640 | **20 / 25 / 30** | Damage 15 × defender-flank (15/23/30). Cardinal aims only (Manhattan reach). Round 30: energy priced by YOUR aim direction. |
| MOVE   | **520** | 570 | 620 | 15 / 20 / 25 | Moving never changes your facing. Blocked tile → fizzle + full refund. Forward move into the foe's forward move on the same tile → CLASH. |
| WAIT   | **580** | — | — | **+5** (gain) | Round 30: halved from 10. Does NOT feed the pulse. |
| REST   | **790** | — | — | 0 | Heals HP *and* MP, 5–15% each, scaled by how LATE the enemy acts. Cancelled by ANY damage that turn (even the grenade's 1). Locked unless you took no damage last turn. |

## 3. Spells (granted by equipped gear)

| Spell | Gear | Tick | Cost | Effect |
|---|---|---|---|---|
| DISCOUNT (buff) | Sage Helm (head) | 20 | 10mp, cd 3 | −5 to every energy cost for 3 turns. |
| BURST (around) | Burst Plate (chest) | 440 | 30mp, cd 2 | 15 dmg to all 8 tiles around you. Ignores guard. |
| BLINK | Blink Greaves (legs) | departs 100, arrives 700 | 40mp, cd 4 | Fixed 2-tile cardinal jump, phases through tile 1, free reface, untargetable in transit. |
| DARK BOLT (line) | Bolt Amulet (jewellery) | launches 350, +200/tile → hits 550/750/950 | 40mp, cd 4 | 25 dmg, range 3, stopped by walls, dodged by leaving the line. Cannot share a turn with GUARD. |
| GRENADE (throw) | — (everyone, once per match) | launches 300, +40/tile → lands 340/380/420 | free | Range 3 (1 diagonally). No real damage (1 chip — enough to cancel a rest) but DRAINS 20 energy and ROOTS: the victim's next move AND pivot are cancelled. Point-blank it lands at 340 — before a 350 swing, enabling the drain-cancel (DRAINED DRY: an emptied tank breaks a queued attack). |

## 4. Statuses

DISCOUNT −5 all energy costs, 3 turns · ROOTED next move/pivot cancelled,
consumed on use · STAGGERED (lost a clash feint) next turn capped to ONE action.

## 5. Facing — the two directional systems (don't mix them up)

**Aim tiers (attacker-relative, round 30 + tick bundle):** where YOU aim
relative to where YOU face — front/side/back sets your attack's TIME (350/540/
640) and ENERGY (20/25/30), and your move's energy (15/20/25) and time
(520/570/620). Diagonal aims and self-tiles count FRONT by ratified design —
in practice this touches only the grenade, since melee and moves are cardinal.

**Flank tiers (defender-relative, the classic rule):** where the attacker
STANDS relative to where the DEFENDER faces — front ×1.0 / side ×1.5 /
back ×2.0 damage, and the guard's block/refund tiers. Attacking someone's back
while facing them costs you the cheap 20 — the aim tax punishes twisting
YOURSELF, not flanking THEM.

Facing changes ONLY via pivot (instant, 5) or blink (free reface). Mobs earn
facing from their last action; every level mob shows a facing bar and spawns
facing you.

## 6. Economy

Pulse: +30 after every 6 of your PLANNED real actions (wait/noop excluded;
fizzles still count — the spring always winds). Wait: +5 each. Guard refunds
by attacker-flank when it blocks: 15/10/0, plus the speed boost. Tanks cap at
100/100/100. Mobs (levels): full engine economy, no free refills — they press,
tire in waves, and their tanks are public (foe HUD, click to inspect).
Creatures may carry FLAT cost overrides replacing the directional formula
(round 32): the **bat flies cheap — move 10, sting 10** — so its kite cycle
runs ~20/turn against +10 income: long press waves, and every guarded sting
is an economic win for you (refund 15 vs its 10 paid).

## 7. The map clock

Every 10 turns the quadrants cycle clockwise and the zone closes one ring
(floor 4×4). A wall landing on you: suppressed, 20 crush. Caught inside the
closing ring: 20 crush + dragged one tile straight centreward (N→S, W→E,
corners diagonal); a blocker on the landing tile is SMASHED for another 20;
a fighter there means you slide one further. Incoming walls are telegraphed.

## 8. The clash (contested forward-forward)

Both forward-move into the same tile: hidden stance pick. push beats pull,
pull beats feint, feint beats push. Same stance = bounce, both −10 energy,
nobody moves. Push win: take the tile, shove for 10. Pull win: take the tile,
yank the loser into your wake, force-face them at you. Feint win: loser is
STAGGERED (next turn: one action). Offline vs AI uses the same oracle.

## 9. Special rules roundup

Line-track (round 27): a range-2+ attack (bats) hits a defender standing on a
NEARER tile of its firing line — you can't dodge INTO the shot; melee keeps the
classic dodge. Guard stops melee only — spells, bolts, bursts and grenades all
ignore it. Any damage cancels a rest and locks rest next turn. Attacking drops
your own guard mid-turn. Staggered planning is trimmed at plan time. Blink
transit = off-board, untargetable.

---

# DEEP ANALYSIS — faults, tensions, cheese (ranked)

**A1 · Side/back-aimed melee is close to a dead option (real tension, worth a
ruling).** [pivot, attack] costs 25 energy and lands at 430. A side-aimed
attack costs the same 25 but lands at 540; back-aimed 30 and 640. So whenever
you can spare both slots, pivot-first strictly beats aiming off-facing — faster
for equal energy. Off-facing attacks only earn their keep when slot 2 must do
something else (guard, move, spell). This was balanced before round 29 (pivot
time made them tie); pivot T=0 broke the tie. Options: accept it ("the pivot IS
the tax — aimed attacks are the slot-economy option"), or halve the aimed tick
tax for melee (190→90, 290→150) so both lines stay live. The harvest will show
whether off-facing attacks vanish from play — watch that telemetry.

**A2 · The pivot is a free metronome (watch item).** Zero time, 5 energy, and
it feeds the pulse — six pivots cost 30 and return 30. A player (or EXTREME,
which found pulse-pacing tricks before) can sprinkle pivots to advance the
pulse with no tempo cost at all. It's energy-neutral so it can't be farmed for
profit, but it makes "do nothing, instantly" a real action. If harvest lines
start showing pivot-dances, the fix is pivot feeding the pulse at half weight —
flag it, don't pre-fix it.

**A3 · Double-wait now earns exactly the activity pulse (residual stall).**
Two waits = +10/turn; an active player's pulse averages +10/turn. Income
parity means stalling no longer *out-earns* acting (round 30 fixed that), but
it matches it — a mutual-turtle game is decided only by the 80-turn draw cap.
Healthy enough to ship; if draw rates creep up in the next harvest, wait wants
to be +3, or +5-once-per-turn.

**A4 · Levels have no turn cap (small real gap).** Duels cap at 80 turns; the
level loops run forever. A player who turtles a melee-only bat into mutual
exhaustion sits in a stalemate the level never adjudicates. One line of
design: levels 3+ get a generous action clock like level 2's, or a turn cap
with retry. Worth doing before more combat levels ship.

**A5 · The turtle (pivot+guard, 280) is strong but honestly answered — as long
as players learn one fact: guard stops melee only.** The counter-web: spells
ignore guard entirely, repositioning outpaces it (moves resolve after guard
but the turtle isn't attacking), and economically a turtle bleeds −20/turn
([pivot,guard] = 5+30−15 refund) while an active foe gains +10 — the turtle
loses the long game by ~30/turn of drift. No fix needed; the teach burden goes
to a future level ("the turtle dies to spells").

**A6 · Boosted-attack vs turtle: checked, no bypass.** Guard-success speed
boost puts next turn's attack at 300 — still after the turtle's 280 guard.
The privilege survives; the boost matters against SLOW defenses only. Sound.

**A7 · Diagonal "front" loophole: checked, closed.** Melee reach is Manhattan
(cardinals only), so no diagonal attack exists to abuse the diagonal=front
rule; it touches only the grenade, as ratified. No action needed.

**A8 · Range-3 bolt rarely connects (old known shape, unchanged this era).**
Launch 350 + 200/tile puts the range-3 hit at 950, after every move band —
against an active foe it's a 40mp bluff unless the target is rooted, resting,
or point-blank. That's the designed identity (a zoning threat, not a snipe),
restated here so nobody reads the 950 as a bug later.

**A9 · Wait's tick (580) with +5 income makes late-turn waits strictly better
than early-turn waits — free timing niggle, zero counterplay impact; noted
only for completeness.**

Net verdict: the era is coherent. One ruling wanted from Fra (A1), one small
build task (A4 level caps), two telemetry watches (A2 pivots, A3 draws) that
the next harvest will answer for free.
