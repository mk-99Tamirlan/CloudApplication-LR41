#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

cd "$HOME/CloudApplication"

DB_USER=$(docker compose exec -T db printenv POSTGRES_USER)
DB_NAME=$(docker compose exec -T db printenv POSTGRES_DB)
RESTORE_DB="cloudapp_restore"
BACKUP_FILE=$(cat evidence/first_backup_path.txt)

test "$RESTORE_DB" != "$DB_NAME"

echo "=== VERIFY BACKUP ==="
sha256sum -c "$BACKUP_FILE.sha256"

echo "=== CREATE TEST DATABASE ==="

docker compose exec -T db createdb \
    -U "$DB_USER" "$RESTORE_DB"

echo "=== FIRST RESTORE ==="

docker compose exec -T db pg_restore \
    -U "$DB_USER" \
    -d "$RESTORE_DB" \
    --no-owner \
    --exit-on-error \
    < "$BACKUP_FILE"

docker compose exec -T db psql \
    -U "$DB_USER" -d "$RESTORE_DB" \
    -c "SELECT * FROM backup_test ORDER BY id;"

echo "=== RECORDS BEFORE DATA LOSS ==="

docker compose exec -T db psql \
    -U "$DB_USER" -d "$RESTORE_DB" \
    -c "SELECT COUNT(*) FROM backup_test;"

echo "=== SIMULATE DATA LOSS ==="

docker compose exec -T db psql \
    -v ON_ERROR_STOP=1 \
    -U "$DB_USER" -d "$RESTORE_DB" \
    -c "DELETE FROM backup_test;"

echo "=== RECORDS AFTER DATA LOSS ==="

docker compose exec -T db psql \
    -U "$DB_USER" -d "$RESTORE_DB" \
    -c "SELECT COUNT(*) FROM backup_test;"

echo "=== SOURCE DATABASE IS SAFE ==="

docker compose exec -T db psql \
    -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT COUNT(*) FROM backup_test;"

echo "=== RESTORE AFTER DATA LOSS ==="

docker compose exec -T db pg_restore \
    -U "$DB_USER" \
    -d "$RESTORE_DB" \
    --clean \
    --if-exists \
    --no-owner \
    --exit-on-error \
    --single-transaction \
    < "$BACKUP_FILE"

echo "=== RESTORED TABLES ==="

docker compose exec -T db psql \
    -U "$DB_USER" -d "$RESTORE_DB" \
    -c '\dt'

echo "=== RESTORED RECORDS ==="

docker compose exec -T db psql \
    -U "$DB_USER" -d "$RESTORE_DB" \
    -c "SELECT * FROM backup_test ORDER BY id;"

echo "=== RESTORED RECORD COUNT ==="

docker compose exec -T db psql \
    -U "$DB_USER" -d "$RESTORE_DB" \
    -c "SELECT COUNT(*) FROM backup_test;"

echo "=== COMPARE SOURCE AND RESTORED DATA ==="

docker compose exec -T db psql \
    -U "$DB_USER" -d "$DB_NAME" \
    -At -c "SELECT * FROM backup_test ORDER BY id;" \
    > backups/source_records.txt

docker compose exec -T db psql \
    -U "$DB_USER" -d "$RESTORE_DB" \
    -At -c "SELECT * FROM backup_test ORDER BY id;" \
    > backups/restored_records.txt

diff -u backups/source_records.txt backups/restored_records.txt

if cmp -s backups/source_records.txt backups/restored_records.txt; then
    echo "Verification: SUCCESS"
else
    echo "Verification: FAILED"
    exit 1
fi

echo "=== RESTORE TEST COMPLETED ==="
