# UKO — HANDOFF (current state)

## 2026-07-17 REPO CLEANUP (audit session) — READ BEFORE ACTING ON OLDER ITEMS BELOW
- **SECRETS:** GD-Sync keys moved out of project.godot into git-ignored `override.cfg` (copy `override.cfg.example`, paste keys — a ready `override.cfg` ships with this delivery). The old pair is in git history: **ROTATE IT in the GD-Sync dashboard.**
- **DEAD TWIN DELETED (Fra-ratified):** the never-loaded Overworld scene-switch story path is gone — Overworld.gd/OverworldEntity/OverworldState/MobBehavior/overworld.tscn + MobAI + GameController's pending_b_gear/pending_b_mob/pending_return_scene/last_match_won + AIOpponent's mob branch. StoryController/MobKind/Mobs2 is THE story system (as item 0 already said). Item 11's "rename MOB_TYPES" is moot (that table died with Overworld); Combatant.attack_range/attack_all_adjacent stay in both engines (parity-covered) for when mob duels return via an explicit bootstrap.
- **EXTREME = ONE BRAIN (Fra-ratified):** EconomyAI/IntentSelector/PlanGenerator/EconomyEval/ResourceModel/TileUtility deleted (~1,100 lines). EXTREME runs the C# ExtremeAI; every fallback now runs the GDScript ExtremeAI("extreme") — the 880/880 numeric twin, never a different fighter. OvernightArena phase 2 is now cs_d2 vs the GDScript twin.
- **ALSO DELETED:** ENet multiplayer twin (NetworkSession/ENetTransport/LoopbackTransport + never-called handshake()/agrees_with()); CavernMobs stubs + CharacterSerpent (make_kind routes serpent→CharacterTwin); Gather/OneStrokeRune minigames; FX legacy grenade builders; trap consts (ExtremeAI ROOT_*/BUDGET_MS/EXPLOIT_LAMBDA + PROFILES["mob"] both languages, Config.energy_pulse_due both languages); CHAMPION_WEIGHTS is now an ARCHIVE comment in ExtremeAI.gd.
- **GATES RE-SITED:** PositionTests 1–4 still used 12×12 coordinates — on the 8×8 their fighters stood off-board/on walls (flee's kill line attacked a border wall = vacuous pass). Re-sited to the 1..6 interior, same tactical shapes. **First run re-baselines; expect changed rates, including press-starving.**
- **NEW GATE COMMAND: `verify_all.bat`** — build → both parity oracles → byte-diff → brain agreement, one command, honors a `UKO_GODOT` env var. Use it after ANY engine/brain change. (run_parity_cs.bat now calls diff_parity.bat; the .ps1 twin is gone.)
- **HYGIENE:** data_UKO_windows_x86_64/ (77 MB export sidecar) + 14 scratch logs untracked & git-ignored; .gitignore's pasted-project.godot header removed; /Build/ now correctly ignored. Debug spam removed (CAVERN banner, StoryCombat blink diagnostic, AIOpponent per-turn prints; GDSync prints behind DEBUG_NET). Small fixes: BG_PATH casing (floor art on case-sensitive exports), hit-flash now actually applied in EventPlayer._impact, ActionMenu duplicate once_per_match check, collision-safe quick-match lobby names, CombatLog.add_line() public API.

## 2026-07-17 ROUND 2 (same audit session) — structure, zero behavior change
- **ResolverEvents** (GD + CS twins): the 27 event type strings live in ONE registry per language; both Resolvers emit via it; EventPlayer/CombatLog match on it, declare their hidden types explicitly, and **warn once on unknown types**. NEW in the log (visible improvement, engine untouched): **CLASH receipts** (bounce / tile taken / stagger / damage — the new physics was mute) and **"blink fizzles"**. Parity goldens unchanged (values byte-identical, verified).
- **Combatant.to_bridge_dict()** = THE 14-key bridge marshal; the five hand copies (AI/BrainAgreement/BridgeBench/Overnight×2) now delegate to it. C# readers unchanged.
- **MatchBootstrap** = the ONE cross-scene handoff (difficulty persists for rematch; online config/opponent consumed via take_*). GameController.pending_* and AI.selected_difficulty are gone.
- **SpriteBook moved** Story/ → Scripts/View/ (duel view no longer depends on a Story file). Class-name references only; no code changes.
- **CameraRig extracted** from StoryController (split step 1 of the planned sequence — **playtest the camera feel before the next split step**: edge-scroll deadzone, cavern teleport, save-load centering, mob pop-in at the border).
- New scripts need .uid files: Godot generates them on first open — **commit them**.
- Deferred with reasons: facing-helper consolidation (remaining copies are mirrored GD↔CS pairs — consolidating one side would break the twin structure); GearBook.all_ids() (the ~8 gear lists disagree on ORDER, and order feeds candidate enumeration + parity fingerprints — needs a Fra decision); mob naming slime/ooze (save migration required); MP turn-deadline → force_default (untestable here); **critical-rest gate fix**: afford-aware threat (don't price melee/spell threats the foe cannot pay for THIS turn) in ThreatModel both languages — design for Fra to ratify, then verify_all + gates.

## 2026-07-18 ROUNDS 4-5 — story-side cleaning (see round-4/5 notes)
- R4: legacy budget-strike mob path DELETED (never executed; all creatures true-action). Guard-refund pass + roam facing + pairwise walling KEPT. PLAYTEST: bat/ooze(split)/twin-boss fights, roam tracking, loot.
- R5: **MinigameOverlay** base (shared open/finish/dim/button; contract = finished(quality: float), AttunementWave now emits 1.0/0.0) + **DayNightClock** extracted (split step 2 — pure time policy; controller applies effects). BUG FIX: the clock now PERSISTS in saves — reloading no longer resets to day 1 (walls still re-derive from seed at load; only the time side is restored). PLAYTEST: gather (gem + mushroom + attunement), a nightfall + dawn, save at night → reload keeps night.

## 2026-07-18 ROUND 6 — MainMenu split (router + GearShopPage + LobbyPage)
- MainMenu is a ROUTER again (title + difficulty + scene routing, ~150 lines). The shop is **GearShopPage**, the whole online lobby lifecycle (GDSyncSession create/teardown, quick/host/join, code LineEdit, handshake → MatchBootstrap → scene change) is **LobbyPage**; the menu knows only their `closed` signals. Behavior-identical: same layouts, same hover ids, same session /root parenting. PLAYTEST: shop buy/equip/unequip/BACK + hover; lobby open/BACK, host shows a code, short join code warns, quick-match status line; PLAY/STORY/difficulty routing.

## 2026-07-18 ROUND 7 — wider cleaning batch (4 independent refactors) + a REAL BUG FIX
- **CAVERN BUG FIXED:** reseed_walls (nightfall) rebuilt `blocked` WITHOUT _carve_cavern — the boss cage's ring and door VANISHED at the first nightfall (generate()'s comment even claimed "also re-run at night"; the old [CAVERN] banner existed because this was known-fragile). generate() + reseed now share ONE `_scatter_walls()` that always carves the cage; _nightfall also re-seals the door if the boss fight is live; generate() pre-clears gem/rest sets so a re-entry regenerate reproduces the seed's exact layout.
- **MobRoamer** (split step 3): wander cadence + step policy + AGGRO radius out of StoryController; controller applies effects.
- **ChoiceOverlay** base: PauseMenu + EndScreen shared hover/click/dim/button machinery deduped (StoryPauseMenu deliberately stays — it's a tabbed panel, not a button list).
- **_cardinal → Resolver.dir_from** delegation (the one aim-snap rule, no copy).
- PLAYTEST: pause menu (Esc, hover, all 3 buttons) + end screen (all 3 buttons) still behave; mobs wander/chase/idle as before; play to NIGHTFALL and check the cavern cage still stands (walk its ring, door open unless mid-boss-fight); re-enter story from a duel — map layout identical.

## 2026-07-18 ROUND 8 — UnitView slimming (UnitFrames extraction); span core stays BY DESIGN
- **UnitFrames** now owns the player animation table (PLAYER_ANIMS, ex-UnitView.ANIMS) + all four asset dirs + every frame builder (player/set/npc/gear-overlay/add_anim). UnitView only PLAYS what the tables declare; asset reorgs edit UnitFrames + SpriteBook, never view code. UnitView 745 → ~650 lines, public surface unchanged (no call-site edits anywhere).
- **DELIBERATELY NOT SPLIT: the serpent span/turn + 2-tile reach-clip machinery.** Its branches encode a graveyard of fixed visual bugs (stranded mid-tile sprites, compounding drift, double-draws — the comments document each). Splitting it into subclasses blind (no runtime here) risks re-introducing exactly those; it should only be attempted WITH the game running on the same screen. It is contained, documented, and correct — leave it until then.
- PLAYTEST: one duel (player anims: idle/move/attack/guard cube/buff/teleport + gear overlays on idle), one story fight (bat rotation aims, ooze mirror + spit, twin boss slither/turn/2-tile bites), an NPC village walk.

## 2026-07-21 ROUND 17 — THE WEB ERA (Fra-ratified: "web only as long as we can change it later"; hosting = PC now, itch.io later)
- **Strategy:** the website build is the GDSCRIPT game -- browsers can't run C#, and the
  mirrored-twin discipline is what makes this a flip, not a rewrite. AI.gd's verified
  fallback ("same brain, GDScript body, NEVER a different one") carries EXTREME; the
  round-13 WebSocket server is already browser-speakable. REVERSIBLE by design: native
  presets, C# brain, and DEPLOY_MOBILE.md all stay live in the repo.
- **run_server.bat now serves the website** (WebSocketServer.cs): non-Upgrade GETs are
  static files from Tools/GameServer/web (repo-root cwd, ./web, exe-relative fallbacks);
  MIME map incl. application/wasm; ../ traversal blocked; 404 page tells you to export;
  Cache-Control no-cache (F5 sees re-exports); COOP/COEP/CORP headers on EVERY response
  so even a threads-ON export boots. One port serves page + matches -> browser clients
  need no address at all.
- **SelfTest suite 0 (static hosting): 16/16 PASS in sandbox** -- probe file verbatim,
  well-formed '/', isolation headers present, RAW ../ blocked via hand-rolled socket
  (HttpClient squashes dot-segments client-side -- that's why the raw TcpClient).
- **ServerSession._platform_default():** on web, default URL = the page's own origin via
  JavaScriptBridge (ws:// from http, wss:// from https); user://server.cfg still
  overrides (the round-16 lobby box keeps working for pointing elsewhere).
- **ExtremeAI.set_profile WEB CLAMP:** OS.has_feature("web") -> budget_ms<=900,
  budget_end_ms<=1200 (duplicate()d dict -- PROFILES is const). Platform clamp, NOT a
  rules change: no C#/background thread on web means the GD brain runs on the MAIN
  thread; 3s/6s would freeze the page. BrainAgreement never runs with the web feature ->
  parity untouched. Native keeps 3000/6000.
- **Judge ships with builds now:** Eval._cfg_load + BrainBridge.LoadWithFallback (twins):
  user:// first (refits win), else res://Data/{value_fn,calibration}.cfg. Data/README.md
  tells Fra to copy his fitted cfgs there before exporting; include_filter="Data/*.cfg"
  added to ALL THREE presets (fresh desktop installs benefit too). NOTE: BrainBridge.cs
  is Godot-C# -- not sandbox-compilable; the edit is 8 surgical lines, Fra's next build
  is the compile check.
- **Web preset (preset.2):** threads OFF (no-SAB, hosts anywhere; our server could do ON
  too), extensions off, BOTH vram compressions (mobile browsers need etc2/astc),
  virtual keyboard ON (LineEdits on phones), export_path=Tools/GameServer/web/index.html
  (straight into the server's web root); exclude_filter strips Tools/*, Scripts/Port/
  CSharp/*, *.cs, *.csproj from the pack. .gitignore: web/* except .gitkeep (never
  commit ~40MB builds). Preset keys hand-written for 4.7 -- DEPLOY_WEB.md has Fra verify
  Thread Support OFF + Virtual Keyboard ON in the dialog on first export.
- **DEPLOY_WEB.md** (new): the second-editor story (STANDARD Godot 4.7.x exports web; the
  .NET editor can't -- keep both, same version), judge-copy step, export, play flow
  (PC http://IP:8765 on any device incl. iPhone Safari), itch.io packaging + the wss/
  Cloudflare-Tunnel caveat for online-from-itch (guide when ready), honest what's-
  different list (0.9s/1.2s EXTREME, per-browser saves, audio unlock tap, GD-Sync
  keyless boot watch item), and the going-back-to-native paragraph.
- **Open risks (watch):** GD-Sync autoload on web is HTTP/WS-based and boots keyless on
  desktop today, but a web-boot hang would point there first (quarantine = its own
  round); html/experimental_virtual_keyboard is experimental -- test typing room codes
  on a phone browser first session; two-editor version skew (always match 4.7.x exactly).

## 2026-07-21 ROUND 16 — MOBILE (Fra-ratified: Android + iPhone guidance, online from day one)
- **LobbyPage server-address box** (the one real feature): a LineEdit above the room-code
  row, prefilled from ServerSession.server_url(), normalized on entry (bare host ->
  ws://host:8765; full ws://-wss:// URLs pass through), persisted to user://server.cfg --
  the SAME file ServerSession already reads, so nothing else changed. Applies on Enter AND
  on any QUICK/HOST/JOIN click (typed-but-unsubmitted counts); when the address changes,
  the live session is rebuilt so the next intent talks to the NEW server. Why: phones
  can't hand-edit user:// files, and this is how a mobile build points at Fra's PC.
- **project.godot:** window/handheld/orientation=4 (sensor landscape);
  input_devices/pointing/emulate_mouse_from_touch=true (explicit -- taps are clicks; a
  Scripts-wide grep confirms NO hover-dependent UI, hover only drives button highlights).
- **export_presets.cfg:** Android preset added (preset.1) -- gradle build ON (REQUIRED for
  C#), internet permission ON, arm64-v8a only, immersive mode, com.chibuzu.uko, APK to
  Build/UKO.apk. Keys hand-written for 4.7: if any renamed, Godot ignores + defaults --
  DEPLOY_MOBILE.md tells Fra to verify the 3 critical toggles in the dialog.
- **DEPLOY_MOBILE.md** (new): Android one-time setup (JDK 17, Android Studio SDK, editor
  paths, templates), preset verification, phone USB debugging, one-click deploy vs APK
  sideload; online-from-phone networking (LAN IP + firewall allow; port-forward + public
  IP for cellular -- same step as inviting friends); iPhone reality (Mac+Xcode, EUR99/yr,
  C# iOS export still EXPERIMENTAL via NativeAOT/trimming) -> ratified sequencing: Android
  now, iPhone at launch.
- **Facts checked 2026-07-21:** .NET Android export solid (experimental label being
  dropped ~4.6/4.7); .NET iOS still experimental (bindings not trimming-safe); C# web
  export still unavailable.
- **NOT done (watch):** GD-Sync autoload still boots keyless on mobile (harmless warning
  at worst; retiring it = its own cleanup round, Fra to call). UI-scale pass if buttons
  feel small on a 6" screen. Play Store (AAB + release keystore + $25) at launch.

## 2026-07-21 ROUND 15 — RING DRAG + SMASH (Fra's stuck-in-the-zone bug -> a real rule)
- **Fra's field report:** rooted an enemy inside the closing ring; it "got stuck there." Two
  distinct diseases found: (1) the old crush rule teleported ring-caught fighters to the
  NEAREST OPEN tile (BFS wander -- could fling them sideways, feels arbitrary), and (2)
  rotation shoves moved the MODEL only -- no resolver event ever moved the VIEW, so the
  sprite stayed put ("stuck" was mostly a model/view desync).
- **The new rule (Fra spec, both engines):** a fighter caught in the closing zone takes a
  crush hit (20) and is DRAGGED ONE TILE straight toward the centre -- north edge drags
  south, west drags east, corners diagonal. If the landing tile holds an INTERIOR blocker,
  the impact SMASHES it: the wall is destroyed and the fighter takes a SECOND crush hit.
  If the landing tile holds the other fighter, they slide one more tile centreward (no
  extra hit; dead-centre pileup nudges south deterministically). Ring tiles themselves are
  never smashable/clearable -- the zone can't grow walkable holes.
- **The crushed_idx-per-hit contract:** Grid.rotate_blockers / SimWorld.RotateBlockers list
  a fighter in `crushed` ONCE PER HIT (catch + each smashed wall). Every caller's existing
  per-entry MAP_CRUSH_DAMAGE(=20) loop (GameController, ValueArena, OvernightSweep/Arena,
  SelfPlayArena, CollectCalibration, HarvestRunner, MatchRoom) therefore pays 20+20
  automatically -- ZERO caller edits.
- **Files:** Scripts/Core/Grid.gd (rotate_blockers rewritten; `_nearest_open` deleted),
  Tools/HarvestRunner/SimWorld.cs (exact mirror; NearestOpen deleted -- compiles into the
  runner AND the server, so training worlds + online matches share the rule),
  Scripts/Core/GameController.gd (_rotate_map now snaps BOTH sprites via set_state after
  any crush -- the actual "stuck" fix).
- **Verified:** GD parses; GameServer release build clean; property probe vs an
  independently written spec oracle -- 8 directional cases exact, smash=2 hits+wall gone,
  foe-landing slide, both-caught distinct landings; fuzz 3,000 generated worlds x 6
  rotations = 18,000 rotations, 5,631 catches, 593 smash hits, 0 oracle diffs, invariants
  (fighters end out of ring, never on walls/each other, ring never holed) all green.
- **Reminder:** runner + server exes rebuild automatically via their bats (they compile
  SimWorld.cs from source). Round-14 two-window test still pending Fra's ServerSession
  parser-error resolution (reload advice sent).

## 2026-07-21 ROUND 14 — THE ONLINE CLIENT (PvP through OUR server; Fra-ratified: own-PC hosting, no bot button)
- **ServerSession** (new, /root node): GDSyncSession's drop-in sibling -- same surface
  (match_ready/match_failed/turn_revealed/opponent_left + quick/host/join/submit_local)
  over a WebSocketPeer to OUR server. New in this era: `hosted(code)` (the SERVER
  assigns room codes), `stance_needed(turn)` + send_stance() (the online clash
  sub-round), and MatchConfig.map_rows (the server's authoritative layout; clients
  Grid.load_rows it -- rotations then derive identically everywhere). Server address:
  ws://127.0.0.1:8765 default; user://server.cfg [server] url=... overrides.
- **ServerTransport** (new): MatchTransport impl; NetworkOpponent unchanged (one new
  transport() getter). MatchTransport base gained the OPTIONAL clash surface
  (stance_needed signal + send_stance no-op) -- GDSyncTransport never fires it.
- **GameController:** loads map_rows when present; online clash hook = the SAME
  StanceOverlay as offline, answered to the server.
- **LobbyPage:** backend swapped to ServerSession (GDSync files untouched as the
  fallback era -- flipping back is re-instancing them in _make_session). HOST now
  shows the server's code when `hosted` arrives. NO vs-AI button online (Fra:
  offline Play already owns difficulty selection; server keeps quick_bot capability
  unused).
- **run_second_instance.bat** (new): second game window for the localhost duel.
- **FRA'S TWO-WINDOW TEST:** run_server.bat (keep open) -> editor Play (window 1) ->
  run_second_instance.bat (window 2) -> both: PLAY ONLINE; window 1 HOST PRIVATE
  (code appears), window 2 JOIN PRIVATE with the code -> duel yourself. Also try
  QUICK on both, a head-on collision (clash overlay online!), and closing one window
  mid-match (other gets the forfeit). Then push everything.
- **INTERNET PLAY (later, when inviting friends):** own-PC hosting needs a router
  port-forward for TCP 8765 + sharing the public IP in friends' user://server.cfg --
  guided when Fra wants it. VPS deploy (DEPLOY_SERVER.md) at launch, Fra-ratified.

## 2026-07-21 ROUND 13 — THE AUTHORITATIVE GAME SERVER (Fra-ratified: custom server, AI in background)
- **Tools/GameServer** (new): the online mode's real home. The same engine sources the
  game ships, hosted behind a hand-rolled RFC-6455 WebSocket layer (TcpListener; no
  packages, no Godot, cross-platform by construction). The server IS the MatchMediator
  made trustworthy: it holds each committed plan until BOTH are in (no client can peek
  -- an airtight upgrade over p2p), detects contested-tile clashes with a pure dry run
  and holds the ONLINE stance sub-round (closing round 11's online gap), resolves every
  turn as the arbiter of record, enforces turn deadlines (auto-wait), awards forfeits on
  disconnect, and appends every completed match to a training csv -- the learn-from-
  humans stream, in the exact v3 format (shared writer: **Tools/Shared/TrainingCsv.cs**).
- **Protocol** (JSON over WS): hello/host/join{code}/quick/quick_bot/plan/stance/leave;
  server: welcome/hosted{code}/queued/matched{seat,rows,gear}/clash/reveal{seq_a,seq_b}/
  over{result}/foe_left/err. Map = server-generated (SimWorld) LAYOUT ROWS shipped in
  matched{} -- round 14's client loads rows instead of seeding (the server can't replay
  Godot's PRNG, and this is cleaner authority anyway). Rotations derive deterministically.
- **Bot seats:** quick_bot duels the EXTREME brain server-side (judge-armed via
  --value-cfg). ALL brain work serializes through one semaphore (the brain's statics are
  single-threaded by design) -- fine for a handful of concurrent bot duels; humans scale.
- **SELF-TESTED, 12/12 PASS** (real ClientWebSocket clients over localhost): bot match
  completes unbeaten; scripted head-on collision fires the clash sub-round and the
  reveal carries stamped stances; leaver forfeits; 3 concurrent bot matches complete;
  training log well-formed with real damage.
- **DISCOVERY -- THE STATUE-STALL FIXTURE (brain gate candidate):** a bot vs a
  full-resource do-nothing statue chips it to ~80 hp then DANCES for 40+ turns once its
  own mp runs dry (the untouched full-mp arsenal reads as danger forever). Reproducible
  offline (probe BotProbe). This is Fra's passivity complaint in lab form -- a prime
  target for gen-2/depth-4, and a candidate 7th position gate.
- **run_server.bat** ("test" arg = selftest) + **DEPLOY_SERVER.md** (local/LAN/VPS).
- **ROUND 14 QUEUED -- the client:** WebSocketTransport (MatchTransport impl) +
  ServerSession beside GDSyncSession, Grid rows-loading, LobbyPage backend, GameController
  online-clash hook (StanceOverlay on {t:"clash"}). Then Fra's two-windows-localhost test.

## 2026-07-20 ROUND 12 — THE THROUGHPUT ENGINE (from-scratch plan, step 1; Fra-ratified)
Fra asked "how would you build it from scratch" -- answer: same search + same flywheel,
but 100x the games and learned move priors. This round ships the first half.
- **Tools/HarvestRunner** (new): the game's C# engine + EXTREME brain compiled into a
  plain console exe -- the SAME source files the game ships (a rules change in the repo
  is automatically a rules change here), no Godot. Parallel at the PROCESS level (the
  brain's statics are single-threaded by design): parent spawns N workers with disjoint
  seed ranges, each writes a shard, parent merges serially -- kill it any time, finished
  waves are already in the csv. **SimWorld.cs** mirrors Grid.gd's generation/rotation/
  shrink/crush rules with its own PRNG (same distribution, fresh layouts every night --
  deliberately NOT Godot's exact seeds; more coverage). **ValueCfg.cs** parses
  value_fn.cfg without Godot (v1 + v3-with-crosses) so nights play JUDGE-ARMED. CSV
  rows come from Eval.ValueFeatures -- the exact inference vector; harvest/fit/
  inference cannot drift. Seed base 900001 (Godot harnesses use 770001+; no collisions).
- **Measured in the sandbox** (2 weak cores, budget 0, depth 3): ~7 matches/min; rows
  byte-compatible with the fitter (32 columns); draw-rate under the round-11 rules came
  back ~17-33% (vs 58% at the old rules -- the passivity levers are biting). On a real
  desktop expect **~12-15k matches/night vs 450 -- ~30x**.
- **run_fast_harvest.bat** (new): builds the runner, harvests **16 HOURS (Fra's ask)**
  straight into user://selfplay_v3.csv, Ctrl+C-safe. Then run_fit_value.bat ->
  run_value_arena.bat exactly as usual. Flags: --minutes --matches --workers --budget --depth.
- **UKO.csproj** now excludes Tools/**/*.cs from the game assembly (standalone exes must
  not be swept into Godot's build). If Godot's build ever complains, report it.
- **DELIVERY NOTE (2026-07-20): the catch-up zip.** Fra's first runner build failed with
  "Eval has no VCROSS" -- his machine was missing round 10's Eval.cs (some zips between
  rounds 10-12 were extracted partially), and rounds 10-11 were never gate-verified on
  his machine. The catch-up zip = EVERY file changed since round 9d (rounds 10 + 11 +
  12 + all bats), one extraction to fully current. After it: Godot Build, verify_all,
  position tests (six green), THEN the 16h harvest.
- **STEP 2 QUEUED (round 13): the learned POLICY head** -- move priors trained from the
  equilibrium mixes in these harvests, replacing the hand candidate ranker (the component
  behind the 9b/11 artifact patches). Needs this round's data volume first.

## 2026-07-20 ROUND 11 — THE RULES ROUND (Fra's bug list + the passivity levers)
- **CRUSH WAS INVISIBLE, NOT MISSING (Fra: "no damage when the blocker lands"):** the
  rotation crush ALWAYS applied hp (proven by a 65,819-case offline property test of the
  rotation/telegraph math -- zero misses) but _rotate_map never refreshed the HUD, so the
  bar only moved after the NEXT resolve. The HUDs now repaint the moment a crush lands.
- **CLASH RPS IS NOW A REAL DECISION (offline).** The resolver's push/pull/feint triangle
  existed but nothing ever set the stance rider -- every collision was push-vs-push =
  a mute bounce. New flow, resolver kept pure: Resolver.clash_pending() (GD-only helper)
  dry-runs the committed plans; on a clash the board dims and **StanceOverlay** (new,
  ChoiceOverlay subclass) takes the player's stance while **ClashOracle** (new) answers
  for the AI -- a 3x3 matrix of the ACTUAL turn outcomes per stance pair, solved with
  NashSolver and sampled (unexploitable over repeated clashes). Stances are stamped on
  the declared moves, then the ONE real resolve runs. ONLINE still plays pre-declared
  push (the stance-exchange message is queued; needs a GD-Sync round-trip).
- **DRAINED DRY (new rule, both resolvers):** grenade tick_per_tile 180 -> 40, so the
  range-1 impact (340) beats a basic swing (350); range 2+ still loses the race. A
  disrupt that EMPTIES the tank breaks the victim's queued basic ATTACK this turn -- no
  refund, new ATTACK_DRAINED event (registry both languages; CombatLog narrates "attack
  breaks -- drained dry"). Phase-2 dispatch now honors the _resolved flag (it never had
  to before -- nothing could cancel violence entries; caught offline when the first
  probe showed the receipt firing while the swing still landed).
- **PIVOT COSTS 5 (both Configs):** free pivots subsidized wait->pivot stalling. This is
  a GAME RULE: every tier and every story creature pays it. Candidate gen now gates
  pivots on affordability (both languages). PLAYTEST WATCH: if a story mob stops turning
  to face (energy-starved kinds), report it -- an exemption for story kinds is trivial.
- **HARVEST ERA v3:** rules moved -> user://selfplay_v3.csv (sweep + fit). v2 rows
  describe a game that no longer exists. The LIVE gen-1 judge stays (slightly stale is
  still better than the hand eval it beat 64.6%) until a v3-trained challenger dethrones
  it -- run the flywheel night AFTER this round is verified in.
- Offline verification: cscheck compiles clean; rule probes green (drain-cancel fires
  r1, absent r2; pivot 4en illegal / 5en works); all six gates green on the C# twin.
  Parity: both resolvers changed in lockstep (same new event type/tick/owner).
- **FRA'S CHECKLIST:** extract -> Build -> verify_all.bat -> run_position_tests.bat (six
  green) -> playtest: (1) step onto a telegraphed tile, watch hp drop THE MOMENT walls
  shift; (2) walk head-on into the AI over an empty tile -> CLASH overlay appears, pick
  each stance across tries, check the log receipts; (3) pivot now shows -5 energy;
  (4) story fight sanity (mobs still turn); (5) one CHALLENGING duel. Then push, then
  the flywheel night (fresh v3 harvest -> fit -> arena) + the sweep night when convenient.

## 2026-07-19 ROUND 10 — "STILL NOT STRONG ENOUGH": think time, flywheel, smarter judge (Fra-ratified 3s+, fronts 1-3)
- **THINK TIME 3s/6s (both languages, PROFILES):** EXTREME now spends 3000ms/turn (6000 in
  the squeezed endgame). At 700ms half the root matrix stayed shallow; at 3s it deepens to
  full coverage. Rollback = two numbers in the profile line.
- **BACKGROUND THINKING (BrainBridge StartChoose/ChooseDone/TakeChosen + AIOpponent poll):**
  a 3-6s synchronous search would freeze the window ("not responding"). The C# search now
  runs on a worker thread; marshaling stays on the calling thread (Godot objects never
  cross); GD polls per frame. ONE search at a time by construction (the turn loop is
  serial). Exceptions fall back to wait with a warning. Non-EXTREME tiers stay synchronous.
- **MEASURED (C# twin, budget-0 deterministic): the judge leaf runs the SAME search at ~70%
  of the hand eval's cost** -- the 3s budget buys ~1.4x more search on top of the raise.
  22 crossed features add ~0% (the leaf is resolver-dominated; the dot product is noise).
- **FIT v3 (FitValue.gd): CROSSED FEATURES + honest validation.** 22 hand-chosen feature
  products (resources x distance, hp fronts, lockout x proximity, curvature squares) appended
  after the 28 base columns; the PAIR LIST travels inside the cfg, so inference (Eval.gd
  learned_p / Eval.cs LearnedP, both crosses-aware now; v1 cfgs still load as K=0) replays
  whatever the fitter chose -- change the list in FitValue only. 80/20 train/val split BY
  MATCH SEED (row-level splits leak outcomes between correlated rows); the reported number
  is VALIDATION accuracy. Output is now **user://value_fn_new.cfg -- THE CHALLENGER.**
- **VALUE ARENA v2: champion vs challenger.** With value_fn_new.cfg + value_fn.cfg both
  present the arena plays NEW vs LIVE (bridge LoadValueSlot/UseValueSlot -- weight-set swap
  per decision, no disk IO); only value_fn.cfg -> the old ON-vs-OFF bootstrap. Budget PINNED
  at 700ms (the live 3s profile would make 450 matches a multi-day run; A/Bs stay comparable
  at the established condition). PROMOTE >=55% -> gates with USE_VALUE -> run_promote_value.bat
  (NEW: copies new -> live with a value_fn_prev.cfg rollback backup; never automatic).
- **NIGHTS PLAY WITH THE JUDGE (OvernightSweep):** harvest + sweep arm value_fn.cfg when
  present (UKO_VALUE=off for a hand-eval baseline). Generation-2 data comes from
  generation-1 play; sweep conclusions describe the brain that ships.
- **SWEEP RE-AIMED (old answers stale -- the eval bottleneck is gone, budget is 3s):**
  PHASE 1 d3@3000 vs d3@700 (what the raise bought), PHASE 2 d4@3000 vs d3@3000 (is depth 4
  the right spend -- if >=55%, flip AI.gd SetDepth(3) to 4), PHASE 3 d4@6000 vs d3@3000.
  60 matches/phase (3s matches are slow; partials count).
- **FRA'S ROUND-10 PROTOCOL:** extract -> Build -> verify_all.bat -> run_position_tests.bat
  (six green; now 5-12 min -- the gates think at live budget) -> ONE EXTREME duel (feel the
  3s pace; window must stay responsive) + one CHALLENGING duel (unchanged) -> push. Then the
  nights, in any order across the week: (1) run_harvest.bat -> run_fit_value.bat ->
  run_value_arena.bat -> if PROMOTE: USE_VALUE gates -> run_promote_value.bat -> push the
  cfg story in HANDOFF; (2) run_sweep.bat -> paste phase results (decides depth 4).
- QUEUED (ratified for later): learn-from-Fra (live-match logging into the harvest CSV +
  opponent-model deepening); judge recalibration night (CAL_A was fitted on the old score
  scale); tiny-MLP judge if crosses plateau.

## 2026-07-19 ROUND 9d — THE JUDGE GOES LIVE (adoption complete)
Full protocol passed: arena FINAL 124-68 (64.6%, +12.4 avg margin, 450 matches) →
six gates green value-OFF → six gates green value-ON (critical-survival 81%). Live
wiring, all in AI.gd (the dispatcher — no harness routes through it, each keeps its
own explicit dial): the C# bridge arms once at setup (SetValueEnabled(LoadValueFn())
— missing/invalid cfg = no-op, hand eval as before; **user://value_fn.cfg IS the
switch**: delete to roll back, run_fit_value.bat to update); the GD extreme fallback
arms via a one-time-loaded cache; and choose_sequence() re-asserts Eval.VALUE_ON =
false per decision so the judge can NEVER leak into CHALLENGING/HARD (tier hygiene —
VALUE_ON is a global static). BrainAgreement stays value-off both languages by design.
**GENERATION 2 (queued, needs Fra):** harvest is still played value-off; next harvest
night should play WITH the judge (more decisive games → sharper labels), then refit →
arena ON-vs-current → adopt if it wins again. That loop is now the standing
improvement engine. PLAYTEST: one EXTREME duel (feel + latency — the judge is a
cheaper leaf than the hand eval, so turns should not get slower), one CHALLENGING
duel (must feel exactly as approved).

## 2026-07-19 ROUND 9c — ADOPTION GATE (arena came back ADOPT)
Fra's 450-match arena (on the 9b brain, both seats): ADOPT locked mathematically at
420/450 — the learned judge won 114-63 decisive (64%), avg margin +12 hp, stable from
match 150 on. Protocol before it goes LIVE: PositionTests gained **USE_VALUE** (flip
true → loads user://value_fn.cfg and arms Eval.VALUE_ON for the whole suite) — the
judge must keep ALL SIX gates green, then the live flip ships (BrainBridge LoadValueFn
+ SetValueEnabled(true) for the EXTREME profile only; CHALLENGING keeps the frozen
hand-eval feel). Draw rate is still the story (243/420 = 58%) — generation 2's
harvest, played WITH the judge, should be more decisive and train a sharper one.

## 2026-07-18 ROUND 9b — GATE TRUTH + HP CONVEXITY (from Fra's first round-9 night results)
Fra's paste: fit fine (21,284 rows, 60.1% train acc, hp +/-0.808 dominant — sane first
generation; note 35,974 draw rows skipped = the stall meta starving the fitter), but
critical-rest still 0% and press-starving 38%. Diagnosed OFFLINE against the C# twin
(exact ChooseMix probabilities, no sampling noise). Three findings, three fixes:
- **BOTH red gates had ARMED "harmless" foes (premise bugs #2 and #3).** Gate 5's
  "locked-out" foe held default FULL MP = two DARK BOLTS (bolt costs 0 energy); the
  brain's hedge was correct play. With foe.mp=0 it presses 100% — its favourite line
  is blink-in -> aoe_burst, which the old predicate (attack/bolt/move only) scored as
  passivity! Predicate now counts burst + blink-close as pressing. Gate 4's foe still
  held the once-per-match GRENADE (costs NO energy, NO mp — drains 20 + roots + cancels
  rest). Premise now spends it: 0 energy + 0 mp + grenade gone = actually harmless.
- **THE BRAIN'S REAL DISEASE (both languages, Eval): hp priced LINEARLY.** A 10-pt heal
  at 15 hp doubles the swings needed to kill you; 10 damage on a 100-hp foe changes
  ~nothing — but dealt/taken and the cheap subgame rank treated them as equal, so aggro
  always outbid survival at death's door. Fixes: (1) **W_DOORSTEP** (new tunable, 2.0):
  leaf term, symmetric — each hp point inside one-turn-kill range (2×ATTACK_DAMAGE) is
  priced; every line at every depth now feels one-shot exposure. (2) **_cheap_rank/
  CheapRank rewritten in win-relevant units**: counts the damage a sequence itself
  COMMITS (spending ranked low before — capped subgames modeled the foe as politely
  walking away instead of swinging the kill), caps damage at remaining hp, lethal
  reach = +/- one full bar. (3) **_capped_cands keeps [rest] in the self-model** when
  offered — a reply set that can only stand-and-trade reads survivable spots as death.
- **GATE 4 RESPEC'D: critical-rest -> critical-SURVIVAL.** With the foe truly inert the
  brain found a line STRICTLY better than resting in place (rest-in-place eats next
  turn's wait->swing, taking the heal right back): chip + step where 20 energy can't
  reach, THEN rest safely. Demanding the literal "rest" id punished better play, so the
  gate now asserts the SPIRIT: after the chosen turn, alive and OUT of the foe's
  next-turn one-shot range (worst incoming < hp). The old stand-and-bang death line
  FAILS this check; any true survival play passes.
- Offline C#-twin gate probabilities after the fixes (expect ~this on the machine, mod
  21-sample noise): flee 100 / grenade 0 / safe-rest 100 / critical-survival 100 /
  press-starving ~100 / no-lead-wait 100. Agreement harness: GD+CS changed in lockstep,
  stays green. Resolver untouched — parity goldens byte-identical.
- **ARENA NOTE:** the round-9 arena verdict must be measured ON this brain — if one ran
  on round-9 code, re-run run_value_arena.bat after 9b for the adoption decision (the
  fit itself, value_fn.cfg, stays valid: it learned states->outcomes, not the brain).
- **FRA'S NIGHT CHECKLIST (9b):** verify_all.bat (green) -> run_position_tests.bat
  (expect SIX green) -> run_value_arena.bat overnight -> paste both.

## 2026-07-18 ROUND 9 — THE AI ROUND (first behavior changes; Fra-ratified "go")
- **ThreatModel wait-aware swing (both languages):** an ADJACENT foe at 10-19 energy was read as harmless, but wait(+10)->swing is real -- the model now budgets energy+WAIT_ENERGY for the swing-only case (2-slot step+swing and blink+swing unchanged: no free slot). Also future-proofed spell energy_cost checks both sides.
- **GATE 4 PREMISE FIXED:** post-kit-fix the "harmless" foe held full MP -> could BURST an adjacent rester (mp-powered, needs no energy) -- the brain was RIGHT not to rest. The gate now zeroes foe.mp too. Expect critical-rest to go green on merit.
- **TERMINAL ANTI-TELL (gate #8, both live losses):** at starved endstates (energy < COST_GUARD) the SAMPLED mix caps its top line at 0.70 and re-spreads the excess -- "low energy -> it will guard" stops being a read. Play-time only: ChooseMix + the agreement harness are deliberately OUTSIDE it (agreement stays green untouched).
- **LEARNED VALUE PIPELINE (built, ships OFF):** the sweep's verdict was "the judge is the bottleneck" -- the leaf judge (_eval_situation) now sits behind ONE dispatch (_leaf/Leaf, both languages) that can swap in a logistic p(win) fitted on selfplay_v2.csv. Flow: run_fit_value.bat (fits + reports + writes user://value_fn.cfg) -> run_value_arena.bat (value-ON vs value-OFF, 150 matches d3@700, ADOPT >=55% / KEEP <50%) -> position gates -> only then flip it on live (BrainBridge.SetValueEnabled). Features = EXACTLY the v2 CSV columns; fit/harvest/inference must change together. Next generations: play with the new judge -> harvest -> refit -> arena again.
- **FRA'S NIGHT CHECKLIST:** verify_all.bat (green; goldens unchanged -- engine untouched) -> run_position_tests.bat (expect critical-rest GREEN now; note all six rates) -> run_fit_value.bat -> run_value_arena.bat overnight -> paste both results.

## 2026-07-18 ROUND 3 — de-hardcoding pass, zero behavior change
- **ui_slot**: SpellBook defs gained an explicit `ui_slot`; ActionMenu reads it (never `ai_role`) — retuning the AI can no longer rewire the player's buttons. Same values today.
- **flip_when**: per-creature sprite-mirroring is DATA in SpriteBook sets; UnitView names no creature (old ooze/bat branch encoded verbatim: bat [], ooze [west,north], default [west]).
- **Engine knowledge home**: `Grid.closed_rings()` (BoardView asks, no longer re-derives the zone rings); `Resolver.dir_from()` public door (StoryCombat's "change both" blink copy now delegates); StoryController's five Chebyshev re-derivations → `Grid.cheb`.
- **ViewConfig**: SHAKE_BLOCKED/SHAKE_AOE/BURST_COUNT_CAST/BURST_COUNT_SOFT/LABEL_STACK_OFFSET named; `DIR_TECH_SPELLS` is the one home for the Tech Spells folder (UnitView + FX read it); `facing_label()` replaces the two hand-rolled N/E/S/W tables. `.gitignore` now catches `verify_*.txt` (two slipped into round 2's commit — this round's apply deletes them so the commit untracks them).
- **ROUND 4 QUEUED (needs its own playtest): legacy mob combat path deletion** — every live kind returns `uses_true_actions()==true`, so MobKind's budget-strike machinery (`_strike_ticks`, chase/kite `_walk/_step`, `attack_damage` path) + StoryCombat's budget branch + the 6 `has_method` guards never run in live play. BUT `attack_pattern`/`cardinal_ring` have live consumers in the Character kinds — the cut needs the branch map read carefully, not a mechanical sweep. Also still queued: afford-aware ThreatModel (Fra to ratify), minigame base class, mob naming, MP turn deadline, StoryController splits 2+ (after the CameraRig playtest), MainMenu/UnitView splits.

## Engine
- **Godot 4.7 .NET (mono)** — the ONLY engine now (editing, playing, bats, and the upcoming C# port). Project converted and green; all four bats repointed to the 4.7 mono *console* exe. GD-Sync's headless "No active debugger / get_path on null" spam is harmless addon noise in every tool run.

## Duel arena
- Grid.SIZE = 8. Spawns (1,4)/(6,4) → contact turn 2–3.
- Rotation + zone COUPLED every 10 turns (Config.MAP_ROTATE_EVERY): ring closes t10 (8→6) and t20 (6→4 floor). Zone = anti-stall backstop by design.
- Blockers 8.5–11% of tiles (~6–7 walls), connectivity-guaranteed, random per match. (Mirrored-map generation = future toggle.)

## Rules that bite
- REST restores HP+MP only; damage cancels an in-progress rest and locks next turn's. Energy comes ONLY from the per-player pulse: +30 per 6 of your own non-wait actions.
- Flank multipliers use the DEFENDER's facing (side ×1.5, back ×2). Attacker facing is irrelevant.
- **Grenade**: once/match; impact 480/660/840 ticks at 1/2/3 tiles (first-action move ≈520 → escapes at 2+, loses point-blank). On hit: root (next action can't MOVE **or PIVOT** — either fizzles and consumes it; other actions consume it freely) + **20 energy drain, applied in exactly one place: `Resolver._apply_disrupt`**. Diagonal throws fly diagonally (throw-shape path).
- **Attacks are aimed DIRECTIONS, not map tiles**: `dir` stored at queue time (player selection + AI candidates), struck tile computed from the attacker's ACTUAL position at strike time; absolute tile remains fallback.
- AI never takes a lone action (trailing WAIT pad; lone REST is the rule-based exception). Rest enters candidates only at 25+ combined HP/MP deficit. Re-casting an already-active self-buff is skipped.

## View layer
- GEOMETRY RULE: duel reads ViewConfig.**BOARD_\*** (8 tiles @ 1.5 = 48px, origin 384,132, frame 382,130,388,388); story reads **VIEW_\*** (12-tile window @ 1.375, origin 312,60, frame 310,58,532,532). NEVER mix.
- Story canvas is wrapped in a clip Control — every board child (NPCs, houses, mobs, FX) cuts at the frame edge. UIFrame takes a `rect` (story passes VIEW_FRAME).
- NPC solidity: WorldGrip.occupied (filled at spawn, resynced in _cull_npc_views, released while asleep); is_blocked checks it → player AND mobs collide.
- UnitView.ANIMS is the single animation source: per-row {dir, prefix, count, fps, loop, offset, **points**}. "points" = which way the art was DRAWN; play_anim computes rotation — callers carry no art knowledge. Missing rows/frames no-op. **After any asset folder reorg: fix the `dir` fields here** (move → BASE_DIR "Move" ×5, points "down"; TECH_DIR → Tech Spells/).

## AI (Scripts/AI)
- One matrix-Nash brain (ExtremeAI): shallow M from real Resolver sims → budgeted selective deepening → iterated dominance → **win-probability transform of all cells when Eval.CAL_A > 0** (depth-3 rescores wrapped the same) → Nash (regret matching) → selective depth-3 re-solve → bounded exploitation (λ × model confidence, situation buckets) → support pruning (MIN_MIX 0.05) → sample.
- **Seat-correct forward model** (me.id branches resolve args/unpacking/win-check). The old me-as-B hardcode structurally biased self-play (10/10 seat-decided) — fixed; live play was always seat-B and unaffected.
- PROFILES: "mob" {90ms, 2/4} · "challenging" {250ms, 3/6→5/9, λ0} · "extreme" {700/**1400 endgame** ms, 4/8→6/10, λ0.6 + persistent OpponentModel (user://uko_opp_model.cfg)}. set_profile also sets weights and loads calibration.
- **Weights: Eval.DEFAULTS for ALL tiers. The evolved champion is SHELVED** after live regressions (passive waits, bolt+pivot ordering, rest-into-bolt); CHAMPION_WEIGHTS const remains in ExtremeAI as evolution's base. Re-adoption requires the full 6-gate suite.
- Eval: tunable static weights + TUNABLE list + DEFAULTS snapshot; zone terms; per-player pulse relief; grenade option value (W_ITEM); desperation fear multiplier (still present; calibration supersedes it in spirit); per-decision subgame cache; **CAL_A + to_winprob** (sigmoid; from user://calibration.cfg — delete the cfg to disable). W_LETHAL exists (user-added, tuned along).
- Story mobs think with the real brain ("mob" profile) via StoryController's engaged loop; kind.plan is fallback. **Ooze split lives in kind hooks — verify split still fires.**

## Tooling (Scripts/AI/Tuning + Scripts/Port; bats in project root)
- **PositionTests.gd** — 6 gates, SAMPLES 21, frequency assertions. Current: flee 100 · hold-grenade 0 · safe-rest 100 · critical-rest 100 · **press-starving FAIL 38% (want ≥60) — deliberately red: the port's first target** · no-lead-wait 100. USE_TUNED flag runs the suite on user://tuned_eval.cfg. Gates pin FULL situations (never maxims). Pending #7–9: grenade-must-convert, no-wait-after-root, flank-from-diagonal (need multi-turn scaffolding).
- **Tuner.gd** — 150 iters, seeds [11,23,37,51,68,84,97], step 0.12, accept 0.55, **resumes from user://tuned_eval.cfg**, HP-margin scoring, runs under the challenging profile. Accepts save the moment they happen (mid-run shutdowns lose nothing).
- **ValidateChampion.gd** (+ run_validate.bat) — champion vs defaults on FRESH seeds [101…505], both seats; ≥55% adopt / <50% keep. History: pre-seat-fix 45% (exposed the bias) → post-fix 63% ADOPT → live regressions → shelved.
- **CollectCalibration.gd** (+ run_calibration.bat) — 40 matches; appends (score,turn,total,a_won) to **user://selfplay_data.csv** (the experience log the future learned value trains on); late-weighted logistic fit. Current A = 0.017832. ~16–19/40 matches hit the 50-turn cap = **stall-meta datum** (equilibrium bots circle at cadence-10; design lever noted, no change).
- **Scripts/Port/ParityDump.gd — port stage ZERO, WRITTEN (was an empty stub) + run_parity.bat added; not yet RUN by Fra**: `extends SceneTree`, emits **673** deterministic (state, plans → outcome) cases → user://parity_gd.txt. Line fmt `idx|grid|Ain|Bin|PA|PB|turn=>result|Aout|Bout|events`. Coverage: 18×18 adjacent cross + 18×18 spaced(dist3) cross + 25 targeted fixtures (flank tiers, guard front/side/back, swap, wall-fizzle, bolt travel/dodge/wall-stop, diagonal grenade root+drain, rooted-carryover, blink settle+fizzle, rest regen/interrupt/locked, energy pulse crossing, no_guard_combo void, in-seq cooldown, spent grenade, lethal, double-KO draw, speed-boost front-of-band, discount cost cut, energy starvation noop). **Three deliberate deviations from the HANDOFF's original spec (flagged to Fra):** (a) NO RNG — arenas hand-built from ASCII templates, not Grid.generate(rng), so the port reproduces only Resolver+Config math; (b) full GEAR ids equipped (`discount_charm/burst_node/blink_boots/dark_focus`), NOT SelfPlayArena.kit() — the tuner kit's entries are spell/status ids not GearBook ids, so spell_ids() returns only "grenade" under it (**latent kit bug flagged this session — see watch item**); (c) fingerprint mirrors Eval._c_key's FIELDS but canonicalizes the 3 dicts as sorted `k=v` (not Godot's str(dict)) for cross-language byte-parity. Next: run the bat, eyeball parity_gd.txt, commit it as the golden file, then start Config.cs.
- All bats: `cd /d "%~dp0"` + hardcoded GODOT console path (**must point at the 4.7 mono console exe**), output redirected to <name>_log.txt then typed.

## Protocol
- Any AI/board change: 6 gates green (press-starving exempt until the port) + think-time sane + play-feel. Misplays: harvest the exact position with replay arrows (HUD shows per-turn resources) → new gate. Gates are exams the brain never reads — understanding must EMERGE (search = imagination, value = judgment); no behavior rules in the brain.
- user:// files are local state: uko_opp_model.cfg (what it knows about you), tuned_eval.cfg (evolution champion), calibration.cfg (P(win) curve — delete to disable), selfplay_data.csv (experience log).

## SWEEP RESULTS (330 matches, 2026-07-11) — THE EVAL IS THE BOTTLENECK NOW
d3@700 vs d2@700 (EQUAL time): **53.9%, +2.6 margin** — consistent with night 1 (53.8%, +5.1): depth 3 is a small, reproducible, FREE win → **PROMOTED: live EXTREME now SetDepth(3)@700ms in AI.gd**. d3@1400 vs d2@700: **50.0%, −2.7** — doubling the budget bought NOTHING. d4@2000: 52.8%, +8.1 — mild, not worth 2s latency. Draws 31–35% and rising with depth (stall meta confirmed: deeper = more cautious, not more lethal). CONCLUSION: search depth/time has hit the ceiling of the hand-tuned leaf eval → **the learned value function is THE lever** (Fra's stated go-to). Training data harvested: user://selfplay_cs.csv (~35–40k rows: seed,turn,seat,hp,mp,energy,foe triple,dist,shrink,action_counts,nade flags,outcome ±1/0). NEXT SESSION: fit logistic value on the CSV → load via bridge (BrainBridge gains SetValueWeights or reads a cfg) → champion-vs-challenger arena + gates before promotion. PRESERVE THE CSV.

## FRA'S MATCH AUTOPSY vs d3 EXTREME (2026-07-11) — GATE CANDIDATES, all from live play
Fra WON again by the same key: terminal-low-energy guard is still predictable (he rested→attacked into the known guard — gate #8's exact failure, 2nd live occurrence). Misplays observed, each a frozen-position gate candidate: (1) **zone-denial burst missed**: pillar spot, shrink incoming forced Fra's double-move; AI rested instead of wait+burst — VERIFIED by band math: wait(600)+burst(440)=1040 == move(520)x2=1040, and BAND_PRIORITY AOE(4) < MOVE(5) → burst resolves FIRST at the tie, catching the mid-move tile (around ignores walls). A true winning line the eval didn't price (incoming-walls + forced-move prediction). (2) **flank-step on a resting foe**: stepped Left+Up instead of Up (which flanks a south-facing rester and beats both pivot+attack and wait+attack lines). (3) **post-grenade lockout not pressed**: grenade drain locked Fra out (GOOD — and genuine: the forward model + W_LOCK/W_ATTRITION price drain lines authentically, NOT scripted), but then attack+step-back instead of double-attack; next turn 1 attack+wait on an adjacent 0-EP foe — press-starving live examples #2 and #3. (4) **resource-lead guard** when Fra's only legal play was double-move (should attack ≥1). (5) **behind-in-resources at distance → waited repeatedly instead of RESTING** (rest-denial understanding is one-sided). (6) cornered guard+attack: Fra half-endorses as a legit tempo combo (eat 15 → double-move → rest +15mp +3 pulse actions) — gate should test it's MIXED/priced, not banned. NEW TOOLING: match dump — every finished duel writes user://last_match.txt (turn | positions/facings | resources | BOTH seqs | damage both ways); Fra pastes it for turn-by-turn analysis → misplays become gates. Replay now AUTO-PLAYS each turn on navigation (no Play press).

## TICK REWORK + CONTESTED-TILE RPS (Fra design session 2026-07-11 — SPEC, not built; engine change → both Resolvers + NEW parity oracle when done)
(1) TRUE SIMULTANEITY at equal ticks (replace band-priority tie order): same-tick events resolve together — burst catches a same-tick mover; mutual lethal = double-KO draw (Claude-proposed, Fra to ratify). (2) SECOND-ACTION TICK TAX: firing two DIFFERENT actions in one turn adds a tick tax to slot 2 (proposal +80; move+move / attack+attack exempt — "same" = same id, Fra to ratify vs same-band). Prices versatility, rewards commitment. (3) DIRECTIONAL MOVE TICKS: forward 520 / side ~570 / back ~620 (proposal) so only forward-vs-forward can collide. (4) CONTESTED-TILE RPS (both enter same tile, same tick, both forward): Claude's proposals — A. SHOULDER READ (recommended): clash resolved by each fighter's OTHER slot: Attack-follow=Aggressive > Move/Wait-follow=Slippery > Guard-follow=Braced > Aggressive; winner takes tile, loser bounces −10 EP; identical follows → both bounce. Mind-game lives in already-chosen sequencing, no new inputs, Nash-mixable. B. Flank Clash (side/back-arc entry wins; front-front bounce). C. Energy Bid (higher remaining EP shoves through). D. Initiative Carry (recent guard wins shoves — extends guard-as-tempo). DECISION CHECKLIST for Fra: tax size; same-id vs same-band; side/back tick numbers; RPS pick; projectile-vs-move at same tick (currently dodge wins by design — simultaneity flips it); mutual-KO rule.

## RATIFIED + BUILT (2026-07-11 pm)
**Fra ratified:** tick tax +80 (same-id exempt), side/back ticks 570/620, TRUE simultaneity incl. blink landings (land on a burst tile at the same tick = hit), double-KO draw. **PUSH/PULL/FEINT counter-proposal (Fra) — Claude's triangle proposal awaiting ratification:** Push beats Pull (shove breaks the grab), Pull beats Feint (grab catches the half-step), Feint beats Push (charge whiffs → attacker loses 1 action next turn via a new 'staggered' status); same-pick = both bounce −10 EP; effects per Fra: Push = tile + small dmg (~10), Pull = tile + displace foe to ANY adjacent tile + force-face-me, Feint = concede tile, foe loses 1 action next turn. Declaration = PRE-DECLARED stance rider on forward moves at planning time (WEGO purity, replay/netcode clean, native 3×3 Nash subgame). Tick rework builds as ONE bundle once triangle is ratified (both Resolvers + new parity oracle).
**BUILT this block (Fra must: dotnet build → re-run BOTH parity dumps + diff → re-run run_brain_agreement.bat):**
- **Grenade +1 chip damage** (SpellBook both languages, `amount:1` on disrupt; _apply_disrupt both Resolvers now routes it through _apply_damage → interrupts an in-progress rest AND blocks next turn's rest via the existing damaged_tick path — zero special cases). View shows the -1 + ROOTED + drain. **Parity goldens legitimately CHANGE** (grenade cases now −1 hp + rest_ready false): regenerate gd oracle, then cs, diff must be IDENTICAL.
- **Eval upgrades, mirrored GD+C# (agreement harness must stay green):** (1) W_SURE_PRESS 0.35 — foe below COST_GUARD → my blockable melee is UNANSWERABLE, priced as sure damage (symmetric). (2) W_REST_PATH 6.0 — Fra's doorway: wounded (deficit≥25) + rest_ready + ThreatModel.rest_safe at turn end → value scaled by deficit (symmetric) — makes eat-hit→disengage→rest and similar lines surface ON MERIT (Fra's correction: no scripted randomness). (3) LOCKOUT CLOCK — attrition scales 0.6–1.0 by starved side's distance to their +30 pulse (waiting out a freshly-pulsed lock is worth less than a deep one; Fra's double-wait line now priced). Both DEFAULTS registries updated identically.

## HARVEST NIGHT v2 QUEUED (2026-07-11, bedtime): OvernightSweep gained UKO_MODE=harvest (run_harvest.bat): 450 mirror matches d3@700 self-play under the NEW physics → user://selfplay_v2.csv with the AUTOPSY FEATURE COLUMNS (my/foe flank tier, actions-to-pulse, lockout + can't-guard flags, rest_ready, burst/bolt cooldowns, cc statuses) — 31 features + outcome. Printout now includes avg-turns and final draw-rate = the new-physics stall telemetry (old baseline: 31–35% draws; if v2 draw-rate spikes, the runners won and we tune the ladder). ORDER OF OPERATIONS TONIGHT (parity BEFORE harvest — bad physics = poisoned data): install 13 files → build → regenerate BOTH oracles + diff IDENTICAL → run_brain_agreement green → run_harvest.bat → sleep. Tomorrow: paste the FINAL line + guard selfplay_v2.csv; then the value-fn fit begins on v2 data.

## TICK BUNDLE — STAGE A ENGINE BUILT (2026-07-11 night). SMOKE-VERIFIED IN C#.
Fra ratified everything: diagonals = FRONT tier (grenade keeps anti-kite speed); RPS triangle Push>Pull>Feint>Push confirmed. BUILT in BOTH engines: (1) universal directional tax — Config.DIR_TAX move 0/50/100, aimed 0/190/290, rel_of()/dir_tax() (diag+self=front), added AFTER final_tick (pure time; BACK_MOVE_TAX retired); (2) versatility tax +80 on a different-id slot 2; (3) TRUE SIMULTANEITY — tick groups resolve in PHASE 1 state (guard/pivot/move/blink_arrive/rest/wait) then PHASE 2 violence (attack/spell/projectile) reading the settled board: "everyone is where they end up at T; all violence at T judges that board" (band-priority tie order replaced; leavers dodge, arrivals get hit — matches Fra's pillar + blink rulings); (4) CLASH RPS in _do_move: both-forward same-tile same-tick → stance triangle (push: tile+10 raw via _apply_damage; pull: tile + loser yanked to winner's origin + forced facing [v1 simplification of "any adjacent"]; feint: concede tile, foe STAGGERED → next turn capped to ONE action, consumed at plan); same-stance bounce −10 EP each; non-forward collisions bounce with refund; (5) stance rider: action dicts carry "stance" (default push) → SchedEntry/PlanAction.Stance, marshaled through both bridges. C# core COMPILES + 10/10 behavioral smoke tests pass (side-dodge, front-catch, push/pull, feint/stagger cap+consume, bounce economy, taxed-pivot race, burst-catches-arrival). 5 matching fixtures added to BOTH ParityDump.gd and PortParityDump.cs. **FRA VERIFY:** dotnet build → regenerate BOTH parity oracles (goldens LEGITIMATELY change massively) → diff must be IDENTICAL → run_brain_agreement.bat (must stay green — candidates unchanged; AI emits no stances yet = default push). STAGE C NEXT SESSION: stance-picker UI on forward moves + tick preview in ActionMenu + AI stance candidates (AIToolkit ×3 on forward moves, both languages) + EventPlayer clash animations. THEN: arena A/B old-vs-new physics (draw rate!), re-harvest, value-fn fit.

## DESIGN LAW (Fra + Claude, 2026-07-11): THE CLOCK IS SHARED PHYSICS
Fra ratified: the directional side/back tick tax applies to EVERY aimed action (spells + blink included). Fra asked whether a future SPEED STAT would break the game — answer: YES, structurally. The bundle's depth lives in tick EQUALITIES and ~20-tick margins (dodge = 520 vs 540; pillar denial = 1040==1040; contested-tile RPS fires ONLY on identical arrival; mirror trades = 350==350). A per-player permanent speed modifier flips dodges on gear not reads, makes simultaneity measure-zero (the RPS never triggers between different-speed players), privatizes the tick arithmetic (reading the opponent requires their stat sheet), and the Nash brain would degenerate the meta into breakpoint shopping. THE LAW: stats may touch resources (energy/damage/HP/range/cooldowns) but NEVER the clock. Safe speed shapes (the existing guard speed_boost is the template): earned in-match, single-action, publicly telegraphed, temporary; or effects on UNCONTESTED time (rest speed, cooldown recovery, pivot cost); or symmetric arena-wide modifiers. STILL OPEN before the tick bundle builds: (a) diagonal aims = side tier? (b) push/pull/feint triangle ratification (Push>Pull>Feint>Push proposed).

## RATIFIED INTO THE TICK BUNDLE (2026-07-11 evening): UNIVERSAL DIRECTIONAL TICK TAX
Fra's refined design (supersedes the critiqued side-damage/back-ban proposal): ONE principle — "you act fastest toward where you face" — the side/back tick tax extends from moves to EVERY tile-aimed action. Dodges EMERGE from arithmetic (fwd move 520 beats side-aimed attack 350+tax), no new mechanic. Claude's proposed ladder (Fra to tune): front attack 350 (mirror duel untouched) | side attack 540 (fwd run dodges by 20 — a read, not a guarantee) | back attack 640 (LEGAL per pricing-not-banning; dodged by fwd AND side moves; punishes only the stationary). Commitment hierarchy: front 350 < side 540 < pivot+attack ~700+tax. OPEN SCOPING (Fra to ratify): (a) tax applies to ALL tile-aimed actions incl. bolt/grenade/blink? (Claude recommends yes; direction-less actions — guard/wait/rest/burst/buff — exempt; back-blink tax = accidental anti-stall counterweight); (b) diagonal aims = side tier (proposed); (c) mob direction-less attacks (ooze burst) exempt. REQUIRED: UI must preview computed fire-tick per option (facing-dependent after slot 1). RISK TO MEASURE: rewards running → arena A/B vs current rules, watch draw rate + match length (meta already 31–35% draws). Ships ONLY inside the tick bundle (tax+80, dir moves, simultaneity, push/pull/feint) = one oracle regen, one re-baseline, then re-harvest for the value fn.

## FRA PROPOSALS UNDER CRITIQUE (2026-07-11, NOT ratified — Claude's devil's-advocate delivered)
(a) Side attack 10 dmg + back attack ILLEGAL (attacker-relative): double facing bookkeeping (attacker aim tier × defender flank tier = 3×3 matrix, UI must predict per-tile), bans violate UKO's price-don't-ban language (rooted+wrong-facing = zero counterplay, death-spirals with stun), and ALL breakpoints shift → obsoletes calibration/gates/selfplay_cs.csv. Safer variant if wanted: side slower OR weaker (not both), back legal-but-slow, shipped inside the tick bundle. (b) Forward move faster than side ATTACK (attacker-relative attack ticks): third tax on the same facing axis → pivot becomes boilerplate, melee slower+weaker together → deepens the 31–35% draw stall; schema change f(facing,aim) across ThreatModel/candgen/both resolvers/story strikes/oracle, overlapping the simultaneity rework. (c) Grenade STUN (cancel next action): FIRST violation of WEGO's commit promise (only death cancels today); fifth effect on an item Fra's own match proved is already a full lockout; devalues FEINT's identity (same prize, cheaper, ranged); 'action after' ambiguity (same-turn schedule surgery vs carried status). Alternatives offered: replace drain with stun (pick ONE lockout), or soft-stun (+ticks on next action). META: any of these obsoletes current baselines + the harvested training data — sequence as: freeze rules → tick bundle → re-harvest → solo A/B each variant in the arena (100 matches: winrate/draws/length).

## AI-STRENGTH ROADMAP (post-sweep, eval is the bottleneck)
1. Learned value fn (fitting next — CSV harvested). 2. RICHER HARVEST COLUMNS needed: facing/flank rel, pulse phase (actions-to-pulse), lockout flags (energy<COST_ATTACK), cooldowns — the autopsy concepts; model can't learn unseen features. 3. Anti-predictability: mixing floor at terminal/low-energy states (gate #8) — both Fra wins came from the guard tell. 4. Autopsy gates as exams (zone-funnel, press-the-lockout). 5. NOT more compute (sweep-proven plateau until the judge improves).

## Next (priority order)
0. **BOSS ARENA TELEPORTER (Fra spec, verbatim — build FIRST next session, read Story/ code first):** "Add to the map on the right side of the outline blockers an open tile, when you step inside it you teleport into this 8x8 square where the boss is. You cannot exit unless you kill the boss, since after killing him a tile highlights and stepping onto it teleports you back to the story map." Implementation notes: lives in the CavernMobs/StoryController world (the CANONICAL mob system — StoryController now uses MobKind.plan() ONLY, ExtremeAI banned from story per Fra's toolkit rule, fixed this session); needs: map edit (open tile right of outline blockers), step-trigger → teleport into a dedicated 8x8 boss room, boss spawn there, exit LOCKED until boss dead, then highlight a return tile → step → teleport back to the story map at/near the entry. Boss FIGHT design itself still pending (Fra: later) — the boss can use its existing behavior for now.

1. **C# engine-brain port** (in `Scripts/Port/CSharp/`, `namespace UKO`): ParityDump✓ → **Config.cs✓ (STAGE 1)** → **Combatant.cs✓ (STAGE 2)** → **Grid.cs✓ (STAGE 3)** → **Resolver.cs✓ + PortParityDump.cs✓ (STAGE 4)** → **PARITY VERIFIED ✓✓ — parity_cs.txt == parity_gd.txt, all 673 cases byte-identical (Fra confirmed via F6 + diff_parity.ps1).** The C# engine is a true twin of the GDScript engine. **CURRENT STEP (option 1, Fra-chosen): MEASURE the boundary before porting the brain.** Built: `ResolverBridge.cs` ([GlobalClass] RefCounted; Resolve() + Echo(); marshal contract = grid as 8 row-strings, combatant as flat dict {id,x,y,facing,hp,mp,energy,action_count,rest_ready,speed_boost,cooldowns,statuses,spent_once,gear}, seq as array of {id,tile?,facing?}; NO events returned — traced all call sites: the AI reads only a/b/result, only GameController's renderer reads events and it stays GDScript) + `Scripts/Port/BridgeBench.gd` + `run_bridge_bench.bat`. The bench: (1) correctness A/B, 330 cases (18×18 cross + 6 delicate fixtures) GDScript-vs-bridge must match; (2) timing, 3×2000 calls → GD resolve vs bridge resolve vs Echo(marshal-only) → prints per-call µs, speedups, a 150-resolve/decision projection, and a VERDICT line (bridge already faster → option 3 viable | compute fast but boundary eats it → search loop must live in C# | compute not faster → re-examine). **MEASUREMENT DONE (Fra ran it): correctness 329/329 ✓; GD resolve 177.3µs | bridge 262.1µs (0.68x, LOSS) | Echo/marshal 202.6µs | C# compute 59.5µs (≈3x faster). 150-resolve decision: GD 26.6ms | bridge 39.3ms | in-C# loop 8.9ms. VERDICT CONFIRMED BY DATA: the boundary eats the win → OPTION 2, the search loop moves into C#.** Per-call bridging is dead (never wire EconomyEval/Eval through ResolverBridge piecemeal); ResolverBridge stays as the eventual ONE-CALL-PER-DECISION top adapter. **BRAIN PORT WRITTEN (this session): the full EXTREME chain is in C#** at `Scripts/Port/CSharp/Brain/` — ThreatModel.cs, AIToolkit.cs, NashSolver.cs, Eval.cs, OpponentModel.cs, ExtremeAI.cs (~1,100 lines) + engine extensions (Grid: DIRS/RotStep/ShrinkLevel/BaseBlocked/IncomingWalls/quadrant-cycling; Config: BlinkLanding, both un-deferred) + **BrainBridge.cs** (the ONE-CALL-PER-DECISION adapter the measurement demanded: ChooseSequence marshals state once, whole search runs in C#; owns the C# OpponentModel with ObserveFoe/Save/LoadModel via ConfigFile; LoadCalibration sets Eval.CAL_A; harness probes CandidatesOf/ScoreRich/ScoreDeep/SolveMatrix/ChooseMixDet). **Scope note: only the EXTREME chain ported** — ExtremeAI→{AIToolkit,Eval,NashSolver,OpponentModel}, Eval→ThreatModel; PlanGenerator/EconomyEval/TileUtility/ResourceModel/IntentSelector belong to CHALLENGING and stay GDScript. **Parity-critical choices:** stable top-k sorts everywhere GDScript used sort_custom (TopRows/WorstCols/CappedCands ties keep original order); Rnd away-from-zero in ThreatModel; clock=Environment.TickCount64; sampling isolated so ChooseMix (pipeline minus sample) is DETERMINISTIC at unlimited budget. **Sandbox-verified:** compiles; RPS→uniform + dominance + determinism; candidates sane (172 at adjacent root, attack+guard offered, no rest at full); bolt threat=25 at range-3+step; starved-foe evaluates better (attrition); full brain deterministic mix, normalized, support-pruned; ~720ms real decision at 700ms budget; top line at adjacent root = blink-behind+backstab p=0.335; opp-model bucket warm + exploit path runs. **PENDING (Fra): run_brain_agreement.bat** — **FIRST RUN: 830/880 green; ALL candidates 1:1, ALL score_rich <1e-6, ALL Nash <1e-9; only score_deep + full-mix diverged. ROOT CAUSE FOUND: Godot's sort_custom is UNSTABLE (my earlier "insertion sort/stable" claim was WRONG — engine parity survived only because Resolver same-tick ties are outcome-neutral). Ties are common in the deep path (_capped_cands cheap-rank ties decide WHICH 3 candidates enter a subgame; _top_rows/_worst_cols ties decide which cells deepen), so tie order = brain behavior. FIX APPLIED (Fra to ratify — touches live GDScript, marginally affects frozen CHALLENGING on ties): explicit value-then-original-index tie-breaks in Eval._capped_cands, ExtremeAI._top_rows, ExtremeAI._worst_cols — converts accidental behavior into defined behavior matching the C# stable top-k. No other sort_custom in the EXTREME chain. C# comments corrected. **AGREEMENT VERIFIED ✓✓ (Fra ran it): ALL 880 CHECKS PASS after the tie-break fix — the C# brain is a numeric twin of the GDScript brain.** **LIVE WIRING DONE (flag-guarded):** discovered live routing was CHALLENGING→ExtremeAI("challenging"), **EXTREME→EconomyAI (the "economy+intent" remodel, marked TEMPORARY/DEBUG_LOG in code)** — the ported ExtremeAI chain is what all gates/tuning targeted. `AI.gd` now: `USE_CSHARP_EXTREME := true` → EXTREME runs BrainBridge.ChooseSequence (falls back silently to EconomyAI if C# unavailable; flip the const to roll back); bridge lazily created + SetProfile("extreme") + LoadCalibration + LoadModel (reads the SAME uko_opp_model.cfg the GDScript model writes — GDScript remains the saver, no write conflict); dead duplicate `_:` match arm removed. `GameController.gd`: observe site now computes sit once, observes, and calls `AI.forward_observation` so the C# opponent model learns live. **⚠️ DESIGN CALL FOR FRA TO RATIFY: this replaces EconomyAI as the live EXTREME tier with the C# ExtremeAI.** EconomyAI/PlanGenerator/EconomyEval chain remains intact & selectable via the flag. **PENDING: Fra builds + plays one EXTREME match to smoke-test the live path.** THEN the payoff: raise Eval.LOOKAHEAD_DEPTH (C# side) to 4–6, re-run press-starving gate (port the gate runner or A/B in-game), learned value on selfplay_data.csv. — 5 frozen positions (incl. a press-starving shape + endgame shrink-2), checks candidates 1:1, score_rich/deep <1e-6, Nash <1e-9, FULL deterministic pipeline mix <1e-6 (GDScript mirror uses ExtremeAI's own statics, unlimited budget, CAL_A=0 both sides). If green → wire GameController's EXTREME branch to BrainBridge (swap is ~10 lines: build dicts, call ChooseSequence, convert back; keep GDScript path behind a flag) → THEN raise depth 4–6 → press-starving gate → learned value. → brain switches forward model → SM-MCTS → learned value on selfplay_data.csv. Targets: press-starving green via depth 4–6; kills horizon-class errors (grenade+wait, rest-into-AoE).
   - **Two architecture decisions (Fra to ratify):** (a) **pure C# core, framework-free** — its own `Vec2I` struct, NOT Godot.Vector2I, so the engine compiles+unit-tests OUTSIDE Godot and a thin `[GlobalClass]` adapter converts at the GDScript boundary later; (b) **typed & faithful** — ACTIONS/SPELLS are typed `ActionDef`/`Effect` with nullable optionals reproducing GDScript `get(key,default)` per use site (no Dictionary-of-Variant).
   - **Stage 1 = the static data layer:** Config.cs + SpellBook.cs + GearBook.cs + Vec2I.cs. vfx/ai_role and gear colour/cost/overlay are view/AI-hint metadata, deliberately NOT ported (engine never reads them). GRID-dependent helpers `projectile_path` (Resolver-critical) + `blink_landing` (AI-only) are DEFERRED to Grid.cs — noted in Config.cs.
   - **Stage 2 (Combatant.cs):** reference type (was RefCounted); Statuses/Cooldowns = Dictionary<string,int>, SpentOnce = Dictionary<string,bool>, Gear = List<string> (4 slots), Pos = Vec2I. Clone() deep-copies the 3 dicts + gear and DROPS the transient RerouteArmed/RerouteTile (matches GDScript). SpellInSlot ported for completeness (view-only). ⚠️ **C# ParityDump note for the Resolver stage:** the fingerprint dict-serializer must emit bools as lowercase `true`/`false` (C# `ToString()` gives `True`) to match GDScript's `{grenade=true}`.
   - **Stage 3 (Grid.cs):** minimal — SIZE=8, `Blocked` (bool[,] indexed [y,x]), InBounds, IsBlocked (OOB=blocked), static Dist/Cheb (delegate to Vec2I). Generation/rotation/zone NOT ported (turn-loop only; Resolver never reads them). `Grid.FromRows("....#...", ...)` tooling helper builds parity/test arenas (mirrors ParityDump._grid_from). Next: Resolver.cs — the big one; then a C# ParityDump that diffs byte-for-byte against parity_gd.txt.
   - **Stage 4 (Resolver.cs, ~806 lines):** full port of the simultaneous-turn engine. Parity-critical choices: (1) `Rnd()` = round-half-AWAY-from-zero (Godot's `round`; C# default is banker's/to-even → would diverge on side-attack 22.5→23 etc.); (2) schedule sort is STABLE by (tick, band_priority) via OrderBy/ThenBy — Godot's sort_custom is insertion-sort (stable) on these <16-elem arrays, so ties keep A-before-B/slot order; unstable List.Sort would diverge. Events carry only Type/Tick/Owner (parity digest tallies Type; data payloads are view-only, omitted). ProjectilePath un-deferred into Config.cs (needs Grid); blink_landing still deferred (AI-only). **Config.cs changed** (added ProjectilePath) — re-copy it.
   - **PortParityDump.cs** = Godot `Node` tool (attach to a node, Play) that writes `user://parity_cs.txt` next to `parity_gd.txt`. **Cross-check DONE here:** cases 648/650/668 (back-flank ×2, front-guard block+refund+boost, lethal+dead_skip) are BYTE-IDENTICAL to the golden lines Fra pasted. **PENDING:** Fra runs it and diffs all 673 lines (fc / Compare-Object). If any mismatch, the likely culprits are a round() site or a same-tick tie order → fix both sides + regenerate golden.
   - **Verified (sandbox):** whole engine compiles offline (net8.0) and the C# ParityDump ran clean producing 673 well-formed lines; Config+Combatant+Grid pass 128 value assertions. (PortParityDump.cs's Godot-only I/O can't be sandbox-compiled; it's a mechanical wrapper over the verified console dump.) (flank tiers, move costs, FinalTick band math, every def's fields, blink-travel, classifiers, effective energy/move cost under discount, CanAfford, planned self-buff, gear map, gold, statuses, empty-def). Test harness (Program.cs/cfgtest.csproj/nuget.config) is STANDALONE — keep it OUTSIDE the Godot project (its Main() would clash); re-run with `dotnet run` to re-check after edits. NOTE: needs `nuget.config` with `<clear/>` sources to restore offline.
2. Behavior gates #7–9 (multi-turn scaffolding).
3. **Wait-haste prototype** behind flags — agreed spec: WAIT_HASTE + full-turn-guard companion flag; full bracket hop; AOE excluded; consumed by next non-wait; non-stacking; public + needs a unit icon.
4. StoryController split (own session, playtest between steps): NpcDirector → GatherDirector → CameraRig; then StoryDirector + beats/flags/DialogBox once the story document is uploaded (story-as-data, TODO placeholder dialogue).
5. Nightly tuner continues (resumes champion; re-audition happens under the calibrated judge + all 6 gates).
6. **Field report from Fra's first live C# EXTREME match:** (a) **DOUBLE-GRENADE BUG — FIXED both engines**: Resolver legalized both slots before resolution set spent_once, so [grenade,grenade] passed; now burned at PLAN time (mirrors cooldowns) in Resolver.gd + Resolver.cs; AIToolkit can_use/CanUse now also reject spent once-per-match items (AI was wasting candidate slots on noop grenades). Latent GDScript bug the port faithfully reproduced. **Re-run BOTH parity bats + diff after this change (golden should be unchanged — single-grenade cases end in the same state — but confirm).** (b) **GRENADE FULLY FIXED (4 layers):** ghost-flight guard in BOTH Resolvers (_launch_projectile throw now defers to _shape_tiles validity from the LIVE tile — a plan-time aim invalidated by a fizzled earlier action is now a spell_miss, never a wrong-hop flight); EventPlayer._plan_flights splits flights when the step index resets (two same-owner same-spell throws no longer weld into a bouncing zigzag); the disrupt burst now matches the THROWER's flight (was: first grenade found, any owner); and a landed grenade now shows 'ROOTED / -20 ENERGY' instead of a '-0' that read as a whiff (root cause of Fra's 'didn't hit' report: it likely DID hit — disrupt deals 0 damage by design and the view showed nothing legible). Golden parity file should be unchanged (no invalid-throw cases in it) — the parity re-run confirms. (c) Behavioral reports = the KNOWN horizon class (blink-away opening; double-wait at 75 energy eating move+bolt; rest at 88hp/73mp/100en into AoE range; guard-when-starved cheese Fra exploited to win) — exactly what depth 4–6 is meant to fix; tonight's overnight run measures whether depth moves these. EconomyAI.DEBUG_LOG set false (would flood overnight logs).
7. **OVERNIGHT SELF-PLAY READY** (`Scripts/Port/OvernightArena.gd` + `run_overnight.bat`): Phase 1 = C# depth-3 vs C# depth-2, 150 seeded matches (does depth buy skill? — the port's whole thesis); Phase 2 = C# depth-2 vs EconomyAI/old-EXTREME, 150 matches (port validation winrate). Full gear both sides, seat alternation, real rotation/zone clock (mirrors _rotate_map incl. crush + rest_ready), 80-turn draw cap, HP-margin tracked, results appended live to user://overnight_results.txt (interruption-safe). `Eval.LOOKAHEAD_DEPTH` now a settable static + `BrainBridge.SetDepth(d)` — the depth dial. Read results next session: if d3>d2 decisively → push d4+ and re-run press-starving gate; if d2>econ → port validated as the stronger EXTREME.
8. **NEXT-NIGHT SWEEP READY** (`Scripts/Port/OvernightSweep.gd` + `run_sweep.bat`): d3@1400 vs d2@700, d4@2000 vs d2@700, d3@700 vs d2@700 (80 matches each; equal-time phase isolates depth itself). New dials: `BrainBridge.SetBudget(ms)` / `ExtremeAI.BudgetOverrideMs`. **Every turn also appends a training row to user://selfplay_cs.csv** (seed,turn,seat,hp,mp,energy,foe triple,dist,shrink,action_counts,nade flags,outcome ±1/0) — the learned-value data harvest starts NOW per Fra's priority call ("#5 is our go-to"). Next session: fit a first value function on that CSV (logistic to start), load via bridge, champion-vs-challenger gate it.
9. **Fra's gate-design correction (encode as gates #7–8, spec'd, not yet built):** guard-when-starved is a LEGITIMATE mixed answer to double-attack — the exploit was determinism + missing pulse-tempo play. Gate #7 "pulse pacing": foe passive/out of press range + me energy-starved → brain should prefer cheap-action lines (sidestep/wait, guard→wait) that advance action_count toward the 6-action pulse (+30), NOT freeze. Gate #8 "guard→wait exists": in starved-defense spots the mix must include guard→wait with nonzero weight (it reportedly never played it). Gates target the C# brain → needs a bridge-based gate runner (PositionTests targets GDScript). NOTE: Eval already has PulseRelief() shaping W_LOCK — the concept exists; depth may surface it, gates verify.
10. **Kit bug FIXED** (SelfPlayArena.DEFAULT_KIT → real gear ids): all historical tuner/calibration/position-test baselines were SPELL-LESS and are hereby stale; first re-runs establish new baselines. (OvernightArena/Sweep always used FULL_GEAR — last night's results are spell-real and remain valid. Fra briefly believed otherwise; corrected.)
11. **MOB AI REDESIGN — BUILT THIS SESSION (Fra spec):** engine gained a per-Combatant attack profile (`attack_range`, `attack_all_adjacent`; defaults 1/false so DUEL behavior & the parity golden file are unchanged — Fra must re-run BOTH parity bats + diff to confirm) in Resolver.gd **and** Resolver.cs + Combatant both languages. New `Scripts/AI/MobAI.gd`: toolkit-restricted chooser — attack/pivot/move/wait ONLY, greedy hunt (in-reach→attack; else best closing step; else pivot to face; else wait), 2 slots with projection. Wiring: `GameController.pending_b_mob` ("bat"/"ooze", consumed with the gear) sets the attack profile after equip and flows into `AIOpponent.new(difficulty, tree, mob)` → MobAI. **Overworld must now set pending_b_mob alongside pending_b_gear when starting a mob duel** (find those call sites next session — not yet audited). bat=range-2 strike; ooze=every attack hits ALL 4 adjacent tiles. Player-side view: attack targeting UI still highlights range-1 tiles only (fine — players aren't mobs); mob attack ANIMATION for range-2/burst hits not yet checked in EventPlayer — verify visually. **FIELD REPORT ROUND 2 + FIXES:** Fra's bat RESTED + seemed to take 3 actions — ROOT CAUSE: the overworld never set pending_b_mob (the flagged wiring gap), so the DUEL brain played the bat; now wired (`Overworld._start_duel` sets `pending_b_mob = m.tag`). Re-test the 3-action report AFTER this fix — if it recurs with MobAI routed, it's real; likely it was the duel brain + projectile visuals. **New per Fra:** (1) mobs always-offensive (MobAI is, by construction); (2) BAT KITING: hugged at dist-1 → `_step_away` backpedals (sweet-spot bonus for landing exactly at attack_range) then the next slot strikes at range — "move backwards + attack"; (3) mob RESOURCE stats (PLACEHOLDERS, Fra tunes): bat hp 45 / energy 70, ooze hp 70 / energy 60 — energy economy + pulse already meter their actions; (4) **DESIGN ITEM (not built): spawn MORE mobs → 2v1 fights.** ⚠️ 2v1 is a real engine project: Resolver/GameController/brains are strictly 1v1 (a,b). Options to scope next time: sequential duels (fake 2v1), or true multi-combatant resolver (big). **⚠️ NAMING GAP FOUND: the live overworld's MOB_TYPES are `grunt`(Imp)/`brute`/`boss` — NOT bat/ooze.** The bat/ooze sprites+design aren't in the spawn table yet. Current state: AIOpponent routes tags [bat,ooze,grunt,brute] → MobAI (so ALL existing simple mobs stop guarding/resting NOW, default melee-1 profile); `boss` stays on the DUEL brain (undesigned + full spell kit). GameController's bat/ooze stat+range profiles activate when Fra either renames MOB_TYPES keys to bat/ooze or adds them as new entries with the right gear/sprites — FRA'S CALL next session. Original spec follows: current story mobs guard/rest = WRONG, they're borrowing the duelist toolkit. Design rule: **monsters use ONLY their own toolkit** — bats & ooze get {attack, pivot, move} ONLY (no guard, no rest, no spells, no grenade). **Bat: attack RANGE 2 tiles.** **Ooze: every attack hits ALL 4 adjacent tiles simultaneously** (cardinal around-melee). Boss fight designed later, separately. Existing "mob" profile in ExtremeAI (90ms) may be reusable for the brain, but candidate generation must be toolkit-restricted per mob type (a MobToolkit/candidates variant, NOT AIToolkit's full duelist set). Attack schema likely needs per-attacker range + multi-tile hit shape support — check Resolver's attack path before designing.
12. Watch items: **SelfPlayArena.DEFAULT_KIT bug** — its entries (`dark_bolt/aoe_burst/energy_discount/blink_step`) are spell/status ids, but equip() treats them as GearBook ids and spell_of() only knows `discount_charm/burst_node/blink_boots/dark_focus`, so spell_ids() returns ONLY `["grenade"]`. Every tuner/calibration/self-play/position-test match has therefore been spell-LESS (grenade only) — the press-starving test's `dark_bolt` press-branch can never fire, and W_DANGER_SPELL/W_MP/spell terms were tuned in a game with no spells. Fix is one line (`DEFAULT_KIT := ["discount_charm","burst_node","blink_boots","dark_focus"]`), but it INVALIDATES the current champion + calibration.cfg + selfplay_data.csv, so it's a Fra design call, not a silent patch. (ParityDump sidesteps it by equipping real gear directly.) · stall meta at cadence-10; grenade oppression on 8×8 (tick_per_tile lever); mirrored-map toggle; 80s duel dressing (side panels w/ portraits → round banner + collapse countdown → frame + braziers); mushroom/day-night persistence across duel returns; document within-tick tiebreaks in-game.
