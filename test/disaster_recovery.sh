#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Local Disaster Recovery Drill Runner
# ==============================================================================
# Spins up local Docker containers for PostgreSQL and MinIO, runs a streaming
# backup, executes the automated DR drill (auto-creation of test DB,
# restoration, verification, and teardown), and validates end-to-end recovery.
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "==> Checking Docker availability..."
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker daemon is not running or accessible. Please start Docker to run DR tests." >&2
  exit 1
fi

NETWORK_NAME="seleimend-dr-net-$$-$(date +%s)"
PG_CONTAINER="dr-postgres-$$"
MINIO_CONTAINER="dr-minio-$$"
IMAGE_TAG="seleimend-db-backup:local-dr-test"

cleanup() {
  echo "==> Cleaning up test containers and network..."
  docker rm -f "${PG_CONTAINER}" "${MINIO_CONTAINER}" > /dev/null 2>&1 || true
  docker network rm "${NETWORK_NAME}" > /dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

echo "==> Creating isolated Docker network ${NETWORK_NAME}..."
docker network create "${NETWORK_NAME}"

echo "==> Starting PostgreSQL 17 container (${PG_CONTAINER})..."
docker run -d --name "${PG_CONTAINER}" --network "${NETWORK_NAME}" \
  -e POSTGRES_DB=source_app_db \
  -e POSTGRES_USER=app_user \
  -e POSTGRES_PASSWORD=secure_db_pass \
  postgres:17-alpine

echo "==> Starting MinIO S3-compatible container (${MINIO_CONTAINER})..."
docker run -d --name "${MINIO_CONTAINER}" --network "${NETWORK_NAME}" \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=miniopassword \
  cgr.dev/chainguard/minio:latest server /tmp/data

echo "==> Waiting for PostgreSQL to become ready..."
for _ in {1..30}; do
  if docker exec "${PG_CONTAINER}" pg_isready -U app_user -d source_app_db > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> Waiting for MinIO to become ready..."
for _ in {1..30}; do
  if docker exec "${MINIO_CONTAINER}" mc ready local > /dev/null 2>&1; then
    docker exec "${MINIO_CONTAINER}" mc alias set myminio http://localhost:9000 minioadmin miniopassword > /dev/null 2>&1
    docker exec "${MINIO_CONTAINER}" mc mb myminio/local-dr-bucket > /dev/null 2>&1
    break
  fi
  sleep 1
done

echo "==> Building container image ${IMAGE_TAG}..."
docker build -t "${IMAGE_TAG}" .

echo "==> Seeding source database with tables and sample records..."
docker exec -i -e PGPASSWORD=secure_db_pass "${PG_CONTAINER}" psql -U app_user -d source_app_db << 'EOF'
  CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL
  );

  INSERT INTO users (username, email) VALUES
    ('user_one', 'one@test.com'),
    ('user_two', 'two@test.com');
EOF

echo "==> Executing streaming backup via seleimend-db-backup..."
docker run --rm --network "${NETWORK_NAME}" \
  -e AUTO_PROVISION_B2="false" \
  -e B2_ENDPOINT="http://${MINIO_CONTAINER}:9000" \
  -e B2_APPLICATION_KEY_ID="minioadmin" \
  -e B2_APPLICATION_KEY="miniopassword" \
  -e B2_BUCKET="local-dr-bucket" \
  -e B2_PREFIX="dr-drill" \
  -e DATABASE_URL="postgresql://app_user:secure_db_pass@${PG_CONTAINER}:5432/source_app_db" \
  "${IMAGE_TAG}" backup

echo "==> Executing automated disaster recovery drill (dr-test)..."
docker run --rm --network "${NETWORK_NAME}" \
  -e AUTO_PROVISION_B2="false" \
  -e B2_ENDPOINT="http://${MINIO_CONTAINER}:9000" \
  -e B2_APPLICATION_KEY_ID="minioadmin" \
  -e B2_APPLICATION_KEY="miniopassword" \
  -e B2_BUCKET="local-dr-bucket" \
  -e B2_PREFIX="dr-drill" \
  -e DATABASE_URL="postgresql://app_user:secure_db_pass@${PG_CONTAINER}:5432/source_app_db" \
  -e DR_VERIFY_QUERY="SELECT count(*) FROM users WHERE username = 'user_one';" \
  "${IMAGE_TAG}" dr-test --latest

echo ""
echo "================================================================"
echo "  LOCAL DISASTER RECOVERY DRILL PASSED SUCCESSFULLY!"
echo "================================================================"
