#!/usr/bin/env bash
# Claude Code Proxy - 交互式配置向导
# 用法: bash setup.sh
set -euo pipefail

# ====== 颜色定义 ======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

# ====== 工具函数 ======
print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       Claude Code Proxy 配置向导 v1.0.0         ║${NC}"
    echo -e "${CYAN}║  让 Claude Code 接入任意 OpenAI 兼容服务商      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
step()    { echo -e "\n${BOLD}${BLUE}>>> $1${NC}"; }

# 读取输入，支持默认值（bash 3.2 兼容）
read_input() {
    local prompt="$1"
    local default="${2:-}"
    local result

    if [ -n "$default" ]; then
        printf "%s [%s]: " "$prompt" "$default"
    else
        printf "%s: " "$prompt"
    fi
    read -r result
    echo "${result:-$default}"
}

# 读取密码（掩码输入）
read_secret() {
    local prompt="$1"
    local result
    printf "%s: " "$prompt"
    read -rs result
    echo ""
    echo "$result"
}

# ====== 环境检测 ======
detect_environment() {
    step "检测运行环境"

    # OS
    case "$(uname -s)" in
        Linux*)  OS_TYPE="Linux" ;;
        Darwin*) OS_TYPE="macOS" ;;
        MINGW*|MSYS*|CYGWIN*) OS_TYPE="Windows" ;;
        *)       OS_TYPE="Unknown" ;;
    esac
    echo -e "  操作系统:  ${BOLD}$OS_TYPE$(uname -m | sed 's/^/ /')${NC}"

    # Python
    HAS_PYTHON=false
    PYTHON_CMD=""
    if command -v python3 &>/dev/null; then
        PYTHON_CMD="python3"
        PYTHON_VER=$($PYTHON_CMD --version 2>&1 | awk '{print $2}')
        HAS_PYTHON=true
        echo -e "  Python:    ${GREEN}$PYTHON_VER${NC} ($PYTHON_CMD)"
    elif command -v python &>/dev/null; then
        PYTHON_CMD="python"
        PYTHON_VER=$($PYTHON_CMD --version 2>&1 | awk '{print $2}')
        HAS_PYTHON=true
        echo -e "  Python:    ${GREEN}$PYTHON_VER${NC} ($PYTHON_CMD)"
    else
        echo -e "  Python:    ${YELLOW}未安装${NC}"
    fi

    # UV
    HAS_UV=false
    if command -v uv &>/dev/null; then
        UV_VER=$(uv --version 2>&1 | awk '{print $2}')
        HAS_UV=true
        echo -e "  UV:        ${GREEN}$UV_VER${NC}"
    else
        echo -e "  UV:        ${YELLOW}未安装${NC}"
    fi

    # Docker
    HAS_DOCKER=false
    if command -v docker &>/dev/null; then
        HAS_DOCKER=true
        echo -e "  Docker:    ${GREEN}已安装${NC}"
    else
        echo -e "  Docker:    ${YELLOW}未安装${NC}"
    fi

    # Claude Code
    HAS_CLAUDE=false
    if command -v claude &>/dev/null; then
        HAS_CLAUDE=true
        echo -e "  Claude:    ${GREEN}已安装${NC}"
    else
        echo -e "  Claude:    ${YELLOW}未安装${NC} (需要: npm install -g @anthropic-ai/claude-code)"
    fi

    # curl
    HAS_CURL=false
    if command -v curl &>/dev/null; then
        HAS_CURL=true
    fi

    echo ""
}

# ====== 服务商选择 ======
select_provider() {
    step "选择 AI 服务商"

    echo "  1) OpenAI          (api.openai.com)"
    echo "  2) DeepSeek        (api.deepseek.com) - 国内推荐"
    echo "  3) Ollama          (本地部署，免费)"
    echo "  4) Azure OpenAI    (微软云)"
    echo "  5) 自定义服务商     (任意 OpenAI 兼容 API)"
    echo ""

    local choice
    while true; do
        choice=$(read_input "请选择 (1-5)" "2")
        case "$choice" in
            1|2|3|4|5) break ;;
            *) warn "请输入 1-5 之间的数字" ;;
        esac
    done

    PROVIDER_CHOICE="$choice"
}

# ====== 配置凭证 ======
configure_credentials() {
    step "配置 API 凭证"

    case "$PROVIDER_CHOICE" in
        1) # OpenAI
            PROVIDER_NAME="OpenAI"
            BASE_URL="https://api.openai.com/v1"
            DEFAULT_BIG="gpt-4o"
            DEFAULT_MIDDLE="gpt-4o"
            DEFAULT_SMALL="gpt-4o-mini"
            echo "  服务商: OpenAI"
            API_KEY=$(read_secret "请输入 OpenAI API Key (sk-...)")
            ;;
        2) # DeepSeek
            PROVIDER_NAME="DeepSeek"
            BASE_URL="https://api.deepseek.com"
            DEFAULT_BIG="deepseek-chat"
            DEFAULT_MIDDLE="deepseek-chat"
            DEFAULT_SMALL="deepseek-chat"
            echo "  服务商: DeepSeek"
            API_KEY=$(read_secret "请输入 DeepSeek API Key")
            ;;
        3) # Ollama
            PROVIDER_NAME="Ollama"
            BASE_URL="http://localhost:11434/v1"
            DEFAULT_BIG="qwen2.5:14b"
            DEFAULT_MIDDLE="qwen2.5:14b"
            DEFAULT_SMALL="qwen2.5:7b"
            echo "  服务商: Ollama (本地)"
            API_KEY="ollama"
            info "Ollama 无需 API Key，已自动填充"
            local custom_url
            custom_url=$(read_input "Ollama 地址" "$BASE_URL")
            BASE_URL="$custom_url"
            ;;
        4) # Azure
            PROVIDER_NAME="Azure OpenAI"
            DEFAULT_BIG="gpt-4o"
            DEFAULT_MIDDLE="gpt-4o"
            DEFAULT_SMALL="gpt-4o-mini"
            echo "  服务商: Azure OpenAI"
            local resource_name
            resource_name=$(read_input "Azure 资源名称 (your-resource-name)")
            local deployment_name
            deployment_name=$(read_input "部署名称 (your-deployment)")
            BASE_URL="https://${resource_name}.openai.azure.com/openai/deployments/${deployment_name}"
            AZURE_API_VERSION=$(read_input "API 版本" "2024-03-01-preview")
            API_KEY=$(read_secret "请输入 Azure API Key")
            ;;
        5) # Custom
            PROVIDER_NAME="自定义"
            DEFAULT_BIG="gpt-4o"
            DEFAULT_MIDDLE="gpt-4o"
            DEFAULT_SMALL="gpt-4o-mini"
            echo "  服务商: 自定义"
            BASE_URL=$(read_input "API Base URL (例: https://api.example.com/v1)")
            API_KEY=$(read_secret "请输入 API Key")
            ;;
    esac

    if [ -z "$API_KEY" ] && [ "$PROVIDER_CHOICE" != "3" ]; then
        error "API Key 不能为空"
        exit 1
    fi
}

# ====== 配置模型 ======
configure_models() {
    step "配置模型映射"

    echo "  Claude Code 会请求不同的 Claude 模型，代理会将其映射到你的模型:"
    echo "    opus  (大模型) → BIG_MODEL"
    echo "    sonnet(中模型) → MIDDLE_MODEL"
    echo "    haiku (小模型) → SMALL_MODEL"
    echo ""

    BIG_MODEL=$(read_input "BIG_MODEL (opus 映射)" "$DEFAULT_BIG")
    MIDDLE_MODEL=$(read_input "MIDDLE_MODEL (sonnet 映射)" "$DEFAULT_MIDDLE")
    SMALL_MODEL=$(read_input "SMALL_MODEL (haiku 映射)" "$DEFAULT_SMALL")
}

# ====== 高级配置 ======
configure_advanced() {
    step "高级配置 (可选)"

    local want_advanced
    want_advanced=$(read_input "是否配置高级选项？(y/N)" "n")

    # 默认值
    PORT="8082"
    HOST="0.0.0.0"
    LOG_LEVEL="WARNING"
    MAX_TOKENS_LIMIT="4096"
    REQUEST_TIMEOUT="90"
    ANTHROPIC_KEY=""

    case "$want_advanced" in
        y|Y|yes|YES)
            PORT=$(read_input "代理端口" "8082")
            LOG_LEVEL=$(read_input "日志级别 (DEBUG/INFO/WARNING/ERROR)" "WARNING")
            MAX_TOKENS_LIMIT=$(read_input "最大 Token 数" "4096")
            REQUEST_TIMEOUT=$(read_input "请求超时(秒)" "90")
            echo ""
            info "设置 ANTHROPIC_API_KEY 可以保护你的代理不被他人使用"
            ANTHROPIC_KEY=$(read_input "ANTHROPIC_API_KEY (留空=不验证)" "")
            ;;
        *)
            info "使用默认高级配置"
            ;;
    esac
}

# ====== 生成 .env ======
write_env_file() {
    step "生成配置文件"

    # 备份已有的 .env
    if [ -f "$ENV_FILE" ]; then
        local backup="${ENV_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        cp "$ENV_FILE" "$backup"
        warn "已备份现有配置到: $(basename "$backup")"
    fi

    cat > "$ENV_FILE" << ENVEOF
# Claude Code Proxy 配置文件
# 由 setup.sh 自动生成于 $(date '+%Y-%m-%d %H:%M:%S')
# 服务商: ${PROVIDER_NAME}

# API 密钥
OPENAI_API_KEY="${API_KEY}"

# API 地址
OPENAI_BASE_URL="${BASE_URL}"

# 模型映射
BIG_MODEL="${BIG_MODEL}"
MIDDLE_MODEL="${MIDDLE_MODEL}"
SMALL_MODEL="${SMALL_MODEL}"

# 服务器设置
HOST="${HOST}"
PORT="${PORT}"
LOG_LEVEL="${LOG_LEVEL}"

# 性能设置
MAX_TOKENS_LIMIT="${MAX_TOKENS_LIMIT}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT}"
ENVEOF

    # Azure 额外配置
    if [ "${AZURE_API_VERSION:-}" != "" ]; then
        echo "" >> "$ENV_FILE"
        echo "# Azure OpenAI" >> "$ENV_FILE"
        echo "AZURE_API_VERSION=\"${AZURE_API_VERSION}\"" >> "$ENV_FILE"
    fi

    # 客户端认证
    if [ -n "${ANTHROPIC_KEY:-}" ]; then
        echo "" >> "$ENV_FILE"
        echo "# 客户端 API Key 验证" >> "$ENV_FILE"
        echo "ANTHROPIC_API_KEY=\"${ANTHROPIC_KEY}\"" >> "$ENV_FILE"
    fi

    info "配置已写入: .env"
}

# ====== 显示摘要 ======
show_summary() {
    step "配置摘要"

    echo -e "  服务商:      ${BOLD}${PROVIDER_NAME}${NC}"
    echo -e "  API 地址:    ${BASE_URL}"
    echo -e "  大模型:      ${BIG_MODEL}"
    echo -e "  中模型:      ${MIDDLE_MODEL}"
    echo -e "  小模型:      ${SMALL_MODEL}"
    echo -e "  代理端口:    ${PORT}"
    echo -e "  日志级别:    ${LOG_LEVEL}"
    if [ -n "${ANTHROPIC_KEY:-}" ]; then
        echo -e "  客户端验证:  ${GREEN}已启用${NC}"
    else
        echo -e "  客户端验证:  ${YELLOW}未启用${NC}"
    fi
    echo ""
}

# ====== 启动提示 ======
offer_start() {
    step "启动代理"

    local want_start
    want_start=$(read_input "是否立即启动代理？(Y/n)" "y")

    case "$want_start" in
        n|N|no|NO)
            echo ""
            info "配置完成！你可以稍后通过以下方式启动:"
            echo ""
            echo "  # 一键启动（推荐）"
            echo "  bash start.sh"
            echo ""
            echo "  # 或手动启动"
            echo "  python start_proxy.py"
            echo ""
            if $HAS_CLAUDE; then
                echo "  # 然后在另一个终端:"
                echo "  ANTHROPIC_BASE_URL=http://localhost:${PORT} claude"
            fi
            echo ""
            ;;
        *)
            if [ -f "$PROJECT_DIR/start.sh" ]; then
                info "正在启动..."
                exec bash "$PROJECT_DIR/start.sh"
            else
                info "start.sh 不存在，请手动启动:"
                echo "  python start_proxy.py"
            fi
            ;;
    esac
}

# ====== 安装依赖提示 ======
check_dependencies() {
    if ! $HAS_PYTHON && ! $HAS_UV && ! $HAS_DOCKER; then
        echo ""
        error "未检测到任何可用的运行环境！"
        echo ""
        echo "  请至少安装以下之一:"
        echo "    - Python 3.9+   : https://python.org"
        echo "    - UV             : curl -LsSf https://astral.sh/uv/install.sh | sh"
        echo "    - Docker         : https://docker.com"
        echo ""
        echo "  或下载预编译二进制（免装 Python）:"
        echo "    https://github.com/fengshao1227/claude-code-proxy/releases"
        echo ""

        local want_continue
        want_continue=$(read_input "仍然继续配置？(y/N)" "n")
        case "$want_continue" in
            y|Y) return ;;
            *) exit 0 ;;
        esac
    fi

    # 如果有 UV 或 Python，检查依赖
    if $HAS_UV; then
        local want_install
        want_install=$(read_input "是否安装 Python 依赖？(uv sync) (Y/n)" "y")
        case "$want_install" in
            n|N) ;;
            *)
                info "正在安装依赖..."
                (cd "$PROJECT_DIR" && uv sync) || warn "依赖安装失败，你可以稍后手动执行 'uv sync'"
                ;;
        esac
    elif $HAS_PYTHON; then
        if ! $PYTHON_CMD -c "import fastapi" &>/dev/null; then
            local want_install
            want_install=$(read_input "是否安装 Python 依赖？(pip install) (Y/n)" "y")
            case "$want_install" in
                n|N) ;;
                *)
                    info "正在安装依赖..."
                    (cd "$PROJECT_DIR" && $PYTHON_CMD -m pip install -r requirements.txt) || warn "依赖安装失败"
                    ;;
            esac
        fi
    fi
}

# ====== 主流程 ======
main() {
    print_banner
    detect_environment
    check_dependencies
    select_provider
    configure_credentials
    configure_models
    configure_advanced
    write_env_file
    show_summary
    offer_start
}

main
