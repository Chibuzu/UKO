# ViewConfig.gd
# SINGLE SOURCE OF TRUTH for how the game LOOKS. Sizes, colors, animation
# timings — all here. Change the feel of the whole game by editing this file;
# nothing else hardcodes a visual number. (Mirror of Config.gd, but for looks.)
class_name ViewConfig
extends RefCounted

# ── Layout ──────────────────────────────────────────────────
const TILE := 32                          # pixel size of one grid tile (32x32 pixel-art)
const BOARD_ORIGIN := Vector2(210, 40)    # board sits to the right of the menu

# ── Colors ──────────────────────────────────────────────────
const COL_OPEN := Color(0.20, 0.22, 0.26)
const COL_BLOCKED := Color(0.10, 0.10, 0.12)
const COL_GRID_LINE := Color(0.30, 0.62, 0.74, 0.40)   # dusky cyan grid — visible but still cold/cyber
const COL_BOARD_EDGE := Color(0.35, 0.40, 0.45)

const COL_A := Color(0.30, 0.55, 0.95)    # player A piece
const COL_B := Color(0.95, 0.35, 0.35)    # player B piece
const COL_FACING := Color(0.95, 0.92, 0.40)  # the facing nub

const COL_HP_BG := Color(0.15, 0.15, 0.18)
const COL_HP_FILL := Color(0.40, 0.85, 0.45)

# Flash tints (the piece briefly turns this color, then back to normal).
const FLASH_HIT := Color(1.0, 0.4, 0.4)
const FLASH_BLOCK := Color(0.45, 0.7, 1.0)
const FLASH_GUARD := Color(0.5, 0.8, 1.0)
const FLASH_GUARD_OK := Color(0.5, 0.95, 0.6)
const FLASH_HEAL := Color(0.45, 0.95, 0.55)
const FLASH_WHIFF := Color(0.6, 0.6, 0.6)

# Floating number colors.
const COL_DMG := Color(1.0, 0.5, 0.5)
const COL_HEAL := Color(0.5, 1.0, 0.6)

# Tile highlight overlays (semi-transparent, painted on top of tiles).
const COL_HL_MOVE := Color(0.40, 0.60, 0.90, 0.45)
const COL_HL_ATTACK := Color(0.90, 0.35, 0.35, 0.45)
const COL_HL_PIVOT := Color(0.55, 0.55, 0.65, 0.40)

# Spell effect flashes (transient tile overlays during playback).
const FX_DUR := 0.35
const COL_FX_AOE := Color(0.95, 0.55, 0.20, 0.55)
const COL_FX_BOLT := Color(0.65, 0.35, 0.90, 0.60)
const COL_FX_BUFF := Color(0.95, 0.82, 0.30, 0.55)
const FLASH_SPELL := Color(0.85, 0.7, 1.0)

# Telegraph: tiles that will become walls at the next quadrant shift.
const COL_GHOST_WALL := Color(0.95, 0.55, 0.20, 0.35)   # incoming-wall fill
const COL_GHOST_EDGE := Color(0.95, 0.62, 0.28, 0.90)   # incoming-wall border

# Action menu.
const MENU_ORIGIN := Vector2(16, 60)
const COL_BTN := Color(0.22, 0.25, 0.30)
const COL_BTN_HOVER := Color(0.32, 0.37, 0.44)
const COL_BTN_OFF := Color(0.14, 0.14, 0.16)
const COL_TEXT := Color(0.90, 0.90, 0.95)
const COL_TEXT_OFF := Color(0.45, 0.45, 0.50)
const COL_WIN_A := Color(0.40, 0.65, 1.0)
const COL_WIN_B := Color(1.0, 0.45, 0.45)
const COL_DRAW := Color(0.90, 0.85, 0.35)
const COL_GOLD := Color(1.0, 0.84, 0.30)   # gold reward / wallet readout

# Combat log panel (far right).
const LOG_ORIGIN := Vector2(620, 40)
const LOG_W := 286
const LOG_H := 384
const LOG_FONT := 12
const LOG_LINE_H := 16
const LOG_MAX_LINES := 200
const COL_LOG_BG := Color(0.10, 0.10, 0.13)
const COL_LOG_HEADER := Color(0.90, 0.85, 0.35)
const COL_LOG_DIM := Color(0.58, 0.60, 0.64)

# ── Animation timings (seconds) ─────────────────────────────
const MOVE_DUR := 0.30      # how long a move slide takes
const PIVOT_DUR := 0.15     # how long a pivot (reface) beat holds
const FLASH_DUR := 0.25     # how long a flash fades back
const HIT_DUR := 0.40       # beat held on a landed hit
const LABEL_DUR := 0.80     # floating number lifetime
const GROUP_GAP := 0.35     # legacy fixed gap; superseded by the tick-proportional pause below
# The pause between tick groups is proportional to the gap in SIM TICKS, so the
# animation timeline mirrors the resolver clock: a bolt crossing tiles 200 ticks
# apart, or a blink in transit for 600, waits in kind. Clamped at both ends.
const SEC_PER_TICK := 0.0015  # animation seconds per simulation tick
const GAP_MIN := 0.10         # floor on the inter-group pause
const GAP_MAX := 1.00         # ceiling, so a far-future event never stalls the match

# ── Juice ───────────────────────────────────────────────────
const HP_DRAIN_DUR := 0.35  # HP bar slides to its new value over this long
const HITSTOP := 0.08       # tiny freeze on a landed hit, for weight
const SHAKE_HIT := 6.0      # screen-shake pixels on a melee hit
const SHAKE_SPELL := 9.0    # screen-shake pixels on a spell hit
const SHAKE_DECAY := 45.0   # how fast shake settles (pixels/sec)
const BURST_COUNT := 16     # particles per impact
const BEAM_DUR := 0.30      # glowing bolt beam lifetime
const RING_DUR := 0.40      # AoE ring expansion lifetime

# Pixel center of a grid tile, in board-local space.
static func tile_center(pos: Vector2i) -> Vector2:
	return Vector2(pos.x * TILE + TILE / 2.0, pos.y * TILE + TILE / 2.0)
