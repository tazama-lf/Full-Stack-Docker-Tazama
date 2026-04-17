# BIAR Merge Analysis: `feat-paysys-e2e` → `tazama/feat/mono-repo-phased-deployment`

## Executive Summary

This document is a blue-team / red-team analysis of the diff between the `feat-paysys-e2e` branch (source) and the `tazama/feat/mono-repo-phased-deployment` branch (target), with a view to merging the source into the target. The source branch adds concrete BIAR component implementations intended to integrate with the existing Tazama stack and to support AWS Server C deployment.

**Commit delta:** 2 commits in source that are not in target (`6fb1e7e`, `7ec1b01`). The target branch is 25 commits ahead of the source, so this is a targeted cherry-pick/merge of BIAR-specific changes only.

---

## 1. Summary of Changes

### Files Added (all new — source only)
| File | Description |
|---|---|
| `biar/automation-orchestrator/Dockerfile` | Custom Python 3.9 image with Java 11 (Temurin), Spark 3.4.2, Hudi, Hadoop-AWS JARs |
| `biar/automation-orchestrator/automation_orchestrator_api.py` | FastAPI service (`/checksubmit`, `/health`) that receives NiFi events and dispatches ETL jobs |
| `biar/automation-orchestrator/lakehouse_automation_pipeline.py` | ~4,900-line PySpark ETL pipeline (Bronze/Silver/Gold layers for alerts, cases, tasks, pacs008/002, network maps, rules, typologies, accounts, views) |
| `biar/datalakehouse-api/Dockerfile` | Python 3.9 + OpenJDK 17 + Spark 3.4.2 + Hudi image |
| `biar/datalakehouse-api/lakehouse_query_api.py` | FastAPI query service (reads Hudi warehouse via Spark, exposes REST endpoints) |
| `biar/datalakehouse-api/requirements.txt` | `fastapi`, `uvicorn[standard]`, `pyspark==3.4.2`, `findspark`, `pydantic` |
| `biar/docker-compose.base.infrastructure.yaml` | Refactored Ozone cluster (3 named datanodes), Tika, Solr, custom NiFi service |
| `biar/docker-compose.dev.biar.yaml` | New Tazama-specific services: `automation-orchestrator` and `datalakehouse-api` |
| `biar/docker-compose.utils.init.yaml` | Init containers: `aws-cli` (S3 bucket bootstrap) and `nifi-init` (parameter context + template import) |
| `biar/docker-config` | Externalised Ozone cluster HDFS/OZONE site XML configuration |
| `biar/env/automation-orchestrator.env` | Env vars for ETL service (S3A endpoint, keys, Spark config) |
| `biar/env/aws-cli.env` | AWS CLI init credentials and endpoint |
| `biar/env/datalakehouse-api.env` | Env vars for query API |
| `biar/env/datanode1.env` / `datanode2.env` / `datanode3.env` | Per-datanode hostnames and bind addresses |
| `biar/env/nifi-init.env` | NiFi init parameters (parameter context names, bucket, HTTP/Ozone endpoints) |
| `biar/env/nifi.env` | NiFi JVM heap, HTTP port, single-user credentials |
| `biar/env/om.env` / `recon.env` / `s3g.env` / `scm.env` / `solr.env` / `tika.env` | Ozone and infrastructure service overrides |
| `biar/nifi/Dockerfile` | NiFi 1.24.0 image + PostgreSQL JDBC 42.7.3 driver |
| `biar/nifi/init.sh` | POSIX shell script: waits for NiFi API, creates/updates parameter context, uploads and instantiates NiFi XML template |
| `biar/nifi/tazama.xml` | NiFi flow template (~1.2 MB XML) for the Tazama BIAR pipeline |

### Files Deleted (target only → removed in source)
| File | Reason |
|---|---|
| `biar/docker-compose.biar.infrastructure.yaml` | Replaced by the split three-file compose structure |

### Files Modified
| File | Nature of Change |
|---|---|
| `biar/tazama-biar.sh` | **Fully rewritten** — 776-line complex launcher replaced by a 105-line focused BIAR launcher with `check_core_reachable()` pre-flight and new compose file references |
| `biar/tazama-biar.bat` | Minor update — compose command updated from single file to three-file stack; label updated to "Deploying BIAR stack…" |
| `extensions/tazama-extensions.sh` | **Partially rewritten** — first 185 lines replaced with a new simpler launcher; old script body remains as dead code (see Critical Bug below) |

---

## 2. Blue-Team Analysis (Defensive / Merge Readiness)

### 2.1 Architecture and Integration

**Positive — Clean decomposition of compose files**
The replacement of the single `docker-compose.biar.infrastructure.yaml` with three layered files is a good architectural decision:
- `base.infrastructure.yaml` — pure infrastructure (Ozone, Tika, Solr, NiFi)
- `dev.biar.yaml` — Tazama application services (ETL pipeline, query API)
- `utils.init.yaml` — one-shot init containers (S3 bucket creation, NiFi parameter/template bootstrap)

This mirrors the layered compose pattern already used in `core/` and `extensions/`, making the structure consistent and composable.

**Positive — Multi-server connectivity pre-check**
`tazama-biar.sh` and `tazama-biar.bat` now perform a pre-flight TCP connectivity check on `SERVER_A_HOST:14222` (NATS) before attempting to deploy. This actively prevents the common failure mode of deploying Server C before Server A is ready. The host is resolved from `.env`, with a `localhost` fallback for single-machine deployments.

**Positive — Ozone cluster maturity**
The source branch upgrades the Ozone cluster from a single-datanode, all-inline-config approach (target) to:
- 3 explicitly named datanodes (`ozone-datanode-1/2/3`) with stable hostnames for intra-cluster Ratis replication
- All Ozone configuration externalised to `docker-config` (a single HDFS/OZONE XML config file shared across all services via `env_file`)
- Tuned replication timeouts and safemode thresholds appropriate for the 3-node layout
- Separate `recon` service dependency on `scm` and `om` (missing in the target)

**Positive — NiFi automation**
The `nifi-init` container provides a reliable, idempotent initialisation flow:
1. Waits for the NiFi API (bounded retries with configurable delay)
2. Creates/updates a parameter context with externalised endpoint values
3. Uploads and instantiates the flow template (with deduplication logic)

Retry counts and delay are configurable via `NIFI_API_WAIT_RETRIES` and `NIFI_API_WAIT_DELAY_SECONDS`, which is good for AWS deployments with variable startup times.

**Positive — ETL pipeline depth**
`lakehouse_automation_pipeline.py` implements a comprehensive Bronze/Silver/Gold medallion architecture covering all core Tazama transaction data types (alerts, cases, tasks, pacs008, pacs002, network maps, typologies, rules, conditions, accounts). View creation for Alert Navigator, Transaction Detail, Transaction History, and Network Navigator are included, which represents the full BIAR analytical layer.

**Positive — Spark session resilience in query API**
`lakehouse_query_api.py` implements a thread-safe singleton Spark session with recovery logic (`_spark._sc._jvm is None` check), warm-up at import time, and thread-pool dispatch for blocking Spark calls. The comment explicitly notes that `nest_asyncio` was removed because it is incompatible with uvicorn's production event loop — this shows deliberate attention to production behaviour.

---

### 2.2 Concerns Requiring Attention Before Merge

#### CRITICAL — Broken `extensions/tazama-extensions.sh`
The file has been corrupted during editing. Lines 1–185 contain a new, correctly-written launcher (new `menu()`, `check_core()`, `pgadmin_prompt()`, `utils()`, helper functions, and the `menu` call at line 185). However, the shell script does not end at line 185. Lines 186–761 are the orphaned tail of the old 776-line script, beginning mid-function:

```bash
# line 185
menu
        deapi_dems="[X]"   ← this is dead code; mid-block from the old apply_configuration()
    fi

    if has_opensearch_required_addons_enabled && ...
```

Because `menu()` in the new code runs an infinite loop and exits cleanly via `quit()→exit 0`, the dead code at lines 186–761 is never reached at runtime. However:
- The file references `print_color`, `RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN` (old colour variables and function) that are **never defined** in the rewritten preamble. Any code path that reaches lines 186+ (e.g., due to future edits, or if a `return`/`break` is added to `menu`) will fail with "command not found".
- The dead code still references the old monolithic compose structure (`-p tazama`, `docker-compose.hub.core.yaml`, etc.) which is incompatible with the new phased deployment model.
- Shell static analysis tools and code reviewers will flag the file as broken.

**Recommendation:** Either (a) delete lines 186–761 (clean the dead code), or (b) keep the full old script and defer the rewrite to a separate PR. The new launcher code at lines 1–185 is functionally complete and correct; only the tail needs removing.

#### HIGH — `docker-compose.hub.extensions.yaml` dropped without updating teardown
The source branch removes `docker-compose.hub.extensions.yaml` from the repository (it is present in the target but absent in the source). However, the `down_extensions()` and `down_all()` functions in the new `extensions/tazama-extensions.sh` still reference `./docker-compose.dev.extensions.yaml` for teardown only — they do not reference the hub variant. If users deployed using hub images and then try to tear down, the composed-down state will be inconsistent.

**Recommendation:** Verify whether `docker-compose.hub.extensions.yaml` should be retained in the source branch, or whether `down_extensions()` should use both dev and hub files (or a common teardown list).

#### HIGH — Hardcoded developer IPs in committed env file
`biar/env/nifi-init.env` contains:
```
PB_HTTP_VALUE=http://10.10.80.20:7619/checksubmit
PB_OZONE_ENDPOINT=http://10.10.80.19:9878
```
These are private IP addresses from the developer's AWS test environment. When other operators deploy from this branch, NiFi's parameter context will point to an address that does not exist in their environment. The first deployment will silently succeed (NiFi accepts the parameter), but the flow will fail to connect.

**Recommendation:** Replace these with template variable references or with localhost/service-name defaults (e.g. `http://localhost:7619/checksubmit` and `http://s3g:9878`). Operators deploying on AWS should override from `.env` or CI secrets.

#### MEDIUM — Hardcoded developer credentials as code-default fallbacks
`biar/automation-orchestrator/lakehouse_automation_pipeline.py`, lines 43–44:
```python
s3_access_key = _env("S3A_ACCESS_KEY", "hassan")
s3_secret_key = _env("S3A_SECRET_KEY", "hassan")
```
And line 42:
```python
s3_endpoint = _env("S3A_ENDPOINT", "http://10.10.80.20:9878")
```
These defaults include a developer's personal name as credentials and a private IP. If the env var is not set, Spark will attempt to connect to the developer's machine. These defaults should be changed to empty strings (failing loudly) or to the `s3g` Docker network service name.

Similarly, `run_full_etl()` contains hardcoded test defaults:
```python
bucket = "marcel"
table = "alerts"
object_key = "2026-04-02T13:31:25.161Z.json"
```
These developer test values will be executed if `run_full_etl` is called without arguments from the API. They should raise a `ValueError` instead.

#### MEDIUM — NiFi default password committed
`biar/env/nifi.env`:
```
SINGLE_USER_CREDENTIALS_PASSWORD=admin123456789
```
NiFi is configured in single-user mode with a predictable password. For development this is acceptable, but this file will be committed to the repository and pulled by anyone deploying the stack. NiFi's web UI will be reachable on the configured port.

**Recommendation:** Document in README that this password must be changed before production deployment. Consider replacing with a placeholder like `REPLACE_ME_admin_password` that fails obviously if not overridden.

#### MEDIUM — `chmod -R 777 /app` in automation-orchestrator Dockerfile
```dockerfile
RUN chmod -R 777 /app
```
This grants world-writable permissions on all application code inside the container. An attacker who achieves code execution in the container can modify the ETL pipeline source without elevated privileges. The `out/` subdirectory (where request metadata is written) likely needs write permissions for the running user, but the entire `/app` directory does not.

**Recommendation:** Set specific permissions: `RUN chown -R nobody:nogroup /app/out && chmod 755 /app && chmod 777 /app/out` (or use a dedicated non-root user).

#### MEDIUM — No authentication on new API endpoints
`automation_orchestrator_api.py` exposes `POST /checksubmit` and `GET /health` with no authentication. `lakehouse_query_api.py` likewise exposes query endpoints with no auth. These services are configured to bind on `0.0.0.0` (all interfaces).

On AWS Server C, if the security group allows inbound access on ports 7619 and 8282 from outside the VPC, any caller can trigger ETL jobs or query the data warehouse. The NiFi-to-orchestrator flow assumes NiFi is the only caller, but there is nothing enforcing this.

**Recommendation:** Add a shared secret or API key check (even a simple header check from an env var) to `/checksubmit`. At minimum, bind the services to the internal Docker network interface only and not expose the ports publicly in the AWS security group.

#### LOW — No `.env.example` for new BIAR variables
The `docker-compose.dev.biar.yaml` references `${AUTOMATION_ORCHESTRATOR_PORT}`, `${DATALAKEHOUSE_API_PORT}`, and `${TAZAMA_WAREHOUSE_HOST_PATH}` from `.env`. None of these appear in an `.env.example` or in the README. A new operator will get a Docker Compose validation error without obvious guidance on what to set.

**Recommendation:** Add these to the existing `.env.example` (or create one in `biar/`) with sensible defaults:
```
AUTOMATION_ORCHESTRATOR_PORT=7619
DATALAKEHOUSE_API_PORT=8282
TAZAMA_WAREHOUSE_HOST_PATH=/opt/Tazama_Warehouse
```

#### LOW — Automation-orchestrator Dockerfile uses single-stage build with all build tools retained
The `automation-orchestrator/Dockerfile` downloads and installs Temurin JDK 11, Spark 3.4.2, and three large JARs in the runtime image (total image size will be >2 GB). A multi-stage build would reduce the final image size and attack surface by keeping only the runtime artefacts.

#### LOW — `from pyspark.sql.types import *` wildcard import
`lakehouse_automation_pipeline.py` line 6 uses `from pyspark.sql.types import *`. Wildcard imports in Python obscure the namespace and can create subtle bugs when PySpark adds new names. This should be replaced with explicit imports.

#### LOW — Ozone `docker-config` contains no sensitive values but lacks a `.gitignore` note
`biar/docker-config` contains only Ozone XML configuration keys with no secrets. However, operators may extend this file with access keys or tokens. A comment in the file and/or a `.gitignore` pattern for `biar/docker-config.local` would help.

---

## 3. Red-Team Analysis (Attack Surface Assessment)

### 3.1 Threat Model

The BIAR stack (Server C) sits downstream of Server A (Tazama core) and Server B (extensions). It processes data written to Ozone by Server A and exposes analytical query APIs. The primary threat vectors are:

1. **Inbound: malicious NiFi trigger payloads** — NiFi calls `POST /checksubmit` with `raw_path`, `bucket`, `table`, `object_key`
2. **Inbound: unauthenticated API access** — Ports 7619 and 8282 are exposed on the host
3. **Internal: Ozone S3 Gateway** — Port 9878 exposes an S3-compatible API with default credentials
4. **Internal: NiFi web UI** — Port 8088 (configurable) with default single-user password
5. **Supply chain: large artefact downloads during Docker build** — Spark, Temurin, Hudi, JDBC JARs from external URLs

### 3.2 Attack Scenarios

#### Scenario 1 — Path traversal via `raw_path`
The `/checksubmit` endpoint accepts `raw_path` as a string and passes it to `run_full_etl()` which constructs `source_path = f"s3a://{bucket}/{table}/{object_key}"` and then calls `spark.read.json(source_path)`. The `raw_path` field itself is also accepted and used as-is in some code paths (see `etl_alerts(spark, WAREHOUSE_ROOT, source_path=str)`).

**Risk:** If an attacker can call `/checksubmit` (no auth), they can supply a path like:
- `s3a://../../` — attempts S3 path traversal within Ozone
- A path pointing to a different bucket or tenant's data
- A `file:///etc/passwd`-style path if Spark's local filesystem access is not restricted

**Likelihood (given no auth):** High. **Likelihood (behind firewall):** Medium.
**Recommendation:** Validate `bucket`, `table`, and `object_key` against an allowlist of known table names and disallow path separators (`/`, `..`) in object key values. Restrict Spark to S3A scheme only.

#### Scenario 2 — ETL job flooding / Denial of Service
The `job_queue` in `automation_orchestrator_api.py` is unbounded. A caller can flood `/checksubmit` with ETL requests, exhausting memory with queued `TriggerRequest` objects and blocking the Spark driver with competing jobs.

**Recommendation:** Set a maximum queue depth (`job_queue = Queue(maxsize=N)`) and return HTTP 429 when the queue is full.

#### Scenario 3 — Ozone S3 Gateway with default credentials
`biar/env/aws-cli.env`:
```
AWS_ACCESS_KEY_ID=tazama
AWS_SECRET_ACCESS_KEY=tazama
```
The `s3g` service exposes port 9878 (S3-compatible API). Any client with network access to this port and knowledge of these credentials can read and write any Ozone bucket, including the Tazama transaction Hudi warehouse. On AWS, if the security group for Server C allows inbound 9878 from the internet (or from Server A's broader VPC CIDR), this is a complete data exfiltration vector.

**Recommendation:** Use AWS Secrets Manager or at minimum a strong randomly-generated credential pair. Restrict port 9878 in the security group to inter-server traffic only (Server A → Server C private subnet).

#### Scenario 4 — NiFi single-user credential brute force
NiFi at `http://<server>:8088` is configured with:
```
SINGLE_USER_CREDENTIALS_USERNAME=admin
SINGLE_USER_CREDENTIALS_PASSWORD=admin123456789
```
NiFi's single-user mode has no lockout policy by default. An attacker with network access to port 8088 can attempt to brute-force or simply guess the password (it is 15 characters but follows a predictable pattern). Control of NiFi gives full control of the data pipeline: the attacker can reroute data to exfiltrate it or modify the flow to inject malicious data.

**Recommendation:** (1) Change the default password before any non-local deployment. (2) Restrict port 8088 to the internal VPC network. (3) Enable TLS on NiFi for AWS deployments.

#### Scenario 5 — Supply chain attack via unpinned Spark download URL
`biar/datalakehouse-api/Dockerfile`:
```dockerfile
RUN curl -fL# "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/..." -o /tmp/spark.tgz
```
The download is from an official Apache mirror but there is no checksum verification. An attacker who can conduct a MITM against `archive.apache.org` (or who compromises the mirror) could substitute a malicious Spark distribution. The same applies to the Hudi JAR downloads from `repo1.maven.org`.

The `automation-orchestrator/Dockerfile` mitigates this partially by using a pinned Temurin release with an explicit tag, but still does not verify checksums for Spark or the three Maven JARs.

**Recommendation:** Add `sha256sum` verification after each `curl` download, using checksums pinned in the Dockerfile.

#### Scenario 6 — NiFi parameter context injection via `nifi-init.env`
The `nifi/init.sh` script constructs JSON payloads by direct string interpolation of environment variables without escaping:
```sh
-d "{\"parameter\":{\"name\":\"$PB_NAME\",\"value\":\"$PB_BUCKET\",\"sensitive\":$PB_SENSITIVE_FALSE}}"
```
If `PB_BUCKET`, `PB_NAME`, or any other env var contains `"` characters or `}`, the constructed JSON will be malformed or could be injected to modify the payload structure.

**Risk (on self-hosted deployment):** Low — values are controlled by the operator via env files. **Risk (in multi-tenant / SaaS context):** High if env vars are ever user-controlled.

**Recommendation:** Use `jq` for JSON construction in the init script to guarantee proper escaping, or at minimum sanitise the env var values before interpolation.

#### Scenario 7 — Dead code in `extensions/tazama-extensions.sh` creates silent failure modes
The ~576 lines of dead code after `menu` at line 185 include functions that reference `docker compose -p tazama` (the monolithic project name) with `--remove-orphans` and `--force-recreate`. If someone runs the script in a bash environment where the `menu()` function fails early (e.g., a non-interactive TTY), the shell will fall through to the dead code section, which calls `deapi_dems="[X]"` as a bare assignment at the top level. In strict mode (`set -e`) this would be a no-op, but subsequent `print_color` calls would fail with "command not found" and exit non-zero.

---

## 4. Merge Readiness Assessment

### 4.1 Conflicts with Target Branch
The target branch (`tazama/feat/mono-repo-phased-deployment`) is 25 commits ahead of the source. The modified files in the source (`biar/tazama-biar.sh`, `biar/tazama-biar.bat`, `extensions/tazama-extensions.sh`) will likely conflict because the target branch also modified these files (the target rewrote them with the same new structure). A merge will require careful conflict resolution:

- `biar/tazama-biar.sh`: Target version is already consistent with the 3-compose-file pattern introduced in source. Likely **no conflict** — the source and target versions appear identical.
- `biar/tazama-biar.bat`: One-line change in compose command — likely **trivial conflict**.
- `extensions/tazama-extensions.sh`: Target has the full refactored version; source has the broken hybrid. This will be a **significant conflict** requiring manual resolution, and the broken dead code in the source version must not be carried into the merge result.

### 4.2 Files in Target Not Present in Source
The following files exist in the target but are absent from the source. They should be **retained** (not overwritten) during merge:
- `biar/README.md` (comprehensive deployment guide)
- `biar/docker-yaml-structure.md`
- `biar/docker-pulls-biar.bat`
- `biar/auth/` (public/private key files for JWT-based auth)
- `extensions/docker-compose.hub.extensions.apis.yaml` (present in target, removed in source — **verify intentionally removed?**)

### 4.3 Net Additions from Source (Safe to Merge)
All files in `biar/automation-orchestrator/`, `biar/datalakehouse-api/`, `biar/nifi/`, `biar/docker-compose.base.infrastructure.yaml`, `biar/docker-compose.dev.biar.yaml`, `biar/docker-compose.utils.init.yaml`, `biar/docker-config`, and all `biar/env/` files are **net-new additions** in the source branch. They do not conflict with anything in the target and can be merged cleanly, subject to the security fixes noted above.

---

## 5. Recommended Pre-Merge Actions

### Blocking (must fix before merge)

1. **Fix `extensions/tazama-extensions.sh`**: Remove lines 186–761 (dead code after the `menu` call). The first 185 lines are the correct new implementation.

2. **Replace hardcoded IPs in `biar/env/nifi-init.env`**: Replace `10.10.80.20` and `10.10.80.19` with `${SERVER_C_HOST}` / `${SERVER_A_HOST}` references, consistent with the pattern used in `automation-orchestrator.env`.

3. **Replace developer name defaults in `lakehouse_automation_pipeline.py`**: Lines 43–44: change `"hassan"` defaults to `""` (raise an error if not set). Line 42: change `"http://10.10.80.20:9878"` default to `"http://s3g:9878"` (Docker service name).

4. **Remove hardcoded test defaults in `run_full_etl()`**: Lines 4797–4800 set `bucket = "marcel"` etc. when not provided. Replace with `raise ValueError("raw_path, bucket, table, and object_key are required")`.

### Strongly Recommended (high value, low effort)

5. **Add API key protection to `/checksubmit`**: Read a shared secret from an env var and verify it in a FastAPI dependency. Return HTTP 401 if missing or wrong.

6. **Fix `chmod -R 777 /app`** in `automation-orchestrator/Dockerfile`: Scope to only the `out/` directory or use a non-root user.

7. **Add `.env.example` in `biar/`** with all required variables documented.

8. **Add checksum verification** for all `curl` downloads in both Dockerfiles.

9. **Add queue depth limit** to `automation_orchestrator_api.py` to prevent unbounded memory growth.

### Nice-to-Have (lower priority)

10. Replace `from pyspark.sql.types import *` with explicit imports in `lakehouse_automation_pipeline.py`.

11. Consider multi-stage build for `automation-orchestrator/Dockerfile` to reduce image size.

12. Add a note in `biar/env/nifi.env` (as a comment) that the NiFi password must be changed for production.

13. Clarify the status of `docker-compose.hub.extensions.yaml` — is it intentionally removed from the source branch?

---

## 6. Overall Verdict

| Dimension | Assessment |
|---|---|
| **Functional completeness** | ✅ The BIAR stack is substantially complete: Ozone cluster, NiFi with automated init, ETL pipeline, and query API are all implemented. |
| **Integration with existing stack** | ✅ Uses consistent compose-layer pattern; connectivity pre-check confirms Server A dependency; env-file pattern consistent with core/extensions. |
| **AWS Server C readiness** | ⚠️ Structurally ready, but hardcoded IPs and default credentials in committed env files must be resolved first. |
| **Security posture** | ⚠️ Multiple medium/high findings. The unauthenticated API surface and default credentials are the primary risks. |
| **Code quality** | ⚠️ The broken `extensions/tazama-extensions.sh` is a blocking quality issue. The Python ETL code is well-structured but has leftover developer test data. |
| **Merge conflict risk** | ⚠️ Medium — `extensions/tazama-extensions.sh` will need manual conflict resolution; all other file additions are clean. |

**Recommendation:** Address the 4 blocking items, complete the merge, then track the remaining recommendations as follow-up issues.
