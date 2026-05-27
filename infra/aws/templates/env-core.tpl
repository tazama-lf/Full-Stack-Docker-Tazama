# SPDX-License-Identifier: Apache-2.0
# tazama-core .env overlay
# ─────────────────────────────────────────────────────────────────────────────
# Applied by deploy-core.ps1 and restart-service.ps1 (on -RepoPull) after the
# git pull via Set-RemoteEnvOverlay.  Each key=value line replaces the matching
# line in core/.env on Server A, overriding the local-dev defaults with values
# that are specific to the AWS deployment.
#
# Not applied when the ALB / custom domain is not active (guard: $out.KeycloakHostname).

KEYCLOAK_HOSTNAME=keycloak.beta.tazama.org
