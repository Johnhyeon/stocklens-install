#!/bin/sh
# telegramlens Installer (macOS / Linux) — POSIX sh
# Usage:
#   curl -LsSf https://raw.githubusercontent.com/Johnhyeon/stocklens-install/main/install-telegram.sh | sh
#
# 4 steps:
#   1) uv (Python package manager) — auto-installs Python runtime if missing
#   2) telegramlens-mcp via `uv tool install`
#   3) Claude Desktop config via `telegramlens-setup`
#   4) License activation via `telegramlens-activate`
#
# 마지막으로 사용자가 직접 `telegramlens-login` 을 실행해 텔레그램 로그인을 완료한다.
# (API 키 발급용 브라우저 + 전화 인증 필요. curl|sh 는 stdin 이 파이프라 /dev/tty 로 받는다.)
#
# 본 스크립트는 Debian/Ubuntu/RaspberryPiOS 의 dash 등 POSIX sh 에서도
# 그대로 동작하도록 작성되어 있다 (echo -e / arrays / [[ ]] 사용 안 함).

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
printf '  telegramlens Installer (%s)\n' "$OS"
printf '==============================================\n\n'

LOCAL_BIN="$HOME/.local/bin"

# ── [1/4] uv ─────────────────────────────────────────────
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

# ── [2/4] telegramlens-mcp ───────────────────────────────
printf '%b[2/4] Installing telegramlens-mcp...%b\n' "$CYAN" "$NC"

if ! uv tool install --force telegramlens-mcp; then
    printf '      %b[FAIL] uv tool install failed.%b\n' "$RED" "$NC"
    exit 1
fi
printf '      %btelegramlens-mcp installed via uv tool%b\n' "$GREEN" "$NC"
printf '\n'

case ":$PATH:" in
    *":$LOCAL_BIN:"*) ;;
    *) [ -d "$LOCAL_BIN" ] && PATH="$LOCAL_BIN:$PATH" && export PATH ;;
esac

# ── [3/4] MCP target config ──────────────────────────────
# TELEGRAMLENS_TARGET 으로 등록 대상 지정 가능: claude-desktop / claude-code / both / auto
TELEGRAMLENS_TARGET="${TELEGRAMLENS_TARGET:-auto}"
export TELEGRAMLENS_TARGET

printf '%b[3/4] Configuring MCP (target=%s)...%b\n' "$CYAN" "$TELEGRAMLENS_TARGET" "$NC"

# Claude 클라이언트(Desktop 앱 또는 Code CLI) 설치 여부 사전 확인.
# 둘 다 없으면 setup 은 빈 config 만 만들고 성공으로 끝나는데, 읽을 앱이 없어
# TelegramLens 가 동작하지 않는다. 조용한 실패를 막기 위해 경고한다.
if [ "$OS" = "macOS" ]; then
    DESKTOP_CFG_DIR="$HOME/Library/Application Support/Claude"
else
    DESKTOP_CFG_DIR="$HOME/.config/Claude"
fi
if [ ! -d "$DESKTOP_CFG_DIR" ] && ! command -v claude > /dev/null 2>&1; then
    printf '      %b[WARN] Claude Desktop / Claude Code 가 설치된 흔적이 없습니다.%b\n' "$YELLOW" "$NC"
    printf '             MCP 설정은 진행하지만, Claude Desktop 을 먼저 설치해야 동작합니다.\n'
    printf '             다운로드: https://claude.ai/download\n'
    printf '             설치 후 이 스크립트를 다시 실행하거나 telegramlens-setup 을 한 번 더 돌리세요.\n\n'
fi

run_setup() {
    if [ -x "$LOCAL_BIN/telegramlens-setup" ]; then
        "$LOCAL_BIN/telegramlens-setup" "$@"
    else
        uv tool run --from telegramlens-mcp telegramlens-setup "$@"
    fi
}
# 갓 설치된 바이너리의 첫 실행이 백신/환경 마무리로 1회성 실패할 수 있어
# 첫 시도 실패 시 잠깐 쉬고 1회 자동 재시도한 뒤에야 [FAIL] 로 종료한다.
setup_ok=0
attempt=1
max_attempts=2
while [ "$attempt" -le "$max_attempts" ]; do
    if run_setup; then
        setup_ok=1
        break
    fi
    if [ "$attempt" -lt "$max_attempts" ]; then
        printf '      %b[RETRY] telegramlens-setup 첫 시도 실패. 3초 후 재시도... (%s/%s)%b\n' "$YELLOW" "$attempt" "$max_attempts" "$NC"
        sleep 3
    fi
    attempt=$((attempt + 1))
done
if [ "$setup_ok" -ne 1 ]; then
    printf '\n'
    printf '%b[FAIL] telegramlens-setup failed after %s attempts.%b\n' "$RED" "$max_attempts" "$NC"
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
    if [ -x "$LOCAL_BIN/telegramlens-activate" ]; then
        "$LOCAL_BIN/telegramlens-activate" "$@"
    else
        uv tool run --from telegramlens-mcp telegramlens-activate "$@"
    fi
}
if [ -n "$LIC_KEY" ]; then
    if ! run_activate "$LIC_KEY"; then
        printf '      %bActivation failed. Check the key and retry: telegramlens-activate <LICENSE-KEY>%b\n' "$YELLOW" "$NC"
    fi
else
    printf '      %bSkipped. Activate later: telegramlens-activate <LICENSE-KEY>%b\n' "$YELLOW" "$NC"
fi
printf '\n'

printf '==============================================\n'
printf '%b  Install complete - 마지막 1단계가 남았습니다%b\n' "$GREEN" "$NC"
printf '==============================================\n\n'
printf '%b  [필수] 텔레그램 로그인%b\n' "$YELLOW" "$NC"
printf '\n'
printf '    telegramlens-login\n'
printf '\n'
printf '  - 실행하면 텔레그램 API 키 발급용 브라우저가 열립니다.\n'
printf '  - 안내에 따라 API_ID/API_HASH 입력 후 전화번호로 로그인하세요.\n'
printf '  - 로그인을 마쳐야 채널 수집이 시작됩니다.\n'
printf '\n'
printf '  로그인 후:\n'
printf '    1. Claude Desktop을 완전히 종료 후 재실행'
if [ "$OS" = "macOS" ]; then
    printf ' (Cmd+Q)'
fi
printf '\n'
printf '    2. Claude에서 "telegram_status" 로 수집 상태 확인\n'
printf '\n'
printf 'Activate:      telegramlens-activate <LICENSE-KEY>\n'
printf 'Login:         telegramlens-login\n'
printf 'Update later:  uv tool upgrade telegramlens-mcp\n'
printf '\n'

# 편의: 지금 바로 로그인할지 물어보고, 동의하면 /dev/tty 로 stdin 을 연결해 실행한다.
run_login() {
    if [ -x "$LOCAL_BIN/telegramlens-login" ]; then
        "$LOCAL_BIN/telegramlens-login"
    else
        uv tool run --from telegramlens-mcp telegramlens-login
    fi
}
if [ -e /dev/tty ]; then
    printf '지금 바로 telegramlens-login 을 실행할까요? (Y/n): '
    GO=""
    read -r GO < /dev/tty || GO=""
    case "$GO" in
        ""|[Yy]*)
            printf '\n'
            run_login < /dev/tty || printf '%b로그인이 완료되지 않았습니다. 나중에 telegramlens-login 을 실행하세요.%b\n' "$YELLOW" "$NC"
            ;;
    esac
fi
