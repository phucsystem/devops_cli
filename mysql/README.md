# MySQL Backup & Restore (Docker)

Docker-based scripts to backup and restore MySQL databases easily.

## Features
- No local MySQL install needed (just Docker)
- Interactive prompts for connection and file selection
- Safe: confirmation required before restore
- Automatic cleanup of containers and temp files

## Usage

### Backup
```bash
./backup_docker.sh
```
- Enter MySQL host, port, database, username, and password
- Backup is saved in `backups/`

### Restore
```bash
./restore_docker.sh
```
- Select a backup file
- Enter MySQL host, port, database, username, and password
- Type `YES` to confirm destructive restore 