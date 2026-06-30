# MobBehavior.gd
# A monster's overworld brain. Its job now is detection: when the player steps
# inside AGGRO_RADIUS it asks for a fight (the controller hands off to a real UKO
# duel). `suppressed` stops you from instantly re-fighting a survivor you're still
# standing next to after a lost duel -- it re-arms once you walk out of range.
# Roaming/patrol can return here later as extra methods; the controller stays the
# same shape (ask the brain, act on the answer).
class_name MobBehavior
extends RefCounted

const AGGRO_RADIUS := 4          # Chebyshev tiles: step inside this and the fight starts

var suppressed: bool = false     # true right after a duel, until the player leaves our range

func in_range(mob: OverworldEntity, player: OverworldEntity) -> bool:
	var to: Vector2i = player.tile() - mob.tile()
	return maxi(abs(to.x), abs(to.y)) <= AGGRO_RADIUS

# Should a duel start with this mob this instant?
func wants_fight(mob: OverworldEntity, player: OverworldEntity) -> bool:
	if in_range(mob, player):
		return not suppressed
	suppressed = false            # left our range -> re-arm for next approach
	return false
