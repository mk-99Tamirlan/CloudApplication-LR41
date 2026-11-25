#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

cd "$HOME/CloudApplication"

DB_USER=$(docker compose exec -T db printenv POSTGRES_USER)
DB_NAME=$(docker compose exec -T db printenv POSTGRES_DB)

FIRST_BACKUP=$(cat evidence/first_backup_path.txt)

sql() {
    docker compose exec -T db psql \
        -v ON_ERROR_STOP=1 \
        -U "$DB_USER" -d "$1" "${@:2}"
}

echo "=== INDEPENDENT TASK ==="

test "$(sql "$DB_NAME" -Atc 'SELECT COUNT(*) FROM backup_test;')" = 3

echo "=== ADD TWO RECORDS ==="

sql "$DB_NAME" -c "INSERT INTO backup_test (description) VALUES
('Cloud Application: контрольная запись 4'),
('Cloud Application: контрольная запись 5');"

sql "$DB_NAME" -c "SELECT * FROM backup_test ORDER BY id;"

echo "=== SECOND BACKUP AND EXECUTION TIME ==="

TIMEFORMAT='Backup time: %3R seconds'
time ./scripts/backup.sh | tee evidence/second_backup.log

SECOND_BACKUP=$(tail -n 1 evidence/second_backup.log)

printf '%s\n' "$SECOND_BACKUP" > evidence/second_backup_path.txt

echo "=== ADD RECORD WITHOUT BACKUP ==="

sql "$DB_NAME" -c "INSERT INTO backup_test (description) VALUES
('Cloud Application: контрольная запись 6');"

echo "=== VERIFY BOTH BACKUPS ==="

sha256sum -c "$FIRST_BACKUP.sha256"
sha256sum -c "$SECOND_BACKUP.sha256"

echo "=== CREATE SEPARATE TEST DATABASES ==="

docker compose exec -T db createdb -U "$DB_USER" cloudapp_restore_v1
docker compose exec -T db createdb -U "$DB_USER" cloudapp_restore_v2

echo "=== RESTORE FIRST BACKUP ==="

docker compose exec -T db pg_restore \
    -U "$DB_USER" -d cloudapp_restore_v1 \
    --no-owner --exit-on-error \
    < "$FIRST_BACKUP"

echo "=== RESTORE SECOND BACKUP ==="

docker compose exec -T db pg_restore \
    -U "$DB_USER" -d cloudapp_restore_v2 \
    --no-owner --exit-on-error \
    < "$SECOND_BACKUP"

echo "=== MEASURE RESTORE TIME ==="

TIMEFORMAT='Restore time: %3R seconds'
time docker compose exec -T db pg_restore \
    -U "$DB_USER" -d cloudapp_restore_v2 \
    --clean --if-exists --no-owner \
    --exit-on-error --single-transaction \
    < "$SECOND_BACKUP"

echo "=== SOURCE DATABASE ==="
sql "$DB_NAME" -c "SELECT * FROM backup_test ORDER BY id;"

echo "=== RESTORED VERSION 1 ==="
sql cloudapp_restore_v1 -c "SELECT * FROM backup_test ORDER BY id;"

echo "=== RESTORED VERSION 2 ==="
sql cloudapp_restore_v2 -c "SELECT * FROM backup_test ORDER BY id;"

SOURCE_COUNT=$(sql "$DB_NAME" -Atc "SELECT COUNT(*) FROM backup_test;")
V1_COUNT=$(sql cloudapp_restore_v1 -Atc "SELECT COUNT(*) FROM backup_test;")
V2_COUNT=$(sql cloudapp_restore_v2 -Atc "SELECT COUNT(*) FROM backup_test;")

echo "=== FINAL COMPARISON ==="

echo "First backup: $V1_COUNT records"
echo "Second backup: $V2_COUNT records"
echo "Current database: $SOURCE_COUNT records"

test "$SOURCE_COUNT" = 6
test "$V1_COUNT" = 3
test "$V2_COUNT" = 5

sql "$DB_NAME" -Atc "SELECT * FROM backup_test WHERE id <= 3 ORDER BY id;" > backups/expected_v1.txt
sql cloudapp_restore_v1 -Atc "SELECT * FROM backup_test ORDER BY id;" > backups/actual_v1.txt

sql "$DB_NAME" -Atc "SELECT * FROM backup_test WHERE id <= 5 ORDER BY id;" > backups/expected_v2.txt
sql cloudapp_restore_v2 -Atc "SELECT * FROM backup_test ORDER BY id;" > backups/actual_v2.txt

diff -u backups/expected_v1.txt backups/actual_v1.txt
diff -u backups/expected_v2.txt backups/actual_v2.txt

echo "=== BACKUP FILE SIZES ==="

stat -c '%n: %s bytes' "$FIRST_BACKUP" "$SECOND_BACKUP"

echo "=== BACKUP DIRECTORY ==="

ls -lh backups/*.dump*

echo "=== GIT SECURITY CHECK ==="

git check-ignore .env "$FIRST_BACKUP" "$SECOND_BACKUP"
git status --short

echo "=== ALL DATABASE TESTS PASSED ==="
