#!/bin/bash
set -euo pipefail

REGION=ca-central-1
ENDPOINT=http://localhost:4566
DB_HOST="${DB_HOST:-localhost}"

cd "$(dirname "$0")"

if [ "${1:-}" = "--reset" ]; then
  echo "reset: deletion of the containers, the LocalStack volume and the tfstate"
  docker compose -f docker-compose.localstack.yml down -v
  rm -rf .localstack-data
  rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup
fi

docker compose -f docker-compose.localstack.yml up -d

printf 'waiting for LocalStack'
until curl -s "$ENDPOINT/_localstack/health" | grep -Eq '"s3": "(available|running)"'; do
  printf '.'
  sleep 2
done
echo ' ready'

lstk terraform --region "$REGION" -chdir=terraform init -input=false
lstk terraform --region "$REGION" -chdir=terraform apply -auto-approve -var "db_host=$DB_HOST"

cd mock-api && npm install
