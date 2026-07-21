# UKO as a website — one build, every device

The web build is the GDScript game: browsers can't run C#, so EXTREME plays
through its verified GDScript twin (same brain, shorter think leash — see
"What's different on web" below). The online server is unchanged — browsers
already speak its language (WebSocket), and `run_server.bat` now serves the
website itself: one bat = the site AND the matches.

---

## One-time: the second editor

Your everyday editor is the **.NET** build of Godot (it compiles the C#
brain). Web export needs the **standard** build of the *exact same version*:

1. godotengine.org/download → **Godot Engine** (the one NOT labeled ".NET"),
   same 4.7.x as your editor. It's a single exe — keep it next to the other.
2. Open the UKO project with it. It will warn about C# scripts — that's
   expected and harmless; don't let it "fix" anything, just proceed.
3. Editor → Manage Export Templates → Download and Install (these are the
   standard templates; your .NET editor's templates don't cover Web).

## Before every export: ship the judge

Copy your fitted files into the repo's `Data/` folder (they ride inside the
build; without them, fresh browsers play EXTREME on the hand eval):

    %APPDATA%\Godot\app_userdata\UKO\value_fn.cfg    ->  UKO-game\Data\value_fn.cfg
    %APPDATA%\Godot\app_userdata\UKO\calibration.cfg ->  UKO-game\Data\calibration.cfg

Re-copy whenever you promote a new judge (`run_promote_value.bat`).

## Export

Standard editor → Project → Export → **Web** (preset is in the repo) →
**Export Project** → keep the default path `Tools/GameServer/web/index.html`.

Verify two options in the dialog the first time (in case your Godot version
renamed a setting and fell back to a default):

- **Thread Support = OFF** (simplest, works everywhere — our server would
  handle ON too, but OFF also works on stricter hosts)
- **Virtual Keyboard = ON** (so phone browsers can type room codes)

## Play it

1. `run_server.bat` on your PC (allow it through the firewall when asked).
2. Any device, any browser:
   - on the PC itself: `http://127.0.0.1:8765`
   - on your Wi-Fi: `http://YOUR-PC-IP:8765` (ipconfig → IPv4, e.g.
     `http://192.168.1.50:8765`) — Android, iPhone, iPad, laptops, all of them.
3. Online play needs no address on web: the game connects back to the very
   machine that served the page. QUICK / HOST / JOIN just work — including
   browser vs. desktop players, same server, same matches.
4. Internet access (friends outside your Wi-Fi): forward TCP 8765 on your
   router to the PC, share `http://YOUR-PUBLIC-IP:8765`. Tell me your router
   model when you're ready and I'll walk you through it.

## itch.io (the public page, when you're ready)

1. Zip the **contents** of `Tools/GameServer/web/` (index.html at the zip root).
2. itch.io → Create new project → Kind: **HTML** → upload the zip → tick
   "This file will be played in the browser". Viewport 1152×648 + fullscreen
   button is a good start.
3. Caveat: itch pages are HTTPS, and HTTPS pages may only open **encrypted**
   connections — so online play from the itch page needs your server behind a
   free Cloudflare Tunnel (gives you a `wss://` address, no port-forward, and
   hides your home IP). That's a 30-minute setup I'll guide when you want the
   public page live; single-player works on itch with zero extra steps.

## What's different on web (honest list)

- **EXTREME thinks 0.9s/1.2s instead of 3s/6s** — the browser runs the
  GDScript twin on the main thread, so the full budget would freeze the page.
  Same brain, same judge, shallower deepening. Native Windows keeps full
  strength; serious ladder play can stay native later if you ever want both.
- **Your AI tools stay desktop programs** — harvest, fitting, arena, sweep,
  parity, and the server itself run on your PC as always (they're not game
  features, nothing is lost for players).
- **Saves live per-browser** (profile/gold/gear persist in that browser's
  storage; clearing site data wipes them).
- **First tap unlocks audio** on iPhone Safari — a browser rule, not a bug.
- **GD-Sync still boots keyless** (the old relay, unused since round 13). If
  the page ever hangs at boot and the browser console (F12) shows GD-Sync
  errors, tell me — quarantining it is a quick round.

## Going back to native

Nothing was removed: the Windows and Android presets, the C# brain, and
DEPLOY_MOBILE.md all stay in the repo. "Web only" is a focus, not a burned
bridge — exporting a native build works any day you want it.
