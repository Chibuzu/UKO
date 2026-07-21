# PromoteValue.gd -- the ONLY road from challenger to live judge. Copies
# user://value_fn_new.cfg over user://value_fn.cfg after a fit has EARNED it:
# arena PROMOTE verdict (>=55% vs the live judge) + all six position gates green
# with USE_VALUE. Keeps one rollback copy (value_fn_prev.cfg) so a bad promote
# is a one-file restore. Run via run_promote_value.bat; never automatic.
extends SceneTree

const LIVE := "user://value_fn.cfg"
const NEW := "user://value_fn_new.cfg"
const PREV := "user://value_fn_prev.cfg"

func _init() -> void:
	if not FileAccess.file_exists(NEW):
		print("[promote] nothing to promote: %s not found (run run_fit_value.bat first)." % NEW)
		quit(1)
		return
	var da := DirAccess.open("user://")
	if da == null:
		print("[promote] ERROR: cannot open user:// for writing.")
		quit(1)
		return
	if FileAccess.file_exists(LIVE):
		da.copy(LIVE, PREV)
		print("[promote] previous live judge backed up -> %s" % PREV)
	da.copy(NEW, LIVE)
	print("[promote] challenger promoted -> %s (live EXTREME reads it next match)." % LIVE)
	print("[promote] rollback: copy %s back over %s." % [PREV, LIVE])
	quit(0)
