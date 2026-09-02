#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

POSTGRES_IMAGE="${POSTGRES_IMAGE:-}"
POSTGRES_PLATFORM="${POSTGRES_PLATFORM:-}"
POSTGRES_USER="${POSTGRES_USER:-geul}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-geul-smoke}"
POSTGRES_APP_DB="${POSTGRES_APP_DB:-geul}"
NETWORK_NAME="${NETWORK_NAME:-geul-postgres-ci-${GITHUB_RUN_ID:-local}-$$}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-geul-postgres-${GITHUB_RUN_ID:-local}-$$}"

if [ -n "${POSTGRES_PLATFORM}" ]; then
  case "${POSTGRES_PLATFORM}" in
    linux/amd64|linux/arm64)
      ;;
    *)
      echo "Unsupported POSTGRES_PLATFORM: ${POSTGRES_PLATFORM}" >&2
      exit 1
      ;;
  esac
fi

usage() {
  cat <<'USAGE'
Usage: scripts/ci/validate-postgres-assets.sh --smoke-image

Options:
  --smoke-image  Smoke-test the local or published POSTGRES_IMAGE artifact.
USAGE
}

case "${1:-}" in
  --smoke-image)
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    echo "Unsupported option: ${1}" >&2
    usage >&2
    exit 1
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "Too many arguments." >&2
  usage >&2
  exit 1
fi

cleanup() {
  docker rm -f -v "${POSTGRES_CONTAINER}" >/dev/null 2>&1 || true
  docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required to smoke-test a postgres image" >&2
    exit 1
  fi
  docker info >/dev/null
}

require_postgres_image() {
  if [ -z "${POSTGRES_IMAGE}" ]; then
    echo "POSTGRES_IMAGE is required for --smoke-image." >&2
    exit 1
  fi
}

run_docker() {
  if [ -n "${POSTGRES_PLATFORM}" ]; then
    docker run --platform "${POSTGRES_PLATFORM}" "$@"
  else
    docker run "$@"
  fi
}

wait_for_postgres() {
  local initialized_schemas
  for _ in $(seq 1 120); do
    if docker logs "${POSTGRES_CONTAINER}" 2>&1 \
      | grep -Fq "PostgreSQL init process complete; ready for start up." \
      && docker exec "${POSTGRES_CONTAINER}" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_APP_DB}" >/dev/null 2>&1; then
      if initialized_schemas="$(
        docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_APP_DB}" -At \
          -c "SELECT string_agg(nspname, ',' ORDER BY nspname) FROM pg_namespace WHERE nspname IN ('kratos', 'spicedb', 'transcoder');" \
          2>/dev/null
      )"; then
        if [ "${initialized_schemas}" = "kratos,spicedb,transcoder" ]; then
          return 0
        fi
      fi
    fi

    if ! docker ps --format '{{.Names}}' | grep -Fxq "${POSTGRES_CONTAINER}"; then
      echo "Postgres container exited before readiness." >&2
      docker logs "${POSTGRES_CONTAINER}" >&2 || true
      return 1
    fi

    sleep 2
  done

  echo "Timed out waiting for Postgres readiness." >&2
  docker logs "${POSTGRES_CONTAINER}" >&2 || true
  return 1
}

assert_packaged_init_scripts() {
  run_docker --rm --entrypoint bash "${POSTGRES_IMAGE}" -euo pipefail -c '
    test -x /docker-entrypoint-initdb.d/01-init-db.sh
    test -x /docker-entrypoint-initdb.d/02-extensions.sh
  '
}

assert_selected_platform() {
  local expected_platform actual_platform selected_image_id
  if [ -z "${POSTGRES_PLATFORM}" ]; then
    return 0
  fi

  expected_platform="${POSTGRES_PLATFORM}"
  selected_image_id="$(docker container inspect --format '{{.Image}}' "${POSTGRES_CONTAINER}")"
  actual_platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "${selected_image_id}")"
  if [ "${actual_platform}" != "${expected_platform}" ]; then
    echo "Unexpected image platform: got '${actual_platform}', expected '${expected_platform}'" >&2
    exit 1
  fi
}

assert_postgres_assets() {
  local expected_schemas actual_schemas expected_extensions actual_extensions actual_versions
  expected_schemas="kratos,spicedb,transcoder"
  actual_schemas="$(
    docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_APP_DB}" -At \
      -c "SELECT string_agg(nspname, ',' ORDER BY nspname) FROM pg_namespace WHERE nspname IN ('kratos', 'spicedb', 'transcoder');"
  )"

  if [ "${actual_schemas}" != "${expected_schemas}" ]; then
    echo "Unexpected schema set: got '${actual_schemas}', expected '${expected_schemas}'" >&2
    exit 1
  fi

  expected_extensions="address_standardizer,btree_gin,fuzzystrmatch,ip4r,pg_trgm,pgcrypto,pgmq,pgroonga,postgis,postgis_raster,postgis_sfcgal,postgis_tiger_geocoder,postgis_topology,unaccent"
  actual_extensions="$(
    docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_APP_DB}" -At \
      -c "SELECT string_agg(extname, ',' ORDER BY extname) FROM pg_extension WHERE extname IN ('address_standardizer', 'btree_gin', 'fuzzystrmatch', 'ip4r', 'pg_trgm', 'pgcrypto', 'pgmq', 'pgroonga', 'postgis', 'postgis_raster', 'postgis_sfcgal', 'postgis_tiger_geocoder', 'postgis_topology', 'unaccent');"
  )"

  if [ "${actual_extensions}" != "${expected_extensions}" ]; then
    echo "Unexpected extension set: got '${actual_extensions}', expected '${expected_extensions}'" >&2
    exit 1
  fi

  actual_versions="$(
    docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_APP_DB}" -At \
      -c "SELECT current_setting('server_version_num') || ',' || postgis_lib_version() || ',' || (SELECT extversion FROM pg_extension WHERE extname = 'pgroonga') || ',' || (SELECT extversion FROM pg_extension WHERE extname = 'pgmq');"
  )"

  if [ "${actual_versions}" != "180006,3.6.4,4.0.8,1.12.0" ]; then
    echo "Unexpected runtime versions: got '${actual_versions}', expected '180006,3.6.4,4.0.8,1.12.0'" >&2
    exit 1
  fi

  docker exec "${POSTGRES_CONTAINER}" bash -euo pipefail -c '
    test "${PG_VERSION}" = "18.6-1.pgdg13+2"
    test "${IP4R_VERSION}" = "2.4.3"
    test "$(dpkg-query --showformat="\${Version}" --show postgresql-18-postgis-3)" = "3.6.4+dfsg-2.pgdg13+1"
    test "$(dpkg-query --showformat="\${Version}" --show postgresql-18-pgdg-pgroonga)" = "4.0.8-1"
  '

  docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_APP_DB}" -v ON_ERROR_STOP=1 \
    -c "SELECT 'hello world'::text @@@ 'hello'::text;" >/dev/null
}

require_postgres_image
require_docker
trap cleanup EXIT

if [[ "${POSTGRES_IMAGE}" == sha256:* ]]; then
  echo "Using locally built Postgres image ID: ${POSTGRES_IMAGE}"
  docker image inspect "${POSTGRES_IMAGE}" >/dev/null
else
  echo "Pulling Postgres image for smoke: ${POSTGRES_IMAGE}"
  if [ -n "${POSTGRES_PLATFORM}" ]; then
    docker pull --platform "${POSTGRES_PLATFORM}" "${POSTGRES_IMAGE}"
  else
    docker pull "${POSTGRES_IMAGE}"
  fi
fi

echo "Validating packaged Postgres init scripts"
assert_packaged_init_scripts

echo "Starting fresh Postgres smoke container"
docker network create "${NETWORK_NAME}" >/dev/null
# Exercise the fresh-install schema contract used by the image smoke test.
run_docker -d \
  --name "${POSTGRES_CONTAINER}" \
  --network "${NETWORK_NAME}" \
  -e POSTGRES_USER="${POSTGRES_USER}" \
  -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  -e POSTGRES_DB=postgres \
  -e POSTGRES_APP_DB="${POSTGRES_APP_DB}" \
  -e DB_SCHEMAS=kratos,spicedb,transcoder \
  "${POSTGRES_IMAGE}" >/dev/null

assert_selected_platform
wait_for_postgres

echo "Validating Postgres init assets"
assert_postgres_assets

echo "Postgres asset validation passed."
