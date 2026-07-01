# FetchQuest.gd
# "Loot X of a specific item and turn it back in." Progress is read LIVE from the bag (no
# stored state), and the hand-in CONSUMES the delivered items before the base pays out -- so
# unlike the other kinds, completing it costs you the materials.
class_name FetchQuest
extends QuestKind

func _item() -> String:
	return String(def.get("item", ""))

func progress() -> int:
	return PlayerInventory.count(_item())

# Only handable once you actually still hold enough (progress can dip if you use/sell items).
func can_turn_in() -> bool:
	return PlayerInventory.count(_item()) >= target_count()

func grant_reward() -> void:
	PlayerInventory.take(_item(), target_count())   # hand the materials over...
	super.grant_reward()                            # ...then gold + any item rewards
