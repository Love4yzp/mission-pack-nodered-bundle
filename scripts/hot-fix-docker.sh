#!/bin/bash
# Set error handling
set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRESS_FILE="${SCRIPT_DIR}/.installation_progress.log"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default values
MODE="local"  # Default to local execution
REMOTE_HOST=""
REMOTE_USER=""
REMOTE_PASS=""
INSTALL_DOCKER_FILE="${SCRIPT_DIR}/install_docker.sh"
REMOTE_PATH="/home/recomputer/"
REMOTE_SCRIPT_PATH="/home/recomputer/install_docker.sh"

# Help function
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -m, --mode MODE       Execution mode: 'local' or 'remote' (default: local)"
    echo "  -h, --host HOST       Remote host IP address (required for remote mode)"
    echo "  -u, --user USER       Remote username (required for remote mode)"
    echo "  -p, --pass PASS       Remote password (required for remote mode)"
    echo "  -n, --no-reboot       Skip automatic reboot after installation"
    echo "  --help                Show this help message"
    echo ""
    echo "Example:"
    echo "  Local execution:  $0 -m local"
    echo "  Remote execution: $0 -m remote -h 192.168.1.10 -u recomputer -p 12345678"
    echo "  Skip reboot:      $0 -n"
}

# Log functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
    echo -e "\n${BLUE}${BOLD}$1${NC}\n"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -h|--host)
            REMOTE_HOST="$2"
            shift 2
            ;;
        -u|--user)
            REMOTE_USER="$2"
            shift 2
            ;;
        -p|--pass)
            REMOTE_PASS="$2"
            shift 2
            ;;
        -n|--no-reboot)
            NO_REBOOT="true"
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate parameters
if [[ "$MODE" != "local" && "$MODE" != "remote" ]]; then
    error "Invalid mode: $MODE. Must be 'local' or 'remote'"
    show_help
    exit 1
fi

if [[ "$MODE" == "remote" ]]; then
    if [[ -z "$REMOTE_HOST" || -z "$REMOTE_USER" || -z "$REMOTE_PASS" ]]; then
        error "Remote mode requires host (-h), user (-u), and password (-p) parameters"
        show_help
        exit 1
    fi
fi

# Function to execute commands locally
run_local_command() {
    eval "$1"
    return $?
}

# Function to execute commands remotely
run_remote_command() {
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_HOST "$1"
    return $?
}

# Function to execute commands based on mode
run_command() {
    if [[ "$MODE" == "local" ]]; then
        run_local_command "$1"
    else
        run_remote_command "$1"
    fi
    return $?
}

# Main execution logic
header "Docker Installation Check"

if [[ "$MODE" == "local" ]]; then
    log "Running in local mode"
    
    # 检查Docker是否已安装
    log "检查Docker是否已安装..."
    if command -v docker &> /dev/null; then
        # 检查Docker版本
        DOCKER_VERSION=$(docker --version | grep -oP '(?<=version )[0-9]+\.[0-9]+\.[0-9]+')
        log "Docker已安装，版本为 $DOCKER_VERSION"
        
        # 检查Docker服务状态
        if systemctl is-active docker &> /dev/null; then
            log "Docker服务正在运行"
            
            # 检查Docker组是否配置正确
            if groups | grep -q docker; then
                log "Docker已正确安装和配置，无需重新安装"
                exit 2
            else
                warn "Docker组配置不正确，需要修复"
                # 修复Docker组配置
                sudo usermod -aG docker $USER
                warn "Docker组已修复，需要重启以应用更改"
                # 继续执行安装流程，会导致重启
            fi
        else
            warn "Docker服务未运行，尝试启动..."
            sudo systemctl start docker
            
            # 再次检查Docker服务状态
            if systemctl is-active docker &> /dev/null; then
                log "Docker服务已成功启动，无需重新安装"
                exit 2
            else
                error "Docker服务无法启动，需要重新安装"
            fi
        fi
    else
        warn "Docker未安装，准备安装..."
        # 本地执行安装脚本
        if [ "$NO_REBOOT" = "true" ]; then
            sudo bash "$INSTALL_DOCKER_FILE" -n
        else
            sudo bash "$INSTALL_DOCKER_FILE"
        fi
        EXIT_STATUS=$?
        
        if [ $EXIT_STATUS -ne 0 ]; then
            error "Docker installation failed, exit status: $EXIT_STATUS"
            exit $EXIT_STATUS
        else
            log "Docker installation script executed successfully"
            warn "Note: Docker installation requires a reboot to take effect"
            # Return status code 0, indicating Docker has been installed and requires reboot
            exit 0
        fi
    fi
else
    log "Running in remote mode on $REMOTE_HOST"
    
    # 检查Docker是否已安装
    log "检查Docker是否已安装..."
    DOCKER_INSTALLED=$(run_remote_command "command -v docker &> /dev/null && echo 'installed' || echo 'not_installed'")

    if [ "$DOCKER_INSTALLED" = "installed" ]; then
        # 检查Docker版本
        DOCKER_VERSION=$(run_remote_command "docker --version | grep -oP '(?<=version )[0-9]+\.[0-9]+\.[0-9]+'")
        log "Docker已安装，版本为 $DOCKER_VERSION"
        
        # 检查Docker服务状态
        DOCKER_STATUS=$(run_remote_command "systemctl is-active docker")
        
        if [ "$DOCKER_STATUS" = "active" ]; then
            log "Docker服务正在运行"
            
            # 检查Docker组是否配置正确
            DOCKER_GROUP_CHECK=$(run_remote_command "groups | grep -q docker && echo 'ok' || echo 'not_ok'")
            
            if [ "$DOCKER_GROUP_CHECK" = "ok" ]; then
                log "Docker已正确安装和配置，无需重新安装"
                # 返回特殊状态码2，表示Docker已正确安装，不需要重启
                exit 2
            else
                warn "Docker组配置不正确，需要修复"
                # 修复Docker组配置
                run_remote_command "sudo usermod -aG docker $REMOTE_USER"
                warn "Docker组已修复，需要重启以应用更改"
                # 继续执行安装流程，会导致重启
            fi
        else
            warn "Docker服务未运行，尝试启动..."
            run_remote_command "sudo systemctl start docker"
            
            # 再次检查Docker服务状态
            DOCKER_STATUS=$(run_remote_command "systemctl is-active docker")
            
            if [ "$DOCKER_STATUS" = "active" ]; then
                log "Docker服务已成功启动，无需重新安装"
                # 返回特殊状态码2，表示Docker已正确安装，不需要重启
                exit 2
            else
                error "Docker服务无法启动，需要重新安装"
            fi
        fi
    else
        warn "Docker未安装，准备安装..."
    fi

    # Step 2: Copy the script to the remote machine
    log "复制Docker安装脚本到远程主机..."
    sshpass -p "$REMOTE_PASS" scp -o StrictHostKeyChecking=no ${INSTALL_DOCKER_FILE} $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH

    EXIT_STATUS1=$?

    # Check if the scp was successful
    if [ $EXIT_STATUS1 -eq 0 ]; then
        log "文件 $INSTALL_DOCKER_FILE 成功复制到 $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"
        
        # Step 3: execute the install_docker.sh on remote machine
        log "在远程主机上执行Docker安装脚本..."
        if [ "$NO_REBOOT" = "true" ]; then
            sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no -t $REMOTE_USER@$REMOTE_HOST "sudo bash $REMOTE_SCRIPT_PATH -n"
        else
            sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no -t $REMOTE_USER@$REMOTE_HOST "sudo bash $REMOTE_SCRIPT_PATH"
        fi
        EXIT_STATUS=$?
        
        if [ $EXIT_STATUS -ne 0 ]; then
            error "Docker安装失败，退出状态: $EXIT_STATUS"
            exit $EXIT_STATUS
        else
            log "Docker安装脚本执行成功"
            warn "注意：Docker安装后需要重启设备才能生效"
            # 返回状态码0，表示Docker已安装，需要重启
            exit 0
        fi
    else
        error "文件复制失败,请检查后重试"
        exit 1
    fi
fi