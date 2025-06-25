#!/bin/bash

# Neo4j Database Backup Script (Docker Version)
# This script runs the backup process inside a Docker container

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

# Function to create backup directory
create_backup_dir() {
    local backup_dir="$(pwd)/neo4j_backups"
    
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
        print_info "Created backup directory: $backup_dir"
    fi
    
    echo "$backup_dir"
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

# Function to run backup in Docker container
run_backup_in_docker() {
    local uri="$1"
    local username="$2"
    local password="$3"
    local backup_dir="$4"
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_filename="neo4j_backup_$timestamp.cypher"
    local container_name="neo4j-backup-$(date +%s)"
    
    print_docker "Starting backup container: $container_name"
    print_info "Backup file: $backup_filename"
    
    # Create the backup script inside container
    local backup_script='
#!/bin/bash
set -e

URI="$1"
USERNAME="$2"
PASSWORD="$3"
BACKUP_FILE="$4"

echo "Starting Neo4j backup process..."

# Try APOC export first
APOC_QUERY="
CALL apoc.export.cypher.all(\"/backups/$BACKUP_FILE\", {
    format: \"cypher-shell\",
    useOptimizations: {type: \"UNWIND_BATCH\", unwindBatchSize: 20}
})
YIELD file, nodes, relationships, properties, time
RETURN file, nodes, relationships, properties, time;
"

if echo "$APOC_QUERY" | cypher-shell -a "$URI" -u "$USERNAME" -p "$PASSWORD" --format plain > /dev/null 2>&1; then
    echo "✓ Backup completed using APOC export"
else
    echo "⚠ APOC export failed, using alternative method..."
    
    # Alternative: Manual export
    {
        echo "// Neo4j Database Backup - Generated on $(date)"
        echo "// URI: $URI"
        echo ""
        
        echo "// === CONSTRAINTS AND INDEXES ==="
        echo "SHOW CONSTRAINTS;" | cypher-shell -a "$URI" -u "$USERNAME" -p "$PASSWORD" --format plain || true
        echo "SHOW INDEXES;" | cypher-shell -a "$URI" -u "$USERNAME" -p "$PASSWORD" --format plain || true
        
        echo ""
        echo "// === NODES ==="
        echo "MATCH (n) RETURN n;" | cypher-shell -a "$URI" -u "$USERNAME" -p "$PASSWORD" --format plain
        
        echo ""
        echo "// === RELATIONSHIPS ==="
        echo "MATCH ()-[r]->() RETURN r;" | cypher-shell -a "$URI" -u "$USERNAME" -p "$PASSWORD" --format plain
        
    } > "/backups/$BACKUP_FILE"
    
    echo "✓ Backup completed using manual export"
fi

# Compress the backup if possible
if command -v gzip &> /dev/null && [ -f "/backups/$BACKUP_FILE" ]; then
    gzip "/backups/$BACKUP_FILE"
    echo "✓ Backup compressed: ${BACKUP_FILE}.gz"
    BACKUP_FILE="${BACKUP_FILE}.gz"
fi

# Show file info
if [ -f "/backups/$BACKUP_FILE" ]; then
    FILE_SIZE=$(du -h "/backups/$BACKUP_FILE" | cut -f1)
    echo "✓ Backup file size: $FILE_SIZE"
    echo "✓ Backup saved to: /backups/$BACKUP_FILE"
else
    echo "✗ Backup file not found!"
    exit 1
fi
'

    # Run the backup in Docker container
    print_docker "Running backup process in container..."
    
    if docker run --rm \
        --name "$container_name" \
        -v "$backup_dir:/backups" \
        -e BACKUP_SCRIPT="$backup_script" \
        neo4j:latest \
        bash -c 'echo "$BACKUP_SCRIPT" > /tmp/backup.sh && chmod +x /tmp/backup.sh && /tmp/backup.sh "'"$uri"'" "'"$username"'" "'"$password"'" "'"$backup_filename"'"'; then
        
        print_docker "Container completed successfully"
        print_info "Backup process completed!"
        
        # Show final backup file info
        local final_backup_file="$backup_dir/$backup_filename"
        if [ -f "$final_backup_file.gz" ]; then
            final_backup_file="$final_backup_file.gz"
        fi
        
        if [ -f "$final_backup_file" ]; then
            local file_size=$(du -h "$final_backup_file" | cut -f1)
            print_info "Final backup: $final_backup_file ($file_size)"
        fi
        
    else
        print_error "Backup failed in Docker container"
        exit 1
    fi
    
    print_docker "Container automatically removed"
}

# Function to cleanup (in case of manual intervention needed)
cleanup() {
    print_warn "Cleaning up any remaining containers..."
    docker ps -a --filter "name=neo4j-backup-" --filter "name=neo4j-test-" -q | xargs -r docker rm -f
}

# Main execution
main() {
    echo "================================================="
    echo "      Neo4j Database Backup (Docker Version)"
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
    
    # Create backup directory
    BACKUP_DIR=$(create_backup_dir)
    echo
    
    # Run backup in Docker
    run_backup_in_docker "$NEO4J_URI" "$NEO4J_USER" "$NEO4J_PASS" "$BACKUP_DIR"
    echo
    
    print_info "Backup process completed successfully!"
    print_info "All Docker containers have been automatically removed."
}

# Handle script interruption
trap 'print_warn "Script interrupted. Cleaning up..."; cleanup; exit 1' INT TERM

# Run main function
main "$@" 