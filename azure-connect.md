# Beacon Bay — Player Connection & Public Server Guide

This guide is intended for **players and collaborators** who want to connect to a Beacon Bay multiplayer session.

It also includes an optional section at the end for anyone who wants to deploy their **own dedicated server**.

> This public guide intentionally excludes private credentials, SSH keys, subscription details, personal file paths, and private Azure account information.

---

# 1. What You Need

To join a Beacon Bay multiplayer session, you need:

- the same Beacon Bay game version as the server
- an Internet connection
- the server's public IP address
- UDP access to the Beacon Bay game port
- Godot only if you are running the project from source

The default Beacon Bay dedicated-server port is:

```text
UDP 24680
```

Ask the server owner for the current server IP.

At the moment, the server IP is:

```text
9.160.166.213
```

---

# 2. Recommended Method — Use the Exported Game

For most players, the easiest method is to use the exported Windows build provided by the server owner.

The package will normally contain files such as:

```text
BeaconBay.exe
BeaconBay.pck
```

Keep the provided files together in the same folder.

Then:

1. Extract the ZIP/package.
2. Run `BeaconBay.exe`.
3. Choose **Join**.
4. Enter the server IP provided by the server owner.
5. Connect.

Example:

```text
Server address: 9.160.166.213
```

Do **not** choose **Host** when joining an existing dedicated server.

The Azure/cloud machine is already acting as the host.

---

# 3. Running the Game From Godot

Developers can also run Beacon Bay directly from the Godot editor.

Before joining, update the repository:

```bash
git pull
```

Check the current commit:

```bash
git log -1 --oneline
```

The client should use the same code version as the dedicated server.

Then:

1. Open the project in Godot.
2. Run the normal desktop game.
3. Choose **Join**.
4. Enter the server IP.
5. Connect.

Do not launch your local game using the dedicated-server `--server` argument when you are joining as a player.

---

# 4. Current Multiplayer Behavior

The current dedicated-server version supports:

```text
1–4 remote players
```

The server itself does not occupy a player slot.

The expected connection flow is:

```text
Player 1 ----Player 2 -----Player 3 ------> Internet ---> Dedicated Server
Player 4 -----/
```

The first connected player can manually start the shift.

The game does not require all four players to connect before starting.

---

# 5. Starting a Game

After connecting:

1. Wait for the game to confirm that you joined the server.
2. Other players may join the same server address.
3. The first connected player can use **START SHIFT TOGETHER** when the group is ready.
4. The session can contain between one and four players.

If you join and unexpectedly see the results from an old session, ask the server owner to restart the dedicated server.

---

# 6. If You Cannot Connect

Check the simple things first.

Confirm that:

- you selected **Join**, not Host
- the server IP is typed correctly
- the server owner has actually started the dedicated server
- your game version matches the server version
- you are using the current build/repository version
- a VPN or proxy is not interfering with UDP traffic

If possible, try another Internet connection such as a mobile hotspot.

Some school, office, public, or restricted networks may filter unusual UDP traffic.

---

# 7. Check Your Game Version

If you run the project from Git, open a terminal in the repository and run:

```bash
git log -1 --oneline
```

Compare the displayed commit with the server owner's current test version.

Also check:

```bash
git status
```

If your local project contains networking modifications that are different from the server version, multiplayer may not work correctly.

---

# 8. Windows Firewall

For a normal client connection, Windows usually allows the outbound traffic automatically.

If Windows displays a firewall prompt for Godot or Beacon Bay, allow the application on the network profile you are using.

If you run from Godot, the firewall entry may appear as:

```text
Godot
Godot Engine
godot.exe
```

If you use the exported build, it may appear as Beacon Bay or as the exported executable.

Do not disable Windows Firewall permanently just to make the game work.

---

# 9. Check Your Public IP

This is normally needed only when troubleshooting with the server owner.

On Windows PowerShell:

```powershell
curl ifconfig.me
```

Alternative:

```powershell
(Invoke-WebRequest -UseBasicParsing https://api.ipify.org).Content
```

This shows the public Internet address used by your current network.

The server owner can compare it with the traffic arriving at the dedicated server.

---

# 10. Two Players on the Same Wi-Fi

Two players connected through the same home/router network may appear to have the same public IP.

That is normal.

For example:

```text
Player A -> 203.0.113.10:52001
Player B -> 203.0.113.10:52002
```

The router uses NAT and different UDP source ports to keep the connections separate.

Players do not need separate public IP addresses.

---

# 11. When Reporting a Connection Problem

Send the server owner:

```text
1. What happens after pressing Join
2. Any error message shown by the game
3. Whether you run the exported game or Godot
4. Your current Git commit, if running from source
5. Whether you use a VPN
6. Whether another network/mobile hotspot changes the result
7. Your public IP, if the server owner asks for it
```

Do not send private SSH keys, passwords, Azure credentials, or account tokens.

---

# 12. Quick Player Checklist

Before asking for deeper troubleshooting:

```text
[ ] Server owner says the server is running
[ ] I have the correct server IP
[ ] I selected Join
[ ] I am using the current game version
[ ] I entered the address correctly
[ ] VPN/proxy is disabled for the test
[ ] I tried reconnecting once
```

If the problem continues, contact the server owner.

---

# Optional: Hosting Your Own Dedicated Server

The following section is for developers or groups that want to host their own Beacon Bay server.

The examples intentionally use placeholders rather than credentials from the main development server.

---

# 13. Dedicated Server Requirements

A small Linux VM is sufficient for the current Beacon Bay dedicated server.

A typical setup is:

```text
OS: Ubuntu Server 24.04 LTS
Architecture: x86_64
CPU: 1–2 vCPU
RAM: approximately 1 GiB or more
Network: public IPv4 address
Game port: UDP 24680
```

A graphical desktop environment is not required.

Beacon Bay runs headlessly.

---

# 14. Azure Example

Create a Linux virtual machine in Azure.

Example configuration:

```text
Resource group: <YOUR_RESOURCE_GROUP>
VM name: <YOUR_VM_NAME>
Region: <AVAILABLE_REGION>
Image: Ubuntu Server 24.04 LTS
Architecture: x64
Authentication: SSH public key
Public IP: Enabled
```

Choose a VM size appropriate for your budget and Azure subscription.

Azure Student or organization-managed subscriptions may restrict available regions or VM sizes.

---

# 15. Open UDP Port 24680

In the Azure VM networking settings, create an inbound Network Security Group rule.

Recommended values:

```text
Source: Any
Source port ranges: *
Destination: Any
Destination port: 24680
Protocol: UDP
Action: Allow
```

You may further restrict the source addresses if your deployment requires stricter access control.

Do not expose unnecessary ports.

---

# 16. Connect to Your Server With SSH

From your local computer:

```bash
ssh -i "<PATH_TO_PRIVATE_KEY>" <SSH_USER>@<SERVER_IP>
```

Example using placeholders:

```bash
ssh -i "./server_key.pem" gameadmin@203.0.113.50
```

Never commit your private SSH key to Git.

Never publish it in documentation.

---

# 17. Create a Server Directory

On the Linux VM:

```bash
mkdir -p ~/beaconbay
cd ~/beaconbay
```

---

# 18. Build the Linux Server

Export the current Beacon Bay project using the Linux dedicated-server export preset.

The output should include files similar to:

```text
BeaconBay.x86_64
BeaconBay.pck
```

The exact export location depends on your local project configuration.

The server build should come from the same source version used by the clients.

---

# 19. Upload the Server Build

From your local computer:

```bash
scp -i "<PATH_TO_PRIVATE_KEY>" "<LOCAL_PATH>/BeaconBay.x86_64" <SSH_USER>@<SERVER_IP>:/home/<SSH_USER>/beaconbay/
```

Then:

```bash
scp -i "<PATH_TO_PRIVATE_KEY>" "<LOCAL_PATH>/BeaconBay.pck" <SSH_USER>@<SERVER_IP>:/home/<SSH_USER>/beaconbay/
```

Example structure only:

```bash
scp -i "./server_key.pem" "./build/server/BeaconBay.x86_64" gameadmin@203.0.113.50:/home/gameadmin/beaconbay/
scp -i "./server_key.pem" "./build/server/BeaconBay.pck" gameadmin@203.0.113.50:/home/gameadmin/beaconbay/
```

---

# 20. Start the Dedicated Server

SSH into the VM:

```bash
cd ~/beaconbay
```

Make the Linux executable runnable:

```bash
chmod +x BeaconBay.x86_64
```

Start Beacon Bay:

```bash
./BeaconBay.x86_64 --headless --server
```

Expected startup output is similar to:

```text
Beacon Bay dedicated server: UDP 24680; waiting for a player to start (1-4 players).
```

Keep the terminal open during a simple test session.

For long-running deployments, consider a process manager or system service later.

---

# 21. Check Whether the Port Is Listening

On the Linux server:

```bash
sudo ss -lunp | grep 24680
```

If the dedicated server is running correctly, UDP port `24680` should appear.

---

# 22. Watch Connection Traffic

For troubleshooting, install `tcpdump`:

```bash
sudo apt update
sudo apt install -y tcpdump
```

Watch Beacon Bay packets:

```bash
sudo tcpdump -ni any udp port 24680
```

Then ask a player to press **Join**.

Stop monitoring with:

```text
Ctrl+C
```

---

# 23. How to Interpret Network Traffic

If no traffic appears when a player presses Join:

```text
Client traffic is probably not reaching the server.
```

Check:

- server address
- UDP rule
- player's network
- VPN/firewall
- whether the game is sending to port 24680

If incoming and outgoing packets both appear:

```text
Client <-> Azure/network path is functioning
```

At that point, investigate:

- client/server version mismatch
- Godot ENet connection handling
- application-level handshake
- multiplayer session state
- server logs

Do not keep changing cloud firewall settings when packet capture already confirms two-way traffic.

---

# 24. Restart Between Test Sessions

The current Beacon Bay dedicated-server implementation may retain the completed game state.

For a new clean test:

```text
Ctrl+C
```

Then restart:

```bash
./BeaconBay.x86_64 --headless --server
```

Players should reconnect after the restart.

---

# 25. Keep Client and Server Versions Synchronized

Before a multiplayer test, developers should commit and share the test version.

Typical workflow:

```bash
git status
git add .
git commit -m "update multiplayer test build"
git push
```

Other developers:

```bash
git pull
git log -1 --oneline
```

An exported server built from uncommitted local changes may not match another developer's supposedly "up-to-date" repository.

For non-developer testers, distributing one exported client package is usually safer.

---

# 26. Security Notes for Public Repositories

Do not commit or publish:

```text
private SSH keys
passwords
Azure access tokens
subscription IDs unless intentionally public
private account information
local credential files
personal file-system paths
```

Safe public documentation should use placeholders such as:

```text
<SERVER_IP>
<SSH_USER>
<YOUR_VM_NAME>
<YOUR_RESOURCE_GROUP>
<PATH_TO_PRIVATE_KEY>
```

The public IP of a game server may be shared intentionally with players, but decide separately whether you want it permanently stored in a public Git repository.

---

# 27. Public Server Quick Reference

Player connection:

```text
Mode: Join
Address: <SERVER_IP>
Protocol: UDP
Port: 24680
Players: 1–4
```

Linux server startup:

```bash
cd ~/beaconbay
chmod +x BeaconBay.x86_64
./BeaconBay.x86_64 --headless --server
```

Check listening port:

```bash
sudo ss -lunp | grep 24680
```

Watch traffic:

```bash
sudo tcpdump -ni any udp port 24680
```

The server owner should provide the active server address separately.
