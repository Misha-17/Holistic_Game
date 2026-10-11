param(
    [string]$GodotConsole = 'C:\Users\singh\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe',
    [string]$GodotGui = 'C:\Users\singh\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$artifactRoot = Join-Path $projectRoot 'artifacts'
$desktopRoot = Join-Path $artifactRoot 'BeaconBay-0.8.0'
$serverRoot = Join-Path $artifactRoot 'AzureServer-0.8.0'
New-Item -ItemType Directory -Force -Path $desktopRoot,$serverRoot | Out-Null
Set-Content -LiteralPath (Join-Path $artifactRoot '.gdignore') -Value ''
$env:APPDATA = Join-Path $projectRoot '.test-user'
$env:LOCALAPPDATA = $env:APPDATA
function Run-Godot([string]$name, [string[]]$arguments) {
    $log = Join-Path $artifactRoot ($name + '.log')
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $GodotConsole @arguments *> $log
    $engineExit = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($engineExit -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Failed to export' -Quiet)) {
        throw "Godot failed: $name. See $log"
    }
}
Run-Godot 'import' @('--headless','--path',$projectRoot,'--editor','--import')
Run-Godot 'desktop-export' @('--headless','--path',$projectRoot,'--export-pack','Windows Desktop',(Join-Path $desktopRoot 'BeaconBay.pck'))
Run-Godot 'server-export' @('--headless','--path',$projectRoot,'--export-pack','Linux Server',(Join-Path $serverRoot 'BeaconBay.pck'))
Copy-Item -LiteralPath $GodotGui -Destination (Join-Path $desktopRoot 'BeaconBay.exe')
@'
@echo off
cd /d "%~dp0"
start "Beacon Bay" "%~dp0BeaconBay.exe" --main-pack "%~dp0BeaconBay.pck"
'@ | Set-Content -LiteralPath (Join-Path $desktopRoot 'Play.cmd') -Encoding ascii
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination $desktopRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'ASSET_CREDITS.md') -Destination $desktopRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'licenses') -Destination $desktopRoot -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'azure-connect.md') -Destination $serverRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'deployment/beacon-bay.service') -Destination $serverRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'deployment/start-server.sh') -Destination $serverRoot
Compress-Archive -LiteralPath $desktopRoot -DestinationPath (Join-Path $artifactRoot 'BeaconBay-Windows-0.8.0.zip') -Force
Compress-Archive -LiteralPath $serverRoot -DestinationPath (Join-Path $artifactRoot 'BeaconBay-AzureServer-0.8.0.zip') -Force
# Source archive only includes source-controlled and eligible new files, never
# recordings, editor cache, credentials, old builds or .git metadata.
Add-Type -AssemblyName System.IO.Compression
$sourceZip = Join-Path $artifactRoot 'BeaconBay-Source-0.8.0.zip'
$stream = [IO.File]::Open($sourceZip, [IO.FileMode]::Create)
$archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
    $files = & git -C $projectRoot ls-files --cached --others --exclude-standard
    foreach ($relative in $files | Sort-Object -Unique) {
        if ($relative -match '(^|/)\.git(/|$)|\.import$|^\.test-user/|^test_output/|^artifacts/') { continue }
        $source = Join-Path $projectRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $entry = $archive.CreateEntry('BeaconBay-Source/' + $relative, [IO.Compression.CompressionLevel]::Optimal)
        $inputStream = [IO.File]::OpenRead($source)
        $outputStream = $entry.Open()
        try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
    }
} finally { $archive.Dispose(); $stream.Dispose() }
Write-Output "Packages ready in $artifactRoot"
