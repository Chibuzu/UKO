# UKO Game Server -- running it

## On your PC (testing, LAN play)
1. `run_server.bat test` -- the server plays full matches against itself over
   real sockets and prints PASS/FAIL per check. All green = healthy.
2. `run_server.bat` -- starts serving on port 8765. Game clients (round 14's
   online menu) connect to `ws://127.0.0.1:8765` on the same PC, or to
   `ws://YOUR-LAN-IP:8765` from another machine in the house (allow the port
   through Windows Firewall when it asks).

## On a rented server (internet play)
Any cheap Linux VPS (~5 euro/month, 1 CPU / 1 GB is plenty -- the game is
turn-based; one small box handles hundreds of concurrent matches).

1. On your PC, build a self-contained Linux binary (no installs needed on the VPS):
   `dotnet publish Tools/GameServer/GameServer.csproj -c Release -r linux-x64 --self-contained -p:PublishSingleFile=true`
2. Upload the file from `Tools/GameServer/bin/Release/net8.0/linux-x64/publish/GameServer`
   to the VPS (WinSCP or any SFTP tool).
3. On the VPS: `chmod +x GameServer && ./GameServer --port 8765 --log matches.csv`
   (keep it alive with `nohup ./GameServer ... &` or a systemd service later).
4. Open TCP port 8765 in the VPS provider's firewall panel.
5. Clients connect to `ws://YOUR-VPS-IP:8765`.

## Flags
`--port N` (8765) | `--deadline S` turn clock (90) | `--bot-budget MS` bot think
time (1500) | `--value-cfg PATH` arm the learned judge for bots | `--log PATH`
training-row csv of every completed match (the learn-from-humans stream --
periodically append it to selfplay_v3.csv and refit) | `--selftest` run the
built-in verification and exit.

## Notes
- Bot matches share ONE brain (single search at a time, by design). A few
  concurrent bot duels are fine; dozens will feel slow. Human-vs-human matches
  are nearly free and scale to hundreds.
- Abandoned matches award a forfeit and are NOT logged as training data.
- No accounts on day one: names are display-only. Rankings/accounts are a
  later round if wanted.
