#!/bin/bash
# Set error handling
set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
REMOTE_USER="recomputer"
REMOTE_PASS="12345678"
REMOTE_DIR="/home/recomputer/sensecraft"
SSID="SenseCraft"
REGION=1  # Default to EU868
TAR_FILE="$SCRIPT_DIR/package/sensecraft.tar.gz"

# Help function
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -m, --mode MODE       Execution mode: 'local' or 'remote' (default: local)"
    echo "  -h, --host HOST       Remote host IP address (required for remote mode)"
    echo "  -u, --user USER       Remote username (default: recomputer)"
    echo "  -p, --pass PASS       Remote password (default: 12345678)"
    echo "  -s, --ssid SSID       SenseCraft SSID (default: SenseCraft)"
    echo "  -r, --region REGION   Region: 1=EU868, 2=US915, 3=LiveLab868 (default: 1)"
    echo "  -f, --file FILE       Path to sensecraft.tar.gz file"
    echo "  --help                Show this help message"
    echo ""
    echo "Example:"
    echo "  Local execution:  $0 -m local -s MySenseCraft -r 1"
    echo "  Remote execution: $0 -m remote -h 192.168.1.10 -s MySenseCraft -r 2"
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

# Check if no arguments were provided
if [ "$#" -eq 0 ]; then
    warn "No parameters provided"
    show_help
    exit 1
fi

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
        -s|--ssid)
            SSID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -f|--file)
            TAR_FILE="$2"
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

if [[ "$MODE" == "remote" && -z "$REMOTE_HOST" ]]; then
    error "Remote mode requires host (-h) parameter"
    show_help
    exit 1
fi

if [[ ! "$REGION" =~ ^[1-3]$ ]]; then
    error "Invalid region: $REGION. Must be 1, 2, or 3"
    show_help
    exit 1
fi

if [[ ! -f "$TAR_FILE" ]]; then
    error "SenseCraft tar file not found: $TAR_FILE"
    exit 1
fi

# Function to execute commands remotely
run_remote_command() {
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_HOST "$1"
    return $?
}

# Function to copy files remotely
copy_remote_file() {
    local src="$1"
    local dest="$2"
    sshpass -p "$REMOTE_PASS" rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no" "$src" "$dest"
    return $?
}

# Main execution logic
header "SenseCraft Installation"

# Display configuration
log "Mode: $MODE"
if [[ "$MODE" == "remote" ]]; then
    log "Remote Host: $REMOTE_HOST"
    log "Remote User: $REMOTE_USER"
fi
log "SSID: $SSID"
log "Region: $REGION"
log "Tar File: $TAR_FILE"
log "------------------------"

# Get tar file version
TAR_VERSION=$(basename "$TAR_FILE" | grep -oP 'v\d+(\.\d+)*' || echo "latest")
log "SenseCraft Version: $TAR_VERSION"

# Set frequency based on region
if [ "$REGION" -eq 1 ]; then
    FREQ="868"
    log "Using frequency: EU868"
elif [ "$REGION" -eq 2 ]; then
    FREQ="915"
    log "Using frequency: US915"
fi

if [[ "$MODE" == "local" ]]; then
    log "Running in local mode"
    
    # Check if SenseCraft is already installed
    log "Checking if SenseCraft is already installed..."
    if docker images | grep -q "sensecraft"; then
        log "SenseCraft images already exist"
        SENSECRAFT_EXISTS=1
    else
        warn "SenseCraft images do not exist, need to install"
        SENSECRAFT_EXISTS=0
    fi
    
    # If needed, extract and setup files
    if [ "$SENSECRAFT_EXISTS" -eq 0 ]; then
        # Check if the sensecraft directory already exists and has content
        if [ -d ~/sensecraft ] && [ "$(ls -A ~/sensecraft 2>/dev/null)" ]; then
            log "Sensecraft directory already exists with content, skipping extraction"
        else
            log "Extracting SenseCraft files..."
            
            # Extract files with progress display
            log "This may take a while depending on the file size..."
            # Check if pv is installed, if not use a workaround with tar verbose output
            if command -v pv >/dev/null 2>&1; then
                # Use pv to show progress with time estimation
                TAR_SIZE=$(stat -c%s "$TAR_FILE")
                pv -s "$TAR_SIZE" "$TAR_FILE" | sudo tar -xf - -C ~ || {
                    error "Failed to extract SenseCraft files"
                    exit 1
                }
                # Fix permissions after extraction
                log "Setting correct permissions..."
                sudo chown -R $USER:$USER ~/sensecraft
                sudo chmod -R 755 ~/sensecraft
            else
                # Fallback to custom progress display with time estimation
                TAR_SIZE=$(stat -c%s "$TAR_FILE")
                START_TIME=$(date +%s)
                
                # Create a temporary file to store progress
                PROGRESS_FILE=$(mktemp)
                
                # Start extraction in background and monitor progress
                (sudo tar -xvf "$TAR_FILE" -C ~ > "$PROGRESS_FILE" 2>&1) &
                EXTRACT_PID=$!
                
                # Monitor progress and display time estimation
                EXTRACTED_SIZE=0
                LAST_SIZE=0
                while kill -0 $EXTRACT_PID 2>/dev/null; do
                    # Get current extracted size by checking the progress file size as an approximation
                    CURRENT_SIZE=$(wc -c < "$PROGRESS_FILE" 2>/dev/null || echo 0)
                    
                    # Only update if size has changed
                    if [ $CURRENT_SIZE -gt $LAST_SIZE ]; then
                        LAST_SIZE=$CURRENT_SIZE
                        # Calculate progress percentage (cap at 99% since we can't accurately measure)
                        PERCENT=$(( (CURRENT_SIZE * 99) / (TAR_SIZE * 2) ))
                        # Ensure percentage doesn't exceed 99%
                        if [ $PERCENT -gt 99 ]; then
                            PERCENT=99
                        fi
                        
                        # Calculate time estimation
                        CURRENT_TIME=$(date +%s)
                        ELAPSED=$((CURRENT_TIME - START_TIME))
                        
                        if [ $PERCENT -gt 0 ]; then
                            # Estimate remaining time
                            TOTAL_TIME=$((ELAPSED * 100 / PERCENT))
                            REMAINING=$((TOTAL_TIME - ELAPSED))
                            
                            # Ensure remaining time is not negative
                            if [ $REMAINING -lt 0 ]; then
                                REMAINING=0
                            fi
                            
                            # Format time
                            MINS=$((REMAINING / 60))
                            SECS=$((REMAINING % 60))
                            
                            printf "\rExtracting: %d%% complete, estimated time remaining: %02d:%02d" $PERCENT $MINS $SECS
                        else
                            printf "\rExtracting: Calculating time remaining..."
                        fi
                    fi
                    sleep 1
                done
                
                # Check if extraction was successful
                wait $EXTRACT_PID
                EXTRACT_STATUS=$?
                rm -f "$PROGRESS_FILE"
                
                if [ $EXTRACT_STATUS -ne 0 ]; then
                    echo
                    error "Failed to extract SenseCraft files"
                    exit 1
                fi
                
                echo -e "\rExtraction complete: 100%                                      "
                
                # Fix permissions after extraction
                log "Setting correct permissions..."
                sudo chown -R $USER:$USER ~/sensecraft
                sudo chmod -R 755 ~/sensecraft
            fi
            
            # Clean old configuration files
            log "Cleaning old configuration files..."
            sudo rm -rf ~/sensecraft/docker-container-datas/sensecraft-fleet/config/* 2>/dev/null || true
            sudo rm -rf ~/sensecraft/docker-container-datas/sensecraft-chirpstack/postgresqldata/* 2>/dev/null || true
            sudo rm -rf ~/sensecraft/docker-container-datas/sensecraft-chirpstack/redisdata/* 2>/dev/null || true
        fi
    else
        log "SenseCraft is already installed, skipping file extraction"
    fi
    
    # Start SenseCraft service
    log "Starting SenseCraft service..."
    cd ~/sensecraft && sudo bash ./startup-scripts/start_sensecraft.sh "$FREQ" || {
        error "Failed to start SenseCraft service"
        exit 1
    }
    
    # Configure SSID
    log "Configuring SSID to: $SSID"
    if [ ! -f ~/sensecraft/factory-datas/env_docker_sensecraft-node-red.env ]; then
        error "Configuration file not found"
        exit 1
    fi
    
    # Display current configuration
    log "Current configuration:"
    cat ~/sensecraft/factory-datas/env_docker_sensecraft-node-red.env
    
    # Update SSID
    sudo sed -i '2s/SENSECRAFT_MISSION_PACK_ID=\\"[^\\"]*\\"/SENSECRAFT_MISSION_PACK_ID=\\"'"$SSID"'\\"/' ~/sensecraft/factory-datas/env_docker_sensecraft-node-red.env || {
        error "Failed to update SSID"
        exit 1
    }
    
    # Display updated configuration
    log "Updated configuration:"
    cat ~/sensecraft/factory-datas/env_docker_sensecraft-node-red.env
    
    log "SenseCraft installation completed successfully"
    
else
    log "Running in remote mode on $REMOTE_HOST"
    
    # Check if SenseCraft is already installed
    log "Checking if SenseCraft is already installed..."
    DOCKER_CHECK=$(run_remote_command "docker images | grep -q 'sensecraft' && echo 'SENSECRAFT_STATUS=EXISTS' || echo 'SENSECRAFT_STATUS=NOT_EXISTS'")
    
    if echo "$DOCKER_CHECK" | grep -q "SENSECRAFT_STATUS=EXISTS"; then
        log "SenseCraft images already exist on remote host"
        SENSECRAFT_EXISTS=1
    else
        warn "SenseCraft images do not exist on remote host, need to install"
        SENSECRAFT_EXISTS=0
    fi
    
    # If needed, transfer and extract files
    if [ "$SENSECRAFT_EXISTS" -eq 0 ]; then
        log "Transferring SenseCraft files..."
        
        # Get filename (without path)
        FILE_NAME=$(basename "$TAR_FILE")
        
        # Check if file already exists on remote host
        log "Checking if $FILE_NAME already exists on remote host..."
        FILE_CHECK=$(run_remote_command "ls -la ~/$FILE_NAME 2>/dev/null || echo 'FILE_NOT_FOUND'")
        
        if [[ "$FILE_CHECK" != *"FILE_NOT_FOUND"* ]]; then
            log "File $FILE_NAME already exists on remote host, skipping copy..."
        else
            # Copy file to remote host
            log "Copying $TAR_FILE to remote host..."
            copy_remote_file "$TAR_FILE" "$REMOTE_USER@$REMOTE_HOST:~" || {
                error "Failed to copy file"
                exit 1
            }
        fi
        
        # Extract files and setup on remote host
        log "Extracting files and setting up on remote host..."
        EXTRACT_RESULT=$(run_remote_command '
            # Extract file
            echo "Extracting '"$FILE_NAME"'..."
            sudo tar -xf ~/'"$FILE_NAME"' -C ~ 
            if [ $? -ne 0 ]; then
                echo "EXTRACT_FAILED"
                exit 1
            fi
            
            # Clean old configuration files, but keep tar file
            echo "Cleaning old configuration files..."
            sudo rm -rf '"$REMOTE_DIR"'/docker-container-datas/sensecraft-fleet/config/* 2>/dev/null || true
            sudo rm -rf '"$REMOTE_DIR"'/docker-container-datas/sensecraft-chirpstack/postgresqldata/* 2>/dev/null || true
            sudo rm -rf '"$REMOTE_DIR"'/docker-container-datas/sensecraft-chirpstack/redisdata/* 2>/dev/null || true
            
            echo "EXTRACT_SUCCESS"
        ')
        
        # Check if extraction was successful
        if [[ "$EXTRACT_RESULT" != *"EXTRACT_SUCCESS"* ]]; then
            error "Remote extraction and cleanup failed"
            exit 1
        fi
    else
        log "SenseCraft is already installed on remote host, skipping file transfer and extraction"
    fi
    
    # Start SenseCraft service
    log "Starting SenseCraft service on remote host..."
    START_RESULT=$(run_remote_command '
        echo "Starting SenseCraft with frequency '"$FREQ"'..."
        cd '"$REMOTE_DIR"' && sudo bash ./startup-scripts/start_sensecraft.sh '"$FREQ"'
        if [ $? -ne 0 ]; then
            echo "START_FAILED"
            exit 1
        fi
        echo "START_SUCCESS"
    ')
    
    if [[ "$START_RESULT" != *"START_SUCCESS"* ]]; then
        error "Failed to start SenseCraft on remote host"
        exit 1
    fi
    
    # Configure SSID
    log "Configuring SSID to: $SSID on remote host..."
    SSID_RESULT=$(run_remote_command "
        echo \"Setting SSID to '$SSID'...\"
        # First check if file exists
        if [ ! -f '$REMOTE_DIR'/factory-datas/env_docker_sensecraft-node-red.env ]; then
            echo \"CONFIG_FILE_NOT_FOUND\"
            exit 1
        fi
        
        # Display file contents for debugging
        echo \"Current configuration:\"
        cat '$REMOTE_DIR'/factory-datas/env_docker_sensecraft-node-red.env
        
        # Use sed to modify SSID
        sudo sed -i '2s/SENSECRAFT_MISSION_PACK_ID=\\\"[^\\\"]*\\\"/SENSECRAFT_MISSION_PACK_ID=\\\"$SSID\\\"/' '$REMOTE_DIR'/factory-datas/env_docker_sensecraft-node-red.env
        if [ \$? -ne 0 ]; then
            echo \"SSID_UPDATE_FAILED\"
            exit 1
        fi
        
        # Display updated file contents to confirm changes
        echo \"Updated configuration:\"
        cat '$REMOTE_DIR'/factory-datas/env_docker_sensecraft-node-red.env
        
        echo \"SSID_SUCCESS\"
    ")
    
    if [[ "$SSID_RESULT" == *"CONFIG_FILE_NOT_FOUND"* ]]; then
        error "Configuration file not found on remote host"
        exit 1
    elif [[ "$SSID_RESULT" == *"SSID_UPDATE_FAILED"* ]]; then
        error "Failed to update SSID on remote host"
        exit 1
    elif [[ "$SSID_RESULT" != *"SSID_SUCCESS"* ]]; then
        error "Unknown error occurred while configuring SSID on remote host"
        exit 1
    fi
fi

log "SenseCraft installation completed successfully"
exit 0