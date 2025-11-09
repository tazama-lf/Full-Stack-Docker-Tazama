# Tazama Docker Compose Structure

This document outlines the structure and organization of Docker Compose files in the Tazama system.

## Core Architecture

The Tazama system is built with a modular Docker Compose architecture that allows for flexible deployment options:

1. **GitHub Development Deployment**: Builds services from GitHub repositories
2. **DockerHub Public Deployment**: Uses pre-built images with minimal rule set (rule-901, rule-902)
3. **DockerHub Full-Service Deployment**: Uses pre-built images with complete rule set (30+ rules)
4. **Multi-Tenant Deployment**: Specialized configuration for multi-tenant environments with mandatory authentication and relay services

## File Hierarchy

### Base Infrastructure Files

#### `docker-compose.base.infrastructure.yaml`
Core infrastructure services common to all deployments:
- **`valkey`**: Valkey cache (Redis fork) for caching and pub/sub messaging
- **`postgres`**: PostgreSQL 18 database with base schema creation
- **`nats`**: NATS messaging system for event-driven communication

All services include health checks and automatic restart policies.

#### `docker-compose.base.override.yaml`
Port mappings for local development access:
- Valkey: `16379:6379`
- NATS: `14222:4222`, `16222:6222`, `18222:8222`
- PostgreSQL: `15432:5432`

### Configuration Files

#### `docker-compose.dev.cfg.yaml`
GitHub development configuration:
- Mounts `00-public-base.sql` (base schema)
- Mounts `01-public-github.sql` (minimal configuration for development)
- Single rule-901 configuration

#### `docker-compose.hub.cfg.yaml`
DockerHub public deployment configuration:
- Mounts `00-public-base.sql` (base schema)
- Mounts `02-public-dockerhub.sql` (minimal configuration with rule-901 and rule-902)

#### `docker-compose.full.cfg.yaml`
DockerHub full-service configuration:
- Mounts `03-full-dockerhub.sql` (complete network map with all typologies and rules)
- Increased PostgreSQL performance settings:
  - Max connections: 1000
  - Shared buffers: 512MB
  - Effective cache size: 2GB

#### `docker-compose.multitenant.cfg.yaml`
Multi-tenant deployment configuration:
- Mounts `04-multitenancy.sql` (tenant-aware network map)
- Enables trust authentication for local testing

### Core Service Files

#### `docker-compose.dev.core.yaml`
GitHub development core services built from source:
- **`admin-service`**: Administration API (port 3100)
- **`tms`**: Transaction Monitoring Service API (port 3000)
- **`ed`**: Event Director
- **`rule-901`**: Rule 901 processor (built from rule-executer)
- **`tp`**: Typology Processor
- **`tadp`**: Transaction Aggregation and Decisioning Processor
- **`ef`**: Event Flow rule processor

All services build from GitHub with `GH_TOKEN` authentication.

#### `docker-compose.hub.core.yaml`
DockerHub core services using pre-built images:
- Same services as dev.core but from `tazamaorg/*` Docker images
- Version controlled via `${TAZAMA_VERSION}` variable

### Rules Files

#### `docker-compose.hub.rules.yaml`
DockerHub minimal rule set:
- **`rule-901`**: Basic transaction validation
- **`rule-902`**: Additional rule processor

#### `docker-compose.full.rules.yaml`
DockerHub complete rule set (30+ rules):
- Rules: 001, 002, 003, 004, 006, 007, 008, 010, 011, 016, 017, 018, 020, 021, 024, 025, 026, 027, 028, 030, 044, 045, 048, 054, 063, 074, 075, 076, 078, 083, 084, 090, 091
- All rules configured with database credentials and environment variables
- All rules depend on valkey and postgres

### Authentication Files

#### `docker-compose.base.auth.yaml`
Base authentication configuration for all deployments:
- **`keycloak`**: Identity and access management (port 8080)
  - Keycloak 23.0.6
  - Development mode with auto-import
  - Imports `00-tazama-test-realm.json`
- **`auth`**: Authentication service (port 3020)
  - Issues and validates JWT tokens
  - Uses RSA key pair for signing
- **`postgres`**: Configured with trust authentication for local testing
- **`tms`** and **`admin-service`**: Configured with JWT authentication enabled

#### `docker-compose.dev.auth.yaml`
GitHub development authentication:
- Builds `auth` service from GitHub source

#### `docker-compose.multitenant.auth.yaml`
Currently empty - multi-tenant auth uses base auth configuration only.

### Relay Files

Relay services enable external system integration by forwarding alerts and interdiction messages to NATS streams.

#### `docker-compose.dev.relay.yaml`
GitHub development relay services (built from source):
- **`rsef`**: Relay service for Event Flow interdictions (global scope)
- **`rstp`**: Relay service for Typology Processor interdictions (global scope)
- **`rstadp`**: Relay service for TADP alerts/investigations (global scope)

All relay services:
- Build from `relay-service` GitHub repository
- Subscribe to internal streams (e.g., `interdiction-service-ef`)
- Publish to external NATS streams (e.g., `relay-service-nats-ef`)

#### `docker-compose.hub.relay.yaml`
DockerHub relay services (pre-built images):
- Same services using `tazamaorg/relay-service-integration-nats` image
- Global scope configuration

#### `docker-compose.multitenant.relay.yaml`
Multi-tenant relay services with per-tenant streams:
- **`rsef-tenant-001`**, **`rsef-tenant-002`**: Event Flow relays per tenant
- **`rstp-tenant-001`**, **`rstp-tenant-002`**: Typology Processor relays per tenant
- **`rstadp-tenant-001`**, **`rstadp-tenant-002`**: TADP relays per tenant

Each tenant has isolated relay streams for complete data segregation.

### Logging Files

#### `docker-compose.dev.logs.base.yaml`
GitHub development base logging (built from source):
- **`event-sidecar`**: Logging sidecar service (port 15000)
  - Receives logs from services via HTTP
  - Publishes to NATS `Lumberjack` subject
- **`lumberjack`**: Log aggregation and processing
  - Consumes logs from NATS
  - Outputs to STDOUT by default

#### `docker-compose.hub.logs.base.yaml`
DockerHub base logging (pre-built images):
- Same services using `tazamaorg/event-sidecar` and `tazamaorg/lumberjack` images

#### `docker-compose.dev.logs.elastic.yaml` / `docker-compose.hub.logs.elastic.yaml`
Elasticsearch integration for logging:
- Extends base logging configuration
- Configures `lumberjack` to forward logs to Elasticsearch
- Configures all services to send logs to `event-sidecar`

### UI Files

#### `docker-compose.hub.ui.yaml`
Demo web interface:
- **`ui`**: Demo UI (port 3001)
  - `tazamaorg/demo-ui:v2.2.0`
  - Provides web interface for testing transactions
- Configures `tms` and `admin-service` with `CORS_POLICY=demo`

### Utility Files

#### `docker-compose.utils.nats-utils.yaml`
NATS utilities and tools:
- **`nats-utilities`**: NATS CLI and management tools (port 4000)
  - Built from `nats-utilities` GitHub repository
  - Provides NATS stream management, monitoring, and debugging

#### `docker-compose.utils.batch-ppa.yaml`
Batch processing for Pain.001 messages:
- **`nats-utilities`** (overridden name): Pain.001 batch processor (port 4000)
  - Built from `batch-ppa` GitHub repository
  - Processes batch payment initiation messages

#### `docker-compose.utils.pgadmin.yaml`
PostgreSQL web-based administration:
- **`pgadmin`**: pgAdmin 4 web interface (port 5050, configurable via `${PGADMIN_PORT}`)
  - Pre-configured connection to Tazama PostgreSQL instance
  - Server configuration via inline config

#### `docker-compose.utils.hasura.yaml`
GraphQL API for databases:
- **`hasura`**: Hasura GraphQL Engine (port 6100)
  - Hasura v2.36.0
  - Connects to all four databases: `event_history`, `raw_history`, `configuration`, `evaluation`
  - Admin secret: `password`
  - Anonymous role enabled for unauthenticated access
- **`hasura-init`**: Initialization service
  - Runs `init.sh` script to configure metadata, track tables, and set permissions
  - Waits 60s for system stabilization before initialization
  - Runs once and exits
- **`postgres`**: Configured with trust authentication and `01-HASURA.sql` initialization

#### `docker-compose.utils.elastic.yaml`
Elasticsearch and Kibana stack:
- **`elasticsearch`**: Elasticsearch single-node (port 9200, configurable via `${ES_PORT}`)
  - Version controlled via `${ELASTIC_STACK_VERSION}`
  - Memory limit: `${ES_MEM_LIMIT}`
  - Security disabled for local development
- **`kibana`**: Kibana visualization (port 5601, configurable via `${KIBANA_PORT}`)
  - Memory limit: `${KB_MEM_LIMIT}`
  - Connected to Elasticsearch

Includes named volumes: `esdata`, `kibanadata`

#### `docker-compose.utils.apm-elastic.yaml`
Application Performance Monitoring with Elastic APM:
- Includes Elasticsearch and Kibana via `docker-compose.dev.elastic.yaml`
- **`apm-server`**: Elastic APM Server (port 8200, configurable via `${APMSERVER_PORT}`)
  - RUM (Real User Monitoring) enabled
  - Connected to Elasticsearch and Kibana
- Configures `tms`, `ed`, `rule-901`, `tp`, `tadp` with APM instrumentation:
  - `APM_ACTIVE=true`
  - `APM_URL=http://apm-server:8200`

#### `docker-compose.base.pgbouncer.yaml`
**Note**: This file appears to be referenced in your batch file but is not included in the attachments. Based on context, it likely configures PgBouncer connection pooling.

## Deployment Patterns

### 1. GitHub Development Deployment
**Command:**
```bash
docker compose \
  -f docker-compose.base.infrastructure.yaml \
  -f docker-compose.base.override.yaml \
  -f docker-compose.dev.cfg.yaml \
  -f docker-compose.dev.core.yaml \
  -p tazama up -d
```

### 2. DockerHub Public Deployment
**Command:**
```bash
docker compose \
  -f docker-compose.base.infrastructure.yaml \
  -f docker-compose.base.override.yaml \
  -f docker-compose.hub.cfg.yaml \
  -f docker-compose.hub.core.yaml \
  -f docker-compose.hub.rules.yaml \
  -p tazama up -d
```

### 3. DockerHub Full-Service Deployment
**Command:**
```bash
docker compose \
  -f docker-compose.base.infrastructure.yaml \
  -f docker-compose.base.override.yaml \
  -f docker-compose.full.cfg.yaml \
  -f docker-compose.hub.core.yaml \
  -f docker-compose.full.rules.yaml \
  -p tazama up -d
```
### 4. Multi-Tenant Deployment
**Command:**
```bash
docker compose \
  -f docker-compose.base.infrastructure.yaml \
  -f docker-compose.base.override.yaml \
  -f docker-compose.base.auth.yaml \
  -f docker-compose.multitenant.cfg.yaml \
  -f docker-compose.hub.core.yaml \
  -f docker-compose.hub.rules.yaml \
  -f docker-compose.multitenant.relay.yaml \
  -p tazama up -d
```

# Tazama Service Port Mappings

When using `docker-compose.base.override.yaml`, the following ports are exposed for local development access:

## Infrastructure Services

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| Valkey | 6379 | 16379 | Cache and pub/sub |
| PostgreSQL | 5432 | 15432 | Database |
| NATS Client | 4222 | 14222 | Messaging |
| NATS Cluster | 6222 | 16222 | Cluster communication |
| NATS HTTP Monitoring | 8222 | 18222 | Monitoring API |

## Core Services

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| TMS | 3000 | 3000 (or `${TMS_PORT}`) | Transaction Monitoring API |
| Admin Service | 3100 | 3100 (or `${ADMIN_PORT}`) | Administration API |

## Authentication Services

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| Keycloak | 8080 | 8080 | Authentication provider |
| Auth Service | 3020 | 3020 | Token generation |

## Logging Services

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| Event Sidecar | Various | 15000 (or `${EVENT_SIDECAR_PORT}`) | Logging sidecar |

## Utility Services

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| pgAdmin | 80 | 5050 (or `${PGADMIN_PORT}`) | PostgreSQL admin UI |
| Hasura | 8080 | 6100 | GraphQL API |
| Elasticsearch | 9200 | 9200 (or `${ES_PORT}`) | Search and analytics |
| Kibana | 5601 | 5601 (or `${KIBANA_PORT}`) | Visualization |
| APM Server | 8200 | 8200 (or `${APMSERVER_PORT}`) | Application monitoring |
| UI | 3001 | 3001 | Demo interface |
| NATS Utilities | 4000 | 4000 | NATS management |
| Batch PPA | 4000 | 4000 | Pain.001 processor |

## Access URLs

Based on the port mappings above, services can be accessed at:

- **PostgreSQL**: `localhost:15432` (user: `postgres`, password: `postgres`)
- **Valkey**: `localhost:16379`
- **NATS**: `localhost:14222` (client), `localhost:18222` (monitoring)
- **TMS API**: `http://localhost:3000` (or `${TMS_PORT}`)
- **Admin API**: `http://localhost:3100` (or `${ADMIN_PORT}`)
- **Keycloak**: `http://localhost:8080` (admin: `admin`, password: `admin`)
- **Auth Service**: `http://localhost:3020`
- **pgAdmin**: `http://localhost:5050` (or `${PGADMIN_PORT}`)
  - Email: `admin@tazama.org`
  - Password: `admin`
- **Hasura Console**: `http://localhost:6100`
  - Admin Secret: `password`
- **Elasticsearch**: `http://localhost:9200` (or `${ES_PORT}`)
- **Kibana**: `http://localhost:5601` (or `${KIBANA_PORT}`)
- **APM Server**: `http://localhost:8200` (or `${APMSERVER_PORT}`)
- **Demo UI**: `http://localhost:3001`
- **NATS Utilities**: `http://localhost:4000`
- **Batch PPA**: `http://localhost:4000`

## Notes

- Many ports are configurable via environment variables (shown in `${VAR_NAME}` format)
- Internal ports are used for service-to-service communication within Docker network
- External ports are mapped for host machine access during development
- Port conflicts will occur if multiple services map to the same external port
- Production deployments should use different port configurations and proper network isolation

# Tazama Environment Variables

Environment variables are managed through `.env` files located in the `env/` directory. Each service has its own environment file for configuration.

## Global Variables

**File**: `.env` (root directory)

Global variables that affect multiple services:

| Variable | Description | Example |
|----------|-------------|---------|
| `TAZAMA_VERSION` | Version tag for DockerHub images | `v2.2.0` |
| `GH_TOKEN` | GitHub Personal Access Token (for builds) | `ghp_xxxxxxxxxxxxx` |
| `BRANCH_NAME` | Branch to build from GitHub (dev deployments) | `main` or `dev` |

## Infrastructure Services

### PostgreSQL
**File**: `env/postgres.env`

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTGRES_USER` | Database superuser | `postgres` |
| `POSTGRES_PASSWORD` | Superuser password | `postgres` |
| `POSTGRES_DB` | Default database | `configuration` |
| `POSTGRES_HOST_AUTH_METHOD` | Authentication method | `trust` (local only) |

### NATS
**File**: `env/nats.env` (if applicable)

NATS configuration variables (may vary based on deployment).

## Core Services

### Transaction Monitoring Service (TMS)
**File**: `env/tms.env`

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `SERVER_URL` | TMS server URL |
| `PORT` | Service port |
| `FUNCTION_NAME` | Service identifier |
| `QUOTING` | Enable/disable quoting |
| `AUTH_ENABLED` | JWT authentication |
| `CERT_PATH` | Path to public key |
| `DATABASE_*` | PostgreSQL connection settings |
| `VALKEY_*` | Valkey connection settings |
| `APM_*` | APM instrumentation settings (if enabled) |

### Admin Service
**File**: `env/admin.env`

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `PORT` | Service port |
| `SERVER_URL` | Admin API URL |
| `AUTH_ENABLED` | JWT authentication |
| `CERT_PATH` | Path to public key |
| `DATABASE_*` | PostgreSQL connection settings |
| `APM_*` | APM instrumentation settings (if enabled) |

### Event Director (ED)
**File**: `env/ed.env`

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `FUNCTION_NAME` | Service identifier |
| `DATABASE_*` | PostgreSQL connection settings |
| `VALKEY_*` | Valkey connection settings |
| `NATS_*` | NATS connection settings |
| `APM_*` | APM instrumentation settings (if enabled) |

### Typology Processor (TP)
**File**: `env/tp.env`

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `FUNCTION_NAME` | Service identifier |
| `DATABASE_*` | PostgreSQL connection settings |
| `VALKEY_*` | Valkey connection settings |
| `NATS_*` | NATS connection settings |
| `APM_*` | APM instrumentation settings (if enabled) |

### Transaction Aggregation and Decisioning Processor (TADP)
**File**: `env/tadp.env`

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `FUNCTION_NAME` | Service identifier |
| `DATABASE_*` | PostgreSQL connection settings |
| `VALKEY_*` | Valkey connection settings |
| `NATS_*` | NATS connection settings |
| `APM_*` | APM instrumentation settings (if enabled) |

### Event Flow (EF)
**File**: `env/event-flow.env`

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `FUNCTION_NAME` | Service identifier |
| `DATABASE_*` | PostgreSQL connection settings |
| `NATS_*` | NATS connection settings |

## Rule Processors

### Rule 901
**File**: `env/rule-901.env`

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `FUNCTION_NAME` | Rule identifier |
| `RULE_NAME` | Rule name |
| `RULE_VERSION` | Rule version |
| `DATABASE_*` | PostgreSQL connection settings |
| `VALKEY_*` | Valkey connection settings |
| `APM_*` | APM instrumentation settings (if enabled) |

### Rule 902
**File**: `env/rule-902.env`

Similar structure to rule-901.env.

### Rule Executer (Base for Full Deployment)
**File**: `env/rule-executer.env`

Base configuration for all rules in full deployment:

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `DATABASE_*` | PostgreSQL connection settings |
| `VALKEY_*` | Valkey connection settings |

Each individual rule (001-091) inherits from this base configuration.

## Authentication Services

### Keycloak
**File**: `env/keycloak.env`

| Variable | Description | Default |
|----------|-------------|---------|
| `KEYCLOAK_ADMIN` | Admin username | `admin` |
| `KEYCLOAK_ADMIN_PASSWORD` | Admin password | `admin` |
| `KC_DB` | Database type | `postgres` |
| `KC_DB_URL_HOST` | Database host | `postgres` |
| `KC_DB_URL_DATABASE` | Database name | `keycloak` |
| `KC_DB_USERNAME` | Database user | `postgres` |
| `KC_DB_PASSWORD` | Database password | `postgres` |

### Auth Service
**File**: `env/auth-service.env`

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `PORT` | Service port |
| `FUNCTION_NAME` | Service identifier |
| `KEYCLOAK_URL` | Keycloak server URL |
| `KEYCLOAK_REALM` | Keycloak realm name |
| `PRIVATE_KEY_PATH` | Path to RSA private key |
| `PUBLIC_KEY_PATH` | Path to RSA public key |

## Relay Services

### NATS Relay
**File**: `env/rs-nats.env`

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `FUNCTION_NAME` | Service identifier |
| `NATS_URL` | NATS server URL |
| `SUBSCRIBE_STREAM` | Internal stream to subscribe to |
| `PUBLISH_STREAM` | External stream to publish to |

For multi-tenant deployments, each tenant has separate relay configuration with tenant-specific streams.

## Logging Services

### Lumberjack
**File**: `env/lumberjack.env`

| Variable | Description |
|----------|-------------|
| `NODE_ENV` | Node.js environment |
| `FUNCTION_NAME` | Service identifier |
| `NATS_URL` | NATS server URL |
| `NATS_SUBJECT` | NATS subject to subscribe to |
| `ELASTICSEARCH_URL` | Elasticsearch URL (if elastic logging enabled) |
| `ELASTICSEARCH_INDEX` | Index pattern for logs |

## Utility Services

### Demo UI
**File**: `env/ui.env`

| Variable | Description |
|----------|-------------|
| `TMS_URL` | TMS API endpoint |
| `ADMIN_URL` | Admin API endpoint |

### pgAdmin
**File**: `env/pgadmin.env`

| Variable | Description | Default |
|----------|-------------|---------|
| `PGADMIN_DEFAULT_EMAIL` | Login email | `admin@tazama.org` |
| `PGADMIN_DEFAULT_PASSWORD` | Login password | `admin` |
| `PGADMIN_LISTEN_PORT` | Internal port | `80` |
| `PGADMIN_PORT` | External port mapping | `5050` |

### Hasura
**File**: `env/hasura.env` (if applicable)

| Variable | Description | Default |
|----------|-------------|---------|
| `HASURA_GRAPHQL_ADMIN_SECRET` | Admin secret | `password` |
| `HASURA_GRAPHQL_UNAUTHORIZED_ROLE` | Anonymous role | `anonymous` |
| `HASURA_GRAPHQL_ENABLE_CONSOLE` | Enable web console | `true` |

### NATS Utilities
**File**: `env/nats-utilities.env`

| Variable | Description |
|----------|-------------|
| `NATS_URL` | NATS server URL |
| `PORT` | Service port |

### Batch PPA
**File**: `env/batch-ppa.env`

| Variable | Description |
|----------|-------------|
| `TMS_URL` | TMS API endpoint |
| `PORT` | Service port |

## Elasticsearch Stack

### Elasticsearch
**File**: `env/elasticsearch.env` (or via docker-compose)

| Variable | Description |
|----------|-------------|
| `ELASTIC_STACK_VERSION` | Elasticsearch version |
| `ES_PORT` | External port mapping |
| `ES_MEM_LIMIT` | Memory limit |
| `discovery.type` | Cluster type |
| `xpack.security.enabled` | Security settings |

### Kibana
**File**: `env/kibana.env` (or via docker-compose)

| Variable | Description |
|----------|-------------|
| `KIBANA_PORT` | External port mapping |
| `KB_MEM_LIMIT` | Memory limit |
| `ELASTICSEARCH_HOSTS` | Elasticsearch URL |

### APM Server
**File**: `env/apm-server.env` (or via docker-compose)

| Variable | Description |
|----------|-------------|
| `APMSERVER_PORT` | External port mapping |
| `apm-server.rum.enabled` | Enable RUM |
| `output.elasticsearch.hosts` | Elasticsearch URL |

## Common Variable Patterns

### Database Connection Variables
Most services use these PostgreSQL connection variables:

| Variable | Description | Typical Value |
|----------|-------------|---------------|
| `DATABASE_NAME` | Database name | `configuration` |
| `DATABASE_USER` | Database user | `postgres` |
| `DATABASE_PASSWORD` | Database password | `postgres` |
| `DATABASE_URL` | Full connection string | `postgresql://postgres:postgres@postgres:5432/configuration` |

### Valkey Connection Variables
Services that use Valkey cache:

| Variable | Description | Typical Value |
|----------|-------------|---------------|
| `VALKEY_DB` | Valkey database number | `0` |
| `VALKEY_AUTH` | Authentication | (empty for local) |
| `VALKEY_SERVERS` | Server connection string | `valkey:6379` |

### NATS Connection Variables
Services that use NATS messaging:

| Variable | Description | Typical Value |
|----------|-------------|---------------|
| `NATS_URL` | NATS server URL | `nats:4222` |
| `PRODUCER_STREAM` | Stream to publish to | Service-specific |
| `CONSUMER_STREAM` | Stream to consume from | Service-specific |

### APM Instrumentation Variables
Services with APM monitoring enabled:

| Variable | Description | Typical Value |
|----------|-------------|---------------|
| `APM_ACTIVE` | Enable APM | `true` or `false` |
| `APM_URL` | APM server URL | `http://apm-server:8200` |
| `APM_SERVICE_NAME` | Service identifier | Service-specific |

## Security Considerations

**WARNING**: The default configuration uses insecure settings for local development:

- `POSTGRES_HOST_AUTH_METHOD=trust` - No password authentication
- Weak default passwords (`admin`, `postgres`)
- Disabled security features in Elasticsearch

**Never use these settings in production!**

For production deployments:
1. Use strong passwords and store them securely
2. Enable proper authentication methods
3. Use secrets management (Docker secrets, Kubernetes secrets, etc.)
4. Enable TLS/SSL for all network communication
5. Restrict network access and use firewalls
6. Enable security features in Elasticsearch/Kibana
7. Use least-privilege access controls