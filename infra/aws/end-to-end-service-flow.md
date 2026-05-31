# End-to-End Service Flow

This document maps all inter-service communication across the three-server Tazama AWS
deployment. Each section below covers a distinct data path or functional area.

| Server | Hostname | Private IP | Stack |
|---|---|---|---|
| Server A | `core.tazama.internal` | `10.0.1.10` | tazama-core |
| Server B | `extensions.tazama.internal` | `10.0.1.20` | tazama-extensions |
| Server C | `biar.tazama.internal` | `10.0.1.30` | tazama-biar |

---

## 1. System Architecture Overview

All three servers sit in a private subnet with no public IPs. User traffic enters via the
Application Load Balancer (public subnet). Operator SSH access uses the EC2 Instance Connect
Endpoint (EICE) — no port 22 exposed to the internet.

```mermaid
flowchart TD
    Client(["Browser / API Client"])
    SFTPc(["SFTP Client"])
    Operator(["Operator / Workstation"])

    subgraph ALBsg["ALB — public subnet"]
        ALB["Application Load Balancer\nPort-based HTTP (Phase E)\nHTTPS :443 (Phase F)"]
    end

    subgraph SA["Server A — core.tazama.internal — 10.0.1.10"]
        TMS["TMS :5000"]
        Admin["Admin API :5100"]
        Auth["Auth Service :3020"]
        KC["Keycloak :8080"]
        DEAPI["DEAPI :3001"]
        DEMS["DEMS :3002"]
        PGA["pgAdmin :5050"]
        Hasura["Hasura :6100"]
        NATS_A[("NATS\n:4222 / ext :14222")]
        PG_A[("PostgreSQL\n:5432 / ext :15432")]
        VK[("Valkey\n:6379 / ext :16379")]
        PIPELINE["NATS Pipeline\nED → Rules → TP / EF / EA"]
        RS["Relay Services\nrsef · rstp · rsea"]
        Logging["Event Sidecar :15000\n+ Lumberjack"]
    end

    subgraph SB["Server B — extensions.tazama.internal — 10.0.1.20"]
        TCSfe["TCS Frontend :5173"]
        TCSbe["TCS Backend :3010"]
        TRSfe["TRS Frontend :5174"]
        TRSbe["TRS Backend :3005"]
        CMSfe["CMS Frontend :5175"]
        CMSbe["CMS Backend :3090"]
        Voila["Voila :18866"]
        PGB["pgAdmin-ext :5051"]
        PG_B[("PostgreSQL\n:5432 / ext :15433")]
        OS[("OpenSearch :9200")]
        CDB[("CouchDB :5984")]
        FLW["Flowable :8080"]
        SFTP["SFTP :12222"]
    end

    subgraph SC["Server C — biar.tazama.internal — 10.0.1.30"]
        NiFi["NiFi :8088"]
        AO["Automation Orchestrator :7619"]
        DLH["Datalakehouse API :8282"]
        JH["JupyterHub :8000"]
        UP["Unstructured Pipeline"]
        Tika["Tika :9998"]
        Solr["Solr :8983 (tunnel only)"]
        Ozone["Ozone Cluster\nS3G :9878 · SCM :9876\nOM :9862 · Recon :9888\nDatanodes ×3"]
    end

    EICE(["EICE Endpoint\n(no port 22 in any SG)"])

    %% ── External ingress ──────────────────────────────────────────────────
    Client -- "HTTP / HTTPS" --> ALB
    SFTPc -- "SFTP :12222" --> SFTP
    Operator -- "SSH via EICE" --> EICE
    EICE -- ":22 (SG only)" --> SA
    EICE -- ":22 (SG only)" --> SB
    EICE -- ":22 (SG only)" --> SC

    %% ── ALB → Server A ───────────────────────────────────────────────────
    ALB -- ":5000" --> TMS
    ALB -- ":5100" --> Admin
    ALB -- ":3020" --> Auth
    ALB -- ":8080" --> KC
    ALB -- ":3001" --> DEAPI
    ALB -- ":3002" --> DEMS
    ALB -- ":5050" --> PGA
    ALB -- ":6100" --> Hasura

    %% ── ALB → Server B ───────────────────────────────────────────────────
    ALB -- ":5173" --> TCSfe
    ALB -- ":3010" --> TCSbe
    ALB -- ":5174" --> TRSfe
    ALB -- ":3005" --> TRSbe
    ALB -- ":5175" --> CMSfe
    ALB -- ":3090" --> CMSbe
    ALB -- ":5051" --> PGB

    %% ── ALB → Server C ───────────────────────────────────────────────────
    ALB -- ":8088" --> NiFi
    ALB -- ":8000" --> JH
    ALB -- ":7619 (listener only)" --> AO
    ALB -- ":8282 (listener only)" --> DLH

    %% ── Server A internal ────────────────────────────────────────────────
    TMS -- "event-director" --> NATS_A
    NATS_A -- "pipeline" --> PIPELINE
    PIPELINE -- "investigation-service" --> NATS_A
    NATS_A -- "relay streams" --> RS
    DEAPI --- NATS_A
    DEMS --- NATS_A
    PIPELINE --- PG_A
    PIPELINE --- VK
    TMS --- PG_A
    TMS --- VK
    DEAPI --- PG_A
    DEAPI --- VK
    DEMS --- PG_A
    DEMS --- VK
    PIPELINE -- "sidecar" --> Logging
    TMS -- "sidecar" --> Logging

    %% ── Server B → Server A (cross-server) ───────────────────────────────
    TCSbe -- "postgres :15432" --> PG_A
    TCSbe -- "NATS :14222" --> NATS_A
    TCSbe -- "auth :3020" --> Auth
    TCSbe -- "keycloak :8080" --> KC
    TCSbe -- "admin :3100" --> Admin
    TRSbe -- "auth :3020" --> Auth
    TRSbe -- "admin :3100" --> Admin
    CMSbe -- "auth :3020" --> Auth
    CMSbe -- "NATS :14222" --> NATS_A
    CMSbe -- "valkey :16379" --> VK

    %% ── Server B internal ────────────────────────────────────────────────
    TCSbe --- OS
    TCSbe --- SFTP
    TRSbe --- OS
    CMSbe --- PG_B
    CMSbe --- OS
    CMSbe --- CDB
    CMSbe --- FLW
    FLW --- PG_B

    %% ── Server B → Server C (direct — bypasses ALB) ──────────────────────
    CMSbe -- "direct :8282" --> DLH

    %% ── Server C → Server A (ETL cross-server) ───────────────────────────
    NiFi -- "postgres ETL :15432" --> PG_A
    NiFi -- "NATS :14222" --> NATS_A

    %% ── Server C → Server B (ETL cross-server) ───────────────────────────
    NiFi -- "postgres ETL :15433" --> PG_B
    NiFi -- "opensearch :9200" --> OS

    %% ── Server C internal ────────────────────────────────────────────────
    NiFi --- Ozone
    AO --- Ozone
    DLH --- Ozone
    JH --- Ozone
    UP --- Tika
    UP --- Solr
    NiFi -- ":7619" --> AO
```

---

## 2. Transaction Processing Pipeline

The core Tazama flow: a financial message is submitted to the TMS, fanned out through the
NATS-based rule evaluation pipeline, decisioned by the Event Adjudicator, and the resulting investigation alert is consumed by the CMS on Server B.

DEAPI and DEMS run inside the `tazama-core` Docker project on **Server A** (launched as a
pre-flight step for extensions) so they share the internal Docker network with NATS, postgres,
and valkey. Their exterior ports (:3001, :3002) allow external callers (Server B frontends
via ALB) to reach them across the network.

```mermaid
sequenceDiagram
    autonumber
    actor Client as Client<br/>(Postman / TCS Frontend)
    participant ALB as ALB
    participant TMS as TMS<br/>Server A :5000
    participant PG_A as PostgreSQL<br/>Server A :5432
    participant VK as Valkey<br/>Server A :6379
    participant NATS as NATS<br/>Server A :4222
    participant ED as Event Director<br/>Server A
    participant Rules as Rule Processors<br/>Server A (901, 902 …)
    participant TP as Typology Processor<br/>Server A
    participant EF as Event Flow<br/>Server A
    participant EA as EA<br/>Server A
    participant RS as Relay Services<br/>Server A (rsef/rstp/rsea)
    participant CMSbe as CMS Backend<br/>Server B :3090
    participant PG_B as PostgreSQL<br/>Server B :5432
    participant OSrch as OpenSearch<br/>Server B :9200
    participant DLH as Datalakehouse API<br/>Server C :8282

    Client->>ALB: POST /v1/evaluate/iso20022/pacs.002.001.12
    ALB->>TMS: forward to :5000
    TMS->>PG_A: write raw transaction (raw_history DB)
    TMS->>NATS: publish → stream: event-director
    TMS-->>ALB: 200 Accepted
    ALB-->>Client: 200 Accepted

    NATS-->>ED: consume ← stream: event-director
    ED->>PG_A: read rule configuration (configuration DB)
    ED->>NATS: publish → per-rule streams (rule-901, rule-902, …)

    par Rule evaluation (parallel, one per active rule)
        NATS-->>Rules: consume ← rule-N stream
        Rules->>PG_A: read rule config + raw/event history
        Rules->>VK: check/update evaluation cache
        Rules->>NATS: publish → stream: typology-processor
    end

    NATS-->>TP: consume ← rule result streams
    TP->>PG_A: read typology configuration
    TP->>VK: aggregate rule results per typology
    TP->>NATS: publish → stream: interdiction-service-tp

    NATS-->>EF: consume ← event-flow rule streams
    EF->>PG_A: read event-flow rule config
    EF->>VK: cache event-flow state
    EF->>NATS: publish → stream: interdiction-service-ef

    NATS-->>RS: rsef consumes ← interdiction-service-ef
    RS->>NATS: republish → relay-service-nats-ef

    NATS-->>RS: rstp consumes ← interdiction-service-tp
    RS->>NATS: republish → relay-service-nats-tp

    NATS-->>EA: consume ← relay-service-nats-tp + relay-service-nats-ef
    EA->>PG_A: read Event Adjudicator config (configuration DB)
    EA->>PG_A: write evaluation result (evaluation DB)
    EA->>NATS: publish → stream: investigation-service (alert)

    NATS-->>RS: rsea consumes ← investigation-service
    RS->>NATS: republish → relay-service-nats-ea

    Note over CMSbe,NATS: CMS Backend (Server B) subscribes to<br/>investigation-service on Server A NATS :14222
    NATS-->>CMSbe: deliver investigation alert (nats://core.tazama.internal:14222)
    CMSbe->>PG_B: store case record (tazama_cms DB)
    CMSbe->>OSrch: index alert (opensearch-node1:9200)

    Note over CMSbe,DLH: CMS analyst opens the case — frontend requests gold lakehouse data
    CMSbe->>DLH: GET /... (direct HTTP :8282, bypasses ALB)
    DLH-->>CMSbe: return structured transaction / analytics data
    CMSbe-->>Client: case detail with enriched data
```

---

## 3. Data Enrichment and Event Monitoring (DEAPI / DEMS)

DEAPI and DEMS are both co-hosted on **Server A** (tazama-core project). They are called by
frontends via the ALB and by the NATS pipeline for enrichment callbacks.

```mermaid
sequenceDiagram
    autonumber
    actor TCSfe as TCS Frontend<br/>Server B :5173
    participant ALB as ALB
    participant DEAPI as DEAPI<br/>Server A :3001
    participant DEMS as DEMS<br/>Server A :3002
    participant PG_A as PostgreSQL<br/>Server A :5432
    participant VK as Valkey<br/>Server A :6379
    participant NATS as NATS<br/>Server A :4222
    participant Sidecar as Event Sidecar<br/>Server A :15000
    participant LJ as Lumberjack<br/>Server A

    Note over TCSfe,DEAPI: Data enrichment request from TCS frontend (via ALB)
    TCSfe->>ALB: GET /enrichment/... (:3001)
    ALB->>DEAPI: forward to Server A :3001
    DEAPI->>PG_A: query enrichment DB
    DEAPI->>VK: check enrichment cache
    DEAPI-->>ALB: enrichment payload
    ALB-->>TCSfe: return enriched data

    Note over DEMS,NATS: DEMS listens on NATS for config change notifications
    NATS-->>DEMS: consume ← stream: config.notification
    DEMS->>PG_A: read updated configuration (configuration DB)
    DEMS->>PG_A: query raw/event history DBs
    DEMS->>VK: update monitoring state
    DEMS->>NATS: publish → stream: dems.notification.response

    Note over DEAPI,NATS: DEAPI listens for enrichment requests over NATS
    NATS-->>DEAPI: consume ← stream: enrichment.notification
    DEAPI->>PG_A: read enrichment DB
    DEAPI->>VK: cache result
    DEAPI->>NATS: publish → stream: enrichment.notification.response

    Note over Sidecar,LJ: All services emit structured logs via sidecar
    DEAPI->>Sidecar: log event (HTTP)
    DEMS->>Sidecar: log event (HTTP)
    Sidecar->>NATS: publish → subject: Lumberjack
    NATS-->>LJ: consume ← Lumberjack
    LJ->>LJ: write to stdout / log sink
```

---

## 4. Tooling Frontend Authentication and API Flows

TCS, TRS, and CMS frontends follow the same auth pattern: the frontend requests a JWT from
the Auth Service (via the TMS auth endpoint or Keycloak), then the backend validates the JWT
locally using the RSA public key.

```mermaid
sequenceDiagram
    autonumber
    actor User as Analyst / User
    participant CMSfe as CMS Frontend<br/>Server B :5175
    participant CMSbe as CMS Backend<br/>Server B :3090
    participant TCSfe as TCS Frontend<br/>Server B :5173
    participant TCSbe as TCS Backend<br/>Server B :3010
    participant TRSfe as TRS Frontend<br/>Server B :5174
    participant TRSbe as TRS Backend<br/>Server B :3005
    participant AuthSvc as Auth Service<br/>Server A :3020
    participant KC as Keycloak<br/>Server A :8080
    participant Admin as Admin API<br/>Server A :5100
    participant PG_A as PostgreSQL<br/>Server A :15432
    participant NATS as NATS<br/>Server A :14222
    participant OS as OpenSearch<br/>Server B :9200
    participant PG_B as PostgreSQL<br/>Server B :15433

    Note over User,KC: Login flow (same for CMS, TCS, TRS)
    User->>CMSfe: navigate to CMS
    CMSfe->>KC: redirect to Keycloak :8080 (OIDC)
    User->>KC: submit credentials
    KC-->>CMSfe: ID token + access token
    CMSfe->>AuthSvc: POST /v1/auth/login (exchange KC token → Tazama JWT)
    AuthSvc->>KC: verify token with Keycloak :8080
    KC-->>AuthSvc: token valid
    AuthSvc-->>CMSfe: Tazama JWT (signed with RSA private key)

    Note over CMSfe,CMSbe: All subsequent API calls carry the JWT
    CMSfe->>CMSbe: GET /api/cases (Bearer JWT)
    CMSbe->>CMSbe: verify JWT (RSA public key on disk)
    CMSbe->>PG_B: query tazama_cms DB
    CMSbe->>OS: search OpenSearch for case records
    CMSbe-->>CMSfe: case list

    Note over TCSfe,PG_A: TCS Backend — reads rule config from Server A postgres
    User->>TCSfe: open Connection Studio
    TCSfe->>TCSbe: GET /api/configurations (Bearer JWT)
    TCSbe->>TCSbe: verify JWT
    TCSbe->>PG_A: read configuration DB (:15432 cross-server)
    TCSbe->>Admin: GET /admin/... (:3100)
    TCSbe->>NATS: publish config change → stream: config.notification (:14222)
    TCSbe-->>TCSfe: configuration data

    Note over TRSfe,Admin: TRS Backend — rule management
    User->>TRSfe: open Rule Studio
    TRSfe->>TRSbe: GET /api/rules (Bearer JWT)
    TRSbe->>TRSbe: verify JWT
    TRSbe->>OS: query OpenSearch rule-studio-audit index
    TRSbe->>Admin: GET /admin/rules (:3100)
    TRSbe-->>TRSfe: rule list
```

---

## 5. BIAR Data Pipeline (NiFi ETL and Analytics)

NiFi orchestrates data movement between Server A's PostgreSQL, Server B's PostgreSQL and
OpenSearch, and the Ozone object store on Server C. The Datalakehouse API exposes the processed
(gold) data to the CMS backend.

```mermaid
sequenceDiagram
    autonumber
    participant NiFi as NiFi<br/>Server C :8088
    participant AO as Automation Orchestrator<br/>Server C :7619
    participant DLH as Datalakehouse API<br/>Server C :8282
    participant JH as JupyterHub<br/>Server C :8000
    participant Ozone as Ozone S3G<br/>Server C :9878
    participant Tika as Tika<br/>Server C :9998
    participant Solr as Solr<br/>Server C :8983
    participant UP as Unstructured Pipeline<br/>Server C
    participant PG_A as PostgreSQL<br/>Server A :15432
    participant PG_B as PostgreSQL<br/>Server B :15433
    participant OS as OpenSearch<br/>Server B :9200
    participant CMSbe as CMS Backend<br/>Server B :3090

    Note over NiFi,PG_A: Scheduled ETL — extract transaction data from Server A
    NiFi->>PG_A: JDBC query (raw_history, event_history, evaluation DBs)
    PG_A-->>NiFi: raw transaction records

    Note over NiFi,PG_B: Extract case/enrichment data from Server B
    NiFi->>PG_B: JDBC query (tazama_cms, tazama_dwh DBs)
    PG_B-->>NiFi: case and enrichment records
    NiFi->>OS: query OpenSearch indices
    OS-->>NiFi: alert / audit records

    Note over NiFi,Ozone: Transform and load into Ozone object store (Hudi tables)
    NiFi->>AO: POST /checksubmit (trigger Spark job)
    AO->>Ozone: write Hudi table partitions (S3A :9878)
    Ozone-->>AO: write confirmed
    AO-->>NiFi: job complete

    Note over NiFi,Ozone: NiFi also writes enriched parquet directly to Ozone
    NiFi->>Ozone: PUT object (S3A :9878)

    Note over UP,Solr: Unstructured document pipeline
    UP->>Tika: extract text from documents (:9998)
    Tika-->>UP: extracted text
    UP->>Solr: index document (:8983)

    Note over DLH,CMSbe: CMS backend reads gold lakehouse data on demand
    CMSbe->>DLH: GET /api/transactions/... (:8282 direct from Server B)
    DLH->>Ozone: read Hudi partition (S3A :9878)
    Ozone-->>DLH: parquet data
    DLH-->>CMSbe: structured gold data (JSON)

    Note over JH,Ozone: Data scientist opens JupyterHub session
    JH->>Ozone: mount Hudi warehouse via S3A (:9878)
    JH->>JH: run PySpark / notebook analysis
```

---

## 6. Cross-Server Connection Reference

All ports listed here traverse the AWS VPC private subnet (`10.0.1.0/24`). They require the
corresponding Security Group ingress rules to be in place.

### Server B → Server A

| Source service | Destination | Port | Protocol | Purpose |
|---|---|---|---|---|
| tcs-backend | PostgreSQL (Server A) | 15432 | TCP/JDBC | Read rule configuration DB |
| tcs-backend | Auth Service | 3020 | TCP/HTTP | JWT validation |
| tcs-backend | NATS | 14222 | TCP/NATS | Publish config.notification |
| tcs-backend | Keycloak | 8080 | TCP/HTTP | OIDC token verification |
| tcs-backend | Admin API | 3100 | TCP/HTTP | Admin operations |
| trs-backend | Auth Service | 3020 | TCP/HTTP | JWT validation |
| trs-backend | Admin API | 3100 | TCP/HTTP | Admin operations |
| cms-backend | Auth Service | 3020 | TCP/HTTP | JWT validation |
| cms-backend | NATS | 14222 | TCP/NATS | Subscribe: investigation-service |
| cms-backend | Valkey | 16379 | TCP/RESP | Redis cache |

### Server B → Server C

| Source service | Destination | Port | Protocol | Purpose |
|---|---|---|---|---|
| cms-backend | Datalakehouse API | 8282 | TCP/HTTP | Gold lakehouse data (direct, not via ALB) |

### Server C → Server A

| Source service | Destination | Port | Protocol | Purpose |
|---|---|---|---|---|
| NiFi | PostgreSQL (Server A) | 15432 | TCP/JDBC | ETL extraction (raw_history, event_history, evaluation) |
| NiFi | NATS | 14222 | TCP/NATS | Pipeline integration |

### Server C → Server B

| Source service | Destination | Port | Protocol | Purpose |
|---|---|---|---|---|
| NiFi | PostgreSQL (Server B) | 15433 | TCP/JDBC | ETL extraction (tazama_cms, tazama_dwh) |
| NiFi | OpenSearch | 9200 | TCP/HTTP | ETL extraction (alert / audit indices) |

### ALB → Servers (per-server, current port-based HTTP routing)

> Ports with `†` have ALB listener target groups configured but the port is **not** currently
> open in the ALB Security Group — those services are accessed via SSH tunnel (Phase E.1).
> They will be opened to the internet when promoted to Phase F subdomain routing.

| Target | Port | Service |
|---|---|---|
| Server A | 5000 | TMS API |
| Server A | 3001 | DEAPI |
| Server A | 3002 | DEMS |
| Server A | 3020 | Auth Service |
| Server A | 5100 | Admin API |
| Server A | 8080 | Keycloak |
| Server A | 5050 | pgAdmin (core) |
| Server A | 6100 | Hasura |
| Server B | 3005 | TRS Backend |
| Server B | 3010 | TCS Backend |
| Server B | 3090 | CMS Backend |
| Server B | 5051 | pgAdmin (extensions) |
| Server B | 5173 | TCS Frontend |
| Server B | 5174 | TRS Frontend |
| Server B | 5175 | CMS Frontend |
| Server C | 8088 | NiFi UI |
| Server C | 8000 `†` | JupyterHub |
| Server C | 7619 `†` | Automation Orchestrator |
| Server C | 8282 `†` | Datalakehouse API |

### Operator-only (SSH tunnel via EICE, no SG inbound rules)

| Server | Port | Service |
|---|---|---|
| Server B | 18866 | Voila (CMS notebook server) |
| Server C | 8983 | Solr UI |
| Server C | 9876 | Ozone SCM |
| Server C | 9878 | Ozone S3G |
| Server C | 9888 | Ozone Recon UI |

---

## 7. NATS Stream Map (Server A)

The full NATS message path through the Server A pipeline for a single transaction evaluation.

```mermaid
flowchart TD
    subgraph Inbound["Inbound"]
        TMS["TMS\n(HTTP entry point)"]
    end

    subgraph Pipeline["NATS Pipeline — Server A internal"]
        direction TB
        ED["Event Director"]
        R901["rule-901"]
        R902["rule-902"]
        Rn["rule-N …"]
        TP["Typology Processor"]
        EF["Event Flow"]
        EA["EA"]
    end

    subgraph Relay["Relay Services"]
        RSEF["rsef\n(relay EF)"]
        RSTP["rstp\n(relay TP)"]
        RSEA["rsea\n(relay EA)"]
    end

    subgraph External["External Consumers (cross-server)"]
        CMSbe["CMS Backend\nServer B :3090\n(NATS :14222)"]
    end

    TMS -- "event-director" --> ED
    ED -- "rule-901" --> R901
    ED -- "rule-902" --> R902
    ED -- "rule-N" --> Rn
    R901 -- "rule result → typology-processor" --> TP
    R902 -- "rule result → typology-processor" --> TP
    Rn -- "rule result → typology-processor" --> TP
    ED -- "event-flow streams" --> EF
    TP -- "interdiction-service-tp" --> RSTP
    EF -- "interdiction-service-ef" --> RSEF
    RSTP -- "relay-service-nats-tp" --> EA
    RSEF -- "relay-service-nats-ef" --> EA
    EA -- "investigation-service" --> RSEA
    EA -- "investigation-service" --> CMSbe
    RSEA -- "relay-service-nats-ea\n(downstream / monitoring)" --> External
```
