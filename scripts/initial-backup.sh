#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

cd "$HOME/CloudApplication"

DB_USER=$(docker compose exec -T db printenv POSTGRES_USER)
DB_NAME=$(docker compose exec -T db printenv POSTGRES_DB)

echo "=== DATABASE SETTINGS ==="
echo "POSTGRES_USER=$DB_USER"
echo "POSTGRES_DB=$DB_NAME"

echo "=== CREATE CONTROL TABLE ==="

docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" <<'SQL'
CREATE TABLE backup_test (
    id SERIAL PRIMARY KEY,
    description VARCHAR(200) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO backup_test (description) VALUES
('Cloud Application: контрольная запись 1'),
('Cloud Application: контрольная запись 2'),
('Cloud Application: контрольная запись 3');

SELECT * FROM backup_test ORDER BY id;
SELECT COUNT(*) AS total_records FROM backup_test;
SQL

echo "=== CREATE BACKUP ==="

mkdir -p backups
chmod 700 backups

BACKUP_FILE="backups/cloudapp_$(date +%Y%m%d_%H%M%S).dump"

docker compose exec -T db pg_dump \
    -U "$DB_USER" -d "$DB_NAME" -Fc > "$BACKUP_FILE"

test -s "$BACKUP_FILE"

echo "=== BACKUP FILE ==="
ls -lh "$BACKUP_FILE"
file "$BACKUP_FILE"
stat -c 'Size: %s bytes' "$BACKUP_FILE"

echo "=== BACKUP CONTENTS ==="

docker compose exec -T db pg_restore --list \
    < "$BACKUP_FILE" > evidence/backup_contents.txt

grep backup_test evidence/backup_contents.txt

echo "=== SHA256 CHECK ==="

sha256sum "$BACKUP_FILE" > "$BACKUP_FILE.sha256"
sha256sum -c "$BACKUP_FILE.sha256"

printf '%s\n' "$BACKUP_FILE" > evidence/first_backup_path.txt

echo "=== BACKUP COMPLETED SUCCESSFULLY ==="
