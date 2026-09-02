#!/bin/bash
set -e

DB_NAME="${POSTGRES_APP_DB:-geul}"

if [[ ! "${DB_NAME}" =~ ^[a-z_][a-z0-9_]*$ ]]; then
  echo "POSTGRES_APP_DB must be a lowercase PostgreSQL identifier: '${DB_NAME}'" >&2
  exit 1
fi

echo "Installing extensions on '$DB_NAME'..."

psql -U "$POSTGRES_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'EOSQL'
-- Extensions
CREATE EXTENSION IF NOT EXISTS pgroonga;
CREATE EXTENSION IF NOT EXISTS ip4r;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS postgis_raster;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
CREATE EXTENSION IF NOT EXISTS postgis_sfcgal;
CREATE EXTENSION IF NOT EXISTS address_standardizer;
CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pgmq;

-- PGroonga full-text search alias operator @@@
CREATE OR REPLACE FUNCTION pgroonga_full_text_search(text, text)
    RETURNS boolean AS $$
BEGIN
    IF $1 IS NULL OR $2 IS NULL THEN RETURN NULL; END IF;
    RETURN $1 &@~ $2;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

DROP OPERATOR IF EXISTS @@@(text, text);
CREATE OPERATOR @@@ (
    LEFTARG = text, RIGHTARG = text,
    FUNCTION = pgroonga_full_text_search
);

CREATE OR REPLACE FUNCTION pgroonga_full_text_search(varchar, text)
    RETURNS boolean AS $$
BEGIN
    IF $1 IS NULL OR $2 IS NULL THEN RETURN NULL; END IF;
    RETURN $1::text &@~ $2;
EXCEPTION WHEN others THEN RETURN FALSE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

DROP OPERATOR IF EXISTS @@@(varchar, text);
CREATE OPERATOR @@@ (
    LEFTARG = varchar, RIGHTARG = text,
    FUNCTION = pgroonga_full_text_search
);
EOSQL

# Create optional domain schemas for a fresh install from DB_SCHEMAS (comma-separated).
if [ -n "${DB_SCHEMAS:-}" ]; then
  IFS=',' read -ra SCHEMAS <<< "$DB_SCHEMAS"
  for schema in "${SCHEMAS[@]}"; do
    schema=$(echo "$schema" | xargs)
    if [ -n "$schema" ]; then
      echo "  Creating schema '$schema'..."
      psql -U "$POSTGRES_USER" -d "$DB_NAME" -c "CREATE SCHEMA IF NOT EXISTS \"$schema\";"
    fi
  done
fi

psql -U "$POSTGRES_USER" -d "$DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -v db_name="$DB_NAME" <<'EOSQL'
ALTER DATABASE :"db_name" SET search_path TO public, postgis;
EOSQL

echo "Extensions installed on '$DB_NAME'."
