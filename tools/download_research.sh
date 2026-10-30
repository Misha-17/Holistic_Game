#!/usr/bin/env sh
# Download every study session the game server has received.
#   sh tools/download_research.sh <server IP> [destination folder]
# Needs SSH access to the server (the same key as for deploying the game).
set -eu
SERVER="${1:?usage: download_research.sh <server IP> [destination]}"
DEST="${2:-./research_downloads}"
REMOTE_USER="${REMOTE_USER:-beacondev}"
REMOTE_FOLDER="${REMOTE_FOLDER:-/opt/beaconbay/research_uploads}"
mkdir -p "$DEST"
if command -v rsync >/dev/null 2>&1; then
  rsync -av "$REMOTE_USER@$SERVER:$REMOTE_FOLDER/" "$DEST/"
else
  scp -r "$REMOTE_USER@$SERVER:$REMOTE_FOLDER/." "$DEST/"
fi
echo "Study files are in $DEST"
