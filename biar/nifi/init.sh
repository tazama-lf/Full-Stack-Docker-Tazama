#!/bin/sh

set -e

BASE_URL="http://biar-nifi:8088/nifi-api"
PB_SENSITIVE_FALSE="${PB_SENSITIVE_FALSE:-${PB_SENSITIVE:-false}}"

echo "Waiting for NiFi API to be ready..."

# Wait until parameter-context API responds properly, with bounded retries.
WAIT_RETRIES="${NIFI_API_WAIT_RETRIES:-60}"
WAIT_DELAY_SECONDS="${NIFI_API_WAIT_DELAY_SECONDS:-5}"
WAIT_ATTEMPT=1

while [ "$WAIT_ATTEMPT" -le "$WAIT_RETRIES" ]; do
  if curl -s "$BASE_URL/flow/parameter-contexts" | grep -q "parameterContexts"; then
    break
  fi
  echo "NiFi API not ready yet (attempt $WAIT_ATTEMPT/$WAIT_RETRIES), retrying in ${WAIT_DELAY_SECONDS}s..."
  WAIT_ATTEMPT=$((WAIT_ATTEMPT + 1))
  sleep "$WAIT_DELAY_SECONDS"
done

if [ "$WAIT_ATTEMPT" -gt "$WAIT_RETRIES" ]; then
  echo "NiFi API did not become ready after $WAIT_RETRIES attempts"
  exit 1
fi

echo "NiFi API is ready"

echo "Creating Parameter Context..."

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
        },
        {
          \"parameter\": {
            \"name\": \"$PB_HTTP_NAME\",
            \"value\": \"$PB_HTTP_VALUE\",
            \"sensitive\": $PB_SENSITIVE_FALSE
          }
        },
        {
          \"parameter\": {
            \"name\": \"$PB_OZONE_NAME\",
            \"value\": \"$PB_OZONE_ENDPOINT\",
            \"sensitive\": $PB_SENSITIVE_FALSE
          }
        }
      ]
    }
  }")

HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
BODY=$(echo "$CREATE_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "409" ]; then
  echo "Failed to create Parameter Context"
  echo "$BODY"
  exit 1
fi

echo "Parameter Context created or already exists"

echo "Fetching Parameter Context ID..."

# Retry until context appears
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

  echo "Waiting for Parameter Context to appear..."
  sleep 3
done

if [ -z "$PARAM_CONTEXT_ID" ]; then
  echo "Parameter Context still not found after retries"
  exit 1
fi

echo "Parameter Context ID: $PARAM_CONTEXT_ID"

echo "Ensuring required parameters exist in context..."

CONTEXT_RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/parameter-contexts/$PARAM_CONTEXT_ID")
CONTEXT_HTTP_CODE=$(echo "$CONTEXT_RESPONSE" | tail -n1)
CONTEXT_BODY=$(echo "$CONTEXT_RESPONSE" | sed '$d')

if [ "$CONTEXT_HTTP_CODE" != "200" ]; then
  echo "Failed to fetch Parameter Context details"
  echo "$CONTEXT_BODY"
  exit 1
fi

CURRENT_PARAMETERS_JSON=$(echo "$CONTEXT_BODY" \
  | tr -d '\n' \
  | sed -n 's/.*"parameters":\[\(.*\)\],"inheritedParameterContexts".*/\1/p' \
  | head -n 1)

UPDATED_PARAMETERS_JSON="$CURRENT_PARAMETERS_JSON"
PARAMS_UPDATED=false

if ! echo "$CONTEXT_BODY" | tr -d '\n' | grep -q "\"name\":\"$PB_NAME\""; then
  if [ -n "$UPDATED_PARAMETERS_JSON" ]; then
    UPDATED_PARAMETERS_JSON="$UPDATED_PARAMETERS_JSON,"
  fi
  UPDATED_PARAMETERS_JSON="$UPDATED_PARAMETERS_JSON{\"parameter\":{\"name\":\"$PB_NAME\",\"value\":\"$PB_BUCKET\",\"sensitive\":$PB_SENSITIVE_FALSE}}"
  PARAMS_UPDATED=true
fi

if ! echo "$CONTEXT_BODY" | tr -d '\n' | grep -q "\"name\":\"$PB_HTTP_NAME\""; then
  if [ -n "$UPDATED_PARAMETERS_JSON" ]; then
    UPDATED_PARAMETERS_JSON="$UPDATED_PARAMETERS_JSON,"
  fi
  UPDATED_PARAMETERS_JSON="$UPDATED_PARAMETERS_JSON{\"parameter\":{\"name\":\"$PB_HTTP_NAME\",\"value\":\"$PB_HTTP_VALUE\",\"sensitive\":$PB_SENSITIVE_FALSE}}"
  PARAMS_UPDATED=true
fi

if ! echo "$CONTEXT_BODY" | tr -d '\n' | grep -q "\"name\":\"$PB_OZONE_NAME\""; then
  if [ -n "$UPDATED_PARAMETERS_JSON" ]; then
    UPDATED_PARAMETERS_JSON="$UPDATED_PARAMETERS_JSON,"
  fi
  UPDATED_PARAMETERS_JSON="$UPDATED_PARAMETERS_JSON{\"parameter\":{\"name\":\"$PB_OZONE_NAME\",\"value\":\"$PB_OZONE_ENDPOINT\",\"sensitive\":$PB_SENSITIVE_FALSE}}"
  PARAMS_UPDATED=true
fi

if [ "$PARAMS_UPDATED" = "true" ]; then
  CONTEXT_REVISION_VERSION=$(echo "$CONTEXT_BODY" \
    | tr -d '\n' \
    | sed -n 's/.*"revision":[[:space:]]*{[^}]*"version":[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
    | head -n 1)

  if [ -z "$CONTEXT_REVISION_VERSION" ]; then
    echo "Failed to determine context revision version"
    exit 1
  fi

  UPDATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$BASE_URL/parameter-contexts/$PARAM_CONTEXT_ID" \
    -H "Content-Type: application/json" \
    -d "{
      \"revision\": { \"version\": $CONTEXT_REVISION_VERSION },
      \"component\": {
        \"id\": \"$PARAM_CONTEXT_ID\",
        \"parameters\": [ $UPDATED_PARAMETERS_JSON ]
      }
    }")

  UPDATE_HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
  UPDATE_BODY=$(echo "$UPDATE_RESPONSE" | sed '$d')

  if [ "$UPDATE_HTTP_CODE" != "200" ]; then
    echo "Failed to update required parameters in context"
    echo "$UPDATE_BODY"
    exit 1
  fi

  echo "Required parameters were added to existing context"
else
  echo "Required parameters already exist"
fi

echo "Fetching Root Process Group ID..."

ROOT_PG_ID=$(curl -s "$BASE_URL/flow/process-groups/root" \
  | tr -d '\n' \
  | awk -F'"id":"' '{print $2}' \
  | cut -d'"' -f1 \
  | head -n 1)

if [ -z "$ROOT_PG_ID" ]; then
  echo "Failed to determine Root Process Group ID"
  exit 1
fi

echo "Root PG ID: $ROOT_PG_ID"

TEMPLATE_TARGET_PG_ID="${NIFI_TEMPLATE_TARGET_PG_ID:-$ROOT_PG_ID}"

echo "Fetching revision..."

REVISION_VERSION=$(curl -s "$BASE_URL/process-groups/$ROOT_PG_ID" \
  | tr -d '\n' \
  | sed -n 's/.*"version":\([0-9]*\).*/\1/p' \
  | head -n 1)

if [ -z "$REVISION_VERSION" ]; then
  echo "Failed to determine revision for process group: $ROOT_PG_ID"
  exit 1
fi

echo "Revision: $REVISION_VERSION"

echo "Applying Parameter Context..."

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

echo "Parameter Context applied successfully"

IMPORT_NIFI_TEMPLATE="${IMPORT_NIFI_TEMPLATE:-true}"

if [ "$IMPORT_NIFI_TEMPLATE" = "true" ]; then
  TEMPLATE_FILE="${NIFI_TEMPLATE_FILE:-/nifi/tazama.xml}"
  TEMPLATE_X="${NIFI_TEMPLATE_X:-0.0}"
  TEMPLATE_Y="${NIFI_TEMPLATE_Y:-0.0}"

  if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Template import enabled but file not found: $TEMPLATE_FILE"
    exit 1
  fi

  TEMPLATE_NAME=$(tr -d '\n' < "$TEMPLATE_FILE" | sed -n 's:.*<name>[[:space:]]*\([^<]*\)[[:space:]]*</name>.*:\1:p' | head -n 1)
  TEMPLATE_ID=""

  echo "Uploading NiFi template from $TEMPLATE_FILE ..."

  UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    "$BASE_URL/process-groups/$TEMPLATE_TARGET_PG_ID/templates/upload" \
    -H "Content-Type: multipart/form-data" \
    -F "template=@$TEMPLATE_FILE")

  UPLOAD_HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | tail -n1)
  UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | sed '$d')

  if [ "$UPLOAD_HTTP_CODE" != "201" ] && [ "$UPLOAD_HTTP_CODE" != "200" ]; then
    if echo "$UPLOAD_BODY" | grep -qi "already exists"; then
      echo "Template already exists in NiFi, reusing existing template ID"

      EXISTING_TEMPLATE_NAME=$(echo "$UPLOAD_BODY" | sed -n "s/.*template named '\([^']*\)'.*/\1/p" | head -n 1)
      if [ -z "$EXISTING_TEMPLATE_NAME" ]; then
        EXISTING_TEMPLATE_NAME="$TEMPLATE_NAME"
      fi

      TEMPLATES_BODY=$(curl -s "$BASE_URL/flow/templates")
      TEMPLATE_ID=$(echo "$TEMPLATES_BODY" \
        | tr -d '\n' \
        | sed 's/},{/}\n{/g' \
        | grep "\"name\":\"$EXISTING_TEMPLATE_NAME\"" \
        | sed -n 's/.*"template":{[^}]*"id":"\([^"]*\)".*/\1/p' \
        | head -n 1)

      if [ -z "$TEMPLATE_ID" ]; then
        TEMPLATE_ID=$(echo "$TEMPLATES_BODY" \
          | tr -d '\n' \
          | sed 's/},{/}\n{/g' \
          | grep "\"name\":\"$EXISTING_TEMPLATE_NAME\"" \
        | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' \
        | head -n 1)
      fi

      if [ -z "$TEMPLATE_ID" ]; then
        echo "Template exists but could not resolve template ID for name: $EXISTING_TEMPLATE_NAME"
        echo "$UPLOAD_BODY"
        exit 1
      fi
    else
      echo "Template upload failed"
      echo "$UPLOAD_BODY"
      exit 1
    fi
  fi

  if [ -z "$TEMPLATE_ID" ]; then
    TEMPLATE_ID=$(echo "$UPLOAD_BODY" \
      | tr -d '\n' \
      | sed -n 's/.*"template"[[:space:]]*:[[:space:]]*{[^}]*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n 1)

    if [ -z "$TEMPLATE_ID" ]; then
      TEMPLATE_ID=$(echo "$UPLOAD_BODY" \
        | tr -d '\n' \
        | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1)
    fi
  fi

  if [ -z "$TEMPLATE_ID" ]; then
    echo "Unable to extract template ID from upload response"
    echo "$UPLOAD_BODY"
    exit 1
  fi

  echo "Instantiating template ID: $TEMPLATE_ID"

  INSTANTIATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    "$BASE_URL/process-groups/$TEMPLATE_TARGET_PG_ID/template-instance" \
    -H "Content-Type: application/json" \
    -d "{
      \"templateId\": \"$TEMPLATE_ID\",
      \"originX\": $TEMPLATE_X,
      \"originY\": $TEMPLATE_Y
    }")

  INSTANTIATE_HTTP_CODE=$(echo "$INSTANTIATE_RESPONSE" | tail -n1)
  INSTANTIATE_BODY=$(echo "$INSTANTIATE_RESPONSE" | sed '$d')

  if [ "$INSTANTIATE_HTTP_CODE" != "201" ] && [ "$INSTANTIATE_HTTP_CODE" != "200" ] && [ "$INSTANTIATE_HTTP_CODE" != "409" ]; then
    echo "Template instantiation failed"
    echo "$INSTANTIATE_BODY"
    exit 1
  fi

  echo "Template imported and instantiated successfully"
else
  echo "Template import skipped (IMPORT_NIFI_TEMPLATE=false)"
fi

echo "Init script finished"
