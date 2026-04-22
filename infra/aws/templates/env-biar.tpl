# tazama-biar .env overlay
# ─────────────────────────────────────────────────────────────────────────────
# Applied by deploy-biar.ps1 at deploy time via sed.
# Each key=value line here replaces the matching line in biar/.env on
# Server C, overriding the local-dev defaults with the AWS private DNS names.
#
# Format: KEY=VALUE  (one per line, no spaces around =)
# ─────────────────────────────────────────────────────────────────────────────

SERVER_A_HOST=core.tazama.internal
SERVER_B_HOST=extensions.tazama.internal
SERVER_C_HOST=biar.tazama.internal

# Ozone S3G endpoint — Docker service name so all containers in tazama-biar use
# the Docker bridge network.  biar/.env ships ${SERVER_C_HOST}:9878 which Docker
# Compose interpolates to the EC2 hostname; port 9878 has no SG inbound rule.
# This overlay entry ensures the correct value even if biar/.env is stale.
S3A_ENDPOINT=http://s3g:9878
