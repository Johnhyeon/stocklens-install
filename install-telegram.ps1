# telegramlens Installer (Windows · PowerShell)
# Usage:
#   powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Johnhyeon/stocklens-install/main/install-telegram.ps1 | iex"
#
# 4 steps:
#   1) uv (Python package manager)  — auto-installs Python runtime if missing
#   2) telegramlens-mcp via `uv tool install`
#   3) Claude Desktop config via `telegramlens-setup`
#   4) License activation via `telegramlens-activate`
#
# 마지막으로 사용자가 직접 `telegramlens-login` 을 실행해 텔레그램 로그인을 완료한다.
# (API 키 발급용 브라우저 + 전화 인증이 필요해 파이프 설치 안에서 돌리지 않는다.)

$ErrorActionPreference = 'Stop'

$ESC = [char]27
function Info($msg)  { Write-Host "$ESC[36m$msg$ESC[0m" }
function OK($msg)    { Write-Host "$ESC[32m$msg$ESC[0m" }
function Warn($msg)  { Write-Host "$ESC[33m$msg$ESC[0m" }
function Err($msg)   { Write-Host "$ESC[31m$msg$ESC[0m" }

Write-Host ""
Write-Host "=============================================="
Write-Host "  telegramlens Installer (Windows)"
Write-Host "=============================================="
Write-Host ""

$LocalBin = Join-Path $env:USERPROFILE ".local\bin"

# ── [1/4] uv ─────────────────────────────────────────────
Info "[1/4] Checking uv..."
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uvCmd) {
    Info "      uv not found. Installing from astral.sh..."
    try {
        Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    } catch {
        Err "      [FAIL] uv installation failed: $_"
        Err "      Manual install: https://docs.astral.sh/uv/getting-started/installation/"
        exit 1
    }
    if (Test-Path $LocalBin) {
        $env:Path = "$LocalBin;$env:Path"
    }
    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uvCmd) {
        Err "      [FAIL] uv installed but not on PATH. Open a new PowerShell and re-run."
        exit 1
    }
    OK "      uv installed: $($uvCmd.Source)"
} else {
    OK "      uv found: $($uvCmd.Source)"
}
Write-Host ""

# ── [2/4] telegramlens-mcp ───────────────────────────────
Info "[2/4] Installing telegramlens-mcp..."

# --force re-creates the tool environment, so re-running upgrades cleanly.
& uv tool install --force telegramlens-mcp
if ($LASTEXITCODE -ne 0) {
    Err "      [FAIL] uv tool install failed."
    exit 1
}
OK "      telegramlens-mcp installed via uv tool"
Write-Host ""

# Ensure .local\bin is on PATH for the rest of this session
if (Test-Path $LocalBin -PathType Container) {
    if (-not ($env:Path -split ';' -contains $LocalBin)) {
        $env:Path = "$LocalBin;$env:Path"
    }
}

# ── [3/4] MCP target config ──────────────────────────────
# $env:TELEGRAMLENS_TARGET 으로 등록 대상 지정: claude-desktop / claude-code / both / auto
if (-not $env:TELEGRAMLENS_TARGET) { $env:TELEGRAMLENS_TARGET = "auto" }

Info "[3/4] Configuring MCP (target=$($env:TELEGRAMLENS_TARGET))..."
$setupExe = Join-Path $LocalBin "telegramlens-setup.exe"
if (Test-Path $setupExe) {
    & $setupExe
} else {
    & uv tool run --from telegramlens-mcp telegramlens-setup
}
if ($LASTEXITCODE -ne 0) {
    Err "      [FAIL] telegramlens-setup failed."
    exit 1
}
Write-Host ""

# ── [4/4] License activation ─────────────────────────────
Info "[4/4] License activation..."
Write-Host "      Enter the license key sent to your email after purchase."
$activateExe = Join-Path $LocalBin "telegramlens-activate.exe"
$licKey = (Read-Host "      License key").Trim()
if ($licKey) {
    if (Test-Path $activateExe) {
        & $activateExe $licKey
    } else {
        & uv tool run --from telegramlens-mcp telegramlens-activate $licKey
    }
    if ($LASTEXITCODE -ne 0) {
        Warn "      Activation failed. Check the key and retry: telegramlens-activate <LICENSE-KEY>"
    }
} else {
    Warn "      Skipped. Activate later: telegramlens-activate <LICENSE-KEY>"
}
Write-Host ""

Write-Host "=============================================="
OK     "  Install complete - 마지막 1단계가 남았습니다"
Write-Host "=============================================="
Write-Host ""
Warn   "  [필수] 텔레그램 로그인 (이 창에서 바로 실행하세요)"
Write-Host ""
Write-Host "    telegramlens-login"
Write-Host ""
Write-Host "  - 실행하면 텔레그램 API 키 발급용 브라우저가 열립니다."
Write-Host "  - 안내에 따라 API_ID/API_HASH 입력 후 전화번호로 로그인하세요."
Write-Host "  - 로그인을 마쳐야 채널 수집이 시작됩니다."
Write-Host ""
Write-Host "  로그인 후:"
Write-Host "    1. Claude Desktop을 완전히 종료(트레이 아이콘 -> Quit) 후 재실행"
Write-Host "    2. Claude에서 'telegram_status' 로 수집 상태 확인"
Write-Host ""
Write-Host "Activate:      telegramlens-activate <LICENSE-KEY>"
Write-Host "Login:         telegramlens-login"
Write-Host "Update later:  uv tool upgrade telegramlens-mcp"
Write-Host ""

# 편의: 지금 바로 로그인할지 물어보고, 동의하면 이 창에서 실행한다(stdin=콘솔이라 정상 동작).
$go = (Read-Host "지금 바로 telegramlens-login 을 실행할까요? (Y/n)").Trim()
if ($go -eq "" -or $go -match '^[Yy]') {
    Write-Host ""
    $loginExe = Join-Path $LocalBin "telegramlens-login.exe"
    if (Test-Path $loginExe) {
        & $loginExe
    } else {
        & uv tool run --from telegramlens-mcp telegramlens-login
    }
}
