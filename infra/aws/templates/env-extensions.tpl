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
