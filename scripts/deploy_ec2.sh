#!/usr/bin/env bash
set -Eeuo pipefail

ARTIFACT_PATH="${1:?Usage: deploy_ec2.sh ARTIFACT COMMIT ENVIRONMENT APP_PORT HEALTHCHECK_PATH}"
COMMIT_SHA="${2:?Missing commit SHA}"
ENVIRONMENT="${3:?Missing environment}"
APP_PORT="${4:?Missing app port}"
HEALTHCHECK_PATH="${5:?Missing health check path}"

if [[ ! "$COMMIT_SHA" =~ ^[a-f0-9]{7,40}$ ]]; then
  echo "Invalid commit SHA" >&2
  exit 2
fi
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
  echo "Invalid environment" >&2
  exit 2
fi
if [[ ! "$APP_PORT" =~ ^[0-9]{1,5}$ ]] || (( APP_PORT < 1 || APP_PORT > 65535 )); then
  echo "Invalid application port" >&2
  exit 2
fi
if [[ "$HEALTHCHECK_PATH" =~ ^/[A-Za-z0-9/_-]*$ ]] ]]; then
  echo "Health check path must start with / and contain no spaces" >&2
  exit 2
fi

APP_ROOT="/opt/github-actions-cicd/$ENVIRONMENT"
RELEASE_DIR="$APP_ROOT/releases/$COMMIT_SHA"
SERVICE_NAME="github-actions-cicd-$ENVIRONMENT"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
SERVICE_USER="${SUDO_USER:-$USER}"
SERVICE_GROUP="$(id -gn "$SERVICE_USER")"
CURRENT_LINK="$APP_ROOT/current"
PREVIOUS_RELEASE="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "Artifact not found: $ARTIFACT_PATH" >&2
  exit 2
fi

sudo apt-get update -y
sudo apt-get install -y python3 curl tar

sudo mkdir -p "$RELEASE_DIR"
sudo tar -xzf "$ARTIFACT_PATH" -C "$RELEASE_DIR"
sudo test -f "$RELEASE_DIR/app.py"

sudo tee "$SERVICE_FILE" >/dev/null <<UNIT
[Unit]
Description=GitHub Actions CI/CD demo ($ENVIRONMENT)
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$CURRENT_LINK
ExecStart=/usr/bin/python3 $CURRENT_LINK/app.py --host 0.0.0.0 --port $APP_PORT
Restart=always
RestartSec=3
Environment=APP_ENV=$ENVIRONMENT

[Install]
WantedBy=multi-user.target
UNIT

sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$APP_ROOT"
sudo ln -sfn "$RELEASE_DIR" "$APP_ROOT/current.next"
sudo mv -Tf "$APP_ROOT/current.next" "$CURRENT_LINK"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

HEALTH_URL="http://127.0.0.1:$APP_PORT$HEALTHCHECK_PATH"
for attempt in $(seq 1 15); do
  if curl --fail --silent "$HEALTH_URL" >/dev/null; then
    echo "Deployment healthy: $ENVIRONMENT ($COMMIT_SHA)"
    exit 0
  fi
  sleep 2
done

echo "Health check failed; attempting rollback" >&2
if [[ -n "$PREVIOUS_RELEASE" && -d "$PREVIOUS_RELEASE" ]]; then
  sudo ln -sfn "$PREVIOUS_RELEASE" "$APP_ROOT/current.rollback"
  sudo mv -Tf "$APP_ROOT/current.rollback" "$CURRENT_LINK"
  sudo systemctl restart "$SERVICE_NAME" || true
else
  sudo systemctl stop "$SERVICE_NAME" || true
  sudo rm -f "$CURRENT_LINK"
fi
exit 1
