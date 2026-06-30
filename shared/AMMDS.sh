#!/bin/sh

######################################################################
# AMMDS QPKG Service Control Script
######################################################################

CONF=/etc/config/qpkg.conf
QPKG_NAME="AMMDS"
QPKG_ROOT=`/sbin/getcfg $QPKG_NAME Install_Path -f ${CONF}`
APACHE_ROOT=`/sbin/getcfg SHARE_DEF defWeb -d Qweb -f /etc/config/def_share.info`
export QNAP_QPKG=$QPKG_NAME

# 路径定义
ENV_FILE="$QPKG_ROOT/config/ammds.env"
BIN_DIR="$QPKG_ROOT"
PID_FILE="/var/run/ammds.pid"

# 日志工具
log_msg() {
    /sbin/log_tool -t 0 -a "[AMMDS] $1"
}

log_warn() {
    /sbin/log_tool -t 1 -a "[AMMDS] $1"
}

log_err() {
    /sbin/log_tool -t 2 -a "[AMMDS] $1"
}

# 检测 CPU 架构并验证（QDK 已按架构打包，运行时验证架构兼容性）
detect_architecture() {
    local arch=$(uname -m)

    case "$arch" in
        x86_64|aarch64|armv7l)
            echo "ammds"
            ;;
        *)
            log_err "Unsupported architecture: $arch"
            echo ""
            return 1
            ;;
    esac
}

# 检查端口是否被占用（返回 0 表示空闲，1 表示被占用）
is_port_in_use() {
    local port=$1
    # 尝试通过 netstat 检测端口
    if command -v /bin/netstat >/dev/null 2>&1; then
        /bin/netstat -tln 2>/dev/null | grep -q ":$port "
        return $?
    fi
    # 备用方案：通过 ss 检测
    if command -v /sbin/ss >/dev/null 2>&1; then
        /sbin/ss -tln 2>/dev/null | grep -q ":$port "
        return $?
    fi
    # 最后备用：检查 /proc/net/tcp
    if [ -f /proc/net/tcp ]; then
        local hex_port=$(printf '%04X' $port)
        grep -q ":$hex_port " /proc/net/tcp 2>/dev/null
        return $?
    fi
    # 无法检测，假设端口可用
    return 0
}

# 生成随机端口 (10000-65535)
generate_random_port() {
    # 使用 awk 生成随机端口
    awk 'BEGIN{srand(); print int(rand()*55535)+10000}'
}

# 查找可用端口（从当前端口开始，若占用则随机选择）
find_available_port() {
    local current_port=$1

    if ! is_port_in_use "$current_port"; then
        echo "$current_port"
        return 0
    fi

    log_warn "Port $current_port is in use, searching for available port..."

    # 尝试随机端口，最多尝试 50 次
    local attempts=0
    while [ $attempts -lt 50 ]; do
        local new_port=$(generate_random_port)
        if ! is_port_in_use "$new_port"; then
            log_msg "Found available port: $new_port"
            echo "$new_port"
            return 0
        fi
        attempts=$((attempts + 1))
    done

    log_err "Failed to find an available port after 50 attempts"
    return 1
}

# 加载环境变量配置
load_env_config() {
    if [ ! -f "$ENV_FILE" ]; then
        log_err "Environment config file not found: $ENV_FILE"
        return 1
    fi

    # 读取配置并导出为环境变量
    set -a
    . "$ENV_FILE"
    set +a

    return 0
}

# 更新配置文件中的端口值
update_config_port() {
    local new_port=$1
    /bin/sed -i "s/^AMMDS_SERVER_PORT=.*/AMMDS_SERVER_PORT=$new_port/" "$ENV_FILE"
    log_msg "Updated AMMDS_SERVER_PORT to $new_port in $ENV_FILE"
}

start_service() {
    # 检查是否已在运行
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE")
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            log_warn "AMMDS is already running (PID: $old_pid)"
            return 0
        fi
        # PID 文件存在但进程已不存在，清理
        rm -f "$PID_FILE"
    fi

    # 检测架构
    local binary_name=$(detect_architecture)
    if [ -z "$binary_name" ]; then
        return 1
    fi

    local binary_path="$BIN_DIR/$binary_name"
    if [ ! -f "$binary_path" ]; then
        log_err "Binary not found: $binary_path"
        return 1
    fi

    # 确保二进制文件可执行
    chmod +x "$binary_path"

    # 加载环境变量
    if ! load_env_config; then
        return 1
    fi

    # 检查端口占用，必要时更换端口
    local port="${AMMDS_SERVER_PORT:-9523}"
    local available_port=$(find_available_port "$port")
    if [ -z "$available_port" ]; then
        return 1
    fi

    if [ "$available_port" != "$port" ]; then
        export AMMDS_SERVER_PORT="$available_port"
        update_config_port "$available_port"
    fi

    log_msg "Starting AMMDS on port $AMMDS_SERVER_PORT (arch: $(uname -m), binary: $binary_name)"

    # 后台启动服务
    "$binary_path" &
    local pid=$!

    # 保存 PID
    echo "$pid" > "$PID_FILE"
    log_msg "AMMDS started successfully (PID: $pid)"
    return 0
}

stop_service() {
    if [ ! -f "$PID_FILE" ]; then
        log_warn "AMMDS is not running (no PID file found)"
        return 0
    fi

    local pid=$(cat "$PID_FILE")
    if [ -z "$pid" ]; then
        log_warn "PID file is empty, cleaning up"
        rm -f "$PID_FILE"
        return 0
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        log_warn "Process $pid is not running, cleaning up PID file"
        rm -f "$PID_FILE"
        return 0
    fi

    log_msg "Stopping AMMDS (PID: $pid)..."

    # 发送 TERM 信号
    kill "$pid" 2>/dev/null

    # 等待进程退出（最多等待 10 秒）
    local wait_count=0
    while kill -0 "$pid" 2>/dev/null && [ $wait_count -lt 20 ]; do
        sleep 0.5
        wait_count=$((wait_count + 1))
    done

    # 如果进程仍未退出，强制终止
    if kill -0 "$pid" 2>/dev/null; then
        log_warn "Process did not stop gracefully, force killing..."
        kill -9 "$pid" 2>/dev/null
        sleep 1
    fi

    rm -f "$PID_FILE"
    log_msg "AMMDS stopped"
    return 0
}

case "$1" in
  start)
    ENABLED=$(/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f $CONF)
    if [ "$ENABLED" != "TRUE" ]; then
        echo "$QPKG_NAME is disabled."
        exit 1
    fi
    start_service
    ;;

  stop)
    stop_service
    ;;

  restart)
    stop_service
    sleep 1
    start_service
    ;;

  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
esac

exit 0
