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

## 3. Core stack (`-p tazama-core`) - ALIGNED

| Canonical name | Old service key | Old container | Notes |
|---|---|---|---|
| tms-service | `tms` | tazama-core-tms-1 | |
| admin-service | `admin-service` | tazama-core-admin-service-1 | |
| event-director | `ed` | tazama-core-ed-1 | |
| typology-processor | `tp` | tazama-core-tp-1 | |
| event-flow | `ef` | tazama-core-ef-1 | |
| event-adjudicator | `event-adjudicator` | tazama-core-event-adjudicator-1 | |
| rule-NNN | `rule-NNN` | tazama-core-rule-NNN-1 | one `rule-executer` repo fans out to per-rule images by design; includes `rule-901`/`rule-902` (own images and env files) |
| relay-service-ef | `rsef` | tazama-core-rsef-1 | image `relay-service-integration-nats`; suffix codes below |
| relay-service-tp | `rstp` | tazama-core-rstp-1 | |
| relay-service-ea | `rsea` | tazama-core-rsea-1 | |
| relay-service-{ef,tp,ea}-tenant-{001,002} | `rsef-tenant-001` etc. | tazama-core-rsef-tenant-001-1 etc. | multitenant relay variants; image `relay-service-integration-nats` |
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
| keycloak | `keycloak` | tazama-core-keycloak-1 | singleton, bare name |
| hasura | `hasura` | tazama-core-hasura-1 | singleton, bare name |
| hasura-init | `hasura-init` | tazama-core-hasura-init-1 | init container |
| elasticsearch | `elasticsearch` | tazama-core-elasticsearch-1 | singleton, bare name |
| kibana | `kibana` | tazama-core-kibana-1 | singleton, bare name |
| apm-server | `apm-server` | apm-server | `container_name` was already pinned |

Relay suffix codes: `ef` = event-flow, `tp` = typology-processor, `ea` = event-adjudicator. The relay is one image (`tazamaorg/relay-service-integration-nats`) deployed once per routed source; the short codes match the relay's frozen runtime identity (`FUNCTION_NAME=relay-service-ef`, `APM_SERVICE_NAME`, NATS stream names `relay-service-nats-ef` etc.). Multitenant relay variants follow the same pattern (`relay-service-ef-tenant-001` etc.).

### Core env files

Renamed to match canonical names: `admin-service.env` (was `admin.env`), `tms-service.env` (was `tms.env`), `event-director.env` (was `ed.env`), `typology-processor.env` (was `tp.env`), `tazama-demo.env` (was `ui.env`), `core-pgadmin.env` (was `pgadmin.env`), `relay-service-nats.env` (was `rs-nats.env`, shared by all NATS relays), `relay-service-rest.env` (was `rs-rest.env`), `relay-service-kafka.env` (was `rs-kafka.env`), `relay-service-rabbitmq.env` (was `rs-rabbitmq.env`).

Kept as-is: `rule-executer.env` (shared base config for all `rule-NNN` services, named after the `rule-executer` repo), plus per-service files already canonical (`event-flow.env`, `event-adjudicator.env`, `rule-901.env`, `rule-902.env`, `batch-ppa.env`, `auth-service.env`, `keycloak.env`, `lumberjack.env`, `nats-utilities.env`).

Deleted: `rs-nats-tp.env` and `rs-nats-ea.env` - superseded by the shared `relay-service-nats.env` plus per-service compose `environment:` overrides (`FUNCTION_NAME`, `CONSUMER_STREAM`, `PRODUCER_STREAM`, `APM_SERVICE_NAME`); they were referenced by no compose file and the tp variant carried a stale `CONSUMER_STREAM=interdiction-service`.

## 4. Extensions stack (`-p tazama-extensions`) - ALIGNED

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
| extensions-pgadmin | `pgadmin` | tazama-extensions-pgadmin-1 | stack prefix per rule 5; image pinned to 9.15.0 and port fallback 5051 to match core hygiene |
| sftp | `sftp` | tazama-sftp-1 | singleton, bare name; fake `-1` removed |
| couchdb | `couchdb` | tazama-cms-couchdb | singleton, bare name |
| flowable | `flowable` | tazama-cms-flowable | singleton, bare name |
| opensearch | `opensearch-node1` | opensearch-node1 | singleton, bare name; fake `node1` removed (node identity is by UUID, `node.name` change is safe) |
| opensearch-init | `opensearch-init` | opensearch-init | |
| opensearch-dashboards | `opensearch-dashboards` | opensearch-dashboards | |

Env files renamed to match: `connection-studio.env`, `rule-studio.env`, `case-management-system.env`, `event-monitoring-service.env`, `data-enrichment-service.env`, `extensions-pgadmin.env`.

Note: `event-monitoring-service.env` and `data-enrichment-service.env` reference `@core-postgres` - that resolves to the **core** postgres (they deploy under `-p tazama-core`).

## 5. Replica whitelist

Containers allowed a trailing `-<digit>`: `ozone-datanode-1`, `ozone-datanode-2`, `ozone-datanode-3`. Canonical names ending in a functional digit code (`rule-901`, `relay-service-ef-tenant-001`) are not suffixes. Everything else must have a suffix-free `container_name`.

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
