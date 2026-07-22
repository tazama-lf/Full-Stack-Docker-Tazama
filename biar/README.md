<!-- SPDX-License-Identifier: Apache-2.0 -->

<a id="top"></a>

<h1></h1>
<h1 style="color: red;">WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.</h1>

- [1. INTRODUCTION](#1-introduction)
- [2. PRE-REQUISITES](#2-pre-requisites)
- [3. DEPLOYMENT ARCHITECTURE](#3-deployment-architecture)
- [4. INSTALLATION STEPS](#4-installation-steps)
  - [4.1. Deploy BIAR stack](#41-deploy-biar-stack)
  - [4.2. Utilities and teardown](#42-utilities-and-teardown)
- [5. OVERVIEW OF SERVICES](#5-overview-of-services)
  - [5.1. Infrastructure (docker-compose.biar.infrastructure.yaml)](#51-infrastructure-docker-composebiarinfrastructureyaml)
  - [5.2. Application services (docker-compose.hub.biar.yaml / docker-compose.dev.biar.yaml)](#52-application-services-docker-composehubbiary-aml--docker-composedevbiaryaml)
  - [5.3. Init containers (docker-compose.utils.init.yaml)](#53-init-containers-docker-composeuttsiinityaml)
- [6. ACCESSING DEPLOYED COMPONENTS](#6-accessing-deployed-components)
- [7. USING JUPYTERHUB AND THE DATA LAKEHOUSE NOTEBOOKS](#7-using-jupyterhub-and-the-data-lakehouse-notebooks)
  - [7.1. Create your account](#71-create-your-account)
  - [7.2. Start your JupyterLab server](#72-start-your-jupyterlab-server)
  - [7.3. Open a notebook](#73-open-a-notebook)
  - [7.4. Run a notebook](#74-run-a-notebook)
  - [7.5. Admin: approve pending users](#75-admin-approve-pending-users)
  - [7.6. Shut down your server when done](#76-shut-down-your-server-when-done)
- [8. TROUBLESHOOTING TIPS](#8-troubleshooting-tips)
- [9. APPENDIX](#9-appendix)
  - [9.1. NiFi flow management](#91-nifi-flow-management)
  - [9.2. Apache Ozone bucket initialisation](#92-apache-ozone-bucket-initialisation)
  - [9.3. Docker Compose YAML structure](#93-docker-compose-yaml-structure)

<h1></h1>
<h1 style="color: red;">WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.</h1>

For production deployment instructions:
 - [On-Premise Detailed Installation Guide](https://github.com/tazama-lf/On-Prem-helm)
 - [AWS Detailed Installation Guide](https://github.com/tazama-lf/EKS-helm)
 - [Google Cloud Detailed Installation Guide](https://github.com/tazama-lf/GKE-helm)
 - [Azure Detailed Installation Guide](https://github.com/tazama-lf/AKS-helm)

# 1. INTRODUCTION

The `biar/` stack provides the Business Intelligence, Analytics, and Reporting (BIAR) infrastructure for Tazama. It adds a data ingestion and processing pipeline built on top of:

- **Apache NiFi** — visual data flow engine that ingests transaction and case data from the core and extensions PostgreSQL databases
- **Apache Ozone** — distributed object storage (S3-compatible) for data lake storage
- **Apache Solr** — full-text search and document indexing
- **Apache Tika** — document parsing and content extraction
- **Automation Orchestrator** — PySpark-based batch processing and Hudi data lake management
- **Datalakehouse API** — REST API for querying the Hudi data lakehouse
- **Unstructured Pipeline** — document ingestion pipeline (Tika + Solr)
- **JupyterHub** — multi-user analytics environment with pre-loaded PySpark notebooks

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

   1. Deploy BIAR stack (DockerHub images)
   2. Deploy BIAR stack (GitHub builds)
   3. Utilities / teardown

Select option (1-3), or (q)uit:
```

## 4.1. Deploy BIAR stack

Options 1 and 2 run a pre-flight connectivity check to verify that `SERVER_A_HOST:14222` (NATS) is reachable. If the check passes, the launcher starts the full BIAR stack using a three-file compose chain.

| Option | Build source |
|---|---|
| 1 | Pre-built DockerHub images (version controlled by `TAZAMA_VERSION` in `.env`) |
| 2 | GitHub source builds (branch controlled by `BIAR_BRANCH` in `.env`) |

**Compose chain used (DockerHub images):**

```
docker compose -p tazama-biar \
  -f ./docker-compose.biar.infrastructure.yaml \
  -f ./docker-compose.hub.biar.yaml \
  -f ./docker-compose.utils.init.yaml \
  up -d
```

`docker-compose.dev.biar.yaml` replaces `docker-compose.hub.biar.yaml` for GitHub source builds.

> [!NOTE]
> Apache Ozone requires a strict startup order. The SCM must fully initialise before the OM starts, and both must be healthy before S3G accepts requests. The launcher handles this with a staged delay (SCM → 20 s → OM → 15 s → full stack). On first boot, expect the stack to take 2–3 minutes before all services are ready.

The `nifi-init` container polls the NiFi API after startup and injects the pre-configured parameter context and flow template when NiFi becomes ready (up to 5 minutes). The `aws-cli` container polls S3G and creates the `tazama` Ozone bucket automatically once S3G is healthy.

## 4.2. Utilities and teardown

Option 3 provides:

```text
Utilities:
  1. Tear down BIAR
```

Teardown brings down all containers and removes all volumes (`--volumes`). Data stored in Solr, NiFi, Ozone, and JupyterHub will be permanently deleted.

<div style="text-align: right"><a href="#top">Top</a></div>

# 5. OVERVIEW OF SERVICES

All services run in the `tazama-biar` Compose project across three compose files.

## 5.1. Infrastructure (docker-compose.biar.infrastructure.yaml)

Shared infrastructure that must be running before any application service starts. These services are always deployed regardless of build source.

| Service | Container | Port | Description |
|---|---|---|---|
| Apache Tika | `biar-tika` | 9998 | Document parsing and content extraction (PDF, Office formats, etc.) |
| Apache Solr | `biar-solr` | 8983 | Full-text search and indexing. Initialises with the `biar_docs` core. |
| Ozone SCM | `ozone-scm-1` | 9876 | Storage Container Manager — Ozone control plane |
| Ozone OM | `ozone-om-1` | — | Object Manager — Ozone namespace service |
| Ozone Datanode 1 | `ozone-datanode-1` | — | Stores object data (no external port) |
| Ozone Datanode 2 | `ozone-datanode-2` | — | Stores object data (no external port) |
| Ozone Datanode 3 | `ozone-datanode-3` | — | Stores object data (no external port) |
| Ozone Recon | `ozone-recon-1` | 9888 | Ozone monitoring and metrics UI |
| Ozone S3G | `ozone-s3g-1` | 9878 | S3-compatible gateway for reading and writing Ozone objects |

> [!NOTE]
> Apache Ozone runs with three datanodes and replication factor 1 in this deployment. This is appropriate for development and testing. A production Ozone deployment should use a minimum of three datanodes with replication factor 3.

## 5.2. Application services (docker-compose.hub.biar.yaml / docker-compose.dev.biar.yaml)

Tazama BIAR application services. The `hub` variant pulls pre-built images from DockerHub; the `dev` variant builds from the `tazama-lf/biar` GitHub repository.

| Service | Container | Port | Description |
|---|---|---|---|
| Apache NiFi | `biar-nifi` | 8088 | Visual data flow engine. Connects to PostgreSQL on Server A (`:15432`) and Server B (`:15433`) to ingest transaction and case data. |
| Automation Orchestrator | `biar-automation-orchestrator` | 7619 | PySpark-based batch processor and Hudi data lake manager. Writes to the shared warehouse at `TAZAMA_WAREHOUSE_HOST_PATH`. |
| Datalakehouse API | `biar-datalakehouse-api` | 8282 | FastAPI REST interface for querying the Hudi data lakehouse. Reads from `TAZAMA_WAREHOUSE_HOST_PATH`. |
| Unstructured Pipeline | `biar-unstructured-pipeline` | — | Document ingestion pipeline that submits files to Tika for parsing and indexes results in Solr (no external port). |
| JupyterHub | `biar-jupyterhub` | 8000 | Multi-user analytics environment. Each user gets an isolated JupyterLab session with pre-loaded PySpark notebooks. Uses `NativeAuthenticator` (sign-up on first visit). |

> [!NOTE]
> `TAZAMA_WAREHOUSE_HOST_PATH` in `biar/.env` controls where the Hudi warehouse is stored on the host. In the AWS deployment this is `/opt/Warehouse` (created by `deploy-biar.ps1`). In a local deployment, set this to any directory you have write access to.

## 5.3. Init containers (docker-compose.utils.init.yaml)

One-shot containers that run at stack startup and remain running for ad-hoc operations.

| Service | Container | Description |
|---|---|---|
| AWS CLI | `ozone-aws-cli` | Polls S3G until healthy, then creates the `tazama` Ozone bucket. Remains running for ad-hoc S3 operations against Ozone. |
| NiFi Init | `nifi-init` | Polls the NiFi API and injects the pre-configured parameter context and flow template when NiFi is ready (up to 5 min). Restarts on failure. |

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

#### Automation Orchestrator
- REST API / Swagger UI: <http://localhost:7619/docs>

#### Datalakehouse API
- REST API / Swagger UI: <http://localhost:8282/docs>

#### JupyterHub
- JupyterHub UI: <http://localhost:8000>
- On first visit, use the **Sign up** form to create an account. The first user whose name matches `JUPYTERHUB_ADMIN` in `env/biar-jupyterhub.env` (default: `admin`) is automatically granted admin rights.
- Each user gets an isolated JupyterLab environment with the shared read-only notebooks pre-loaded from `/srv/notebooks/`.

<div style="text-align: right"><a href="#top">Top</a></div>

# 7. USING JUPYTERHUB AND THE DATA LAKEHOUSE NOTEBOOKS

JupyterHub provides a multi-user analytics environment pre-loaded with PySpark notebooks that query the Tazama Hudi data lakehouse. Each user gets their own isolated JupyterLab process; user accounts and server state persist across container restarts.

## 7.1. Create your account

1. Open JupyterHub at <http://localhost:8000> (or `http://<Server C>:8000` in a multi-server deployment).
2. Click **Sign up** on the login page.
3. Enter username `admin` and a strong password, then click **Create User**. You will be redirected back to the login page.
4. Log in with the same `admin` username and password.

> [!IMPORTANT]
> **The first account created must use the admin username.** The admin username is set by `JUPYTERHUB_ADMIN` in `biar/env/biar-jupyterhub.env` (default: `admin`). If the first sign-up uses a different name, no account will have admin rights and you will not be able to approve subsequent users. If this happens, stop the stack, delete the `jupyterhub_data` volume, and restart.

> [!NOTE]
> There is no pre-seeded password. The password you choose during sign-up is hashed and stored in the SQLite database on the `jupyterhub_data` volume. It persists across container restarts.

Because `open_signup = True`, subsequent users can sign up immediately and are granted access automatically. To manage or revoke users, use the Admin panel at <http://localhost:8000/hub/admin>. If you want to require admin approval for new users, set `c.NativeAuthenticator.open_signup = False` in the JupyterHub config and rebuild the image.

## 7.2. Start your JupyterLab server

1. After signing up (or logging in), you will be taken to the JupyterHub home page.
2. Click **Start My Server**.
3. JupyterHub will spawn a JupyterLab process for your user. This takes 15–30 seconds on first launch while PySpark initialises.
4. JupyterLab will open automatically in your browser once the server is ready.

Each user's server runs as a separate Linux process inside the container, using the shared environment variables (`S3A_ENDPOINT`, `S3A_ACCESS_KEY`, `WAREHOUSE_ROOT`, etc.) that are forwarded automatically from the container's env.

## 7.3. Open a notebook

The shared notebooks are at `/srv/notebooks/` and appear in the JupyterLab file browser on the left. They are read-only in that location — to edit a notebook, first copy it to your home directory:

1. Right-click the notebook in the file browser.
2. Click **Copy**.
3. Navigate to `/home/<your-username>/` in the file browser.
4. Click **Paste**.

You can then open and edit the copy freely without affecting other users.

Available notebooks:

| Notebook | Description |
|---|---|
| `Dashboard_Metrics.ipynb` | Key BIAR dashboard metrics summary |
| `Executive_Overview_Dashboard.ipynb` | High-level executive view of transaction monitoring results |
| `Fraud_Trend_Analysis_Dashboard.ipynb` | Time-series analysis of detected fraud patterns |
| `Fraud_Typology_Effectiveness_Dashboard.ipynb` | Per-typology rule effectiveness and hit-rate analysis |
| `Case_Management_Trend_Dashboard.ipynb` | Case volume and resolution trends over time |
| `Case_Tracking_Analysis_Dashboard.ipynb` | Detailed case lifecycle and escalation analysis |
| `TMS_Performance_Dashboard.ipynb` | Transaction Monitoring Service throughput and latency metrics |

## 7.4. Run a notebook

1. Open a notebook (from `/srv/notebooks/` or your home copy).
2. Ensure a kernel is attached — the kernel status indicator appears in the top-right corner of the notebook. If no kernel is running, select **Python 3** from the kernel picker.
3. Run cells individually with **Shift + Enter**, or run the entire notebook via **Run → Run All Cells**.

All notebooks read Spark configuration from environment variables. The key variables and their defaults are:

| Variable | Default | Description |
|---|---|---|
| `S3A_ENDPOINT` | `http://s3g:9878` | Ozone S3G endpoint for Spark S3A reads |
| `S3A_ACCESS_KEY` | `tazama` | Ozone S3 access key |
| `S3A_SECRET_KEY` | `tazama` | Ozone S3 secret key |
| `WAREHOUSE_ROOT` | `/opt/Tazama_Warehouse` | Path to the Hudi warehouse root inside the container |
| `SPARK_DRIVER_MEMORY` | `4g` | Heap memory per user Spark session |

These defaults match the values in `biar/env/biar-jupyterhub.env` and the Ozone credentials in `biar/.env`. Override them in `biar-jupyterhub.env` before deploying if your Ozone is configured differently.

> [!NOTE]
> Each user's Spark session starts a JVM on first notebook execution. Expect a 20–30 second delay before the first cell produces output. Subsequent cells in the same session run much faster.

## 7.5. Admin: approve pending users

If `open_signup` is disabled, new user registrations will be in a **pending** state until an admin approves them.

1. Log in as the admin user.
2. Navigate to <http://localhost:8000/hub/authorize>.
3. Click **Authorize** next to each pending username.

An admin can also manage users, stop servers, and view server logs from the JupyterHub Admin panel at <http://localhost:8000/hub/admin>.

## 7.6. Shut down your server when done

Each running JupyterLab server consumes Spark driver memory (`SPARK_DRIVER_MEMORY`, default 4 GB). Shut it down when not in use to free resources for other users.

1. In JupyterLab, go to **File → Hub Control Panel**.
2. Click **Stop My Server**.
3. Your work is saved automatically — notebooks you saved to your home directory will still be there when you restart.

<div style="text-align: right"><a href="#top">Top</a></div>

# 8. TROUBLESHOOTING TIPS

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

# 9. APPENDIX

## 9.1. NiFi flow management

The BIAR NiFi instance does not ship with a pre-configured flow. After first boot:

1. Open the NiFi UI at <http://localhost:8088/nifi>
2. Log in with username `admin` and password `admin123456789` (change this for any shared deployment)
3. Import or build a flow that reads from the PostgreSQL databases on Server A (`SERVER_A_HOST:15432`) and Server B (`SERVER_B_HOST:15433`)

NiFi state and flow configuration are persisted in named Docker volumes (`nifi_conf`, `nifi_state`, `nifi_db`, `nifi_flowfile`, `nifi_content`, `nifi_provenance`). These volumes survive container restarts. They are removed by a teardown with `--volumes`.

To export a configured flow for reuse, use NiFi's built-in `Download flow definition` option (right-click the process group in the canvas). Store the exported JSON in version control.

## 9.2. Apache Ozone bucket initialisation

The `ozone-aws-cli` container automatically creates the `tazama` bucket each time the stack is started (the `|| true` in the entrypoint makes the command idempotent if the bucket already exists). The bucket name is controlled by `AWS_BUCKET_NAME` in `biar/.env`. To interact with Ozone manually using the S3-compatible API:

```
docker exec ozone-aws-cli aws --endpoint-url http://s3g:9878 s3 ls
```

The Ozone S3G access key is `tazama` and secret key is `tazama` in the default configuration (set via `S3A_ACCESS_KEY` and `S3A_SECRET_KEY` in `biar/.env`). These are committed defaults appropriate for a local development deployment only.

## 9.3. Docker Compose YAML structure

The BIAR stack uses three compose files composed together:

| File | Purpose |
|---|---|
| `docker-compose.biar.infrastructure.yaml` | Always-on infrastructure: Tika, Solr, Ozone (SCM, OM, 3× datanodes, Recon, S3G) |
| `docker-compose.hub.biar.yaml` | Application services from DockerHub: NiFi, Automation Orchestrator, Datalakehouse API, Unstructured Pipeline, JupyterHub |
| `docker-compose.dev.biar.yaml` | Application services built from GitHub source (replaces `hub.biar` for dev deployments) |
| `docker-compose.utils.init.yaml` | Init containers: `aws-cli` (Ozone bucket creation), `nifi-init` (NiFi flow injection) |

View [docker-yaml-structure.md](./docker-yaml-structure.md) for additional detail about the Docker Compose files in the wider Tazama repository.

<div style="text-align: right"><a href="#top">Top</a></div>
