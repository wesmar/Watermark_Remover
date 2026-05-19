$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Building SignGuiPatcher (x64 MASM)"         -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$VSBASE  = "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.50.35717\bin\Hostx64"
$ML64    = "$VSBASE\x64\ml64.exe"
$LINK64  = "$VSBASE\x64\link.exe"
$DUMPBIN = "$VSBASE\x64\dumpbin.exe"

$SDKBASE    = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.22621.0"
$SDKBIN     = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64"
$SDKINCLUDE = "C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0"
$LIBPATH    = "$SDKBASE\um\x64"

$env:PATH    += ";$SDKBIN"
$env:INCLUDE  = "$SDKINCLUDE\um;$SDKINCLUDE\shared"

$OUTDIR = Join-Path $ScriptDir "bin"
if (-not (Test-Path $OUTDIR)) { New-Item -ItemType Directory -Path $OUTDIR | Out-Null }

$BuildSuccess = $true

$FILES = @("strutil", "token", "patch", "window", "cli", "main")

Push-Location $ScriptDir

# Compile resource
Write-Host ""
Write-Host ">>> Compiling resources..." -ForegroundColor Cyan
& rc /c65001 /I "$SDKINCLUDE\um" /I "$SDKINCLUDE\shared" /fo sp.res sp.rc
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: rc.exe failed" -ForegroundColor Red
    $BuildSuccess = $false
}

if ($BuildSuccess) {
    Write-Host ""
    Write-Host ">>> Assembling modules..." -ForegroundColor Cyan
    foreach ($f in $FILES) {
        Write-Host "    $f.asm" -ForegroundColor Gray
        & $ML64 /c /Cp /Cx /Zi /I x64 /Fo "x64\$f.obj" "x64\$f.asm"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: ml64 failed on $f.asm" -ForegroundColor Red
            $BuildSuccess = $false
            break
        }
    }
}

if ($BuildSuccess) {
    Write-Host ""
    Write-Host ">>> Linking..." -ForegroundColor Cyan

    $objs = $FILES | ForEach-Object { "x64\$_.obj" }

    $linkArgs = $objs + @(
        "sp.res",
        "/subsystem:windows",
        "/entry:mainCRTStartup",
        "/nodefaultlib",
        "/Brepro",
        "/out:bin\SignGuiPatcher.exe",
        "/MANIFEST:EMBED",
        "/MANIFESTINPUT:sp.manifest",
        "/MANIFESTUAC:level='requireAdministrator' uiAccess='false'",
        "/LIBPATH:$LIBPATH",
        "kernel32.lib",
        "user32.lib",
        "advapi32.lib",
        "shlwapi.lib",
        "shell32.lib",
        "dwmapi.lib",
        "gdi32.lib",
        "cabinet.lib"
    )

    & $LINK64 $linkArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: link.exe failed" -ForegroundColor Red
        $BuildSuccess = $false
    }
}

# Verify import table
if ($BuildSuccess) {
    Write-Host ""
    Write-Host ">>> Verifying imports with dumpbin..." -ForegroundColor Cyan

    $exePath = "bin\SignGuiPatcher.exe"
    $imports = & $DUMPBIN /imports $exePath
    $dependents = & $DUMPBIN /dependents $exePath

    $blockedImportPatterns = @(
        "msvcr",
        "vcruntime",
        "ucrtbase",
        "rstrtmgr"
    )

    $blockedFound = $imports | Select-String ($blockedImportPatterns -join "|")
    if ($blockedFound) {
        $blockedFound | ForEach-Object { Write-Host "ERROR: blocked import detected: $_" -ForegroundColor Red }
        $BuildSuccess = $false
    } else {
        Write-Host "[PASS] No CRT or Restart Manager imports" -ForegroundColor Green
    }

    $allowedDlls = @(
        "ADVAPI32.dll",
        "CABINET.dll",
        "DWMAPI.dll",
        "GDI32.dll",
        "KERNEL32.dll",
        "SHELL32.dll",
        "SHLWAPI.dll",
        "USER32.dll"
    )

    $actualDlls = $dependents |
        ForEach-Object {
            if ($_ -match "^\s*([A-Za-z0-9_.-]+\.dll)\s*$") {
                $matches[1]
            }
        } |
        Sort-Object -Unique

    $unexpectedDlls = $actualDlls | Where-Object { $allowedDlls -notcontains $_ }
    if ($unexpectedDlls) {
        $unexpectedDlls | ForEach-Object { Write-Host "ERROR: unexpected dependent DLL: $_" -ForegroundColor Red }
        $BuildSuccess = $false
    } else {
        Write-Host "[PASS] Dependent DLL set is expected" -ForegroundColor Green
    }

    Write-Host "      Dependents: $($actualDlls -join ', ')" -ForegroundColor Gray

    if ($BuildSuccess) {
        Write-Host "[PASS] Import verification complete" -ForegroundColor Green
    }
}

Pop-Location

# Cleanup
Write-Host ""
Write-Host ">>> Cleaning intermediates..." -ForegroundColor Yellow
Remove-Item "$ScriptDir\x64\*.obj" -ErrorAction SilentlyContinue
Remove-Item "$ScriptDir\*.res"     -ErrorAction SilentlyContinue

Write-Host ""
if ($BuildSuccess) {
    $size = (Get-Item "$ScriptDir\bin\SignGuiPatcher.exe").Length
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "STATUS: SUCCESS  →  sp\bin\SignGuiPatcher.exe  ($size bytes)" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    exit 0
} else {
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "STATUS: FAILED"                              -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    exit 1
}
