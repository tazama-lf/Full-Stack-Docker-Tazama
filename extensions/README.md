<!-- SPDX-License-Identifier: Apache-2.0 -->

<a id="top"></a>

<h1></h1>
<h1 style="color: red;">WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.</h1>

- [1. INTRODUCTION](#1-introduction)
- [2. PRE-REQUISITES](#2-pre-requisites)
- [3. DEPLOYMENT ARCHITECTURE](#3-deployment-architecture)
- [4. INSTALLATION STEPS](#4-installation-steps)
  - [4.1. Server A pre-flight: DEMS and DEAPI](#41-server-a-pre-flight-dems-and-deapi)
  - [4.2. Server B extensions stack](#42-server-b-extensions-stack)
  - [4.3. Utilities and teardown](#43-utilities-and-teardown)
- [5. OVERVIEW OF SERVICES](#5-overview-of-services)
  - [5.1. Server A APIs (joined to tazama-core)](#51-server-a-apis-joined-to-tazama-core)
  - [5.2. Extensions infrastructure (Server B)](#52-extensions-infrastructure-server-b)
  - [5.3. Extensions services (Server B)](#53-extensions-services-server-b)
- [6. ACCESSING DEPLOYED COMPONENTS](#6-accessing-deployed-components)
- [7. TROUBLESHOOTING TIPS](#7-troubleshooting-tips)
- [8. APPENDIX](#8-appendix)
  - [8.1. Authentication public key](#81-authentication-public-key)
  - [8.2. Docker Compose YAML structure](#82-docker-compose-yaml-structure)

<h1></h1>
<h1 style="color: red;">WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.</h1>

For production deployment instructions:
 - [On-Premise Detailed Installation Guide](https://github.com/tazama-lf/On-Prem-helm)
 - [AWS Detailed Installation Guide](https://github.com/tazama-lf/EKS-helm)
 - [Google Cloud Detailed Installation Guide](https://github.com/tazama-lf/GKE-helm)
 - [Azure Detailed Installation Guide](https://github.com/tazama-lf/AKS-helm)

# 1. INTRODUCTION

The `extensions/` stack adds Tazama's extended tooling on top of the core deployment. It provides the browser-based studios and the case management system that operators use to configure rules, review transaction data, and investigate fraud cases. It also contributes two API services (DEMS and DEAPI) that are deployed onto the core server rather than the extensions server, because the core processors depend on them directly.

In a local single-machine deployment, everything runs on `localhost`. In the AWS multi-server deployment, the extensions infrastructure and services run on a dedicated Server B instance, while DEMS and DEAPI run on Server A alongside the core stack.

This guide covers the local deployment using the included launcher scripts. For the AWS deployment see [infra/aws/aws-deployment-instructions.md](../infra/aws/aws-deployment-instructions.md).

<div style="text-align: right"><a href="#top">Top</a></div>

# 2. PRE-REQUISITES

The pre-requisites for deploying the extensions stack are the same as for the core stack:

- Git
- Code editor (this guide assumes VS Code)
- Docker Desktop for Windows with WSL (or Linux/macOS equivalent)
- GitHub personal access token with `read:packages` permissions

> [!NOTE] **Notes on GitHub personal access token**
> - A GitHub personal access token must be created with `read:packages` permissions to pull images from the GitHub Container Registry (`ghcr.io`)
> - Add the token as a Windows environment variable called `GH_TOKEN`. If the token had been set as an environment variable, you can verify with: `echo %GH_TOKEN%` (cmd) or `echo $env:GH_TOKEN` (PowerShell)
> - Once the token is set, authenticate Docker with `ghcr.io`. Docker stores the credential securely and reuses it automatically for all subsequent image pulls. Repeat this step whenever your PAT expires or is rotated:
>
>   **PowerShell:**
>   ```powershell
>   echo $env:GH_TOKEN | docker login ghcr.io -u <your-github-username> --password-stdin
>   ```
>   **Command prompt:**
>   ```
>   echo %GH_TOKEN% | docker login ghcr.io -u <your-github-username> --password-stdin
>   ```

In addition, the **core stack must be running** before the extensions stack is started. The DEMS and DEAPI pre-flight step (Section 4.1) requires the `tazama-core` Docker Compose project to be active on the same machine.

<div style="text-align: right"><a href="#top">Top</a></div>

# 3. DEPLOYMENT ARCHITECTURE

The extensions stack is split into two parts that must be deployed in order:

| Part | Where | What | When |
|---|---|---|---|
| Server A pre-flight | Server A (core machine) | DEMS, DEAPI -- joined to the `tazama-core` compose project | Before starting Server B |
| Extensions stack | Server B (this machine) | PostgreSQL, SFTP, CouchDB, Flowable, OpenSearch, TCS, TRS, CMS | After DEMS and DEAPI are running |

**Why is the pre-flight on Server A?**
The Data Enrichment API (DEAPI) and the Data Enrichment Monitoring Service (DEMS) are consumed by rule processors and the TMS which all run on Server A. They must be reachable from within the `tazama-core` Docker network, so they join that Compose project rather than the extensions project.

**Single-machine local deployment:**
On a single machine, Server A and Server B are both `localhost`. Run the pre-flight step first (options 1 or 2 in the launcher), then the extensions stack (options 3 or 4).

<div style="text-align: right"><a href="#top">Top</a></div>

# 4. INSTALLATION STEPS

Navigate to the `extensions/` folder and run the launcher:

**Windows**
```
tazama-extensions.bat
```
**PowerShell**
```powershell
.\tazama-extensions.bat
```
**Unix (Linux/macOS)**
```
./tazama-extensions.sh
```

The launcher presents the following menu:

```text
============================================================
 Tazama Extensions Launcher
============================================================

 Server A pre-flight  (run on Server A before Server B):
   1. Deploy DEMS + DEAPI  (GitHub builds)
   2. Deploy DEMS + DEAPI  (DockerHub images)

 Server B extensions stack:
   3. Deploy extensions    (GitHub builds)
   4. Deploy extensions    (DockerHub images)

   5. Utilities / teardown

Select option (1-5), or (q)uit:
```

## 4.1. Server A pre-flight: DEMS and DEAPI

Options 1 and 2 deploy DEMS and DEAPI onto the running `tazama-core` Compose project on Server A. The launcher checks that `tazama-core` is running before proceeding.

| Option | Build source |
|---|---|
| 1 | GitHub source builds (branch controlled by `DEMS_BRANCH` and `DEAPI_BRANCH` in `.env`) |
| 2 | Pre-built DockerHub images (version controlled by `TAZAMA_VERSION` in `.env`) |

**Compose chain used (appended to tazama-core project):**

GitHub builds:
```
docker compose -p tazama-core -f ./docker-compose.dev.extensions.apis.yaml up -d
```

DockerHub images:
```
docker compose -p tazama-core -f ./docker-compose.hub.extensions.apis.yaml up -d
```

Both files deploy:
- `tazama-dems-1` -- Data Enrichment Monitoring Service (port `3002`)
- `tazama-deapi-1` -- Data Enrichment API (port `3001`)

## 4.2. Server B extensions stack

Options 3 and 4 deploy the full extensions infrastructure and services. The launcher prompts:

```text
Include pgAdmin? [y/N]:
```

pgAdmin is an optional add-on. See Section 5.2 for details.

The launcher also automatically copies `../core/auth/test-public-key.pem` into `./auth/` if it is not already present. TCS and TRS require this key for JWT validation.

| Option | Build source |
|---|---|
| 3 | GitHub source builds (branches controlled in `.env`) |
| 4 | Pre-built DockerHub images (version controlled by `TAZAMA_VERSION`) |

**Compose chain used (GitHub builds example):**

```
docker compose -p tazama-extensions \
  -f ./docker-compose.extensions.infrastructure.yaml \
  -f ./docker-compose.dev.extensions.yaml \
  [-f ./docker-compose.utils.pgadmin.yaml]   # if pgAdmin is selected
  up -d
```

The `docker-compose.hub.extensions.yaml` file replaces `docker-compose.dev.extensions.yaml` for DockerHub image deployments.

## 4.3. Utilities and teardown

Option 5 in the launcher provides teardown and utility commands:

```text
Utilities:
  1. Tear down extensions stack  (Server B)
  2. Remove DEMS + DEAPI         (Server A)
  3. Tear down all
  4. Start pgAdmin               (Server B)
```

All teardown commands also remove volumes (`--volumes`). Data stored in PostgreSQL, SFTP, CouchDB, and OpenSearch will be permanently deleted.

<div style="text-align: right"><a href="#top">Top</a></div>

# 5. OVERVIEW OF SERVICES

## 5.1. Server A APIs (joined to tazama-core)

These services run on Server A and join the `tazama-core` Docker Compose project:

| Service | Container | Port | Description |
|---|---|---|---|
| DEAPI | `tazama-deapi-1` | 3001 | Data Enrichment API -- enriches transaction data with external information |
| DEMS | `tazama-dems-1` | 3002 | Data Enrichment Monitoring Service -- monitors data enrichment activity |

## 5.2. Extensions infrastructure (Server B)

These infrastructure services are started as part of the `tazama-extensions` Compose project:

| Service | Container | Port | Description |
|---|---|---|---|
| PostgreSQL | `postgres` | 15433 | Dedicated PostgreSQL instance for CMS and extensions services |
| SFTP | `tazama-sftp-1` | 12222 | SFTP server for transaction file uploads (used by TCS) |
| CouchDB | `tazama-cms-couchdb` | 5984 | Document database for CMS audit and case data |
| Flowable | `tazama-cms-flowable` | 8081 | Workflow engine for CMS case lifecycle management |
| OpenSearch | `opensearch-node1` | 9200 | Search and indexing for transaction and case data |
| DB Migration | `cms-migrations` | -- | One-shot container: applies CMS schema to PostgreSQL on startup |
| pgAdmin | `pgadmin` | 5051 | Optional PostgreSQL web UI (included if pgAdmin is selected) |

> [!NOTE]
> The PostgreSQL instance in the extensions stack (port 15433) is separate from the core PostgreSQL instance (port 15432). The CMS and extensions services connect to the extensions PostgreSQL; the core processors connect to the core PostgreSQL.

## 5.3. Extensions services (Server B)

| Service | Container | Port | Description |
|---|---|---|---|
| TCS backend | `tcs-backend` | 3010 | Transaction Configuration Studio API |
| TCS frontend | `tcs-frontend` | 5173 | Transaction Configuration Studio web UI |
| TRS backend | `trs-backend` | 3005 | Transaction Rule Studio API |
| TRS frontend | `trs-frontend` | 5174 | Transaction Rule Studio web UI |
| CMS backend | `tazama-cms-backend` | 3090 | Case Management System API |
| CMS frontend | `tazama-cms-frontend` | 5175 | Case Management System web UI |

<div style="text-align: right"><a href="#top">Top</a></div>

# 6. ACCESSING DEPLOYED COMPONENTS

After a successful deployment, the following web interfaces are accessible from `localhost` (or the Server B IP address in a multi-server deployment):

#### Server A APIs
- DEAPI: <http://localhost:3001>
- DEMS: <http://localhost:3002>

#### Transaction Configuration Studio (TCS)
- TCS API: <http://localhost:3010>
- TCS UI: <http://localhost:5173>

#### Transaction Rule Studio (TRS)
- TRS API: <http://localhost:3005>
- TRS UI: <http://localhost:5174>

#### Case Management System (CMS)
- CMS API: <http://localhost:3090>
- CMS UI: <http://localhost:5175>

#### Infrastructure
- OpenSearch: <http://localhost:9200>
- CouchDB: <http://localhost:5984>
- Flowable: <http://localhost:8081>
- SFTP: `sftp://localhost:12222` (user: `user`, password: `password`)
- PostgreSQL (extensions): `localhost:15433`
- pgAdmin (optional): <http://localhost:5051>

<div style="text-align: right"><a href="#top">Top</a></div>

# 7. TROUBLESHOOTING TIPS

### TCS or TRS show authentication errors

TCS and TRS validate JWTs using the public key mounted from `./auth/test-public-key.pem`. If this file does not exist, the services will reject all authenticated requests. The launcher script copies the key from `../core/auth/test-public-key.pem` automatically, but if the copy failed (e.g. core was not yet cloned), copy it manually:

```
copy ..\core\auth\test-public-key.pem .\auth\test-public-key.pem
```

### CMS backend fails to start

The CMS backend depends on `migrate`, `flowable`, and `opensearch-node1`. OpenSearch takes up to 60 seconds to become healthy on a cold start. If the CMS backend exits immediately, wait for OpenSearch to finish initialising and then re-run the compose command, or restart the container:

```
docker restart tazama-cms-backend
```

### DEMS/DEAPI pre-flight fails with "tazama-core is not running"

Ensure you have started the core stack on this machine first using `tazama-core.bat` (or `.sh`) from the `core/` folder. The pre-flight launcher checks for a running `tazama-core` Compose project before deploying.

### OpenSearch container exits at startup

OpenSearch requires `vm.max_map_count` to be at least 262144. On Linux/WSL:
```bash
sudo sysctl -w vm.max_map_count=262144
```

To persist across reboots, add `vm.max_map_count=262144` to `/etc/sysctl.conf`.

<div style="text-align: right"><a href="#top">Top</a></div>

# 8. APPENDIX

## 8.1. Authentication public key

TCS and TRS validate incoming JWT tokens using an RSA public key. The key pair is generated by the Tazama Authentication Service and lives in `core/auth/`. The extensions launcher automatically copies the public key to `extensions/auth/test-public-key.pem` when deploying the Server B extensions stack.

If you are deploying on separate machines (Server A and Server B), you must manually copy the file from Server A to Server B before starting the extensions stack:

```
scp <server-a>:/<path>/full-stack-docker-tazama/core/auth/test-public-key.pem \
    ./<path>/full-stack-docker-tazama/extensions/auth/test-public-key.pem
```

In the AWS deployment, the deploy scripts handle this step automatically -- see [infra/aws/aws-deployment-instructions.md](../infra/aws/aws-deployment-instructions.md) Section D.3.

<div style="text-align: right"><a href="#top">Top</a></div>

## 8.2. Docker Compose YAML structure

View this file for additional detail about the Docker Compose files in this stack and how they relate to each other: [Docker Compose YAML Structure Overview](./docker-yaml-structure.md)

<div style="text-align: right"><a href="#top">Top</a></div>
