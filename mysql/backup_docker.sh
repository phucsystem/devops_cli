#!/bin/bash

# MySQL Database Backup Script (Docker Version)
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
    echo "   MySQL Database Backup"
    echo "==============================="
    check_docker
    print_info "Please provide MySQL connection details:"
    prompt_input "Host (e.g., host.docker.internal)" MYSQL_HOST
    prompt_input "Port (default 3306)" MYSQL_PORT
    MYSQL_PORT=${MYSQL_PORT:-3306}
    prompt_input "Database name" MYSQL_DB
    prompt_input "Username" MYSQL_USER
    prompt_input "Password" MYSQL_PASS true
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_DIR="$(pwd)/backups"
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/mysql_backup_${MYSQL_DB}_$TIMESTAMP.sql"
    print_info "Starting backup to $BACKUP_FILE.gz"
    docker run --rm \
        -e MYSQL_PWD="$MYSQL_PASS" \
        --network host \
        -v "$BACKUP_DIR:/backup" \
        mysql:latest \
        sh -c "mysqldump -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER $MYSQL_DB > /backup/$(basename $BACKUP_FILE)"
    if command -v gzip &> /dev/null; then
        gzip "$BACKUP_FILE"
        print_info "Backup compressed: $BACKUP_FILE.gz"
    fi
    print_info "Backup completed!"
}

main "$@" 