# StockLens Installer (Windows · PowerShell)
# Usage:
#   powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Johnhyeon/stocklens-install/main/install.ps1 | iex"
#
# 3 steps:
#   1) uv (Python package manager)  — auto-installs Python runtime if missing
#   2) stocklens-mcp via `uv tool install`
#   3) Claude Desktop config via `stocklens-setup`

$ErrorActionPreference = 'Stop'

# PowerShell 7.3+ 는 native 명령이 0이 아닌 코드로 끝나면 $ErrorActionPreference='Stop'
# 때문에 그 줄에서 스크립트를 즉시 중단한다. 그러면 아래의 `if ($LASTEXITCODE -ne 0)`
# [FAIL] 메시지까지 도달하지 못하고 "조용히 끝난" 것처럼 보인다. 우리는 모든 native
# 호출 뒤에 직접 $LASTEXITCODE 를 검사하므로, 이 자동 중단을 꺼서 에러를 표면화한다.
# (Windows PowerShell 5.1 에는 이 변수가 없어 무해하게 무시된다.)
$PSNativeCommandUseErrorActionPreference = $false

$ESC = [char]27
function Info($msg)  { Write-Host "$ESC[36m$msg$ESC[0m" }
function OK($msg)    { Write-Host "$ESC[32m$msg$ESC[0m" }
function Warn($msg)  { Write-Host "$ESC[33m$msg$ESC[0m" }
function Err($msg)   { Write-Host "$ESC[31m$msg$ESC[0m" }

Write-Host ""
Write-Host "=============================================="
Write-Host "  StockLens Installer (Windows)"
Write-Host "=============================================="
Write-Host ""

$LocalBin = Join-Path $env:USERPROFILE ".local\bin"

# ── [1/3] uv ─────────────────────────────────────────────
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
    # uv installer adds %USERPROFILE%\.local\bin to user PATH for new shells.
    # Patch current session so the next steps see it immediately.
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

# ── [2/3] stocklens-mcp ──────────────────────────────────
Info "[2/4] Installing stocklens-mcp..."

# Idempotent install: --force re-creates the tool environment if it already exists,
# so re-running the script reliably upgrades to the latest PyPI version.
# uv tool은 격리 환경이라 시스템 pip의 옛 naver-stock-mcp가 남아있어도 충돌하지 않음.
& uv tool install --force stocklens-mcp
if ($LASTEXITCODE -ne 0) {
    Err "      [FAIL] uv tool install failed."
    exit 1
}
OK "      stocklens-mcp installed via uv tool"
Write-Host ""

# Ensure .local\bin is on PATH for the rest of this session
if (Test-Path $LocalBin -PathType Container) {
    if (-not ($env:Path -split ';' -contains $LocalBin)) {
        $env:Path = "$LocalBin;$env:Path"
    }
}

# ── [3/3] MCP target config ──────────────────────────────
# $env:STOCKLENS_TARGET 으로 등록 대상 지정: claude-desktop / claude-code / both / auto
if (-not $env:STOCKLENS_TARGET) { $env:STOCKLENS_TARGET = "auto" }

Info "[3/4] Configuring MCP (target=$($env:STOCKLENS_TARGET))..."

# Claude 클라이언트(Desktop 앱 또는 Code CLI) 설치 여부를 미리 확인.
# 둘 다 없으면 setup 은 빈 config 폴더만 만들고 "성공"으로 끝나는데, 정작 이를
# 읽을 앱이 없어 StockLens 가 동작하지 않는다. 조용한 실패를 막기 위해 경고한다.
$hasDesktopApp = (Test-Path (Join-Path $env:APPDATA "Claude")) -or `
    (Get-ChildItem (Join-Path $env:LOCALAPPDATA "Packages") -Filter "*Claude*" -Directory -ErrorAction SilentlyContinue)
$hasCodeCli = $null -ne (Get-Command claude -ErrorAction SilentlyContinue)
if (-not $hasDesktopApp -and -not $hasCodeCli) {
    Warn "      [WARN] Claude Desktop / Claude Code 가 설치된 흔적이 없습니다."
    Warn "             MCP 설정은 진행하지만, Claude Desktop 을 먼저 설치해야 동작합니다."
    Warn "             다운로드: https://claude.ai/download"
    Warn "             설치 후 이 스크립트를 다시 실행하거나 'stocklens-setup' 을 한 번 더 돌리세요."
    Write-Host ""
}

$setupExe = Join-Path $LocalBin "stocklens-setup.exe"

# 갓 설치된 미서명 exe 의 "첫 실행"은 Windows Defender/SmartScreen 스캔이나 uv 의
# 도구 환경 마무리 때문에 1회성으로 실패할 수 있다(두 번째부터는 사라짐). 그래서
# 첫 시도가 실패하면 잠깐 쉬고 1회 자동 재시도한 뒤에야 [FAIL] 로 종료한다.
$maxAttempts = 2
$setupOk = $false
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    $reason = $null
    try {
        if (Test-Path $setupExe) {
            & $setupExe stocklens
        } else {
            & uv tool run --from stocklens-mcp stocklens-setup stocklens
        }
        if ($LASTEXITCODE -eq 0) { $setupOk = $true; break }
        $reason = "exit $LASTEXITCODE"
    } catch {
        $reason = "$_"
    }
    if ($attempt -lt $maxAttempts) {
        Warn "      [RETRY] setup 첫 시도 실패 ($reason). 3초 후 재시도... ($attempt/$maxAttempts)"
        Start-Sleep -Seconds 3
    }
}
if (-not $setupOk) {
    Err "      [FAIL] MCP configuration failed after $maxAttempts attempts ($reason)."
    Err "             수동 확인: stocklens-setup  /  진단: stocklens-doctor"
    exit 1
}
Write-Host ""

# ── [4/4] License activation ─────────────────────────────
Info "[4/4] License activation..."
Write-Host "      Enter the license key sent to your email after purchase."
$activateExe = Join-Path $LocalBin "stocklens-activate.exe"
$licKey = (Read-Host "      License key").Trim()
if ($licKey) {
    if (Test-Path $activateExe) {
        & $activateExe $licKey
    } else {
        & uv tool run --from stocklens-mcp stocklens-activate $licKey
    }
    if ($LASTEXITCODE -ne 0) {
        Warn "      Activation failed. Check the key and retry: stocklens-activate <LICENSE-KEY>"
    }
} else {
    Warn "      Skipped. Activate later: stocklens-activate <LICENSE-KEY>"
}
Write-Host ""

# ── Verify ───────────────────────────────────────────────
Info "Verifying installation..."
$doctorExe = Join-Path $LocalBin "stocklens-doctor.exe"
if (Test-Path $doctorExe) {
    & $doctorExe
} else {
    & uv tool run --from stocklens-mcp stocklens-doctor
}
if ($LASTEXITCODE -ne 0) {
    Err ""
    Err "[FAIL] Doctor reported critical issues. See above for fix commands."
    exit 1
}
Write-Host ""

Write-Host "=============================================="
OK     "  Installation complete"
Write-Host "=============================================="
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. FULLY quit Claude Desktop (tray icon -> Quit)"
Write-Host "  2. Restart Claude Desktop"
Write-Host "  3. Try: '삼성전자 현재가'"
Write-Host ""
Write-Host "Activate:      stocklens-activate <LICENSE-KEY>"
Write-Host "Update later:  uv tool upgrade stocklens-mcp"
Write-Host "Diagnose:      stocklens-doctor"
Write-Host ""
