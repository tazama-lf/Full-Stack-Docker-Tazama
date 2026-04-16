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

# Public URLs for browser-facing VITE_ variables
# (services without an ALB subdomain are left as private-DNS fallbacks until
#  additional ALB entries are added: SANDBOX_API_URL, NATS_API_URL, DEMS_ENDPOINT, ADMIN_ENDPOINT)
TRS_API_URL=https://trs-api.beta.tazama.org
TCS_API_URL=https://tcs-api.beta.tazama.org
CMS_API_URL=https://cms-api.beta.tazama.org
SIMULATION_ENDPOINT=https://tms.beta.tazama.org/v1/evaluate/iso20022/pacs.002.001.12

# CORS — allow browser origins from the public subdomains
# Overrides the private-DNS SERVER_B_HOST fallback in env/trs.env and env/tcs.env
ALLOWED_ORIGINS=https://trs.beta.tazama.org
CORS_ORIGINS=https://tcs.beta.tazama.org,https://cms.beta.tazama.org
