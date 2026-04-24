<!-- SPDX-License-Identifier: Apache-2.0 -->

<a id="top"></a>

<h1></h1>
<h1 style="color: red;">WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.</h1>

- [1. INTRODUCTION](#1-introduction)
- [2. REPOSITORY STRUCTURE](#2-repository-structure)
- [3. STACK OVERVIEW](#3-stack-overview)
  - [3.1. Core (`core/`)](#31-core-core)
  - [3.2. Extensions (`extensions/`)](#32-extensions-extensions)
  - [3.3. BIAR (`biar/`)](#33-biar-biar)
- [4. DEPLOYMENT OPTIONS](#4-deployment-options)
  - [4.1. Local single-machine deployment](#41-local-single-machine-deployment)
  - [4.2. AWS multi-server deployment](#42-aws-multi-server-deployment)
- [5. PRE-REQUISITES](#5-pre-requisites)
- [6. QUICK START (LOCAL)](#6-quick-start-local)

<h1></h1>
<h1 style="color: red;">WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.</h1>

For production deployment instructions:
 - [On-Premise Detailed Installation Guide](https://github.com/tazama-lf/On-Prem-helm)
 - [AWS Detailed Installation Guide](https://github.com/tazama-lf/EKS-helm)
 - [Google Cloud Detailed Installation Guide](https://github.com/tazama-lf/GKE-helm)
 - [Azure Detailed Installation Guide](https://github.com/tazama-lf/AKS-helm)

# 1. INTRODUCTION

This repository contains the full Tazama stack as a set of composable Docker Compose configurations. It is intended for local development, exploration, testing, and sandbox deployments. It is **not** a production deployment.

The stack is divided into three independent sub-folders, each with its own README, launcher scripts, and Docker Compose files:

| Folder | Stack | Deployed to |
|---|---|---|
| [`core/`](core/README.md) | Core transaction processing pipeline | Server A |
| [`extensions/`](extensions/README.md) | Studios and Case Management System | Server B (APIs on Server A) |
| [`biar/`](biar/README.md) | Business Intelligence, Analytics, and Reporting | Server C |

Each stack can be deployed independently on the same machine for local development, or on separate servers for a closer-to-production sandbox on AWS.

<div style="text-align: right"><a href="#top">Top</a></div>

# 2. REPOSITORY STRUCTURE

```
full-stack-docker-tazama/
|-- core/               Core stack -- TMS, processors, rules, Keycloak, PostgreSQL, NATS, Valkey
|-- extensions/         Extensions stack -- TCS, TRS, CMS, OpenSearch, SFTP, CouchDB, Flowable
|-- biar/               BIAR stack -- NiFi, Ozone, Solr, Tika
|-- infra/
|   |-- aws/            AWS OpenTofu infrastructure and deploy scripts
|       |-- aws-deployment-instructions.md    Full AWS deployment guide
|       |-- scripts/    PowerShell deploy scripts (deploy.ps1, deploy-core.ps1, etc.)
|       |-- terraform/  OpenTofu (Terraform) configurations for VPC, EC2, ALB, Route 53
```

<div style="text-align: right"><a href="#top">Top</a></div>

# 3. STACK OVERVIEW

## 3.1. Core (`core/`)

The core stack is the heart of Tazama. It runs the transaction monitoring pipeline and all supporting infrastructure.

**Services:**
- PostgreSQL -- primary database (port 15432)
- NATS -- pub/sub messaging (ports 14222, 16222, 18222)
- Valkey -- in-memory cache (port 16379)
- Transaction Monitoring Service (TMS) API -- port 5000
- Admin Service API -- port 5100
- Event Director, Typology Processor, TADProcesser, rule processors
- Keycloak (Authentication) -- port 8080
- Authentication Service API -- port 3020
- NATS Utilities (REST proxy) -- port 4000
- pgAdmin (optional) -- port 15050
- Hasura GraphQL (optional) -- port 6100
- Lumberjack logging (optional)
- Demo UI (optional) -- port 3001

**Launcher:** `core/tazama-core.bat` (Windows) / `core/tazama-core.sh` (Unix)

See [core/README.md](core/README.md) for full installation instructions.

## 3.2. Extensions (`extensions/`)

The extensions stack provides the browser-based configuration studios and case management system. It also contributes two API services (DEMS and DEAPI) that are deployed onto the core server and join the `tazama-core` Docker Compose project.

**Server A APIs (joined to core):**
- Data Enrichment API (DEAPI) -- port 3001
- Data Enrichment Monitoring Service (DEMS) -- port 3002

**Server B infrastructure and services:**
- PostgreSQL (extensions) -- port 15433
- SFTP -- port 12222
- CouchDB -- port 5984
- Flowable -- port 8081
- OpenSearch -- port 9200
- Transaction Configuration Studio (TCS) -- API port 3010, UI port 5173
- Transaction Rule Studio (TRS) -- API port 3005, UI port 5174
- Case Management System (CMS) -- API port 3090, UI port 5175
- Voila notebook server -- port 18866
- pgAdmin (optional) -- port 5051

**Launcher:** `extensions/tazama-extensions.bat` (Windows) / `extensions/tazama-extensions.sh` (Unix)

**Pre-requisite:** The core stack must be running before DEMS/DEAPI are deployed.

See [extensions/README.md](extensions/README.md) for full installation instructions.

## 3.3. BIAR (`biar/`)

The BIAR stack provides a data ingestion and reporting pipeline that reads from the PostgreSQL instances on both the core server and the extensions server.

**Services:**
- Apache NiFi (data flow) -- port 8088
- Apache Ozone (object storage) -- S3G port 9878, OM port 9874, Recon port 9888, SCM port 9876
- Apache Solr (search/indexing) -- port 8983
- Apache Tika (document analysis) -- port 9998

**Launcher:** `biar/tazama-biar.bat` (Windows) / `biar/tazama-biar.sh` (Unix)

**Pre-requisite:** The core stack must be running and reachable at `SERVER_A_HOST:14222` before the BIAR stack is started.

See [biar/README.md](biar/README.md) for full installation instructions.

<div style="text-align: right"><a href="#top">Top</a></div>

# 4. DEPLOYMENT OPTIONS

## 4.1. Local single-machine deployment

All three stacks can run on a single machine for local development. The launcher scripts default `SERVER_A_HOST` and `SERVER_B_HOST` to `localhost` or `host.docker.internal` as appropriate. Deploy in order:

1. **Core** -- Start `core/tazama-core.bat` and select a deployment type
2. **Extensions** (optional) -- Run `extensions/tazama-extensions.bat`:
   - First deploy DEMS + DEAPI (pre-flight, options 1 or 2)
   - Then deploy the extensions stack (options 3 or 4)
3. **BIAR** (optional) -- Start `biar/tazama-biar.bat` (option 1)

Each stack is independent. You can run core alone, or core + extensions, or all three. BIAR works best when extensions is also running so that it has CMS data to ingest.

## 4.2. AWS multi-server deployment

For a sandbox environment on AWS that mirrors a closer-to-production topology, the three stacks are deployed to separate EC2 instances across a private VPC:

| Server | Role | Stack |
|---|---|---|
| Server A | Core + DEMS/DEAPI | `core/` + extensions APIs |
| Server B | Extensions | `extensions/` |
| Server C | BIAR | `biar/` |

Infrastructure is provisioned with OpenTofu (Terraform-compatible) from the `infra/aws/` folder. Deployment to the instances is handled by PowerShell scripts that tunnel over AWS EC2 Instance Connect (EICE) -- no SSH keys or open port 22 required.

Full instructions: [infra/aws/aws-deployment-instructions.md](infra/aws/aws-deployment-instructions.md)

<div style="text-align: right"><a href="#top">Top</a></div>

# 5. PRE-REQUISITES

For a local deployment you will need:

- Git
- Code editor (VS Code recommended)
- Docker Desktop for Windows with WSL (or Linux/macOS equivalent)
- GitHub personal access token with `read:packages` permissions (required for core and extensions; not required for biar)

> [!NOTE]
> Set your GitHub personal access token as a Windows environment variable named `GH_TOKEN`, then authenticate Docker:
> ```powershell
> echo $env:GH_TOKEN | docker login ghcr.io -u <your-github-username> --password-stdin
> ```

For the AWS deployment you will additionally need:

- AWS CLI configured with a profile that has the necessary IAM permissions (see the AWS deployment guide)
- OpenTofu (`tofu`) -- <https://opentofu.org/docs/intro/install/>
- PowerShell 7+ (for the deploy scripts)

<div style="text-align: right"><a href="#top">Top</a></div>

# 6. QUICK START (LOCAL)

```powershell
# Clone the repository
git clone https://github.com/tazama-lf/full-stack-docker-tazama -b main
cd full-stack-docker-tazama

# Start Docker Desktop, then deploy the core stack
cd core
.\tazama-core.bat        # choose option 2 (Public DockerHub) for the fastest start

# Optionally deploy the extensions stack (core must be running first)
cd ..\extensions
.\tazama-extensions.bat  # choose option 2 (DEMS+DEAPI, DockerHub), then option 4 (extensions, DockerHub)

# Optionally deploy the BIAR stack (core must be running first)
cd ..\biar
.\tazama-biar.bat        # choose option 1
```

After deploying the core stack, verify it is healthy:
```powershell
curl http://localhost:5000
# Expected: {"status":"UP"}
```

See each stack's README for detailed configuration options, service port listings, and troubleshooting guidance.

<div style="text-align: right"><a href="#top">Top</a></div>
