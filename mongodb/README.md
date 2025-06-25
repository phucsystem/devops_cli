# MongoDB Backup & Restore (Docker)

Docker-based scripts to backup and restore MongoDB databases easily.

## Features
- No local MongoDB install needed (just Docker)
- Interactive prompts for connection and file selection
- Safe: confirmation required before restore
- Automatic cleanup of containers and temp files

## Usage

### Backup
```bash
./backup_docker.sh
```
- Enter MongoDB host, port, database, username, and password (leave blank if not needed)
- Backup is saved in `backups/`

### Restore
```bash
./restore_docker.sh
```
- Select a backup file
- Enter MongoDB host, port, database, username, and password (leave blank if not needed)
- Type `YES` to confirm destructive restore 