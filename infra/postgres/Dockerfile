FROM postgres:18.6-trixie@sha256:06cad38a5d9f5d24b4d83d86def30795d5e4b757fedbf5281172b576dedcd941

ARG POSTGRESQL_PACKAGE_VERSION=18.6-1.pgdg13+2
ARG POSTGIS_PACKAGE_VERSION=3.6.4+dfsg-2.pgdg13+1
ARG PGROONGA_PACKAGE_VERSION=4.0.8-1
ARG IP4R_VERSION=2.4.3
ARG PGMQ_VERSION=1.12.0

LABEL org.opencontainers.image.title="geul-postgres" \
      description="PostgreSQL 18.6 + PostGIS 3.6.4 + PGroonga 4.0.8 + ip4r 2.4.3 + PGMQ 1.12.0"

# The official PostgreSQL base supplies both linux/amd64 and linux/arm64.
# PostGIS is installed from PGDG because postgis/postgis does not publish arm64.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates curl gnupg git \
    postgresql-client-18=${POSTGRESQL_PACKAGE_VERSION} \
    postgresql-server-dev-18=${POSTGRESQL_PACKAGE_VERSION} \
    postgresql-18-postgis-3=${POSTGIS_PACKAGE_VERSION} \
    postgresql-18-postgis-3-scripts=${POSTGIS_PACKAGE_VERSION} \
    && rm -rf /var/lib/apt/lists/*

# Install the reviewed PGroonga release from the official Groonga repository.
RUN curl -fsSL https://packages.groonga.org/debian/groonga-apt-source-latest-trixie.deb -o groonga-apt-source-latest-trixie.deb && \
    apt-get install -y --no-install-recommends ./groonga-apt-source-latest-trixie.deb && \
    rm groonga-apt-source-latest-trixie.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends postgresql-18-pgdg-pgroonga=${PGROONGA_PACKAGE_VERSION} && \
    rm -rf /var/lib/apt/lists/*

ENV PG_VERSION=18.6-1.pgdg13+2
ENV PGROONGA_VERSION=4.0.8
ENV IP4R_VERSION=${IP4R_VERSION}
ENV PGMQ_VERSION=${PGMQ_VERSION}

WORKDIR /tmp

# Build and install ip4r
RUN git clone https://github.com/RhodiumToad/ip4r.git && \
    cd ip4r && \
    git checkout ${IP4R_VERSION} && \
    make && \
    make install && \
    cd .. && \
    rm -rf ip4r

# PGMQ is a SQL-only PGXS extension. Pin the reviewed release so extension
# upgrades remain coupled to an immutable Geul Postgres image.
RUN git clone --depth 1 --branch v${PGMQ_VERSION} https://github.com/pgmq/pgmq.git && \
    cd pgmq/pgmq-extension && \
    make && \
    make install && \
    cd /tmp && \
    rm -rf pgmq

WORKDIR /
COPY init/ /docker-entrypoint-initdb.d/

CMD ["postgres"]
