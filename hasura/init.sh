#!/bin/bash
# filepath: ./hasura/init.sh
set -e

echo "=========================================="
echo "Hasura Initialization Script"
echo "=========================================="

echo ""
echo "=========================================="
echo "Clearing existing metadata..."
echo "=========================================="

# Reset Hasura metadata
curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: password" \
    -d '{"type":"clear_metadata","args":{}}' \
    http://hasura:8080/v1/metadata > /dev/null 2>&1
echo "✓ Metadata cleared"
echo ""

echo ""
echo "=========================================="
echo "Removing existing data sources..."
echo "=========================================="

for source in event_history raw_history configuration evaluation; do
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: password" \
        -d "{\"type\":\"pg_drop_source\",\"args\":{\"name\":\"$source\",\"cascade\":true}}" \
        http://hasura:8080/v1/metadata > /dev/null 2>&1
done
echo "✓ Sources removed"
echo ""

# Function to make API calls to Hasura
call_hasura_api() {
  local payload=$1
  local description=$2
  echo "→ $description"
  
  response=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://hasura:8080/v1/metadata \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: password" \
    -d "$payload")
  
  if [ "$response" = "200" ]; then
    echo "  ✓ Success"
  else
    echo "  ✗ Failed (HTTP $response)"
  fi
}

echo ""
echo "=========================================="
echo "Adding Data Sources"
echo "=========================================="

# Add event_history database
call_hasura_api '{
  "type": "pg_add_source",
  "args": {
    "name": "event_history",
    "configuration": {
      "connection_info": {
        "database_url": {
          "from_env": "HASURA_GRAPHQL_DATABASE_URL_EVENT_HISTORY"
        }
      }
    }
  }
}' "Adding event_history database"

# Add raw_history database
call_hasura_api '{
  "type": "pg_add_source",
  "args": {
    "name": "raw_history",
    "configuration": {
      "connection_info": {
        "database_url": {
          "from_env": "HASURA_GRAPHQL_DATABASE_URL_RAW_HISTORY"
        }
      }
    }
  }
}' "Adding raw_history database"

# Add configuration database
call_hasura_api '{
  "type": "pg_add_source",
  "args": {
    "name": "configuration",
    "configuration": {
      "connection_info": {
        "database_url": {
          "from_env": "HASURA_GRAPHQL_DATABASE_URL_CONFIGURATION"
        }
      }
    }
  }
}' "Adding configuration database"

# Add evaluation database
call_hasura_api '{
  "type": "pg_add_source",
  "args": {
    "name": "evaluation",
    "configuration": {
      "connection_info": {
        "database_url": {
          "from_env": "HASURA_GRAPHQL_DATABASE_URL_EVALUATION"
        }
      }
    }
  }
}' "Adding evaluation database"

echo ""
echo "=========================================="
echo "Tracking Tables - event_history"
echo "=========================================="

# Track tables in event_history
for table in entity account account_holder transaction condition governed_as_creditor_by governed_as_debtor_by governed_as_creditor_account_by governed_as_debtor_account_by; do
  call_hasura_api "{
    \"type\": \"pg_track_table\",
    \"args\": {
      \"source\": \"event_history\",
      \"table\": \"$table\"
    }
  }" "Tracking table: $table"
done

echo ""
echo "=========================================="
echo "Tracking Tables - raw_history"
echo "=========================================="

# Track tables in raw_history
for table in pacs002 pacs008 pain001 pain013; do
  call_hasura_api "{
    \"type\": \"pg_track_table\",
    \"args\": {
      \"source\": \"raw_history\",
      \"table\": \"$table\"
    }
  }" "Tracking table: $table"
done

echo ""
echo "=========================================="
echo "Tracking Tables - configuration"
echo "=========================================="

# Track tables in configuration
for table in network_map rule typology; do
  call_hasura_api "{
    \"type\": \"pg_track_table\",
    \"args\": {
      \"source\": \"configuration\",
      \"table\": \"$table\"
    }
  }" "Tracking table: $table"
done

echo ""
echo "=========================================="
echo "Tracking Tables - evaluation"
echo "=========================================="

# Track tables in evaluation
call_hasura_api '{
  "type": "pg_track_table",
  "args": {
    "source": "evaluation",
    "table": "evaluation"
  }
}' "Tracking table: evaluation"

echo ""
echo "=========================================="
echo "Setting Permissions - event_history"
echo "=========================================="

# Set permissions for anonymous role on event_history tables
for table in entity account account_holder transaction condition governed_as_creditor_by governed_as_debtor_by governed_as_creditor_account_by governed_as_debtor_account_by; do
  # Insert permission
  call_hasura_api "{
    \"type\": \"pg_create_insert_permission\",
    \"args\": {
      \"source\": \"event_history\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"check\": {},
        \"columns\": \"*\"
      }
    }
  }" "Insert permission for $table"
  
  # Select permission
  call_hasura_api "{
    \"type\": \"pg_create_select_permission\",
    \"args\": {
      \"source\": \"event_history\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"columns\": \"*\",
        \"filter\": {}
      }
    }
  }" "Select permission for $table"
  
  # Update permission
  call_hasura_api "{
    \"type\": \"pg_create_update_permission\",
    \"args\": {
      \"source\": \"event_history\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"columns\": \"*\",
        \"filter\": {},
        \"check\": {}
      }
    }
  }" "Update permission for $table"
  
  # Delete permission
  call_hasura_api "{
    \"type\": \"pg_create_delete_permission\",
    \"args\": {
      \"source\": \"event_history\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"filter\": {}
      }
    }
  }" "Delete permission for $table"
done

echo ""
echo "=========================================="
echo "Setting Permissions - raw_history"
echo "=========================================="

# Set permissions for anonymous role on raw_history tables
for table in pacs002 pacs008 pain001 pain013; do
  # Insert permission
  call_hasura_api "{
    \"type\": \"pg_create_insert_permission\",
    \"args\": {
      \"source\": \"raw_history\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"check\": {},
        \"columns\": \"*\"
      }
    }
  }" "Insert permission for $table"
  
  # Select permission
  call_hasura_api "{
    \"type\": \"pg_create_select_permission\",
    \"args\": {
      \"source\": \"raw_history\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"columns\": \"*\",
        \"filter\": {}
      }
    }
  }" "Select permission for $table"
  
  # Update permission
  call_hasura_api "{
    \"type\": \"pg_create_update_permission\",
    \"args\": {
      \"source\": \"raw_history\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"columns\": \"*\",
        \"filter\": {},
        \"check\": {}
      }
    }
  }" "Update permission for $table"
  
  # Delete permission
  call_hasura_api "{
    \"type\": \"pg_create_delete_permission\",
    \"args\": {
      \"source\": \"raw_history\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"filter\": {}
      }
    }
  }" "Delete permission for $table"
done

echo ""
echo "=========================================="
echo "Setting Permissions - configuration"
echo "=========================================="

# Set permissions for anonymous role on configuration tables
for table in network_map rule typology; do
  # Insert permission
  call_hasura_api "{
    \"type\": \"pg_create_insert_permission\",
    \"args\": {
      \"source\": \"configuration\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"check\": {},
        \"columns\": \"*\"
      }
    }
  }" "Insert permission for $table"
  
  # Select permission
  call_hasura_api "{
    \"type\": \"pg_create_select_permission\",
    \"args\": {
      \"source\": \"configuration\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"columns\": \"*\",
        \"filter\": {}
      }
    }
  }" "Select permission for $table"
  
  # Update permission
  call_hasura_api "{
    \"type\": \"pg_create_update_permission\",
    \"args\": {
      \"source\": \"configuration\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"columns\": \"*\",
        \"filter\": {},
        \"check\": {}
      }
    }
  }" "Update permission for $table"
  
  # Delete permission
  call_hasura_api "{
    \"type\": \"pg_create_delete_permission\",
    \"args\": {
      \"source\": \"configuration\",
      \"table\": \"$table\",
      \"role\": \"anonymous\",
      \"permission\": {
        \"filter\": {}
      }
    }
  }" "Delete permission for $table"
done

echo ""
echo "=========================================="
echo "Setting Permissions - evaluation"
echo "=========================================="

# Set permissions for anonymous role on evaluation table
# Insert permission
call_hasura_api '{
  "type": "pg_create_insert_permission",
  "args": {
    "source": "evaluation",
    "table": "evaluation",
    "role": "anonymous",
    "permission": {
      "check": {},
      "columns": "*"
    }
  }
}' "Insert permission for evaluation"

# Select permission
call_hasura_api '{
  "type": "pg_create_select_permission",
  "args": {
    "source": "evaluation",
    "table": "evaluation",
    "role": "anonymous",
    "permission": {
      "columns": "*",
      "filter": {}
    }
  }
}' "Select permission for evaluation"

# Update permission
call_hasura_api '{
  "type": "pg_create_update_permission",
  "args": {
    "source": "evaluation",
    "table": "evaluation",
    "role": "anonymous",
    "permission": {
      "columns": "*",
      "filter": {},
      "check": {}
    }
  }
}' "Update permission for evaluation"

# Delete permission
call_hasura_api '{
  "type": "pg_create_delete_permission",
  "args": {
    "source": "evaluation",
    "table": "evaluation",
    "role": "anonymous",
    "permission": {
      "filter": {}
    }
  }
}' "Delete permission for evaluation"

echo ""
echo "=========================================="
echo "✓ Hasura initialization complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - Added 4 data sources"
echo "  - Tracked 9 tables in event_history"
echo "  - Tracked 4 tables in raw_history"
echo "  - Tracked 3 tables in configuration"
echo "  - Tracked 1 table in evaluation"
echo "  - Set full permissions for 'anonymous' role on all tables"
echo "=========================================="