# MSHV build helper for this Windows machine.
#
# What this script does:
# 1) Moves to the repository root (folder where this script lives).
# 2) Adds the known Qt/MinGW tool folders to PATH for this session.
# 3) Regenerates the Makefile with qmake so new sources are included.
# 4) Runs a parallel release build (mingw32-make -j4 release).
# 5) Prints success/failure and exits with the same build status code.

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# Resolve repo root from script location so it works no matter where it is launched from.
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RepoRoot

# Tool locations used by this machine.
$QtBin = 'C:\QT\5.15.2\mingw81_64\bin'
$MingwBin = 'C:\QT\Tools\mingw810_64\bin'

# Prepend tool folders to PATH only if they exist.
if (Test-Path $QtBin) {
    $env:PATH = "$QtBin;$env:PATH"
}
if (Test-Path $MingwBin) {
    $env:PATH = "$MingwBin;$env:PATH"
}

Write-Host "Building MSHV (release) from: $RepoRoot" -ForegroundColor Cyan

# Regenerate the Makefile before building so qmake picks up new files.
& qmake MSHV_WIN64.pro -o Makefile
if ($LASTEXITCODE -ne 0) {
    Write-Host "qmake failed with exit code $LASTEXITCODE." -ForegroundColor Red
    exit $LASTEXITCODE
}

# Run release build.
& mingw32-make -j4 release
$BuildExitCode = $LASTEXITCODE

if ($BuildExitCode -eq 0) {
    Write-Host 'Build completed successfully.' -ForegroundColor Green
} else {
    Write-Host "Build failed with exit code $BuildExitCode." -ForegroundColor Red
}

exit $BuildExitCode
