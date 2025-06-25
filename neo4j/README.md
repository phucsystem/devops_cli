# Neo4j Backup & Restore (Docker)

Docker-based scripts to backup and restore Neo4j databases easily.

## Features
- No local Neo4j install needed (just Docker)
- Interactive prompts for connection and file selection
- Safe: confirmation required before restore
- Automatic cleanup of containers and temp files

## Usage

### Backup
```bash
./backup_docker.sh
```
- Enter Neo4j URI (e.g., `bolt://host.docker.internal:7687`)
- Enter username and password
- Backup is saved in `neo4j_backups/`

### Restore
```bash
./restore_docker.sh
```
- Select a backup file
- Enter Neo4j URI, username, and password
- Type `YES` to confirm destructive restore 