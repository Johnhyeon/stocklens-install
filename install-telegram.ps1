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

# PowerShell 7.3+ 는 native 명령이 0이 아닌 코드로 끝나면 $ErrorActionPreference='Stop'
# 때문에 그 줄에서 스크립트를 즉시 중단해, 아래 `if ($LASTEXITCODE -ne 0)` [FAIL]
# 메시지까지 도달하지 못하고 "조용히 끝난" 것처럼 보인다. 모든 native 호출 뒤에
# 직접 $LASTEXITCODE 를 검사하므로 이 자동 중단을 꺼서 에러를 표면화한다.
# (Windows PowerShell 5.1 에는 이 변수가 없어 무해하게 무시된다.)
$PSNativeCommandUseErrorActionPreference = $false

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

# Claude 클라이언트(Desktop 앱 또는 Code CLI) 설치 여부 사전 확인.
# 둘 다 없으면 setup 은 빈 config 폴더만 만들고 "성공"으로 끝나는데, 읽을 앱이 없어
# TelegramLens 가 동작하지 않는다. 조용한 실패를 막기 위해 경고한다.
$hasDesktopApp = (Test-Path (Join-Path $env:APPDATA "Claude")) -or `
    (Get-ChildItem (Join-Path $env:LOCALAPPDATA "Packages") -Filter "*Claude*" -Directory -ErrorAction SilentlyContinue)
$hasCodeCli = $null -ne (Get-Command claude -ErrorAction SilentlyContinue)
if (-not $hasDesktopApp -and -not $hasCodeCli) {
    Warn "      [WARN] Claude Desktop / Claude Code 가 설치된 흔적이 없습니다."
    Warn "             MCP 설정은 진행하지만, Claude Desktop 을 먼저 설치해야 동작합니다."
    Warn "             다운로드: https://claude.ai/download"
    Warn "             설치 후 이 스크립트를 다시 실행하거나 'telegramlens-setup' 을 한 번 더 돌리세요."
    Write-Host ""
}

$setupExe = Join-Path $LocalBin "telegramlens-setup.exe"

# 갓 설치된 미서명 exe 의 "첫 실행"은 Windows Defender/SmartScreen 스캔이나 uv 의
# 도구 환경 마무리 때문에 1회성으로 실패할 수 있다(두 번째부터는 사라짐). 그래서
# 첫 시도가 실패하면 잠깐 쉬고 1회 자동 재시도한 뒤에야 [FAIL] 로 종료한다.
$maxAttempts = 2
$setupOk = $false
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    $reason = $null
    try {
        if (Test-Path $setupExe) {
            & $setupExe
        } else {
            & uv tool run --from telegramlens-mcp telegramlens-setup
        }
        if ($LASTEXITCODE -eq 0) { $setupOk = $true; break }
        $reason = "exit $LASTEXITCODE"
    } catch {
        $reason = "$_"
    }
    if ($attempt -lt $maxAttempts) {
        Warn "      [RETRY] telegramlens-setup 첫 시도 실패 ($reason). 3초 후 재시도... ($attempt/$maxAttempts)"
        Start-Sleep -Seconds 3
    }
}
if (-not $setupOk) {
    Err "      [FAIL] telegramlens-setup failed after $maxAttempts attempts ($reason)."
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
