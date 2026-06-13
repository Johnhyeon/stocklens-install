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

# arrays 대신 함수 + "$@" 으로 우회 (POSIX 호환).
run_setup() {
    if [ -x "$LOCAL_BIN/stocklens-setup" ]; then
        "$LOCAL_BIN/stocklens-setup" "$@"
    else
        uv tool run --from stocklens-mcp stocklens-setup "$@"
    fi
}

if ! run_setup stocklens; then
    printf '\n'
    printf '%b[FAIL] stocklens-setup failed.%b\n' "$RED" "$NC"
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
