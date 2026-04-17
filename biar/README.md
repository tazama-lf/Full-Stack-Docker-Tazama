<!-- SPDX-License-Identifier: Apache-2.0 -->

<a id="top"></a>

<h1></h1>
<h1 style="color: red;">WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.</h1>

- [1. INTRODUCTION](#1-introduction)
- [2. PRE-REQUISITES](#2-pre-requisites)
- [3. DEPLOYMENT ARCHITECTURE](#3-deployment-architecture)
- [4. INSTALLATION STEPS](#4-installation-steps)
  - [4.1. Deploy BIAR infrastructure](#41-deploy-biar-infrastructure)
  - [4.2. Utilities and teardown](#42-utilities-and-teardown)
- [5. OVERVIEW OF SERVICES](#5-overview-of-services)
- [6. ACCESSING DEPLOYED COMPONENTS](#6-accessing-deployed-components)
- [7. TROUBLESHOOTING TIPS](#7-troubleshooting-tips)
- [8. APPENDIX](#8-appendix)
  - [8.1. NiFi flow management](#81-nifi-flow-management)
  - [8.2. Apache Ozone bucket initialisation](#82-apache-ozone-bucket-initialisation)
  - [8.3. Docker Compose YAML structure](#83-docker-compose-yaml-structure)

<h1></h1>
<h1 style="color: red;">WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.</h1>

For production deployment instructions:
 - [On-Premise Detailed Installation Guide](https://github.com/tazama-lf/On-Prem-helm)
 - [AWS Detailed Installation Guide](https://github.com/tazama-lf/EKS-helm)
 - [Google Cloud Detailed Installation Guide](https://github.com/tazama-lf/GKE-helm)
 - [Azure Detailed Installation Guide](https://github.com/tazama-lf/AKS-helm)

# 1. INTRODUCTION

The `biar/` stack provides the Business Intelligence, Analytics, and Reporting (BIAR) infrastructure for Tazama. It adds a data ingestion and processing pipeline built on top of Apache NiFi, Apache Ozone (object storage), Apache Solr (search), and Apache Tika (document analysis). NiFi connects to the PostgreSQL databases on both the core server (Server A) and the extensions server (Server B) to ingest transaction and case data for reporting purposes.

This stack is self-contained and does not add to or modify any existing Compose project. It runs under its own `tazama-biar` Compose project. The core stack (and optionally the extensions stack) must be running and accessible before the BIAR stack is started.

This guide covers the local deployment using the included launcher scripts. For the AWS deployment see [infra/aws/aws-deployment-instructions.md](../infra/aws/aws-deployment-instructions.md).

<div style="text-align: right"><a href="#top">Top</a></div>

# 2. PRE-REQUISITES

- Git
- Code editor (this guide assumes VS Code)
- Docker Desktop for Windows with WSL (or Linux/macOS equivalent)
- At least 4 GB of additional free memory (NiFi, Ozone, and Solr each have significant heap requirements)

Unlike the core and extensions stacks, the BIAR stack does not pull images from `ghcr.io` -- all services use public DockerHub images. A GitHub personal access token is therefore not required.

**The core stack must be running** before starting the BIAR stack. The launcher script verifies that the core NATS service is reachable at `SERVER_A_HOST:14222` before proceeding. In a single-machine deployment this defaults to `localhost`. In a multi-server deployment, set `SERVER_A_HOST` in `biar/.env` to the private IP address of Server A.

<div style="text-align: right"><a href="#top">Top</a></div>

# 3. DEPLOYMENT ARCHITECTURE

The BIAR stack runs on a dedicated server (Server C in the AWS deployment, or `localhost` in a single-machine development deployment).

| Dependency | Why required |
|---|---|
| Core PostgreSQL `SERVER_A_HOST:15432` | NiFi reads transaction and evaluation data from the core Postgres instance |
| Extensions PostgreSQL `SERVER_B_HOST:15433` | NiFi reads CMS and case data from the extensions Postgres instance |
| Core NATS `SERVER_A_HOST:14222` | Used at startup to verify the core stack is reachable before deploying |

In `biar/.env`, set `SERVER_A_HOST` and `SERVER_B_HOST` to the appropriate addresses:

```ini
# Single-machine local deployment (default)
SERVER_A_HOST=localhost
SERVER_B_HOST=localhost

# Multi-server deployment (example)
SERVER_A_HOST=10.0.1.10
SERVER_B_HOST=10.0.1.20
```

<div style="text-align: right"><a href="#top">Top</a></div>

# 4. INSTALLATION STEPS

Navigate to the `biar/` folder and run the launcher:

**Windows**
```
tazama-biar.bat
```
**PowerShell**
```powershell
.\tazama-biar.bat
```
**Unix (Linux/macOS)**
```
./tazama-biar.sh
```

The launcher presents the following menu:

```text
============================================================
 Tazama BIAR Launcher
============================================================

 Pre-requisite: tazama-core must be running on Server A

   1. Deploy BIAR infrastructure
   2. Utilities / teardown

Select option (1-2), or (q)uit:
```

## 4.1. Deploy BIAR infrastructure

Option 1 runs a pre-flight connectivity check to verify that `SERVER_A_HOST:14222` (NATS) is reachable. If the check passes, it starts the full BIAR stack:

```
docker compose -p tazama-biar -f ./docker-compose.biar.infrastructure.yaml up -d
```

The `aws-cli` container runs last. It waits ~15 seconds for the S3G gateway to become available, then creates the `biar-bucket` object-storage bucket in Apache Ozone, and remains running as a utility container for any subsequent S3 operations against Ozone.

## 4.2. Utilities and teardown

Option 2 provides:

```text
Utilities:
  1. Tear down BIAR
```

Teardown brings down all containers and removes all volumes (`--volumes`). Data stored in Solr, NiFi, and Ozone will be permanently deleted.

<div style="text-align: right"><a href="#top">Top</a></div>

# 5. OVERVIEW OF SERVICES

All services run in the `tazama-biar` Compose project on a single compose file (`docker-compose.biar.infrastructure.yaml`).

| Service | Container | Port | Description |
|---|---|---|---|
| Apache Tika | `biar-tika` | 9998 | Document parsing and content extraction (PDF, Office formats, etc.) |
| Apache Solr | `biar-solr` | 8983 | Full-text search and indexing. Initialises with the `biar_docs` core. |
| Apache NiFi | `biar-nifi` | 8088 | Visual data flow engine. Connects to PostgreSQL on Server A and Server B to ingest transaction and case data. |
| Ozone SCM | `scm` | 9876 | Storage Container Manager -- Ozone control plane |
| Ozone OM | `om` | 9874 | Object Manager -- Ozone namespace service |
| Ozone Datanode | `datanode` | -- | Stores actual object data (no external port) |
| Ozone Recon | `recon` | 9888 | Ozone monitoring and metrics UI |
| Ozone S3G | `s3g` | 9878 | S3-compatible gateway for reading and writing Ozone objects |
| AWS CLI | `ozone-aws-cli` | -- | One-shot utility: creates the `biar-bucket` bucket in Ozone via the S3G endpoint, then stays running for ad-hoc S3 operations |

> [!NOTE]
> Apache Ozone runs as a single-node cluster in this deployment (replication factor 1). This is appropriate for development and testing. A production Ozone deployment requires a minimum of three datanodes.

<div style="text-align: right"><a href="#top">Top</a></div>

# 6. ACCESSING DEPLOYED COMPONENTS

After a successful deployment, the following interfaces are accessible from `localhost` (or the Server C address in a multi-server deployment):

#### Apache NiFi
- NiFi UI: <http://localhost:8088/nifi>
- Default credentials: username `admin`, password `admin123456789`

> [!NOTE]
> **Change the NiFi admin password before exposing this service on a shared network.** The default password is committed in the repository and is publicly known. See the AWS deployment instructions for the approach used to override it at deploy time.

#### Apache Solr
- Solr Admin UI: <http://localhost:8983>
- `biar_docs` core query interface: <http://localhost:8983/solr/biar_docs/query>

#### Apache Tika
- Tika REST API: <http://localhost:9998>

#### Apache Ozone
- Object Manager API: <http://localhost:9874>
- Recon monitoring UI: <http://localhost:9888>
- S3-compatible gateway: <http://localhost:9878>
- Storage Container Manager: <http://localhost:9876>

<div style="text-align: right"><a href="#top">Top</a></div>

# 7. TROUBLESHOOTING TIPS

### NiFi fails to start or takes a very long time

NiFi requires significant heap memory and can take 2-3 minutes to initialise on first boot. It generates TLS certificates and writes its state store on first run. If the container exits immediately, check the logs:

```
docker logs biar-nifi
```

If you see `OutOfMemoryError`, increase Docker Desktop's memory allocation. NiFi is configured with 512 MB initial and 1 GB maximum heap by default.

If NiFi shows an error about an existing `./conf/nifi.properties` that conflicts with environment variables, the NiFi volume contains state from a previous run with different credentials. Stop and remove volumes before redeploying:

```
docker compose -p tazama-biar -f ./docker-compose.biar.infrastructure.yaml down --volumes
```

### Ozone SCM or OM does not start

Ozone services use a `ENSURE_*_INITIALIZED` flag to detect first-boot and run initialisation. If the SCM or OM container exits early, check the logs for a missing `VERSION` file:

```
docker logs scm
docker logs om
```

On retry after a failed initialisation, ensure volumes are clean before redeploying (see teardown command above).

### Pre-flight check fails: "tazama-core is not reachable"

The launcher checks that `SERVER_A_HOST:14222` is reachable via TCP. If the check fails:
1. Verify the core stack is running: `docker ps | findstr nats`
2. Check that `SERVER_A_HOST` in `biar/.env` is set to the correct address
3. On Linux/WSL, verify the port is not blocked by a host firewall

<div style="text-align: right"><a href="#top">Top</a></div>

# 8. APPENDIX

## 8.1. NiFi flow management

The BIAR NiFi instance does not ship with a pre-configured flow. After first boot:

1. Open the NiFi UI at <http://localhost:8088/nifi>
2. Log in with username `admin` and password `admin123456789` (change this for any shared deployment)
3. Import or build a flow that reads from the PostgreSQL databases on Server A (`SERVER_A_HOST:15432`) and Server B (`SERVER_B_HOST:15433`)

NiFi state and flow configuration are persisted in named Docker volumes (`nifi_conf`, `nifi_state`, `nifi_db`, `nifi_flowfile`, `nifi_content`, `nifi_provenance`). These volumes survive container restarts. They are removed by a teardown with `--volumes`.

To export a configured flow for reuse, use NiFi's built-in `Download flow definition` option (right-click the process group in the canvas). Store the exported JSON in version control.

## 8.2. Apache Ozone bucket initialisation

The `ozone-aws-cli` container automatically creates the `biar-bucket` bucket each time the stack is started (the `|| true` in the entrypoint makes the command idempotent if the bucket already exists). To interact with Ozone manually using the S3-compatible API:

```
docker exec ozone-aws-cli aws --endpoint-url http://s3g:9878 s3 ls
```

The Ozone S3G access key is `admin` and secret key is `admin` in the default configuration. These are committed defaults appropriate for a local development deployment only.

## 8.3. Docker Compose YAML structure

View this file for additional detail about the Docker Compose files in this stack: [Docker Compose YAML Structure Overview](./docker-yaml-structure.md)

<div style="text-align: right"><a href="#top">Top</a></div>
