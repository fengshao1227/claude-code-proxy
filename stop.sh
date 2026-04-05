#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Claude Code Proxy — 停止脚本
#  停止后台运行的代理服务
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.proxy.pid"
ENV_FILE="${SCRIPT_DIR}/.env"
DEFAULT_PORT=8082

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---- 工具函数 ----

info()  { printf "${CYAN}[信息]${NC} %s\n" "$1"; }
ok()    { printf "${GREEN}[成功]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[警告]${NC} %s\n" "$1"; }
die()   { printf "${RED}[错误]${NC} %s\n" "$1" >&2; exit 1; }

# 从 .env 文件解析变量值
parse_env_var() {
    local key="$1"
    local default="$2"
    if [ ! -f "$ENV_FILE" ]; then
        printf '%s' "$default"
        return
    fi
    local val
    val=$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | sed "s/^${key}=//" | sed 's/^["'\'']//' | sed 's/["'\'']*$//' | sed 's/[[:space:]]*#.*$//' | tr -d '[:space:]')
    if [ -z "$val" ]; then
        printf '%s' "$default"
    else
        printf '%s' "$val"
    fi
}

# ---- 停止进程 ----

stop_by_pid_file() {
    if [ ! -f "$PID_FILE" ]; then
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if [ -z "$pid" ]; then
        info "PID 文件为空，正在清理"
        rm -f "$PID_FILE"
        return 1
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        info "进程 (PID: ${pid}) 已不存在，正在清理 PID 文件"
        rm -f "$PID_FILE"
        return 1
    fi

    info "正在停止代理进程 (PID: ${pid}) ..."
    kill "$pid" 2>/dev/null || true

    # 等待进程退出（最多 5 秒）
    local waited=0
    while [ "$waited" -lt 5 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            ok "代理进程已停止"
            rm -f "$PID_FILE"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # 进程没退出，强制终止
    warn "进程未响应 SIGTERM，正在强制终止 ..."
    kill -9 "$pid" 2>/dev/null || true
    sleep 1

    if ! kill -0 "$pid" 2>/dev/null; then
        ok "代理进程已强制终止"
    else
        warn "无法终止进程 ${pid}，请手动处理"
    fi

    rm -f "$PID_FILE"
    return 0
}

stop_by_port() {
    local port="$1"

    info "正在通过端口 ${port} 查找代理进程 ..."

    local pid
    pid=$(lsof -ti :"$port" -sTCP:LISTEN 2>/dev/null || true)

    if [ -z "$pid" ]; then
        return 1
    fi

    info "通过端口 ${port} 找到进程 (PID: ${pid})"
    kill "$pid" 2>/dev/null || true

    # 等待进程退出
    local waited=0
    while [ "$waited" -lt 5 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            ok "代理进程已停止"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    warn "进程未响应 SIGTERM，正在强制终止 ..."
    kill -9 "$pid" 2>/dev/null || true
    ok "代理进程已强制终止"
    return 0
}

# ---- 主流程 ----

main() {
    printf "\n${CYAN}╔══════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║   Claude Code Proxy — 停止服务       ║${NC}\n"
    printf "${CYAN}╚══════════════════════════════════════╝${NC}\n\n"

    local port
    port=$(parse_env_var "PORT" "$DEFAULT_PORT")

    # 策略一：通过 PID 文件停止
    if stop_by_pid_file; then
        return 0
    fi

    # 策略二：通过端口查找停止
    if stop_by_port "$port"; then
        rm -f "$PID_FILE"
        return 0
    fi

    # 都没找到
    warn "未找到正在运行的代理进程 (端口: ${port})"
    info "如果代理运行在其他端口，请手动终止对应进程"
    rm -f "$PID_FILE" 2>/dev/null || true
}

main
