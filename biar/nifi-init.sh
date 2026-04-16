#!/bin/sh

set -e

BASE_URL="http://nifi:8088/nifi-api"

echo "⏳ Waiting for NiFi API to be ready..."

# Wait until parameter-context API responds properly
until curl -s "$BASE_URL/flow/parameter-contexts" | grep -q "parameterContexts"; do
  sleep 5
done

echo "✅ NiFi API is ready"

echo "🚀 Creating Parameter Context..."

CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/parameter-contexts" \
  -H "Content-Type: application/json" \
  -d "{
    \"revision\": { \"version\": 0 },
    \"component\": {
      \"name\": \"$PB_CONTEXT_NAME\",
      \"parameters\": [
        {
          \"parameter\": {
            \"name\": \"$PB_NAME\",
            \"value\": \"$PB_BUCKET\",
            \"sensitive\": $PB_SENSITIVE_FALSE
          }
        }
      ]
    }
  }")

HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
BODY=$(echo "$CREATE_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "409" ]; then
  echo "❌ Failed to create Parameter Context"
  echo "$BODY"
  exit 1
fi

echo "✅ Parameter Context created or already exists"

echo "🔍 Fetching Parameter Context ID..."

# Retry until context appears (IMPORTANT)
for i in $(seq 1 10); do
  PARAM_CONTEXT_ID=$(curl -s "$BASE_URL/flow/parameter-contexts" \
    | tr -d '\n' \
    | sed 's/.*"parameterContexts":\[\(.*\)\].*/\1/' \
    | sed 's/},{/}\n{/g' \
    | grep "\"name\":\"$PB_CONTEXT_NAME\"" \
    | sed 's/.*"id":"\([^"]*\)".*/\1/' \
    | head -n 1)

  if [ -n "$PARAM_CONTEXT_ID" ]; then
    break
  fi

  echo "⏳ Waiting for Parameter Context to appear..."
  sleep 3
done

if [ -z "$PARAM_CONTEXT_ID" ]; then
  echo "❌ Parameter Context still not found after retries"
  exit 1
fi

echo "✅ Parameter Context ID: $PARAM_CONTEXT_ID"

echo "🔍 Fetching Root Process Group ID..."

ROOT_PG_ID=$(curl -s "$BASE_URL/flow/process-groups/root" \
  | tr -d '\n' \
  | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' \
  | head -n 1)

echo "✅ Root PG ID: $ROOT_PG_ID"

echo "🔍 Fetching revision..."

REVISION_VERSION=$(curl -s "$BASE_URL/process-groups/$ROOT_PG_ID" \
  | tr -d '\n' \
  | sed -n 's/.*"version":\([0-9]*\).*/\1/p' \
  | head -n 1)

echo "✅ Revision: $REVISION_VERSION"

echo "🔗 Applying Parameter Context..."

curl -s -X PUT "$BASE_URL/process-groups/$ROOT_PG_ID" \
  -H "Content-Type: application/json" \
  -d "{
    \"revision\": { \"version\": $REVISION_VERSION },
    \"component\": {
      \"id\": \"$ROOT_PG_ID\",
      \"parameterContext\": {
        \"id\": \"$PARAM_CONTEXT_ID\"
      }
    }
  }" >/dev/null

echo "✅ Parameter Context applied successfully"
echo "🎉 Init script finished"