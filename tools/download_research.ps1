# Download every study session the game server has received.
#   powershell -ExecutionPolicy Bypass -File tools/download_research.ps1 -Server <server IP>
# Needs SSH access to the server (the same key as for deploying the game).
# Files arrive as research_downloads\<session>\<pc>\events\... and \voice\...
# Running it again only copies what is new or changed (scp copies again; use
# the same destination folder).
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [string]$User = 'beacondev',
    [string]$RemoteFolder = '/opt/beaconbay/research_uploads',
    [string]$Destination = '.\research_downloads'
)
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
scp -r "${User}@${Server}:${RemoteFolder}/*" $Destination
if ($LASTEXITCODE -ne 0) { throw "Download failed. Check the server address, your SSH key and that a study session has been played." }
Write-Host "Study files are in $((Resolve-Path $Destination).Path)"
