#!/usr/bin/env bash
set -Eeuo pipefail

cd "$HOME/CloudApplication"

echo "=== CONTAINER STATUS ==="
docker compose ps

echo "=== APPLICATION HEALTH ==="
curl -fsS http://127.0.0.1:8000/health
echo

echo "=== UNAUTHORIZED REQUEST ==="
STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/records)
echo "HTTP status: $STATUS"
test "$STATUS" = 401

echo "=== AUTHORIZED REQUEST ==="
APP_PASSWORD=$(grep '^APP_PASSWORD=' .env | cut -d= -f2-)

curl -fsS -u "student:$APP_PASSWORD" \
    http://127.0.0.1:8000/records \
    | python3 -m json.tool --no-ensure-ascii \
    | tee evidence/application_records.json

python3 -c 'import json; d=json.load(open("evidence/application_records.json")); assert d["count"] == 6; assert d["database"] == "connected"; print("Application verification: SUCCESS")'

echo "=== DATABASE STATUS ==="
docker compose exec -T db psql -U cloudapp -d cloudapp \
    -c "SELECT COUNT(*) FROM backup_test;"

echo "=== ALL APPLICATION TESTS PASSED ==="
