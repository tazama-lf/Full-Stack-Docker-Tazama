#!/bin/bash
# Tazama EC2 bootstrap - Amazon Linux 2023
# Rendered by OpenTofu from bootstrap.sh.tpl. DO NOT EDIT THE RENDERED COPY.
#
# Template variables (substituted by OpenTofu):
#   ${region}  - AWS region (e.g. ap-south-1)
#
# Bash variables use $${VAR} in the template so OpenTofu leaves them alone;
# they appear as $${VAR} in the rendered script.

set -euo pipefail
exec > >(tee /var/log/tazama-bootstrap.log | logger -t tazama-bootstrap) 2>&1

REGION="${region}"
REPO_URL="https://github.com/tazama-lf/full-stack-docker-tazama.git"
REPO_BRANCH="${repo_branch}"
REPO_DIR="/home/ec2-user/full-stack-docker-tazama"
EC2_USER="ec2-user"

echo "[bootstrap] Starting - $(date)"

# ── Docker CE ────────────────────────────────────────────────────────────────
echo "[bootstrap] Installing Docker CE..."
dnf install -y docker git
systemctl enable --now docker
usermod -aG docker "$EC2_USER"
echo "[bootstrap] Docker $(docker --version) installed"

# ── Docker Compose v2 plugin ─────────────────────────────────────────────────
echo "[bootstrap] Installing Docker Compose plugin..."
COMPOSE_VER=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
  | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)".*/\1/')
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL \
  "https://github.com/docker/compose/releases/download/$${COMPOSE_VER}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
echo "[bootstrap] Docker Compose $${COMPOSE_VER} installed"

# ── Docker Buildx plugin ─────────────────────────────────────────────────────
echo "[bootstrap] Installing Docker Buildx plugin..."
BUILDX_VER=$(curl -fsSL https://api.github.com/repos/docker/buildx/releases/latest \
  | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)".*/\1/')
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL \
  "https://github.com/docker/buildx/releases/download/$${BUILDX_VER}/buildx-$${BUILDX_VER}.linux-amd64" \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
echo "[bootstrap] Docker Buildx $${BUILDX_VER} installed"

# ── Clone repo ───────────────────────────────────────────────────────────────
echo "[bootstrap] Cloning repo (branch: $${REPO_BRANCH})..."
git clone --branch "$${REPO_BRANCH}" "$REPO_URL" "$REPO_DIR"
chown -R "$EC2_USER:$EC2_USER" "$REPO_DIR"
echo "[bootstrap] Repo cloned to $REPO_DIR"

# ── Fetch GH_TOKEN from SSM and authenticate with ghcr.io ────────────────────
# The EC2 instance profile (AmazonSSMReadOnlyAccess) authorises this call.
# The token is used only to authenticate Docker with ghcr.io. It is NOT
# written to /etc/environment or any .env file — credentials are stored in
# the Docker credential store (~/.docker/config.json) instead.
echo "[bootstrap] Fetching GH_TOKEN from SSM..."
GH_TOKEN=$(aws ssm get-parameter \
  --name /tazama/gh_token \
  --with-decryption \
  --region "$REGION" \
  --query Parameter.Value \
  --output text)

# Log in as root and copy the credential store to ec2-user so deploy scripts
# running as ec2-user can pull images without re-authenticating.
echo "$${GH_TOKEN}" | docker login ghcr.io -u tazama-ci --password-stdin
mkdir -p /home/ec2-user/.docker
cp /root/.docker/config.json /home/ec2-user/.docker/config.json
chown -R "$EC2_USER:$EC2_USER" /home/ec2-user/.docker
echo "[bootstrap] ghcr.io login complete"

# ── Bootstrap complete marker ─────────────────────────────────────────────────
touch /home/ec2-user/.bootstrap-complete
echo "[bootstrap] Done - $(date)"
