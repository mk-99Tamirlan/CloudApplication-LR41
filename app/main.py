import os
import psycopg
from flask import Flask, jsonify, request, Response
from hmac import compare_digest

app = Flask(__name__)

def authorized():
    auth = request.authorization
    return bool(
        auth
        and compare_digest(auth.username or "", "student")
        and compare_digest(
            auth.password or "",
            os.environ["APP_PASSWORD"]
        )
    )

def get_records():
    with psycopg.connect(
        host="db",
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"]
    ) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, description, created_at "
                "FROM backup_test ORDER BY id"
            )
            return [
                {"id": r[0], "description": r[1],
                 "created_at": str(r[2])}
                for r in cur.fetchall()
            ]

@app.get("/health")
def health():
    return jsonify(status="ok")

@app.get("/")
@app.get("/records")
def records():
    if not authorized():
        return Response(
            "Authorization required", 401,
            {"WWW-Authenticate": 'Basic realm="Cloud Application"'}
        )
    data = get_records()
    return jsonify(
        application="Cloud Application",
        database="connected",
        count=len(data),
        records=data
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
