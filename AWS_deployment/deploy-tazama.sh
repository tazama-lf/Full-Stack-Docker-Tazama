#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# deploy-tazama.sh
#
# Runs on the EC2 instance via SSM Session Manager (NOT via SSH).
# Pulls Docker images and starts the full Tazama stack.
#
# Prerequisites:
#   - Bootstrap (user data) has completed: check /var/log/tazama-bootstrap.log
#   - GH_TOKEN has been set in /opt/tazama/.env (replace the REPLACE_ME placeholder)
#
# Usage (from SSM session as ec2-user):
#   /opt/tazama/AWS_deployment/deploy-tazama.sh
#
# Or remotely without an interactive session:
#   aws ssm send-command \
#     --instance-ids <instance-id> \
#     --document-name "AWS-RunShellScript" \
#     --parameters 'commands=["/opt/tazama/AWS_deployment/deploy-tazama.sh 2>&1 | tee /var/log/tazama-deploy.log"]' \
#     --region eu-west-1

set -e
cd /opt/tazama

# ---------------------------------------------------------------------------
# 1. Pre-flight checks
# ---------------------------------------------------------------------------
echo "--- Pre-flight checks ---"

if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed. Has the bootstrap script finished?"
    echo "       Check: cat /var/log/tazama-bootstrap.log"
    exit 1
fi

if grep -q "REPLACE_ME" .env; then
    echo "ERROR: GH_TOKEN is not set in /opt/tazama/.env"
    echo "       Edit the file and replace REPLACE_ME with your GitHub personal access token."
    echo "       The token requires 'packages:write' and 'read:org' permissions."
    exit 1
fi

echo "Checks passed."

# ---------------------------------------------------------------------------
# 2. Patch env/ui.env for remote access
#    The default env/ui.env uses localhost URLs which only work on the same
#    machine. We replace them with the instance's public IP so that external
#    users can access the Demo UI.
# ---------------------------------------------------------------------------
echo ""
echo "--- Patching Demo UI environment for remote access ---"

# Use IMDSv2 to fetch the public IP (more secure than IMDSv1)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/public-ipv4)

echo "Instance public IP: $PUBLIC_IP"

# Back up the original env file on first run so we can restore it if needed
if [ ! -f env/ui.env.orig ]; then
    cp env/ui.env env/ui.env.orig
    echo "Original env/ui.env backed up to env/ui.env.orig"
fi

# Always restore from backup before patching (makes this script safe to re-run)
cp env/ui.env.orig env/ui.env

# Replace localhost URLs with the public IP
sed -i "s|http://localhost:3001|http://${PUBLIC_IP}:3001|g" env/ui.env
sed -i "s|http://localhost:5000|http://${PUBLIC_IP}:5000|g" env/ui.env
sed -i "s|http://localhost:5100|http://${PUBLIC_IP}:5100|g" env/ui.env

# Fix the NATS port to use the mapped port from base.override.yaml (14222 not 4222)
# when the Demo UI back-end connects from outside the Docker network.
# Note: since the UI container runs on the same Docker host it uses the internal
# hostname 'nats' and internal port 4222. No change needed here.

echo "env/ui.env patched."

# ---------------------------------------------------------------------------
# 3. Log into GitHub Container Registry (required for tazamaorg images)
# ---------------------------------------------------------------------------
echo ""
echo "--- GitHub Container Registry login ---"
GH_TOKEN_VALUE=$(grep "^GH_TOKEN=" .env | cut -d'=' -f2)
echo "$GH_TOKEN_VALUE" | docker login ghcr.io -u x-token --password-stdin
echo "Logged in to ghcr.io"

# ---------------------------------------------------------------------------
# 4. Pull images before starting (gives a cleaner startup with no race conditions)
# ---------------------------------------------------------------------------
echo ""
echo "--- Pulling Docker images (this may take several minutes) ---"

docker compose \
    -f docker-compose.base.infrastructure.yaml \
    -f docker-compose.base.override.yaml \
    -f docker-compose.full.cfg.yaml \
    -f docker-compose.hub.core.yaml \
    -f docker-compose.full.rules.yaml \
    -f docker-compose.hub.logs.base.yaml \
    -f docker-compose.hub.ui.yaml \
    -f docker-compose.utils.hasura.yaml \
    -f docker-compose.utils.pgadmin.yaml \
    -f docker-compose.utils.nats-utils.yaml \
    pull

# ---------------------------------------------------------------------------
# 5. Start the stack
# ---------------------------------------------------------------------------
echo ""
echo "--- Starting Tazama stack ---"

docker compose \
    -f docker-compose.base.infrastructure.yaml \
    -f docker-compose.base.override.yaml \
    -f docker-compose.full.cfg.yaml \
    -f docker-compose.hub.core.yaml \
    -f docker-compose.full.rules.yaml \
    -f docker-compose.hub.logs.base.yaml \
    -f docker-compose.hub.ui.yaml \
    -f docker-compose.utils.hasura.yaml \
    -f docker-compose.utils.pgadmin.yaml \
    -f docker-compose.utils.nats-utils.yaml \
    up -d

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Tazama stack deployed."
echo ""
echo "  Demo UI:        http://${PUBLIC_IP}:3001"
echo "  TMS API:        http://${PUBLIC_IP}:5000/documentation"
echo "  Admin API:      http://${PUBLIC_IP}:5100/documentation"
echo "  NATS utilities: http://${PUBLIC_IP}:4000"
echo "  Hasura GraphQL: http://${PUBLIC_IP}:6100  (admin access only)"
echo "  pgAdmin:        http://${PUBLIC_IP}:5050  (admin access only)"
echo ""
echo "Allow ~2-3 minutes for all services to reach healthy state."
echo "Monitor container health: docker ps"
echo "Monitor resource usage:   docker stats --no-stream"
echo "============================================================"
