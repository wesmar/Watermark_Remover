#Requires -Version 5.1
<#
.SYNOPSIS
    Master build script for SignGuiPatcher.

.DESCRIPTION
    Orchestrates the full build pipeline:
      [1/3]  ExplorerFrame\build.ps1       — assembles & links ExplorerFrame.dll
      [2/3]  inline — CAB-compresses DLL and embeds it into
                                             WaterMarkRemover\x64\ICON\SignGuiPatcher.ico
      [3/3]  WaterMarkRemover\build.ps1    — assembles & links SignGuiPatcher.exe

    All paths are relative to this script's location.
    Individual sub-builds remain independently runnable from their own directories.

.PARAMETER SkipEF
    Skip step 1 (ExplorerFrame build). Useful when the DLL is already up to date.

.PARAMETER SkipPkg
    Skip step 2 (icon packaging). Useful when the icon is already up to date.

.PARAMETER SkipWMR
    Skip step 3 (WaterMarkRemover build).

.EXAMPLE
    .\build.ps1
    .\build.ps1 -SkipEF          # reuse existing DLL, repackage + rebuild EXE
    .\build.ps1 -SkipEF -SkipPkg # only rebuild the EXE
#>
param(
    [switch]$SkipEF,
    [switch]$SkipPkg,
    [switch]$SkipWMR
)

$ErrorActionPreference = "Stop"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-Step {
    param(
        [string]$Label,
        [string]$Step,
        [scriptblock]$Action
    )
    Write-Host ""
    Write-Host "════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Step  $Label"                              -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "  ABORTED at: $Label"                        -ForegroundColor Red
        Write-Host "════════════════════════════════════════════" -ForegroundColor Red
        exit 1
    }
}

$StartTime = Get-Date

# ── [1/3] ExplorerFrame ──────────────────────────────────────────────────────
if ($SkipEF) {
    Write-Host ""
    Write-Host "[1/3] ExplorerFrame — SKIPPED" -ForegroundColor DarkGray
    $DllPath = "$Root\ExplorerFrame\bin\ExplorerFrame.dll"
    if (-not (Test-Path $DllPath)) {
        Write-Host "ERROR: DLL not found at $DllPath  (cannot skip a missing artifact)" -ForegroundColor Red
        exit 1
    }
} else {
    Invoke-Step -Step "[1/3]" -Label "ExplorerFrame DLL" -Action {
        & "$Root\ExplorerFrame\build.ps1"
    }
}

# ── [2/3] Package DLL → icon ────────────────────────────────────────────────
if ($SkipPkg) {
    Write-Host ""
    Write-Host "[2/3] Package DLL -> icon — SKIPPED" -ForegroundColor DarkGray
} else {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  [2/3]  Package DLL -> icon"                -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    $DllFile    = "$Root\ExplorerFrame\bin\ExplorerFrame.dll"
    $IconFile   = "$Root\IcoBuilder\SignGuiPatcher.ico"
    $OutputFile = "$Root\WaterMarkRemover\x64\ICON\SignGuiPatcher.ico"
    $ICON_SIZE  = 1662

    Write-Host "  DLL    : $DllFile"    -ForegroundColor Gray
    Write-Host "  Icon   : $IconFile"   -ForegroundColor Gray
    Write-Host "  Output : $OutputFile" -ForegroundColor Gray
    Write-Host ""

    foreach ($f in @($DllFile, $IconFile)) {
        if (-not (Test-Path $f)) {
            Write-Host "ERROR: file not found: $f" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host ">>> Compressing DLL (makecab LZX)..." -ForegroundColor Cyan

    $TempDir = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "sgp_ico_$([System.IO.Path]::GetRandomFileName())"
    )
    New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

    $TempDll = Join-Path $TempDir "ExplorerFrame.dll"
    Copy-Item $DllFile $TempDll -Force

    $DdfContent = ".Set CabinetNameTemplate=ef.cab`r`n" +
                  ".Set DiskDirectoryTemplate=$TempDir`r`n" +
                  ".Set CompressionType=LZX`r`n" +
                  ".Set CompressionMemory=21`r`n" +
                  ".Set MaxCabinetSize=0`r`n" +
                  ".Set Cabinet=on`r`n" +
                  ".Set Compress=on`r`n" +
                  "`"$TempDll`" ExplorerFrame.dll`r`n"

    $DdfPath = Join-Path $TempDir "pkg.ddf"
    [System.IO.File]::WriteAllText($DdfPath, $DdfContent, [System.Text.Encoding]::ASCII)

    $proc = Start-Process -FilePath "makecab.exe" `
        -ArgumentList "/F", "`"$DdfPath`"" `
        -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "ERROR: makecab.exe failed (exit $($proc.ExitCode))" -ForegroundColor Red
        exit 1
    }

    $CabPath = Join-Path $TempDir "ef.cab"
    if (-not (Test-Path $CabPath)) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "ERROR: CAB not created at $CabPath" -ForegroundColor Red
        exit 1
    }

    $DllSize = (Get-Item $DllFile).Length
    $CabSize = (Get-Item $CabPath).Length
    Write-Host "    DLL $DllSize b  ->  CAB $CabSize b  (saved $($DllSize - $CabSize) b)" -ForegroundColor Gray

    Write-Host ">>> Building icon+CAB payload..." -ForegroundColor Cyan

    $IcoBytes = [System.IO.File]::ReadAllBytes($IconFile)
    if ($IcoBytes.Length -lt $ICON_SIZE) {
        Write-Host "ERROR: icon is $($IcoBytes.Length) b; need >= $ICON_SIZE" -ForegroundColor Red
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }
    $IconHeader = $IcoBytes[0..($ICON_SIZE - 1)]
    $CabBytes   = [System.IO.File]::ReadAllBytes($CabPath)

    $Combined = [byte[]]::new($IconHeader.Length + $CabBytes.Length)
    [Array]::Copy($IconHeader, 0, $Combined, 0,                  $IconHeader.Length)
    [Array]::Copy($CabBytes,   0, $Combined, $IconHeader.Length, $CabBytes.Length)

    [System.IO.File]::WriteAllBytes($OutputFile, $Combined)
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "============================================"                           -ForegroundColor Green
    Write-Host "  STATUS: SUCCESS"                                                      -ForegroundColor Green
    Write-Host "  Output : $OutputFile"                                                 -ForegroundColor Green
    Write-Host "  Layout : icon=$ICON_SIZE b + CAB=$CabSize b = $($Combined.Length) b" -ForegroundColor Green
    Write-Host "============================================"                           -ForegroundColor Green
}

# ── [3/3] WaterMarkRemover ───────────────────────────────────────────────────
if ($SkipWMR) {
    Write-Host ""
    Write-Host "[3/3] WaterMarkRemover — SKIPPED" -ForegroundColor DarkGray
} else {
    Invoke-Step -Step "[3/3]" -Label "SignGuiPatcher.exe" -Action {
        & "$Root\WaterMarkRemover\build.ps1"
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────
$Elapsed = (Get-Date) - $StartTime
Write-Host ""
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  BUILD COMPLETE  ($([int]$Elapsed.TotalSeconds)s)"  -ForegroundColor Green

$ExePath = "$Root\WaterMarkRemover\bin\SignGuiPatcher.exe"
if (Test-Path $ExePath) {
    $Size = (Get-Item $ExePath).Length
    Write-Host "  Output: WaterMarkRemover\bin\SignGuiPatcher.exe  ($Size bytes)" -ForegroundColor Green
}
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
