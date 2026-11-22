# Azure server

Beacon Bay runs desktop clients against a headless Godot **4.7 stable** Linux server. Use client/server build **0.8.0**, network protocol **8**. The first player starts the session; after results, that player can continue or replay without restarting the server.

The prepared `BeaconBay-AzureServer-0.8.0.zip` contains a Linux Server resource pack and service files. It does **not** contain the Linux Godot executable. This workspace has not provisioned, updated or tested a live Azure VM.

## Install

1. Use an Ubuntu x86_64 Azure VM with the official matching Godot 4.7 Linux executable at `/usr/local/bin/godot`. Make it executable. A display server is not needed.
2. Create a `beaconbay` service user and place `BeaconBay.pck` in `/opt/beacon-bay/`.
3. Copy `beacon-bay.service` to `/etc/systemd/system/`. It runs as that user and stores engine state in `/var/lib/beacon-bay`.
4. Allow inbound **UDP 24680** in the Azure network security group and the VM firewall. Restrict SSH to your administrator address. The game does not need inbound TCP 24680.
5. Run `sudo systemctl daemon-reload` and `sudo systemctl enable --now beacon-bay`.
6. Inspect startup with `sudo journalctl -u beacon-bay -f`. It should report waiting for 1–4 players on UDP 24680.

For a manual launch from the pack folder:

```sh
/usr/local/bin/godot --headless --main-pack BeaconBay.pck -- --server --port=24680
```

`start-server.sh` also supports `GODOT_BIN` and `PORT`. A valid custom port is 1024–65535; adjust firewall rules and have players join `address:port`.

## Connect and verify

Run the matching Windows build, choose **Play with friends**, enter the VM public address, and join. Wait for the group; the first player clicks **Start shift together**. The server uses no player seat. Repeat sessions begin from the same fixed game-time emergency schedule.

Verify all four department assignments, simultaneous dispatch, join/leave, a complete shift and replay. Enable microphone/recording controls on consenting clients and check their local WAV/JSONL files. No input or audio recording files should appear on the server.

Team voice uses ENet on the game port (16 kHz mono PCM). Headsets avoid feedback. Voice and game commands use separate network channels. Recordings stay on each player's computer; the server only relays voice packets.

This server supports one team per process. Run separate instances on separate UDP ports for concurrent groups. Each instance uses the same scenario and phase schedule. There is no account system or public matchmaking.

## Update

Stop the service, replace the pack with the new version, and restart. Distribute the matching client build to every player. Keep the previous pack for rollback; never mix client versions in one room.
