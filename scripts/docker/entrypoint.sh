#!/bin/sh

# Copy default logo to the frontend public folder if it doesn't exist
cp -rn /tmp/img/* /opt/app/frontend/public/img

# Compute the internal ports before starting anything, so Caddy's
# {$BACKEND_PORT} and {$FRONTEND_PORT} placeholders resolve to the same
# ports the servers actually bind. Bump them if they collide with the
# platform-assigned public port (PORT), which Caddy binds.
FRONTEND_PORT=3333
[ "$FRONTEND_PORT" = "$PORT" ] && FRONTEND_PORT=$((PORT + 1))
export FRONTEND_PORT

BACKEND_PORT="${BACKEND_PORT:-8080}"
[ "$BACKEND_PORT" = "$PORT" ] && BACKEND_PORT=$((PORT + 1))
export BACKEND_PORT

if [ "$CADDY_DISABLED" != "true" ]; then
  # Start Caddy
  echo "Starting Caddy..."
  if [ "$TRUST_PROXY" = "true" ]; then
    caddy start --adapter caddyfile --config /opt/app/reverse-proxy/Caddyfile.trust-proxy &
  else
    caddy start --adapter caddyfile --config /opt/app/reverse-proxy/Caddyfile &
  fi
else
  echo "Caddy is disabled. Skipping..."
fi

# Run the frontend server
PORT=$FRONTEND_PORT HOSTNAME=0.0.0.0 node frontend/server.js &

# Run the backend server
cd backend

# When the platform provides S3 credentials in the environment (e.g. Freepod),
# generate the config file from those variables. The file is written to the
# (ephemeral) data directory and re-created on every start, so it always
# reflects the current credentials.
if [ -n "$AWS_ENDPOINT_URL_S3" ] && [ -n "$S3_BUCKET" ]; then
  DATA_DIR="${DATA_DIRECTORY:-./data}"
  mkdir -p "$DATA_DIR"
  echo "Generating config from platform environment..."
  cat > "$DATA_DIR/config.yaml" <<EOF
general:
  appUrl: "${PV_APP_URL:-https://files.prutser.freepod.eu}"
security:
  allowRegistration: "${PV_ALLOW_REGISTRATION:-false}"
  allowUnauthenticatedShares: "${PV_ALLOW_UNAUTHENTICATED_SHARES:-false}"
share:
  maxSize: "${PV_MAX_SIZE:-100000000000}"
s3:
  enabled: true
  endpoint: "${AWS_ENDPOINT_URL_S3}"
  region: "${AWS_REGION}"
  bucketName: "${S3_BUCKET}"
  key: "${AWS_ACCESS_KEY_ID}"
  secret: "${AWS_SECRET_ACCESS_KEY}"
  useChecksum: false
EOF
  export CONFIG_FILE="$DATA_DIR/config.yaml"
fi

./node_modules/.bin/prisma migrate deploy && node dist/prisma/seed/config.seed.js && node dist/src/main

# Wait for all processes to finish
wait -n
