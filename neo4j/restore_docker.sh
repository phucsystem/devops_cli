#!/bin/bash

# Neo4j Database Restore Script (Docker Version)
# This script runs the restore process inside a Docker container

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_docker() { echo -e "${BLUE}[DOCKER]${NC} $1"; }

# Function to prompt for input with optional masking
prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local mask="${3:-false}"
    
    if [ "$mask" = "true" ]; then
        echo -n "$prompt: "
        read -s value
        echo  # New line after hidden input
    else
        echo -n "$prompt: "
        read value
    fi
    
    eval "$var_name='$value'"
}

# Function to check Docker availability
check_docker() {
    print_info "Checking Docker availability..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker first"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    
    print_info "Docker check passed"
}

# Function to list available backup files
list_backup_files() {
    local backup_dir="$(pwd)/neo4j_backups"
    
    if [ ! -d "$backup_dir" ]; then
        print_error "Backup directory not found: $backup_dir"
        print_info "Please run the backup script first or specify a different directory"
        exit 1
    fi
    
    print_info "Available backup files:"
    echo
    
    local files=($(find "$backup_dir" -name "*.cypher*" -type f | sort -r))
    
    if [ ${#files[@]} -eq 0 ]; then
        print_error "No backup files found in $backup_dir"
        exit 1
    fi
    
    for i in "${!files[@]}"; do
        local file="${files[$i]}"
        local filename=$(basename "$file")
        local filesize=$(du -h "$file" | cut -f1)
        local filedate=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        
        printf "%2d) %s (%s) - %s\n" $((i+1)) "$filename" "$filesize" "$filedate"
    done
    
    echo
    echo -n "Select backup file (1-${#files[@]}): "
    read selection
    
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#files[@]} ]; then
        print_error "Invalid selection"
        exit 1
    fi
    
    echo "${files[$((selection-1))]}"
}

# Function to test Neo4j connection using Docker
test_connection() {
    local uri="$1"
    local username="$2"
    local password="$3"
    
    print_info "Testing connection to Neo4j using Docker..."
    
    local container_name="neo4j-test-$(date +%s)"
    
    if docker run --rm --name "$container_name" \
        neo4j:latest \
        cypher-shell -a "$uri" -u "$username" -p "$password" \
        "RETURN 1 as test;" > /dev/null 2>&1; then
        print_info "Connection successful"
        return 0
    else
        print_error "Connection failed. Please check your credentials and URI"
        return 1
    fi
}

# Function to confirm database clear
confirm_restore() {
    local backup_file="$1"
    local filename=$(basename "$backup_file")
    
    print_warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    print_warn "This will:"
    print_warn "1. Clear ALL existing data in the target database"
    print_warn "2. Restore data from: $filename"
    print_warn "3. This action CANNOT be undone"
    echo
    
    echo -n "Are you sure you want to proceed? (type 'YES' to confirm): "
    read confirmation
    
    if [ "$confirmation" != "YES" ]; then
        print_info "Restore cancelled by user"
        exit 0
    fi
    
    print_info "Restore confirmed, proceeding..."
}

# Function to prepare backup file
prepare_backup_file() {
    local backup_file="$1"
    local work_dir="$2"
    
    local filename=$(basename "$backup_file")
    local prepared_file="$work_dir/$filename"
    
    # Copy backup file to work directory
    cp "$backup_file" "$prepared_file"
    
    # Decompress if it's a .gz file
    if [[ "$prepared_file" == *.gz ]]; then
        print_info "Decompressing backup file..."
        gunzip "$prepared_file"
        prepared_file="${prepared_file%.gz}"
    fi
    
    echo "$prepared_file"
}

# Function to run restore in Docker container
run_restore_in_docker() {
    local uri="$1"
    local username="$2"
    local password="$3"
    local backup_file="$4"
    
    local container_name="neo4j-restore-$(date +%s)"
    local work_dir="$(pwd)/neo4j_restore_temp"
    
    # Create temporary work directory
    mkdir -p "$work_dir"
    
    # Prepare backup file
    local prepared_file=$(prepare_backup_file "$backup_file" "$work_dir")
    local restore_filename=$(basename "$prepared_file")
    
    print_docker "Starting restore container: $container_name"
    print_info "Restore file: $restore_filename"
    
    # Create the restore script inside container
    local restore_script='
#!/bin/bash
set -e

URI="$1"
USERNAME="$2"
PASSWORD="$3"
RESTORE_FILE="$4"

echo "Starting Neo4j restore process..."

# First, clear the database
echo "🗑️  Clearing existing database..."
CLEAR_QUERY="
MATCH (n)
DETACH DELETE n;
"

if echo "$CLEAR_QUERY" | cypher-shell -a "$URI" -u "$USERNAME" -p "$PASSWORD" --format plain > /dev/null 2>&1; then
    echo "✓ Database cleared successfully"
else
    echo "⚠ Warning: Failed to clear database or database was already empty"
fi

# Check if backup file exists
if [ ! -f "/restore/$RESTORE_FILE" ]; then
    echo "✗ Restore file not found: /restore/$RESTORE_FILE"
    exit 1
fi

echo "📁 Restore file size: $(du -h "/restore/$RESTORE_FILE" | cut -f1)"

# Try to restore using cypher-shell
echo "🔄 Restoring data from backup..."

# Check if file contains APOC export format or manual export
if grep -q "CALL apoc" "/restore/$RESTORE_FILE" 2>/dev/null; then
    # APOC format - try to run as is
    echo "📦 Detected APOC export format"
    if cypher-shell -a "$URI" -u "$USERNAME" -p "$PASSWORD" --format plain < "/restore/$RESTORE_FILE"; then
        echo "✓ Restore completed using APOC format"
    else
        echo "✗ APOC restore failed"
        exit 1
    fi
else
    # Manual export format - process line by line
    echo "📋 Detected manual export format, processing..."
    
    # Filter out comments and empty lines, then execute
    grep -v "^//" "/restore/$RESTORE_FILE" | grep -v "^$" > "/tmp/filtered_restore.cypher"
    
    if [ -s "/tmp/filtered_restore.cypher" ]; then
        if cypher-shell -a "$URI" -u "$USERNAME" -p "$PASSWORD" --format plain < "/tmp/filtered_restore.cypher"; then
            echo "✓ Restore completed using manual format"
        else
            echo "⚠ Some restore operations may have failed, but continuing..."
        fi
    else
        echo "⚠ No valid Cypher statements found in restore file"
    fi
fi

# Verify restore
echo "🔍 Verifying restore..."
NODE_COUNT=$(echo "MATCH (n) RETURN count(n) as nodes;" | cypher-shell -a "$URI" -u "$USERNAME" -p "$PASSWORD" --format plain | tail -1)
REL_COUNT=$(echo "MATCH ()-[r]->() RETURN count(r) as relationships;" | cypher-shell -a "$URI" -u "$USERNAME" -p "$PASSWORD" --format plain | tail -1)

echo "✓ Restore verification:"
echo "  - Nodes: $NODE_COUNT"
echo "  - Relationships: $REL_COUNT"

if [ "$NODE_COUNT" = "0" ] && [ "$REL_COUNT" = "0" ]; then
    echo "⚠ Warning: No data was restored. Please check your backup file."
else
    echo "🎉 Restore completed successfully!"
fi
'

    # Run the restore in Docker container
    print_docker "Running restore process in container..."
    
    if docker run --rm \
        --name "$container_name" \
        -v "$work_dir:/restore" \
        -e RESTORE_SCRIPT="$restore_script" \
        neo4j:latest \
        bash -c 'echo "$RESTORE_SCRIPT" > /tmp/restore.sh && chmod +x /tmp/restore.sh && /tmp/restore.sh "'"$uri"'" "'"$username"'" "'"$password"'" "'"$restore_filename"'"'; then
        
        print_docker "Container completed successfully"
        print_info "Restore process completed!"
        
    else
        print_error "Restore failed in Docker container"
        # Cleanup temp directory
        rm -rf "$work_dir"
        exit 1
    fi
    
    # Cleanup temp directory
    rm -rf "$work_dir"
    print_docker "Container automatically removed"
    print_info "Temporary files cleaned up"
}

# Function to cleanup (in case of manual intervention needed)
cleanup() {
    print_warn "Cleaning up any remaining containers..."
    docker ps -a --filter "name=neo4j-restore-" --filter "name=neo4j-test-" -q | xargs -r docker rm -f
    
    # Cleanup temp directory if it exists
    if [ -d "$(pwd)/neo4j_restore_temp" ]; then
        rm -rf "$(pwd)/neo4j_restore_temp"
        print_info "Temporary files cleaned up"
    fi
}

# Main execution
main() {
    echo "================================================="
    echo "      Neo4j Database Restore (Docker Version)"
    echo "================================================="
    echo
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Check Docker
    check_docker
    echo
    
    # Pull Neo4j image if not present
    print_docker "Ensuring Neo4j Docker image is available..."
    docker pull neo4j:latest > /dev/null 2>&1 || true
    echo
    
    # List and select backup file
    BACKUP_FILE=$(list_backup_files)
    echo
    
    # Prompt for connection details
    print_info "Please provide Neo4j connection details:"
    prompt_input "Neo4j URI (e.g., bolt://host.docker.internal:7687)" "NEO4J_URI"
    prompt_input "Username" "NEO4J_USER"
    prompt_input "Password" "NEO4J_PASS" "true"
    echo
    
    # Validate inputs
    if [[ -z "$NEO4J_URI" || -z "$NEO4J_USER" || -z "$NEO4J_PASS" ]]; then
        print_error "All fields are required"
        exit 1
    fi
    
    # Test connection
    if ! test_connection "$NEO4J_URI" "$NEO4J_USER" "$NEO4J_PASS"; then
        exit 1
    fi
    echo
    
    # Confirm restore operation
    confirm_restore "$BACKUP_FILE"
    echo
    
    # Run restore in Docker
    run_restore_in_docker "$NEO4J_URI" "$NEO4J_USER" "$NEO4J_PASS" "$BACKUP_FILE"
    echo
    
    print_info "Restore process completed successfully!"
    print_info "All Docker containers have been automatically removed."
}

# Handle script interruption
trap 'print_warn "Script interrupted. Cleaning up..."; cleanup; exit 1' INT TERM

# Run main function
main "$@" 