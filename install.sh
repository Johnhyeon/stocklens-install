#!/bin/sh
# StockLens Installer (macOS / Linux) — POSIX sh
# Usage:
#   curl -LsSf https://raw.githubusercontent.com/Johnhyeon/stocklens-install/main/install.sh | sh
#
# Target override (default: auto-detect):
#   STOCKLENS_TARGET=claude-code curl -LsSf .../install.sh | sh
#
# 3 steps:
#   1) uv (Python package manager) — auto-installs Python runtime if missing
#   2) stocklens-mcp via `uv tool install`
#   3) Claude Desktop / Claude Code config via `stocklens-setup`
#
# 본 스크립트는 Debian/Ubuntu/RaspberryPiOS 등 /bin/sh 가 dash 인 환경에서도
# 그대로 동작하도록 POSIX sh 만 사용 (echo -e / arrays / [[ ]] 사용 안 함).

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

case "$(uname -s)" in
    Darwin) OS="macOS" ;;
    Linux)  OS="Linux" ;;
    *)      OS="Unknown" ;;
esac

printf '\n'
printf '==============================================\n'
printf '  StockLens Installer (%s)\n' "$OS"
printf '==============================================\n\n'

LOCAL_BIN="$HOME/.local/bin"

# ── [1/3] uv ─────────────────────────────────────────────
printf '%b[1/4] Checking uv...%b\n' "$CYAN" "$NC"
if ! command -v uv > /dev/null 2>&1; then
    printf '      uv not found. Installing from astral.sh...\n'
    if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
        printf '      %b[FAIL] uv installation failed.%b\n' "$RED" "$NC"
        printf '      Manual install: https://docs.astral.sh/uv/getting-started/installation/\n'
        exit 1
    fi
    if [ -d "$LOCAL_BIN" ]; then
        PATH="$LOCAL_BIN:$PATH"
        export PATH
    fi
    if ! command -v uv > /dev/null 2>&1; then
        printf '      %b[FAIL] uv installed but not on PATH. Open a new terminal and re-run.%b\n' "$RED" "$NC"
        exit 1
    fi
    printf '      %buv installed: %s%b\n' "$GREEN" "$(command -v uv)" "$NC"
else
    printf '      %buv found: %s%b\n' "$GREEN" "$(command -v uv)" "$NC"
fi
printf '\n'

# ── [2/3] stocklens-mcp ──────────────────────────────────
printf '%b[2/4] Installing stocklens-mcp...%b\n' "$CYAN" "$NC"

# --force re-creates the tool environment, so re-running upgrades cleanly.
# uv tool 격리 환경이라 시스템 pip의 옛 naver-stock-mcp가 남아있어도 충돌하지 않음.
if ! uv tool install --force stocklens-mcp; then
    printf '      %b[FAIL] uv tool install failed.%b\n' "$RED" "$NC"
    exit 1
fi
printf '      %bstocklens-mcp installed via uv tool%b\n' "$GREEN" "$NC"
printf '\n'

case ":$PATH:" in
    *":$LOCAL_BIN:"*) ;;
    *) [ -d "$LOCAL_BIN" ] && PATH="$LOCAL_BIN:$PATH" && export PATH ;;
esac

# ── [3/3] MCP target config ──────────────────────────────
# STOCKLENS_TARGET 으로 등록 대상 지정 가능: claude-desktop / claude-code / both / auto
STOCKLENS_TARGET="${STOCKLENS_TARGET:-auto}"
export STOCKLENS_TARGET

printf '%b[3/4] Configuring MCP (target=%s)...%b\n' "$CYAN" "$STOCKLENS_TARGET" "$NC"

# Claude 클라이언트(Desktop 앱 또는 Code CLI) 설치 여부 사전 확인.
# 둘 다 없으면 setup 은 빈 config 만 만들고 성공으로 끝나는데, 읽을 앱이 없어
# StockLens 가 동작하지 않는다. 조용한 실패를 막기 위해 경고한다.
if [ "$OS" = "macOS" ]; then
    DESKTOP_CFG_DIR="$HOME/Library/Application Support/Claude"
else
    DESKTOP_CFG_DIR="$HOME/.config/Claude"
fi
if [ ! -d "$DESKTOP_CFG_DIR" ] && ! command -v claude > /dev/null 2>&1; then
    printf '      %b[WARN] Claude Desktop / Claude Code 가 설치된 흔적이 없습니다.%b\n' "$YELLOW" "$NC"
    printf '             MCP 설정은 진행하지만, Claude Desktop 을 먼저 설치해야 동작합니다.\n'
    printf '             다운로드: https://claude.ai/download\n'
    printf '             설치 후 이 스크립트를 다시 실행하거나 stocklens-setup 을 한 번 더 돌리세요.\n\n'
fi

# arrays 대신 함수 + "$@" 으로 우회 (POSIX 호환).
run_setup() {
    if [ -x "$LOCAL_BIN/stocklens-setup" ]; then
        "$LOCAL_BIN/stocklens-setup" "$@"
    else
        uv tool run --from stocklens-mcp stocklens-setup "$@"
    fi
}

# 갓 설치된 바이너리의 첫 실행이 백신/환경 마무리로 1회성 실패할 수 있어
# 첫 시도 실패 시 잠깐 쉬고 1회 자동 재시도한 뒤에야 [FAIL] 로 종료한다.
setup_ok=0
attempt=1
max_attempts=2
while [ "$attempt" -le "$max_attempts" ]; do
    if run_setup stocklens; then
        setup_ok=1
        break
    fi
    if [ "$attempt" -lt "$max_attempts" ]; then
        printf '      %b[RETRY] stocklens-setup 첫 시도 실패. 3초 후 재시도... (%s/%s)%b\n' "$YELLOW" "$attempt" "$max_attempts" "$NC"
        sleep 3
    fi
    attempt=$((attempt + 1))
done
if [ "$setup_ok" -ne 1 ]; then
    printf '\n'
    printf '%b[FAIL] stocklens-setup failed after %s attempts.%b\n' "$RED" "$max_attempts" "$NC"
    exit 1
fi
printf '\n'

# ── [4/4] License activation ─────────────────────────────
# curl | sh 일 때 stdin은 파이프라 read 가 막힌다. /dev/tty 가 있으면 거기서 키를 받는다.
printf '%b[4/4] License activation...%b\n' "$CYAN" "$NC"
printf '      Enter the license key sent to your email after purchase.\n'
LIC_KEY=""
if [ -e /dev/tty ]; then
    printf '      License key: '
    read -r LIC_KEY < /dev/tty || LIC_KEY=""
fi
run_activate() {
    if [ -x "$LOCAL_BIN/stocklens-activate" ]; then
        "$LOCAL_BIN/stocklens-activate" "$@"
    else
        uv tool run --from stocklens-mcp stocklens-activate "$@"
    fi
}
if [ -n "$LIC_KEY" ]; then
    if ! run_activate "$LIC_KEY"; then
        printf '      %bActivation failed. Check the key and retry: stocklens-activate <LICENSE-KEY>%b\n' "$YELLOW" "$NC"
    fi
else
    printf '      %bSkipped. Activate later: stocklens-activate <LICENSE-KEY>%b\n' "$YELLOW" "$NC"
fi
printf '\n'

# ── Verify ───────────────────────────────────────────────
printf '%bVerifying installation...%b\n' "$CYAN" "$NC"
run_doctor() {
    if [ -x "$LOCAL_BIN/stocklens-doctor" ]; then
        "$LOCAL_BIN/stocklens-doctor"
    else
        uv tool run --from stocklens-mcp stocklens-doctor
    fi
}
if ! run_doctor; then
    printf '\n'
    printf '%b[FAIL] Doctor reported critical issues. See above for fix commands.%b\n' "$RED" "$NC"
    exit 1
fi
printf '\n'

printf '==============================================\n'
printf '%b  Installation complete%b\n' "$GREEN" "$NC"
printf '==============================================\n\n'
printf 'Next steps:\n'
printf '  1. Fully quit Claude Desktop\n'
if [ "$OS" = "macOS" ]; then
    printf '     (Cmd+Q or menu bar -> Claude -> Quit)\n'
fi
printf '  2. Restart Claude Desktop\n'
printf '  3. Try: "삼성전자 현재가"\n\n'
printf 'Activate:      stocklens-activate <LICENSE-KEY>\n'
printf 'Update later:  uv tool upgrade stocklens-mcp\n'
printf 'Diagnose:      stocklens-doctor\n\n'
