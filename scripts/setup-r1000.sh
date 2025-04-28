#!/bin/bash
# Set error handling
set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRESS_FILE="${SCRIPT_DIR}/.installation_progress.log"

# Default values
MODE="local"  # Default to local execution
R1000_IP=""
REMOTE_USER="recomputer"
REMOTE_PASS="12345678"
FACTORY_IP=""
SSID=""
REGION=""

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Help function
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -m, --mode MODE       Execution mode: 'local' or 'remote' (default: local)"
    echo "  -i, --ip IP           R1000 IP address (required for remote mode)"
    echo "  -u, --user USER       Remote username (default: recomputer)"
    echo "  -p, --pass PASS       Remote password (default: 12345678)"
    echo "  -f, --factory-ip IP   Factory IP address for Docker registry (required for remote mode, optional for local mode)"
    echo "  -s, --ssid SSID       WiFi SSID for Sensecraft"
    echo "  -r, --region REGION   Region for Sensecraft"
    echo "  --help                Show this help message"
    echo ""
    echo "Example:"
    echo "  Local execution:  $0 -m local -s MySenseCraft -r US"
    echo "  Local execution with factory IP:  $0 -m local -f 192.168.1.100 -s MySenseCraft -r US"
    echo "  Remote execution: $0 -m remote -i 192.168.1.10 -f 192.168.1.100 -s MySenseCraft -r US"
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
        -i|--ip)
            R1000_IP="$2"
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
        -f|--factory-ip)
            FACTORY_IP="$2"
            shift 2
            ;;
        -s|--ssid)
            SSID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
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

if [[ "$MODE" == "remote" && -z "$R1000_IP" ]]; then
    error "Remote mode requires R1000 IP address (-i)"
    show_help
    exit 1
fi

if [[ "$MODE" == "remote" && -z "$FACTORY_IP" ]]; then
    error "Factory IP address (-f) is required for remote mode"
    show_help
    exit 1
fi

if [[ -z "$SSID" || -z "$REGION" ]]; then
    error "SSID (-s) and REGION (-r) are required"
    show_help
    exit 1
fi

# Function to execute commands remotely
run_remote_command() {
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no $REMOTE_USER@$R1000_IP "$1"
    return $?
}

header "R1000 Setup"

log "Installing Docker"
if [[ "$MODE" == "local" ]]; then
    # Local mode - directly run the script
    bash $SCRIPT_DIR/hot-fix-docker.sh -m local
else
    # Remote mode - pass remote parameters
    bash $SCRIPT_DIR/hot-fix-docker.sh -m remote -h "$R1000_IP" -u "$REMOTE_USER" -p "$REMOTE_PASS" -f "$FACTORY_IP"
fi
EXIT_STATUS=$?

if [ $EXIT_STATUS -eq 1 ]; then
    error "Failed to install Docker, please retry"
    exit $EXIT_STATUS
elif [ $EXIT_STATUS -eq 0 ]; then
    warn "Docker has been installed, please reboot the device..."
    if [[ "$MODE" == "remote" ]]; then
        bash $SCRIPT_DIR/wait_for_reboot.sh $R1000_IP
        run_remote_command "sudo rm ~/install_docker.sh"
    else
        log "Local mode, please manually reboot the device and continue"
        read -p "Press Enter to continue..." </dev/tty
    fi
elif [ $EXIT_STATUS -eq 2 ]; then
    log "Docker has been installed, no need to reboot"
    # Skip reboot step, but still clean up script file (if exists)
    if [[ "$MODE" == "remote" ]]; then
        run_remote_command "if [ -f ~/install_docker.sh ]; then sudo rm ~/install_docker.sh; fi"
    fi
fi
log "Docker installation completed"

header "Setting Sensecraft"
if [[ "$MODE" == "local" ]]; then
    # 本地执行Sensecraft设置
    if [ -f "/home/recomputer/livelab-mission-setup/r1000/script/modify_env.sh" ]; then
        bash /home/recomputer/livelab-mission-setup/r1000/script/modify_env.sh $SSID $REGION $R1000_IP
        EXIT_STATUS=$?
    else
        error "找不到Sensecraft设置脚本，请确认路径是否正确"
        EXIT_STATUS=1
    fi
else
    # 远程执行Sensecraft设置
    # 首先检查是否有websocket-meshtastic-bridge容器运行
    run_remote_command "docker run -d -p 5800:5800 --device=/dev/ttyACM0:/dev/ttyACM0 --restart=always --name websocket-meshtastic-bridge sensecraft-missionpack.seeed.cn/suzhou/websocket-meshtastic-bridge:latest"
    
    # 执行远程Sensecraft设置
    if [ -f "/home/pi/livelab-mission-setup/r1000/script/modify_env.sh" ]; then
        bash /home/pi/livelab-mission-setup/r1000/script/modify_env.sh $SSID $REGION $R1000_IP
        EXIT_STATUS=$?
    else
        error "找不到Sensecraft设置脚本，请确认路径是否正确"
        EXIT_STATUS=1
    fi
fi
log "Sensecraft设置完成"

if [ $EXIT_STATUS -ne 0 ]; then
    error "设置Sensecraft失败,请重试"
    exit $EXIT_STATUS
fi

log "R1000 配置成功！"
