<#
.SYNOPSIS
Build Chibi for Windows and Android using the project's Godot export presets.

.EXAMPLE
.\tools\build.ps1

.EXAMPLE
.\tools\build.ps1 -Target Android -GodotPath 'C:\Tools\Godot\Godot_console.exe'

.NOTES
Install the export templates for your Godot version. For Android, configure Java SDK Path
and Android SDK Path in Godot's Editor Settings, or provide JAVA_HOME and ANDROID_HOME
if Godot has no configured overrides. The APK uses Godot's debug signer for sideloading.
#>
[CmdletBinding()]
param(
    [ValidateSet('All', 'Windows', 'Android')]
    [string]$Target = 'All',

    [string]$GodotPath = $env:GODOT_PATH
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not $GodotPath) {
    $command = Get-Command godot, godot4 -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        $GodotPath = $command.Source
    } elseif ($env:USERPROFILE) {
        $godotFolder = Join-Path $env:USERPROFILE 'Downloads/Godot'
        $download = Get-ChildItem -LiteralPath $godotFolder -Filter 'Godot_*_console.exe' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($download) {
            $GodotPath = $download.FullName
        }
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot editor executable not found. Pass -GodotPath or set GODOT_PATH to its full path.'
}
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).ProviderPath
if ($GodotPath -like '*.exe' -and $GodotPath -notlike '*_console.exe') {
    $consolePath = [IO.Path]::ChangeExtension($GodotPath, $null) + '_console.exe'
    if (Test-Path -LiteralPath $consolePath -PathType Leaf) {
        $GodotPath = $consolePath
    }
}

$exports = @(
    @{ Target = 'Windows'; Preset = 'Windows Desktop'; Mode = '--export-release'; Folder = 'windows'; File = 'Chibi.exe' }
    @{ Target = 'Android'; Preset = 'Android'; Mode = '--export-debug'; Folder = 'android'; File = 'Chibi.apk' }
) | Where-Object { $Target -eq 'All' -or $Target -eq $_.Target }

$buildRoot = Join-Path $projectRoot 'builds'
$null = New-Item -Path $buildRoot -ItemType Directory -Force
$buildRoot = (Resolve-Path -LiteralPath $buildRoot).ProviderPath
$ignorePath = Join-Path $buildRoot '.gdignore'
if (-not (Test-Path -LiteralPath $ignorePath)) {
    $null = New-Item -Path $ignorePath -ItemType File
}

$lockPath = Join-Path $buildRoot '.build.lock'
try {
    $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    throw "Could not lock $buildRoot. Close other build processes and check directory access. $_"
}

$stageName = '.stage-' + [guid]::NewGuid().ToString('N')
$staging = Join-Path $buildRoot $stageName
$keepStage = $false
try {
    foreach ($export in $exports) {
        $stagedFolder = Join-Path $staging $export.Folder
        $null = New-Item -Path $stagedFolder -ItemType Directory -Force
        $stagedFile = Join-Path $stagedFolder $export.File

        Write-Host "Exporting $($export.Target)..."
        & $GodotPath --headless --path $projectRoot $($export.Mode) $($export.Preset) $stagedFile
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stagedFile -PathType Leaf)) {
            throw "$($export.Target) export failed. Check the Godot output, export templates, and platform SDK settings."
        }
        if ($export.Target -eq 'Windows' -and
                -not (Test-Path -LiteralPath (Join-Path $stagedFolder 'Chibi.pck') -PathType Leaf)) {
            throw 'Windows export did not produce Chibi.pck.'
        }
    }

    # Publish complete directories so Windows sidecar files stay with the executable.
    foreach ($export in $exports) {
        $published = Join-Path $buildRoot $export.Folder
        $previous = Join-Path $staging ('previous-' + $export.Folder)
        if (Test-Path -LiteralPath $published) {
            [IO.Directory]::Move($published, $previous)
        }

        try {
            [IO.Directory]::Move((Join-Path $staging $export.Folder), $published)
        } catch {
            if (Test-Path -LiteralPath $previous) {
                try {
                    [IO.Directory]::Move($previous, $published)
                } catch {
                    $keepStage = $true
                    Write-Warning "The previous build is at $previous."
                }
            }
            throw
        }
        Write-Host "Built $(Join-Path $published $export.File)"
    }
} finally {
    try {
        if (-not $keepStage -and (Test-Path -LiteralPath $staging -PathType Container)) {
            $resolvedStage = Get-Item -LiteralPath $staging -Force
            if (-not $resolvedStage.LinkType -and $resolvedStage.Parent.FullName -eq $buildRoot -and
                    $resolvedStage.Name -eq $stageName) {
                Remove-Item -LiteralPath $resolvedStage.FullName -Recurse -Force
            }
        }
    } finally {
        $lock.Dispose()
    }
}
