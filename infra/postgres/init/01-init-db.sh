#!/bin/bash
set -e

DB_NAME="${POSTGRES_APP_DB:-geul}"

if [[ ! "${DB_NAME}" =~ ^[a-z_][a-z0-9_]*$ ]]; then
  echo "POSTGRES_APP_DB must be a lowercase PostgreSQL identifier: '${DB_NAME}'" >&2
  exit 1
fi

DB_EXISTS=$(psql -U "$POSTGRES_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")

if [ "$DB_EXISTS" != "1" ]; then
  echo "Creating database '$DB_NAME' with ICU (und) default collation..."
  psql -U "$POSTGRES_USER" -d postgres \
    -v ON_ERROR_STOP=1 \
    -v db_name="$DB_NAME" \
    -v db_owner="$POSTGRES_USER" <<'EOSQL'
CREATE DATABASE :"db_name"
  WITH OWNER = :"db_owner"
       ENCODING = 'UTF8'
       LOCALE_PROVIDER = 'icu'
       ICU_LOCALE = 'und'
       TEMPLATE = template0;
EOSQL
else
  echo "Database '$DB_NAME' already exists."
fi
