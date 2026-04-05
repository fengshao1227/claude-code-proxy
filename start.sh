#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Claude Code Proxy — 一键启动脚本
#  启动代理服务并自动连接 claude CLI
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.proxy.pid"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/proxy.log"
ENV_FILE="${SCRIPT_DIR}/.env"
DEFAULT_PORT=8082
HEALTH_TIMEOUT=15

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

# 从 .env 文件解析变量值（兼容带引号和不带引号）
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

# ---- 前置检查 ----

check_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        die "未找到 .env 文件。请复制 .env.example 为 .env 并填写配置：\n       cp .env.example .env"
    fi
    info "已加载配置文件: .env"
}

check_port_available() {
    local port="$1"
    if lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        die "端口 ${port} 已被占用。请先停止占用该端口的进程，或在 .env 中修改 PORT。"
    fi
}

check_claude_exists() {
    if ! command -v claude >/dev/null 2>&1; then
        die "未找到 claude 命令。请先安装 Claude Code CLI：\n       npm install -g @anthropic-ai/claude-code"
    fi
}

# ---- 运行时检测 ----

detect_runtime() {
    # 优先级: 预编译二进制 > uv > python3 > docker
    if [ -x "${SCRIPT_DIR}/claude-code-proxy" ]; then
        RUNTIME="binary"
        info "检测到预编译二进制: ./claude-code-proxy"
    elif command -v uv >/dev/null 2>&1; then
        RUNTIME="uv"
        info "检测到运行时: uv"
    elif command -v python3 >/dev/null 2>&1; then
        RUNTIME="python3"
        info "检测到运行时: python3"
    elif command -v docker >/dev/null 2>&1; then
        RUNTIME="docker"
        info "检测到运行时: docker"
    else
        die "未找到可用运行时。请安装以下任一工具：\n       - uv (推荐): curl -LsSf https://astral.sh/uv/install.sh | sh\n       - python3: brew install python3\n       - docker: brew install --cask docker"
    fi
}

# ---- 启动代理 ----

start_proxy() {
    local port="$1"

    mkdir -p "$LOG_DIR"

    info "正在启动代理服务 (端口: ${port}) ..."

    case "$RUNTIME" in
        binary)
            nohup "${SCRIPT_DIR}/claude-code-proxy" > "$LOG_FILE" 2>&1 &
            ;;
        uv)
            cd "$SCRIPT_DIR"
            nohup uv run start_proxy.py > "$LOG_FILE" 2>&1 &
            ;;
        python3)
            cd "$SCRIPT_DIR"
            nohup python3 start_proxy.py > "$LOG_FILE" 2>&1 &
            ;;
        docker)
            cd "$SCRIPT_DIR"
            nohup docker compose up --build > "$LOG_FILE" 2>&1 &
            ;;
    esac

    local pid=$!
    echo "$pid" > "$PID_FILE"
    info "代理进程已启动 (PID: ${pid})"
}

# ---- 健康检查 ----

wait_for_health() {
    local port="$1"
    local url="http://127.0.0.1:${port}/health"
    local elapsed=0

    info "等待代理服务就绪 (最长 ${HEALTH_TIMEOUT} 秒) ..."

    while [ "$elapsed" -lt "$HEALTH_TIMEOUT" ]; do
        if curl -s -o /dev/null -w '' "$url" 2>/dev/null; then
            ok "代理服务已就绪"
            return 0
        fi

        # 检查进程是否还活着
        if [ -f "$PID_FILE" ]; then
            local pid
            pid=$(cat "$PID_FILE")
            if ! kill -0 "$pid" 2>/dev/null; then
                warn "代理进程已退出，启动失败"
                print_failure_log
                return 1
            fi
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    warn "健康检查超时 (${HEALTH_TIMEOUT} 秒)"
    print_failure_log
    return 1
}

print_failure_log() {
    printf "\n${RED}--- 最近 20 行日志 ---${NC}\n"
    if [ -f "$LOG_FILE" ]; then
        tail -20 "$LOG_FILE"
    else
        printf "  (日志文件不存在)\n"
    fi
    printf "${RED}--- 日志结束 ---${NC}\n\n"
}

# ---- 启动 Claude CLI ----

launch_claude() {
    local port="$1"
    local api_key="$2"

    local base_url="http://127.0.0.1:${port}"

    info "正在启动 Claude Code CLI ..."
    printf "  代理地址: ${CYAN}${base_url}${NC}\n"

    local env_vars=()
    env_vars+=("ANTHROPIC_BASE_URL=${base_url}")

    if [ -n "$api_key" ]; then
        env_vars+=("ANTHROPIC_API_KEY=${api_key}")
    fi

    # 传递所有额外参数给 claude
    env "${env_vars[@]}" claude "$@"
}

# ---- 主流程 ----

main() {
    printf "\n${CYAN}╔══════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║   Claude Code Proxy — 一键启动       ║${NC}\n"
    printf "${CYAN}╚══════════════════════════════════════╝${NC}\n\n"

    check_env_file

    local port
    port=$(parse_env_var "PORT" "$DEFAULT_PORT")

    local api_key
    api_key=$(parse_env_var "ANTHROPIC_API_KEY" "")

    # 如果已经有代理在运行，先检查
    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            warn "检测到代理已在运行 (PID: ${old_pid})"
            # 尝试健康检查，如果健康就直接启动 claude
            if curl -s -o /dev/null -w '' "http://127.0.0.1:${port}/health" 2>/dev/null; then
                ok "代理服务运行正常，直接连接"
                check_claude_exists
                launch_claude "$port" "$api_key" "$@"
                return $?
            else
                warn "代理进程存在但未响应，正在重启 ..."
                kill "$old_pid" 2>/dev/null || true
                sleep 1
                rm -f "$PID_FILE"
            fi
        else
            info "清理过期的 PID 文件"
            rm -f "$PID_FILE"
        fi
    fi

    check_port_available "$port"
    check_claude_exists
    detect_runtime
    start_proxy "$port"

    if ! wait_for_health "$port"; then
        # 清理失败的进程
        if [ -f "$PID_FILE" ]; then
            local pid
            pid=$(cat "$PID_FILE")
            kill "$pid" 2>/dev/null || true
            rm -f "$PID_FILE"
        fi
        die "代理服务启动失败，请检查日志: ${LOG_FILE}"
    fi

    printf "\n"
    launch_claude "$port" "$api_key" "$@"
}

main "$@"
