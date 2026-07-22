# Tazama Docker Compose Structure

This document describes the structure and organization of Docker Compose files across all three Tazama stacks.

## Repository Overview

The repository is divided into three independent sub-folders, each deployable on the same machine (local dev) or on separate servers (AWS sandbox):

| Folder | Stack | Project name | Typical server |
|--------|-------|--------------|----------------|
| `core/` | Core transaction processing pipeline | `tazama-core` | Server A |
| `extensions/` | Studios and Case Management System | `tazama-extensions` | Server B (APIs on Server A) |
| `biar/` | Business Intelligence, Analytics, and Reporting | `tazama-biar` | Server C |

---

# CORE STACK (`core/`)

## Core Architecture

The core stack uses a modular, layered Docker Compose design with four deployment modes:

1. **GitHub Dev** - builds services from GitHub source
2. **DockerHub Public** - pre-built images with minimal rule set (rule-901, rule-902)
3. **DockerHub Full-service** - pre-built images with complete rule set (30+ rules)
4. **Multi-Tenant** - per-tenant relay streams, mandatory auth

## File Hierarchy

### Base Infrastructure Files

#### `docker-compose.base.infrastructure.yaml`
Core infrastructure services shared by all deployments:
- **`valkey`**: Valkey 7.2.5 cache (Redis fork) for caching and pub/sub
- **`postgres`**: PostgreSQL 18 with base schema init scripts; health-checked
- **`nats`**: NATS 2 messaging system

All services have health checks and `restart: always`.

#### `docker-compose.base.override.yaml`
Host port mappings for local development access:
- Valkey: `16379:6379`
- NATS: `14222:4222`, `16222:6222`, `18222:8222`
- PostgreSQL: `15432:5432`

### Configuration Files

#### `docker-compose.dev.cfg.yaml`
GitHub dev configuration - mounts two SQL init files:
- `00-public-base.sql` - base schema
- `01-public-github.sql` - minimal dev config (rule-901 only)

#### `docker-compose.hub.cfg.yaml`
DockerHub public configuration - mounts:
- `00-public-base.sql` - base schema
- `02-public-dockerhub.sql` - minimal config (rule-901 and rule-902)

#### `docker-compose.full.cfg.yaml`
DockerHub full-service configuration - mounts:
- `03-full-dockerhub.sql` - complete network map with all typologies and rules
- Increased PostgreSQL performance settings: `max_connections=1000`, `shared_buffers=512MB`, `effective_cache_size=2GB`

#### `docker-compose.multitenant.cfg.yaml`
Multi-tenant configuration - mounts:
- `04-multitenancy.sql` - tenant-aware network map
- Enables `POSTGRES_HOST_AUTH_METHOD=trust` for local testing

### Core Service Files

#### `docker-compose.dev.core.yaml`
GitHub dev core services (built from source via `GH_TOKEN`):
- **`admin-service`**: Administration API (port `${ADMIN_PORT}:3100`)
- **`tms-service`**: Transaction Monitoring Service API (port `${TMS_PORT}:3000`)
- **`event-director`**: Event Director
- **`rule-901`**: Rule 901 (built from `rule-executer` repo)
- **`typology-processor`**: Typology Processor
- **`event-adjudicator`**: Event Adjudicator
- **`event-flow`**: Event Flow rule processor
- **`tazama-demo`**: Demo UI (built from `tazama-demo` repo, port `${DEMO_PORT:-3011}:3011`)

#### `docker-compose.hub.core.yaml`
DockerHub core services using `tazamaorg/*:${TAZAMA_VERSION}` images:
- Same services as dev.core but from pre-built DockerHub images, except `rule-901` (delivered by the rules files below)
- Adds **`batch-ppa`**: `tazamaorg/batch-ppa:${TAZAMA_VERSION}` (port `4100:4100`) - Pain.001 batch processor; depends on `core-postgres` (healthy) and `tms-service`
- **`tazama-demo`**: `tazamaorg/tazama-demo:${TAZAMA_VERSION}` (port `${DEMO_PORT:-3011}:3011`), configured via `env/tazama-demo.env`; sets `CORS_POLICY=demo` on `tms-service` and `admin-service`

### Rules Files

#### `docker-compose.hub.rules.yaml`
DockerHub minimal rule set:
- **`rule-901`**: `tazamaorg/rule-901`
- **`rule-902`**: `tazamaorg/rule-902`

#### `docker-compose.full.rules.yaml`
DockerHub complete rule set (33 rules):
- Rules: 001, 002, 003, 004, 006, 007, 008, 010, 011, 016, 017, 018, 020, 021, 024, 025, 026, 027, 028, 030, 044, 045, 048, 054, 063, 074, 075, 076, 078, 083, 084, 090, 091
- All rules use `env/rule-executer.env` as base config
- All depend on `valkey` and `core-postgres`

### Authentication Files

#### `docker-compose.base.auth.yaml`
Base auth overlay applied on top of any core deployment:
- **`keycloak`**: Keycloak 23.0.6 identity provider (port `8080:8080`)
  - Dev mode with auto-import of `00-tazama-test-realm.json`
- **`auth-service`**: Auth service `tazamaorg/auth-service:${TAZAMA_VERSION}` (port `3020:3020`)
  - Issues and validates JWT tokens using RSA key pair
- **`core-postgres`**: Overridden with `POSTGRES_HOST_AUTH_METHOD=trust`
- **`tms-service`**, **`admin-service`**: Overridden with `AUTHENTICATED=true` and public key mount

#### `docker-compose.dev.auth.yaml`
Overrides `auth-service` to build from GitHub source instead of DockerHub.

### Relay Files

Relay services forward interdiction and alert messages to external NATS streams.

#### `docker-compose.dev.relay.yaml`
GitHub dev relay services (built from `relay-service` GitHub repo):
- Configures `event-flow`, `typology-processor`, `event-adjudicator` with `SUPPRESS_ALERTS=false` and `INTERDICTION_DESTINATION=global`
  - **`relay-service-ef`**: Event Flow interdiction relay (`interdiction-service-ef` → `relay-service-nats-ef`)
  - **`relay-service-tp`**: Typology Processor interdiction relay (`interdiction-service-tp` → `relay-service-nats-tp`)
  - **`relay-service-ea`**: Event Adjudicator alert relay (`investigation-service` → `relay-service-nats-ea`)

#### `docker-compose.hub.relay.yaml`
Same relay services using `tazamaorg/relay-service-integration-nats:${TAZAMA_VERSION}`.

#### `docker-compose.multitenant.relay.yaml`
Per-tenant relay services with `INTERDICTION_DESTINATION=tenant`:
  - **`relay-service-ef-tenant-001`**, **`relay-service-ef-tenant-002`**: Event Flow relays per tenant
  - **`relay-service-tp-tenant-001`**, **`relay-service-tp-tenant-002`**: Typology Processor relays per tenant
  - **`relay-service-ea-tenant-001`**, **`relay-service-ea-tenant-002`**: Event Adjudicator relays per tenant

### Logging Files

#### `docker-compose.dev.logs.base.yaml`
GitHub dev base logging (built from source):
- **`event-sidecar`**: Logging sidecar (port `15000:${EVENT_SIDECAR_PORT}`) - receives HTTP logs, publishes to NATS `Lumberjack` subject
- **`lumberjack`**: Log aggregation - consumes from NATS, outputs to STDOUT

#### `docker-compose.hub.logs.base.yaml`
Same services using `tazamaorg/event-sidecar` and `tazamaorg/lumberjack` images.

#### `docker-compose.dev.logs.elastic.yaml` / `docker-compose.hub.logs.elastic.yaml`
Elasticsearch integration overlay:
- Configures `lumberjack` to forward to Elasticsearch
- Adds `SIDECAR_HOST` env var to `tms-service`, `admin-service`, `event-director`, `event-flow`, `rule-901`/`rule-902`, `typology-processor`, `event-adjudicator`

### Utility Files

#### `docker-compose.utils.nats-utils.yaml`
- **`nats-utilities`**: Built from `nats-utilities` GitHub repo (port `4000:4000`)
  - NATS stream management, monitoring, and debugging tools

#### `docker-compose.utils.pgadmin.yaml`
- **`core-pgadmin`**: pgAdmin 4.9 (port `${PGADMIN_PORT:-5050}:80`)
  - Pre-configured Tazama server connection via inline `servers.json`

#### `docker-compose.utils.hasura.yaml`
- **`core-postgres`**: Overridden with trust auth and `01-HASURA.sql` init
- **`hasura`**: Hasura GraphQL Engine v2.36.0 (port `6100:8080`)
  - Connects to `event_history`, `raw_history`, `configuration`, `evaluation` databases
  - Admin secret: `password`; anonymous role enabled
- **`hasura-init`**: `curlimages/curl` one-shot container
  - Waits 10s after Hasura health check, then runs `init.sh` to configure metadata

#### `docker-compose.utils.elastic.yaml`
- **`elasticsearch`**: Single-node Elasticsearch (port `${ES_PORT}:9200`)
- **`kibana`**: Kibana (port `${KIBANA_PORT}:5601`)
- Named volumes: `esdata`, `kibanadata`

#### `docker-compose.utils.apm-elastic.yaml`
- Includes Elasticsearch/Kibana via `docker-compose.utils.elastic.yaml`
- **`apm-server`**: Elastic APM Server (port `${APMSERVER_PORT}:8200`) with RUM enabled
- Injects `APM_ACTIVE=true` and `APM_URL=http://apm-server:8200` into `tms-service`, `event-director`, `rule-901`, `typology-processor`, `event-adjudicator`

## Core Deployment Patterns

### 1. GitHub Dev
```bash
docker compose \
  -f docker-compose.base.infrastructure.yaml \
  -f docker-compose.base.override.yaml \
  -f docker-compose.dev.cfg.yaml \
  -f docker-compose.dev.core.yaml \
  -p tazama-core up -d
```

### 2. DockerHub Public
```bash
docker compose \
  -f docker-compose.base.infrastructure.yaml \
  -f docker-compose.base.override.yaml \
  -f docker-compose.hub.cfg.yaml \
  -f docker-compose.hub.core.yaml \
  -f docker-compose.hub.rules.yaml \
  -p tazama-core up -d
```

### 3. DockerHub Full-service
```bash
docker compose \
  -f docker-compose.base.infrastructure.yaml \
  -f docker-compose.base.override.yaml \
  -f docker-compose.full.cfg.yaml \
  -f docker-compose.hub.core.yaml \
  -f docker-compose.full.rules.yaml \
  -p tazama-core up -d
```

### 4. Multi-Tenant
```bash
docker compose \
  -f docker-compose.base.infrastructure.yaml \
  -f docker-compose.base.override.yaml \
  -f docker-compose.base.auth.yaml \
  -f docker-compose.multitenant.cfg.yaml \
  -f docker-compose.hub.core.yaml \
  -f docker-compose.hub.rules.yaml \
  -f docker-compose.multitenant.relay.yaml \
  -p tazama-core up -d
```

## Core Port Mappings

### Infrastructure Services

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| Valkey | 6379 | 16379 | Cache and pub/sub |
| PostgreSQL | 5432 | 15432 | Database |
| NATS Client | 4222 | 14222 | Messaging |
| NATS Cluster | 6222 | 16222 | Cluster communication |
| NATS HTTP Monitoring | 8222 | 18222 | Monitoring API |

### Core Services

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| TMS | 3000 | `${TMS_PORT}` | Transaction Monitoring API |
| Admin Service | 3100 | `${ADMIN_PORT}` | Administration API |

### Authentication Services

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| Keycloak | 8080 | 8080 | Identity provider |
| Auth Service | 3020 | 3020 | Token generation |

### Logging Services

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| Event Sidecar | `${EVENT_SIDECAR_PORT}` | 15000 | Logging sidecar |

### Core Utility Services

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| pgAdmin | 80 | `${PGADMIN_PORT:-5050}` | PostgreSQL admin UI |
| Hasura | 8080 | 6100 | GraphQL API |
| Elasticsearch | 9200 | `${ES_PORT}` | Search and analytics |
| Kibana | 5601 | `${KIBANA_PORT}` | Visualization |
| APM Server | 8200 | `${APMSERVER_PORT}` | Application monitoring |
| Demo UI | 3001 | 3001 | Demo interface |
| NATS Utilities | 4000 | 4000 | NATS management |
| Batch PPA | 4100 | 4100 | Pain.001 processor |

### Core Access URLs

- **PostgreSQL**: `localhost:15432` (user: `postgres`, password: `unused`)
- **Valkey**: `localhost:16379`
- **NATS**: `localhost:14222` (client), `localhost:18222` (monitoring)
- **TMS API**: `http://localhost:${TMS_PORT}`
- **Admin API**: `http://localhost:${ADMIN_PORT}`
- **Keycloak**: `http://localhost:8080` (admin/admin)
- **Auth Service**: `http://localhost:3020`
- **pgAdmin**: `http://localhost:5050` (admin@tazama.org / admin)
- **Hasura Console**: `http://localhost:6100` (admin secret: `password`)
- **Elasticsearch**: `http://localhost:${ES_PORT}`
- **Kibana**: `http://localhost:${KIBANA_PORT}`
- **APM Server**: `http://localhost:${APMSERVER_PORT}`
- **Demo UI**: `http://localhost:3011`
- **NATS Utilities**: `http://localhost:4000`
- **Batch PPA**: `http://localhost:4100`

---

# EXTENSIONS STACK (`extensions/`)

The extensions stack provides the studio tools (TCS, TRS) and Case Management System (CMS), plus API services (DEMS, DEAPI) that run on Server A alongside core.

## File Hierarchy

### Infrastructure File

#### `docker-compose.extensions.infrastructure.yaml`
Extension-specific infrastructure (Server B):
- **`extensions-postgres`**: PostgreSQL 18 with persistent volume (port `${POSTGRESQL_CMS_PORT}:5432`, default `15433`)
- **`sftp`**: SFTP server `atmoz/sftp` (port `${SFTP_PORT}:22`, default `12222`) for file uploads
- **`couchdb`**: CouchDB 3.3 (port `${COUCHDB_PORT}:5984`, default `5984`) for CMS document storage
- **`case-management-system-migrate`**: `tazamaorg/case-management-system-migrate` one-shot migration container
- **`flowable`**: Flowable REST BPM engine (port `${FLOWABLE_PORT}:8080`, default `8081`)
- **`opensearch`**: OpenSearch 2.13.0 single-node (port `${OPENSEARCH_PORT:-9200}:9200`)
  - Disabled security plugin; tuned for low-write audit use case
- **`opensearch-init`**: One-shot init that applies index template (30s refresh, async translog)
- Named volumes: `sftp_data`, `couchdb_data`, `postgres_data`, `opensearch_data`

### Extensions Service Files

#### `docker-compose.dev.extensions.yaml`
GitHub dev extensions (Server B, built from source):
- **`connection-studio-backend`**: TCS API (port `${TCS_PORT}:3010`, default `3010`)
- **`connection-studio-frontend`**: TCS UI (port `${TCS_FRONTEND_PORT}:5173`, default `5173`)
- **`rule-studio-backend`**: Typology Rule Studio API (port `${TRS_BACKEND_PORT}:3005`, default `3005`)
- **`rule-studio-frontend`**: TRS UI (port `${TRS_FRONTEND_PORT}:5174`, default `5174`)
- **`case-management-system-backend`**: CMS API (port `${CMS_BACKEND_PORT}:3090`, default `3090`)
- **`case-management-system-frontend`**: CMS UI (port `${CMS_FRONTEND_PORT}:5175`, default `5175`)
- **`case-management-system-voila`**: CMS Voila visualization server (port `${VOILA_PORT:-18866}:8866`)

#### `docker-compose.hub.extensions.yaml`
DockerHub extensions (Server B) using `tazamaorg/*:${TAZAMA_VERSION}` images:
- Same services as dev.extensions but from pre-built DockerHub images

### API Service Files (Server A pre-flight)

These services join the **`tazama-core`** Docker project and run on Server A.

#### `docker-compose.dev.extensions.apis.yaml`
GitHub dev API services (Server A):
- **`event-monitoring-service`**: Data/Event Monitoring Service (port `${DEMS_PORT}:3002`, default `3002`)
- **`data-enrichment-service`**: Data Enrichment API (port `${DEAPI_PORT}:3001`, default `3001`)

#### `docker-compose.hub.extensions.apis.yaml`
DockerHub API services (Server A):
- Same services using `tazamaorg/event-monitoring-service` and `tazamaorg/data-enrichment-service`

### Utility Files

#### `docker-compose.utils.pgadmin.yaml`
- **`extensions-pgadmin`**: pgAdmin 4.9 (port `${PGADMIN_PORT:-5050}:80`, default `5051` per `.env`)
  - Pre-configured Tazama server connection; note: uses port 5051 on Server B to avoid conflict with core's 5050

## Extensions Deployment Patterns

### Server A pre-flight (DEMS + DEAPI, runs in `tazama-core` project)

```bash
# GitHub builds
docker compose -p tazama-core \
  -f ./docker-compose.dev.extensions.apis.yaml up -d

# DockerHub images
docker compose -p tazama-core \
  -f ./docker-compose.hub.extensions.apis.yaml up -d
```

### Server B extensions stack

```bash
# GitHub builds
docker compose -p tazama-extensions \
  -f ./docker-compose.extensions.infrastructure.yaml \
  -f ./docker-compose.dev.extensions.yaml \
  up -d

# DockerHub images
docker compose -p tazama-extensions \
  -f ./docker-compose.extensions.infrastructure.yaml \
  -f ./docker-compose.hub.extensions.yaml \
  up -d
```

## Extensions Port Mappings

| Service | Internal Port | External Port (default) | Purpose |
|---------|---------------|-------------------------|---------|
| PostgreSQL (CMS) | 5432 | `${POSTGRESQL_CMS_PORT}` (15433) | CMS database |
| SFTP | 22 | `${SFTP_PORT}` (12222) | File uploads |
| CouchDB | 5984 | `${COUCHDB_PORT}` (5984) | Document store |
| Flowable | 8080 | `${FLOWABLE_PORT}` (8081) | BPM engine |
| OpenSearch | 9200 | `${OPENSEARCH_PORT}` (9200) | Search / audit log |
| TCS Backend | 3010 | `${TCS_PORT}` (3010) | Connection Studio API |
| TCS Frontend | 5173 | `${TCS_FRONTEND_PORT}` (5173) | Connection Studio UI |
| TRS Backend | 3005 | `${TRS_BACKEND_PORT}` (3005) | Rule Studio API |
| TRS Frontend | 5174 | `${TRS_FRONTEND_PORT}` (5174) | Rule Studio UI |
| CMS Backend | 3090 | `${CMS_BACKEND_PORT}` (3090) | Case Management API |
| CMS Frontend | 5175 | `${CMS_FRONTEND_PORT}` (5175) | Case Management UI |
| Voila | 8866 | `${VOILA_PORT}` (18866) | CMS visualization server |
| DEMS (Server A) | 3002 | `${DEMS_PORT}` (3002) | Event Monitoring Service |
| DEAPI (Server A) | 3001 | `${DEAPI_PORT}` (3001) | Data Enrichment API |
| pgAdmin | 80 | `${PGADMIN_PORT}` (5051) | PostgreSQL admin UI |

---

# BIAR STACK (`biar/`)

The BIAR (Business Intelligence, Analytics, and Reporting) stack provides data ingestion (NiFi), object storage (Apache Ozone/S3), analytics (JupyterHub), an automation orchestrator, and document processing.

## File Hierarchy

### Infrastructure File

#### `docker-compose.biar.infrastructure.yaml`
BIAR infrastructure services:
- **`biar-tika`**: Apache Tika `logicalspark/docker-tikaserver` (port `${TIKA_PORT}:9998`, default `9998`) - document parsing
- **`biar-solr`**: Apache Solr 9 (port `${SOLR_PORT}:8983`, default `8983`) - search indexing; `biar_docs` core pre-created
- Apache Ozone 2.0.0 object storage cluster:
  - **`ozone-scm`**: Storage Container Manager (port `9876:9876`)
  - **`ozone-om`**: Ozone Manager (port `9862:9862`)
  - **`ozone-datanode-1`**, **`ozone-datanode-2`**, **`ozone-datanode-3`**: Data nodes (no host ports)
  - **`ozone-recon`**: Recon server (port `9888:9888`)
  - **`ozone-s3g`**: S3 Gateway (port `9878:9878`) - exposes S3-compatible API

### BIAR Service Files

#### `docker-compose.hub.biar.yaml`
DockerHub BIAR services using `tazamaorg/biar-*:${TAZAMA_VERSION}` images:
- **`biar-nifi`**: NiFi data ingestion (ports `${NIFI_PORT}:8088`, `8081:8081`, default `8088`)
  - Persistent volumes for conf, state, db, flowfile, content, provenance
  - Depends on `ozone-s3g`
- **`biar-automation-orchestrator`**: Automation/Spark orchestrator (port `${AUTOMATION_ORCHESTRATOR_PORT}:7619`, default `7619`)
  - Mounts `${TAZAMA_WAREHOUSE_HOST_PATH}:/opt/Tazama_Warehouse`
- **`biar-datalakehouse-api`**: Data lakehouse REST API (port `${DATALAKEHOUSE_API_PORT}:8282`, default `8282`)
  - Mounts `${TAZAMA_WAREHOUSE_HOST_PATH}:/opt/Tazama_Warehouse`
- **`biar-unstructured-pipeline`**: Unstructured document ingestion pipeline
  - Depends on `biar-tika` and `biar-solr`
- **`biar-jupyterhub`**: JupyterHub analytics environment (port `${JUPYTERHUB_PORT}:8000`, default `8000`)
  - Persistent volumes for data and notebooks
  - Read-only warehouse mount

#### `docker-compose.dev.biar.yaml`
GitHub dev BIAR services (same structure, built from `tazama-lf/biar.git` subdirs).

### Utility / Init Files

#### `docker-compose.utils.init.yaml`
One-shot initialization containers:
- **`ozone-aws-cli`**: `amazon/aws-cli` - waits for S3 gateway, creates the configured bucket
- **`biar-nifi-init`**: `curlimages/curl` - runs `nifi/init.sh` to bootstrap NiFi flows

## BIAR Deployment Patterns

```bash
# DockerHub images
docker compose -p tazama-biar \
  -f ./docker-compose.biar.infrastructure.yaml \
  -f ./docker-compose.hub.biar.yaml \
  -f ./docker-compose.utils.init.yaml \
  up -d

# GitHub builds
docker compose -p tazama-biar \
  -f ./docker-compose.biar.infrastructure.yaml \
  -f ./docker-compose.dev.biar.yaml \
  -f ./docker-compose.utils.init.yaml \
  up -d
```

## BIAR Port Mappings

| Service | Internal Port | External Port (default) | Purpose |
|---------|---------------|-------------------------|---------|
| Tika | 9998 | `${TIKA_PORT}` (9998) | Document parsing |
| Solr | 8983 | `${SOLR_PORT}` (8983) | Search indexing |
| Ozone SCM | 9876 | 9876 | Storage Container Manager |
| Ozone OM | 9862 | 9862 | Ozone Manager |
| Ozone Recon | 9888 | 9888 | Recon dashboard |
| Ozone S3 Gateway | 9878 | 9878 | S3-compatible API |
| NiFi | 8088 | `${NIFI_PORT}` (8088) | Data ingestion UI |
| NiFi (secondary) | 8081 | 8081 | NiFi HTTP listener |
| Automation Orchestrator | 7619 | `${AUTOMATION_ORCHESTRATOR_PORT}` (7619) | Spark/automation API |
| Datalakehouse API | 8282 | `${DATALAKEHOUSE_API_PORT}` (8282) | Data lakehouse REST API |
| JupyterHub | 8000 | `${JUPYTERHUB_PORT}` (8000) | Analytics notebooks |

---

# Global Environment Variables

Root-level `.env` files in each sub-folder share these key variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `TAZAMA_VERSION` | Docker image tag for DockerHub images | `v2.2.0`, `rc`, `latest` |
| `GH_TOKEN` | GitHub PAT for source builds | `ghp_xxx` |
| `BRANCH_NAME` | Default branch for GitHub builds | `dev`, `main` |
| `SERVER_A_HOST` | Hostname/IP of Server A (for cross-server refs) | `localhost`, `10.0.1.x` |
| `SERVER_B_HOST` | Hostname/IP of Server B | `localhost`, `10.0.2.x` |

## Common Variable Patterns

### Database Connection

| Variable | Typical Value |
|----------|---------------|
| `POSTGRES_USER` | `postgres` |
| `POSTGRES_PASSWORD` | `unused` |
| `DATABASE_URL` | `postgresql://postgres:@postgres:5432/<db>` |

### Valkey

| Variable | Typical Value |
|----------|---------------|
| `VALKEY_DB` | `0` |
| `VALKEY_AUTH` | *(empty for local)* |
| `VALKEY_SERVERS` | `valkey:6379` |

### NATS

| Variable | Typical Value |
|----------|---------------|
| `NATS_URL` | `nats:4222` |
| `PRODUCER_STREAM` | Service-specific |
| `CONSUMER_STREAM` | Service-specific |

### APM Instrumentation

| Variable | Typical Value |
|----------|---------------|
| `APM_ACTIVE` | `true` or `false` |
| `APM_URL` | `http://apm-server:8200` |
| `APM_SERVICE_NAME` | Service-specific |

---

# Security Notes

**WARNING**: The default configuration uses insecure settings for local development only:
- `POSTGRES_PASSWORD=unused` with `POSTGRES_HOST_AUTH_METHOD=trust` - no password auth
- Weak default passwords (`admin`, `password`)
- Disabled security plugins (OpenSearch, Elasticsearch)
- Self-signed RSA keys for JWT

**Never use these settings in production.** Production deployments should use secrets management, strong passwords, TLS, and least-privilege access controls.
