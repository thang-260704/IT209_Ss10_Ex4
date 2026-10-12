#!/usr/bin/env bash
# Session 10 - Bài 4: Custom Bridge Network + Named Volume bằng Docker CLI
# Chạy: bash commands.sh
set -euo pipefail

NET=app-net
VOL=db-data
DB=db-server
APP=app-container
APP_IMAGE=hw-backend:v1          # image Express từ bài 2 (Node.js 18 Alpine)
DB_USER=appuser
DB_NAME=appdb
DB_PASS="${DB_PASS:-AppSecure@123}"   # có thể ghi đè: DB_PASS=xxx bash commands.sh

step() { echo; echo "===== $* ====="; }

wait_db() {
  echo -n "Chờ PostgreSQL sẵn sàng"
  until docker exec "$DB" pg_isready -U "$DB_USER" -d "$DB_NAME" -q; do echo -n "."; sleep 1; done
  echo " OK"
}

run_db() {
  docker run -d --name "$DB" \
    --network "$NET" \
    -v "$VOL":/var/lib/postgresql/data \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASS" \
    -e POSTGRES_DB="$DB_NAME" \
    postgres:15-alpine
}

psql_db() { docker exec "$DB" psql -U "$DB_USER" -d "$DB_NAME" -c "$1"; }

step "0. Dọn tài nguyên cũ (nếu chạy lại script)"
docker rm -f "$APP" "$DB" 2>/dev/null || true
docker volume rm "$VOL" 2>/dev/null || true
docker network rm "$NET" 2>/dev/null || true

step "1. Tạo Custom Bridge Network: $NET"
docker network create --driver bridge "$NET"

step "2. Tạo Named Volume: $VOL"
docker volume create "$VOL"

step "3. Khởi chạy Database container: $DB"
run_db
wait_db

step "4. Khởi chạy Backend container: $APP (kết nối DB qua hostname $DB)"
docker run -d --name "$APP" \
  --network "$NET" \
  -p 8084:3000 \
  -e DB_HOST="$DB" \
  -e DB_PORT=5432 \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASS" \
  -e DB_NAME="$DB_NAME" \
  "$APP_IMAGE"
docker exec "$APP" sh -c 'env | grep ^DB_ | grep -v PASSWORD'

step "5. Kiểm tra DNS nội bộ: $APP ping $DB"
docker exec "$APP" ping -c 2 "$DB"
docker network inspect "$NET" --format '{{range .Containers}}{{.Name}} => {{.IPv4Address}}{{"\n"}}{{end}}'

step "6. Thêm dữ liệu vào DB"
psql_db "CREATE TABLE students (id SERIAL PRIMARY KEY, name TEXT NOT NULL, class TEXT);"
psql_db "INSERT INTO students (name, class) VALUES ('Nguyen Quyet Thang','IT209'), ('Docker Volume','Session 10');"
psql_db "SELECT * FROM students;"

step "7. Xoá cứng container DB: docker rm -f $DB"
docker rm -f "$DB"
docker ps -a --filter name="$DB" --format '{{.Names}}' | grep -q . && echo "Container vẫn còn" || echo "Container $DB đã bị xoá"
docker volume ls --filter name="$VOL"

step "8. Khởi chạy lại container DB mới, gắn cùng volume $VOL"
run_db
wait_db

step "9. Xác minh dữ liệu sau khi tái tạo container"
psql_db "SELECT * FROM students;"

step "HOÀN TẤT"
docker ps --filter network="$NET"
