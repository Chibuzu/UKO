# AI.gd
# Difficulty dispatcher. The game asks AI.choose_sequence(difficulty, ...) and
# this routes to the right "brain". Each brain has the SAME signature as the
# player's input would produce: it returns a 1-2 action sequence.
#
# Tiers (this is a simultaneous-move game, so the ladder is really HOW MUCH the
# AI reasons about the hidden enemy move):
#   EASY        - StubOpponent: a fixed reaction ladder, no look-ahead.
#   CHALLENGING - ChallengingAI: scores its own candidate sequences by playing
#                 them through the real resolver against one assumed enemy move.
#   HARD        - (TODO) model a distribution of enemy moves and counter.
#   EXTREME     - (TODO) solve the per-turn matrix near-optimally.
# HARD/EXTREME fall back to CHALLENGING for now so the menu can offer all four.
class_name AI
extends RefCounted

enum Difficulty { EASY, CHALLENGING, HARD, EXTREME }

# Chosen on the main menu's difficulty page; read by GameController at startup.
# A static var carries it across the menu->game scene change (no autoload needed;
# requires Godot 4.1+ — on 4.0 use a small autoload singleton instead).
static var selected_difficulty: int = Difficulty.CHALLENGING

static func choose_sequence(difficulty: int, me: Combatant, foe: Combatant,
		grid: Grid, spells: Array, opp_model = null) -> Array:
	match difficulty:
		Difficulty.EASY:
			return StubOpponent.choose_sequence(me, foe, grid, spells)
		Difficulty.CHALLENGING:
			return ChallengingAI.choose_sequence(me, foe, grid, spells)
		Difficulty.HARD:
			return HardAI.choose_sequence(me, foe, grid, spells, opp_model)
		Difficulty.EXTREME:
			return ExtremeAI.choose_sequence(me, foe, grid, spells, opp_model)  # game-theoretic equilibrium
		_:
			return StubOpponent.choose_sequence(me, foe, grid, spells)
		_:
			return StubOpponent.choose_sequence(me, foe, grid, spells)

static func name_of(difficulty: int) -> String:
	match difficulty:
		Difficulty.EASY: return "Easy"
		Difficulty.CHALLENGING: return "Challenging"
		Difficulty.HARD: return "Hard"
		Difficulty.EXTREME: return "Extreme"
		_: return "?"
