# Geul Postgres

Public source repository for the Geul PostgreSQL image.

The image packages PostgreSQL 18.6, PostGIS 3.6.4, PGroonga 4.0.8, ip4r 2.4.3,
PGMQ 1.12.0, and the initialization scripts under `infra/postgres/init`.

Maintainer: state303 <state303@dsub.io>

## Run

Published image candidates:

```text
registry.dsub.io/echovisionlab/geul-postgres:v<version>
registry.dsub.io/echovisionlab/geul-postgres:sha-<release-commit>
```

Example local run:

```sh
docker run -d --name geul-postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=change-me \
  -e POSTGRES_APP_DB=geul \
  -v geul-postgres-data:/var/lib/postgresql \
  registry.dsub.io/echovisionlab/geul-postgres:v<version>
```

`POSTGRES_USER` and `POSTGRES_PASSWORD` follow the official PostgreSQL image
contract. `POSTGRES_APP_DB` selects the database initialized by this image and
defaults to `geul`; it must be a lowercase PostgreSQL identifier.
`DB_SCHEMAS` is an optional comma-separated list of schemas to create.

Initialization runs only for an empty data directory. It does not rename,
migrate, or rewrite an existing PostgreSQL cluster. PostgreSQL 18 uses
`/var/lib/postgresql`; a PostgreSQL 17 data directory requires a separate
upgrade/restore procedure.

## Development

Build and smoke-test the image locally:

```sh
docker build -t geul-postgres:local -f infra/postgres/Dockerfile infra/postgres
POSTGRES_IMAGE="$(docker image inspect --format '{{.Id}}' geul-postgres:local)" \
  scripts/ci/validate-postgres-assets.sh --smoke-image
```

The smoke validator checks the packaged init scripts, database, optional
schemas, extensions, pinned runtime versions, and the PGroonga `@@@` operator.
It accepts `POSTGRES_IMAGE`, `POSTGRES_PLATFORM`, `POSTGRES_USER`,
`POSTGRES_PASSWORD`, and `POSTGRES_APP_DB` environment overrides.

Check the tracked image provenance and script syntax:

```sh
node scripts/ci/generate-release-provenance.mjs --check
node --check scripts/ci/assert-multiarch-image.mjs
bash -n scripts/ci/validate-postgres-assets.sh infra/postgres/init/01-init-db.sh infra/postgres/init/02-extensions.sh
```

Pull requests use GitHub-hosted runners. Releases use Release Please and publish
the immutable multi-platform image through the GitHub Actions release workflow;
registry credentials remain GitHub secrets and are not stored here.

This repository contains no application-schema migrator or deployment
configuration. Those remain owned by the consuming application or domain.

## License

PolyForm Noncommercial 1.0.0. Commercial use requires a separate license from
Echo Vision Lab. See [LICENSE.md](LICENSE.md).
