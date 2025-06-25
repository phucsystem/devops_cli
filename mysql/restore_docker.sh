#!/bin/bash

# MySQL Database Restore Script (Docker Version)
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

list_backup_files() {
    local backup_dir="$(pwd)/backups"
    if [ ! -d "$backup_dir" ]; then
        print_error "Backup directory not found: $backup_dir"
        exit 1
    fi
    local files=($(find "$backup_dir" -type f \( -name "*.sql" -o -name "*.sql.gz" \) | sort -r))
    if [ ${#files[@]} -eq 0 ]; then
        print_error "No backup files found in $backup_dir"
        exit 1
    fi
    print_info "Available backup files:"
    for i in "${!files[@]}"; do
        local file="${files[$i]}"
        local filename=$(basename "$file")
        local filesize=$(du -h "$file" | cut -f1)
        printf "%2d) %s (%s)\n" $((i+1)) "$filename" "$filesize"
    done
    echo -n "Select backup file (1-${#files[@]}): "
    read selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#files[@]} ]; then
        print_error "Invalid selection"
        exit 1
    fi
    echo "${files[$((selection-1))]}"
}

confirm_restore() {
    print_warn "⚠️  This will DROP ALL TABLES in the target database and restore from backup."
    echo -n "Type 'YES' to continue: "
    read confirmation
    if [ "$confirmation" != "YES" ]; then
        print_info "Restore cancelled."
        exit 0
    fi
}

main() {
    echo "==============================="
    echo "   MySQL Database Restore"
    echo "==============================="
    check_docker
    BACKUP_FILE=$(list_backup_files)
    print_info "Selected: $(basename "$BACKUP_FILE")"
    prompt_input "Host (e.g., host.docker.internal)" MYSQL_HOST
    prompt_input "Port (default 3306)" MYSQL_PORT
    MYSQL_PORT=${MYSQL_PORT:-3306}
    prompt_input "Database name" MYSQL_DB
    prompt_input "Username" MYSQL_USER
    prompt_input "Password" MYSQL_PASS true
    confirm_restore
    TMP_DIR=$(mktemp -d)
    RESTORE_FILE="$TMP_DIR/restore.sql"
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        print_info "Decompressing backup..."
        gunzip -c "$BACKUP_FILE" > "$RESTORE_FILE"
    else
        cp "$BACKUP_FILE" "$RESTORE_FILE"
    fi
    print_info "Dropping all tables in $MYSQL_DB..."
    docker run --rm -e MYSQL_PWD="$MYSQL_PASS" --network host mysql:latest \
        sh -c "mysql -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -e 'SET FOREIGN_KEY_CHECKS=0; SET GROUP_CONCAT_MAX_LEN=32768; SET @tables = NULL; SELECT GROUP_CONCAT(CONCAT(\'\\`\', table_name, '\\`\')) INTO @tables FROM information_schema.tables WHERE table_schema=\'$MYSQL_DB\'; SET @tables = IFNULL(@tables, 'dummy'); SET @drop = CONCAT('DROP TABLE IF EXISTS ', @tables); PREPARE stmt FROM @drop; EXECUTE stmt; DEALLOCATE PREPARE stmt;' $MYSQL_DB"
    print_info "Restoring from backup..."
    docker run --rm -e MYSQL_PWD="$MYSQL_PASS" --network host -v "$TMP_DIR:/restore" mysql:latest \
        sh -c "mysql -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER $MYSQL_DB < /restore/restore.sql"
    rm -rf "$TMP_DIR"
    print_info "Restore completed!"
}

main "$@" 