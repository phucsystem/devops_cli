#!/bin/bash

# MongoDB Database Backup Script (Docker Version)
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local mask="${3:-false}"
    if [ "$mask" = "true" ]; then
        echo -n "$prompt: "
        read -s value
        echo
    else
        echo -n "$prompt: "
        read value
    fi
    eval "$var_name='$value'"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker."
        exit 1
    fi
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running."
        exit 1
    fi
}

main() {
    echo "==============================="
    echo "   MongoDB Database Backup"
    echo "==============================="
    check_docker
    print_info "Please provide MongoDB connection details:"
    prompt_input "Host (e.g., host.docker.internal)" MONGO_HOST
    prompt_input "Port (default 27017)" MONGO_PORT
    MONGO_PORT=${MONGO_PORT:-27017}
    prompt_input "Database name" MONGO_DB
    prompt_input "Username (leave blank for none)" MONGO_USER
    prompt_input "Password (leave blank for none)" MONGO_PASS true
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_DIR="$(pwd)/backups"
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/mongo_backup_${MONGO_DB}_$TIMESTAMP.archive.gz"
    print_info "Starting backup to $BACKUP_FILE"
    AUTH_ARGS=""
    if [ -n "$MONGO_USER" ]; then
        AUTH_ARGS="--username $MONGO_USER --password $MONGO_PASS --authenticationDatabase admin"
    fi
    docker run --rm --network host -v "$BACKUP_DIR:/backup" mongo:latest \
        sh -c "mongodump --host $MONGO_HOST --port $MONGO_PORT --db $MONGO_DB $AUTH_ARGS --archive=/backup/tmp.archive && gzip /backup/tmp.archive && mv /backup/tmp.archive.gz /backup/$(basename $BACKUP_FILE)"
    print_info "Backup completed!"
}

main "$@" 