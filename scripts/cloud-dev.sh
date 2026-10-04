#!/usr/bin/env bash
# 云端虚拟显示调试：在 Xvfb 里运行游戏/编辑器，用 noVNC 通过浏览器查看和操作。
# 用法：
#   scripts/cloud-dev.sh game     # 启动游戏窗口 + noVNC
#   scripts/cloud-dev.sh editor   # 启动 Godot 编辑器 + noVNC（内存紧张，慎用）
#   scripts/cloud-dev.sh status   # 查看运行状态
#   scripts/cloud-dev.sh stop     # 全部停止
set -euo pipefail

DISP=:99
SCREEN=1280x800x24
VNC_PORT=5900
NOVNC_PORT=6080
BIND=172.17.0.1
GODOT="${GODOT:-$HOME/tools/godot}"
RUN=/tmp/opencode/suiko-dev
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$RUN"

alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

start_xvfb() {
    [ -d /tmp/.X11-unix ] || { sudo mkdir -p /tmp/.X11-unix; sudo chmod 1777 /tmp/.X11-unix; }
    if ! alive "$RUN/xvfb.pid"; then
        Xvfb "$DISP" -screen 0 "$SCREEN" -nolisten tcp >"$RUN/xvfb.log" 2>&1 &
        echo $! >"$RUN/xvfb.pid"
        sleep 2
    fi
}

start_vnc() {
    if ! alive "$RUN/x11vnc.pid"; then
        x11vnc -display "$DISP" -forever -shared -rfbport "$VNC_PORT" -localhost \
            -nopw >"$RUN/x11vnc.log" 2>&1 &
        echo $! >"$RUN/x11vnc.pid"
    fi
    if ! alive "$RUN/novnc.pid"; then
        websockify --web=/usr/share/novnc "$BIND:$NOVNC_PORT" "localhost:$VNC_PORT" \
            >"$RUN/novnc.log" 2>&1 &
        echo $! >"$RUN/novnc.pid"
    fi
    echo "noVNC: http://$BIND:$NOVNC_PORT/vnc.html?autoconnect=true （经 NPM 反代后用域名访问）"
}

start_app() {
    start_xvfb
    local name="$1"; shift
    if alive "$RUN/$name.pid"; then
        echo "$name 已在运行 (pid $(cat "$RUN/$name.pid"))"
    else
        DISPLAY="$DISP" LIBGL_ALWAYS_SOFTWARE=1 "$GODOT" --path "$PROJECT" "$@" \
            >"$RUN/$name.log" 2>&1 &
        echo $! >"$RUN/$name.pid"
        echo "$name 已启动 (pid $(cat "$RUN/$name.pid"))"
    fi
    start_vnc
}

stop_all() {
    for name in game editor novnc x11vnc xvfb; do
        if alive "$RUN/$name.pid"; then
            kill "$(cat "$RUN/$name.pid")" 2>/dev/null || true
            echo "已停止 $name"
        fi
        rm -f "$RUN/$name.pid"
    done
}

status() {
    for name in game editor novnc x11vnc xvfb; do
        if alive "$RUN/$name.pid"; then
            echo "$name: 运行中 (pid $(cat "$RUN/$name.pid"))"
        else
            echo "$name: 未运行"
        fi
    done
    free -h | sed -n '2p'
}

case "${1:-}" in
    game)   start_app game ;;
    editor) start_app editor --editor ;;
    status) status ;;
    stop)   stop_all ;;
    *) echo "用法: $0 {game|editor|status|stop}"; exit 1 ;;
esac
