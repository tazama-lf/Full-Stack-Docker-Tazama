#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# reset-tazama.sh
#
# Runs on the EC2 instance via SSM Session Manager.
# Stops all Tazama containers, wipes all Docker volumes (full state reset),
# and restarts the stack with a clean database.
#
# Use this between beta user sessions or to clear accumulated test data.
# The env/tazama-demo.env patch from the initial deploy is preserved - no re-patching needed.
#
# Usage (from SSM session as ec2-user):
#   /opt/tazama/AWS_deployment/reset-tazama.sh
#
# Or remotely without an interactive session:
#   aws ssm send-command \
#     --instance-ids <instance-id> \
#     --document-name "AWS-RunShellScript" \
#     --parameters 'commands=["/opt/tazama/AWS_deployment/reset-tazama.sh 2>&1 | tee /var/log/tazama-reset.log"]' \
#     --region eu-west-1

set -e
cd /opt/tazama

COMPOSE_CMD="docker compose \
    -f docker-compose.base.infrastructure.yaml \
    -f docker-compose.base.override.yaml \
    -f docker-compose.full.cfg.yaml \
    -f docker-compose.hub.core.yaml \
    -f docker-compose.full.rules.yaml \
    -f docker-compose.hub.logs.base.yaml \
    -f docker-compose.utils.hasura.yaml \
    -f docker-compose.utils.pgadmin.yaml \
    -f docker-compose.utils.nats-utils.yaml"

# ---------------------------------------------------------------------------
# 1. Stop and remove all containers and volumes
#    --volumes removes named volumes (Postgres data, NATS streams, Valkey cache)
#    This is a full state wipe - all transaction history and configuration is lost.
# ---------------------------------------------------------------------------
echo "--- Stopping Tazama stack and wiping volumes ---"
eval "$COMPOSE_CMD down --volumes"
echo "All containers stopped and volumes removed."

# ---------------------------------------------------------------------------
# 2. Restart the stack
#    env/tazama-demo.env is already patched from the initial deploy - no re-patching needed.
# ---------------------------------------------------------------------------
echo ""
echo "--- Restarting Tazama stack ---"
eval "$COMPOSE_CMD up -d"

# ---------------------------------------------------------------------------
# 3. Summary
# ---------------------------------------------------------------------------
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/public-ipv4)

echo ""
echo "============================================================"
echo "Tazama stack reset complete. Clean state."
echo ""
echo "  Demo UI:        http://${PUBLIC_IP}:3011"
echo "  TMS API:        http://${PUBLIC_IP}:5000/documentation"
echo "  Admin API:      http://${PUBLIC_IP}:5100/documentation"
echo ""
echo "Allow ~2-3 minutes for all services to reach healthy state."
echo "============================================================"
