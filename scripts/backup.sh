#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

mkdir -p backups
chmod 700 backups

DB_USER=$(docker compose exec -T db printenv POSTGRES_USER)
DB_NAME=$(docker compose exec -T db printenv POSTGRES_DB)

STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backups/cloudapp_${STAMP}.dump"

test ! -e "$BACKUP_FILE"

TEMP_FILE=$(mktemp "${BACKUP_FILE}.tmp.XXXXXX")
trap 'rm -f "$TEMP_FILE"' EXIT

docker compose exec -T db pg_dump \
    -U "$DB_USER" -d "$DB_NAME" -Fc > "$TEMP_FILE"

test -s "$TEMP_FILE"

docker compose exec -T db pg_restore --list \
    < "$TEMP_FILE" > /dev/null

mv "$TEMP_FILE" "$BACKUP_FILE"

sha256sum "$BACKUP_FILE" > "$BACKUP_FILE.sha256"
sha256sum -c "$BACKUP_FILE.sha256"

echo "Backup: SUCCESS"
echo "Size: $(stat -c %s "$BACKUP_FILE") bytes"
echo "$BACKUP_FILE"
