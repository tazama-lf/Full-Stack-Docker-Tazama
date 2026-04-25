# tazama-extensions .env overlay
# ─────────────────────────────────────────────────────────────────────────────
# Applied by deploy-extensions.ps1 at deploy time via sed.
# Each key=value line here replaces the matching line in extensions/.env on
# Server B, overriding the local-dev defaults with the AWS private DNS names.
#
# Format: KEY=VALUE  (one per line, no spaces around =)
# ─────────────────────────────────────────────────────────────────────────────

SERVER_A_HOST=core.tazama.internal
SERVER_B_HOST=extensions.tazama.internal
SERVER_C_HOST=biar.tazama.internal

# Backend service URL: TRS backend (Server B) -> Admin service (Server A)
# trs.env hardcodes port 3100 (container-internal); ADMIN_PORT on Server A is 5100.
# Loading .env after trs.env means this override wins (last env_file entry wins).
ADMIN_SERVICE_URL=http://core.tazama.internal:5100

# Public URLs for browser-facing VITE_ variables
# (SANDBOX_API_URL, NATS_API_URL, DEMS_ENDPOINT still use private-DNS fallbacks
#  until additional ALB entries are added)
TRS_API_URL=https://trs-api.beta.tazama.org
TCS_API_URL=https://tcs-api.beta.tazama.org
CMS_API_URL=https://cms-api.beta.tazama.org
VOILA_URL=https://voila.beta.tazama.org
SIMULATION_ENDPOINT=https://tms.beta.tazama.org/v1/evaluate/iso20022/pacs.002.001.12
ADMIN_ENDPOINT=https://admin.beta.tazama.org

# CORS — allow browser origins from the public subdomains
# Overrides the private-DNS SERVER_B_HOST fallback in env/trs.env and env/tcs.env
ALLOWED_ORIGINS=https://trs.beta.tazama.org
CORS_ORIGINS=https://tcs.beta.tazama.org,https://cms.beta.tazama.org

# Datalakehouse API — Server C private IP + published port
# extensions/env/cms.env ships a dev default (10.10.80.20:8001); this overlay
# replaces it with the correct Server C address for every AWS deployment.
GOLD_LAKEHOUSE_API_URL=http://biar.tazama.internal:8282
