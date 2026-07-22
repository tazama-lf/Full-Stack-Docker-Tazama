# Tazama Naming Registry

This is the single source of truth for component names across the Tazama deployment pipeline. Ratified 22 Jul 2026 (Phase 0 of the name alignment plan). Every rename PR references this document.

## 1. Rules

1. **Canonical name = GitHub repo name.** Every downstream layer inherits the repo name verbatim. Monorepo subcomponents use `<repo>-<subcomponent>` (e.g. `connection-studio-frontend`). Images deliberately deployed multiple times use `<function>-<instance>` (e.g. `rule-001`, `relay-service-ef`).
2. **Docker Hub image = canonical name** (`tazamaorg/<canonical-name>`). Exception: `rule-executer` fans out to `rule-NNN` images by design.
3. **Compose service key = canonical name.** No abbreviations.
4. **Container name = canonical name, no suffix.** Every single-instance service sets an explicit `container_name: <canonical-name>`. Only genuinely replicated services keep a real numeric suffix (see whitelist in section 5).
5. **Global uniqueness with symmetric stack prefixes.** Service keys and container names must be unique across core, extensions, and biar. Duplicated infrastructure gets a stack prefix on ALL instances (`core-postgres` / `extensions-postgres`); singleton infrastructure keeps its bare name until a second instance appears.
6. **No network aliases.** Service-key renames and all hostname references are updated atomically in the same commit. Short names survive only as docs shorthand or CLI input sugar.
7. **env file names follow the canonical name** (`env/event-director.env`, not `env/ed.env`).
8. **Compose project names are unchanged** (`tazama-core`, `tazama-extensions`, `tazama-biar`).

## 2. BIAR stack (`-p tazama-biar`) - ALIGNED

### Application services

| Canonical name | Image | Service key | Container | Notes |
|---|---|---|---|---|
| biar-nifi | tazamaorg/biar-nifi | `biar-nifi` | `biar-nifi` | hostname `biar-nifi` |
| biar-automation-orchestrator | tazamaorg/biar-automation-orchestrator | `biar-automation-orchestrator` | `biar-automation-orchestrator` | |
| biar-datalakehouse-api | tazamaorg/biar-datalakehouse-api | `biar-datalakehouse-api` | `biar-datalakehouse-api` | |
| biar-unstructured-pipeline | tazamaorg/biar-unstructured-pipeline | `biar-unstructured-pipeline` | `biar-unstructured-pipeline` | |
| biar-jupyterhub | tazamaorg/biar-jupyterhub | `biar-jupyterhub` | `biar-jupyterhub` | renamed from `biar-jupyterlab` (it runs JupyterHub) |

### Infrastructure and init (third-party images, canonical name = service key)

| Canonical name | Image | Container | Notes |
|---|---|---|---|
| biar-tika | logicalspark/docker-tikaserver | `biar-tika` | |
| biar-solr | solr:9 | `biar-solr` | |
| ozone-scm | apache/ozone | `ozone-scm` | was `ozone-scm-1` (fake `-1`) |
| ozone-om | apache/ozone | `ozone-om` | was `ozone-om-1` (fake `-1`) |
| ozone-datanode-1/2/3 | apache/ozone | `ozone-datanode-1/2/3` | real replicas, suffix kept |
| ozone-recon | apache/ozone | `ozone-recon` | was `ozone-recon-1`; hostname `ozone-recon` |
| ozone-s3g | apache/ozone | `ozone-s3g` | was `ozone-s3g-1`; S3A endpoint is `http://ozone-s3g:9878` |
| ozone-aws-cli | amazon/aws-cli | `ozone-aws-cli` | init container; ozone- prefix because it operates on the Ozone cluster |
| biar-nifi-init | curlimages/curl | `biar-nifi-init` | init container; was service key `nifi-init` |

### BIAR env files

`env/biar-nifi.env`, `env/biar-automation-orchestrator.env`, `env/biar-datalakehouse-api.env`, `env/biar-unstructured-pipeline.env`, `env/biar-jupyterhub.env`, `env/biar-tika.env`, `env/ozone-docker-config` (shared Ozone cluster config, not per-service).

## 3. Core stack (`-p tazama-core`) - target, lands with the core Phase 1 PR

| Canonical name | Old service key | Old container | Notes |
|---|---|---|---|
| tms-service | `tms` | tazama-core-tms-1 | |
| admin-service | `admin-service` | tazama-core-admin-service-1 | |
| event-director | `ed` | tazama-core-ed-1 | |
| typology-processor | `tp` | tazama-core-tp-1 | |
| event-flow | `ef` | tazama-core-ef-1 | |
| event-adjudicator | `event-adjudicator` | tazama-core-event-adjudicator-1 | |
| rule-NNN | `rule-NNN` | tazama-core-rule-NNN-1 | one `rule-executer` repo fans out to per-rule images by design |
| relay-service-ef | `rsef` | tazama-core-rsef-1 | image `relay-service-integration-nats`; suffix codes below |
| relay-service-tp | `rstp` | tazama-core-rstp-1 | |
| relay-service-ea | `rsea` | tazama-core-rsea-1 | |
| event-sidecar | `event-sidecar` | tazama-core-event-sidecar-1 | |
| lumberjack | `lumberjack` | tazama-core-lumberjack-1 | |
| auth-service | `auth-service` | tazama-core-auth-service-1 | |
| batch-ppa | `batch-ppa` | tazama-core-batch-ppa-1 | |
| tazama-demo | `tazama-demo` | tazama-core-tazama-demo-1 | double prefix disappears with rule 4 |
| nats-utilities | `nats-utilities` | tazama-core-nats-utilities-1 | |
| core-postgres | `postgres` | tazama-core-postgres-1 | stack prefix per rule 5 |
| core-pgadmin | `pgadmin` | tazama-core-pgadmin-1 | stack prefix per rule 5 |
| nats | `nats` | tazama-core-nats-1 | singleton, bare name |
| valkey | `valkey` | tazama-core-valkey-1 | singleton, bare name |

Relay suffix codes: `ef` = event-flow, `tp` = typology-processor, `ea` = event-adjudicator. The relay is one image (`tazamaorg/relay-service-integration-nats`) deployed once per routed source; the short codes match the relay's frozen runtime identity (`FUNCTION_NAME=relay-service-ef`, `APM_SERVICE_NAME`, NATS stream names `relay-service-nats-ef` etc.). Multitenant relay variants follow the same pattern and are finalized in the core Phase 1 PR.

## 4. Extensions stack (`-p tazama-extensions`) - target, lands with the extensions Phase 1 PR

| Canonical name | Old service key | Old container | Notes |
|---|---|---|---|
| connection-studio-backend | `connection-studio-backend` | tcs-backend | |
| connection-studio-frontend | `connection-studio-frontend` | tcs-frontend | |
| rule-studio-backend | `trs-backend` | trs-backend | image already `rule-studio-backend` |
| rule-studio-frontend | `trs-frontend` | trs-frontend | |
| case-management-system-backend | `cms-backend` | tazama-cms-backend | |
| case-management-system-frontend | `cms-frontend` | tazama-cms-frontend | |
| case-management-system-voila | `voila` | tazama-cms-voila | |
| case-management-system-migrate | `migrate` | cms-migrations | |
| event-monitoring-service | `dems` | tazama-dems-1 | fake `-1` removed; deploys under `-p tazama-core` from extensions/ |
| data-enrichment-service | `deapi` | tazama-deapi-1 | fake `-1` removed; deploys under `-p tazama-core` from extensions/ |
| extensions-postgres | `postgres` | tazama-extensions-postgres-1 | stack prefix per rule 5; volume key `postgres_data` unchanged |
| extensions-pgadmin | `pgadmin` | tazama-extensions-pgadmin-1 | stack prefix per rule 5 |
| keycloak | `keycloak` | tazama-extensions-keycloak-1 | singleton, bare name |
| couchdb | `couchdb` | tazama-extensions-couchdb-1 | singleton, bare name |
| flowable | `flowable` | tazama-extensions-flowable-1 | singleton, bare name |

## 5. Replica whitelist

Containers allowed a trailing `-<digit>`: `ozone-datanode-1`, `ozone-datanode-2`, `ozone-datanode-3`. Everything else must have a suffix-free `container_name`.

## 6. Shorthand table (docs and CLI sugar only)

Never used as service keys, container names, or DNS names.

| Shorthand | Canonical |
|---|---|
| tms | tms-service |
| ed | event-director |
| tp | typology-processor |
| ef | event-flow |
| ea | event-adjudicator |
| dems | event-monitoring-service |
| deapi | data-enrichment-service |
| tcs | connection-studio |
| trs | rule-studio |
| cms | case-management-system |
