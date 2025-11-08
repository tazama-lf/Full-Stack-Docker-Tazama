#!/bin/bash
# filepath: ./start.sh

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Function to display menu
show_menu() {
    clear
    echo ""
    print_color $BLUE "Select docker deployment type:"
    echo ""
    echo "1. Public (GitHub)"
    echo "2. Full deployment"
    echo "3. Multitenant deployment"
    echo ""
    echo "(q)uit"
    echo ""
}

# Function to toggle addon
toggle_addon() {
    local addon=$1
    if [[ "${!addon}" == "[ ]" ]]; then
        eval "$addon='[X]'"
    else
        eval "$addon='[ ]'"
    fi
}

# Function to show addons menu
show_addons_menu() {
    clear
    echo ""
    print_color $BLUE "UTILITY ADDONS:"
    echo ""
    echo "1. $natsutils NATS Utilities"
    echo "2. $batchppa Batch PPA"
    echo "3. $pgadmin pgAdmin for PostgreSQL"
    echo "4. $hasura Hasura GraphQL API for PostgreSQL"
    echo "5. $pgbouncer PgBouncer Connection Pooling"
    echo ""
    echo "Toggle addons (1-5), (a)pply current selection, (r)eturn, or (q)uit"
    echo ""
}

# Function to build docker compose command
build_docker_command() {
    local cmd="docker compose"
    
    # Base files
    cmd="$cmd -f docker-compose.base.infrastructure.yaml"
    cmd="$cmd -f docker-compose.base.override.yaml"
    
    # Deployment type specific files
    case $deployment_type in
        "github")
            cmd="$cmd -f docker-compose.base.github.yaml"
            ;;
        "full")
            cmd="$cmd -f docker-compose.full.cfg.yaml"
            cmd="$cmd -f docker-compose.full.rules.yaml"
            cmd="$cmd -f docker-compose.full.processors.yaml"
            ;;
        "multitenant")
            cmd="$cmd -f docker-compose.multitenant.cfg.yaml"
            cmd="$cmd -f docker-compose.multitenant.rules.yaml"
            cmd="$cmd -f docker-compose.multitenant.processors.yaml"
            cmd="$cmd -f docker-compose.multitenant.auth.yaml"
            ;;
    esac
    
    # Add utility addons
    if [[ "$volumes" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.utils.volumes.yaml"
    fi
    
    if [[ "$auth" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.base.auth.yaml"
    fi
    
    if [[ "$basiclogs" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.utils.basiclogs.yaml"
    fi
    
    if [[ "$natsutils" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.utils.natsutils.yaml"
    fi
    
    if [[ "$ui" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.utils.ui.yaml"
    fi
    
    if [[ "$relay" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.utils.relay.yaml"
    fi
    
    if [[ "$pgadmin" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.utils.pgadmin.yaml"
    fi
    
    if [[ "$hasura" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.utils.hasura.yaml"
    fi
    
    if [[ "$batchppa" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.utils.batchppa.yaml"
    fi
    
    if [[ "$pgbouncer" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.utils.pgbouncer.yaml"
        cmd="$cmd -f docker-compose.base.pgbouncer.yaml"
    fi
    
    echo "$cmd"
}

# Function to show utilities menu
show_utils_menu() {
    clear
    echo ""
    print_color $BLUE "Utilities:"
    echo ""
    echo "1. View all logs"
    echo "2. Stop and remove Tazama containers"
    echo "3. Database utilities"
    echo ""
    echo "(r)eturn or (q)uit"
    echo ""
}

# Function to show database utilities menu
show_dbutils_menu() {
    clear
    echo ""
    print_color $BLUE "Database utilities:"
    echo ""
    echo "1. List all PostgreSQL databases"
    echo "2. List all PostgreSQL tables in all databases"
    echo "3. Reset Hasura metadata"
    echo "4. Diagnose Hasura initialization issues"
    echo "5. Hasura health diagnostics"
    echo "6. Keycloak realm diagnostics"
    echo "7. Reset Keycloak"
    echo "8. PgBouncer statistics"
    echo ""
    echo "(r)eturn or (q)uit"
    echo ""
}

# Initialize addon states
volumes="[ ]"
auth="[ ]"
basiclogs="[ ]"
natsutils="[ ]"
ui="[ ]"
relay="[ ]"
pgadmin="[ ]"
hasura="[ ]"
batchppa="[ ]"
pgbouncer="[ ]"

deployment_type=""

# Main menu loop
while true; do
    show_menu
    read -p "Enter choice: " choice
    
    case $choice in
        1)
            deployment_type="github"
            ;;
        2)
            deployment_type="full"
            ;;
        3)
            deployment_type="multitenant"
            auth="[X]"  # Auth is mandatory for multitenant
            ;;
        q|Q)
            echo "Exiting..."
            exit 0
            ;;
        *)
            print_color $RED "Invalid choice. Please try again."
            sleep 1
            continue
            ;;
    esac
    
    # Addons menu loop
    while true; do
        show_addons_menu
        read -p "Enter choice: " addon_choice
        
        case $addon_choice in
            1) toggle_addon "natsutils" ;;
            2) toggle_addon "batchppa" ;;
            3) toggle_addon "pgadmin" ;;
            4) toggle_addon "hasura" ;;
            5) toggle_addon "pgbouncer" ;;
            a|A)
                # Apply and deploy
                clear
                echo ""
                print_color $YELLOW "Deployment Configuration:"
                echo "  Type: $deployment_type"
                echo "  NATS Utilities: $natsutils"
                echo "  Batch PPA: $batchppa"
                echo "  pgAdmin: $pgadmin"
                echo "  Hasura: $hasura"
                echo "  PgBouncer: $pgbouncer"
                echo "  Auth: $auth"
                echo ""
                
                read -p "Deploy with this configuration? (y/n): " confirm
                
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    echo ""
                    print_color $GREEN "Stopping existing Tazama containers..."
                    docker compose -p tazama down --volumes --remove-orphans 2>/dev/null || true
                    
                    echo ""
                    print_color $GREEN "Deploying Tazama..."
                    
                    cmd=$(build_docker_command)
                    echo ""
                    print_color $BLUE "Executing: $cmd -p tazama up -d --remove-orphans --force-recreate"
                    echo ""
                    
                    $cmd -p tazama up -d --remove-orphans --force-recreate
                    
                    echo ""
                    print_color $GREEN "✓ Deployment complete!"
                    echo ""
                    
                    # Show utilities menu
                    while true; do
                        show_utils_menu
                        read -p "Enter choice: " util_choice
                        
                        case $util_choice in
                            1)
                                # View logs
                                print_color $BLUE "Showing logs (Ctrl+C to exit)..."
                                docker compose -p tazama logs -f
                                ;;
                            2)
                                # Stop and remove
                                echo ""
                                read -p "Remove volumes (all data will be lost)? (y/n): " remove_vols
                                
                                if [[ "$remove_vols" == "y" || "$remove_vols" == "Y" ]]; then
                                    print_color $YELLOW "WARNING: This will delete ALL database data!"
                                    docker compose -p tazama down --volumes --remove-orphans
                                else
                                    docker compose -p tazama down --remove-orphans
                                fi
                                
                                # Explicitly remove Keycloak
                                echo ""
                                print_color $BLUE "Ensuring Keycloak container is removed..."
                                docker rm tazama-keycloak-1 2>/dev/null || true
                                
                                echo ""
                                print_color $GREEN "Done."
                                read -p "Press Enter to continue..."
                                ;;
                            3)
                                # Database utilities
                                while true; do
                                    show_dbutils_menu
                                    read -p "Enter choice: " db_choice
                                    
                                    case $db_choice in
                                        1)
                                            # List databases
                                            echo ""
                                            print_color $BLUE "=== PostgreSQL Databases ==="
                                            docker exec tazama-postgres-1 psql -U postgres -c "\l"
                                            echo ""
                                            read -p "Press Enter to continue..."
                                            ;;
                                        2)
                                            # List tables
                                            echo ""
                                            print_color $BLUE "=== PostgreSQL Tables ==="
                                            for db in event_history raw_history configuration evaluation hasura; do
                                                echo ""
                                                print_color $YELLOW "Database: $db"
                                                docker exec tazama-postgres-1 psql -U postgres -d $db -c "\dt" 2>/dev/null || echo "  (database not found)"
                                            done
                                            echo ""
                                            read -p "Press Enter to continue..."
                                            ;;
                                        3)
                                            # Reset Hasura metadata
                                            echo ""
                                            print_color $YELLOW "WARNING: This will clear all Hasura metadata!"
                                            read -p "Continue? (y/n): " reset_confirm
                                            
                                            if [[ "$reset_confirm" == "y" || "$reset_confirm" == "Y" ]]; then
                                                print_color $BLUE "Clearing Hasura metadata..."
                                                curl -s -X POST \
                                                    -H "Content-Type: application/json" \
                                                    -H "x-hasura-admin-secret: password" \
                                                    -d '{"type":"clear_metadata","args":{}}' \
                                                    http://localhost:6100/v1/metadata
                                                echo ""
                                                print_color $GREEN "✓ Metadata cleared"
                                                
                                                print_color $BLUE "Restarting Hasura init..."
                                                docker restart tazama-hasura-init-1 2>/dev/null || true
                                            fi
                                            echo ""
                                            read -p "Press Enter to continue..."
                                            ;;
                                        4)
                                            # Diagnose Hasura
                                            echo ""
                                            print_color $BLUE "=== HASURA DIAGNOSTICS ==="
                                            echo ""
                                            print_color $YELLOW "--- Container Status ---"
                                            docker ps -a | grep hasura
                                            echo ""
                                            print_color $YELLOW "--- Hasura Logs (last 50 lines) ---"
                                            docker logs --tail 50 tazama-hasura-1 2>&1
                                            echo ""
                                            print_color $YELLOW "--- Hasura Init Logs ---"
                                            docker logs tazama-hasura-init-1 2>&1
                                            echo ""
                                            read -p "Press Enter to continue..."
                                            ;;
                                        5)
                                            # Hasura health check
                                            echo ""
                                            print_color $BLUE "=== HASURA HEALTH CHECK ==="
                                            echo ""
                                            print_color $YELLOW "Testing external access (localhost:6100)..."
                                            curl -v http://localhost:6100/healthz 2>&1 | grep -E "Connected|HTTP|OK"
                                            echo ""
                                            print_color $YELLOW "Testing internal access (from container)..."
                                            docker exec tazama-hasura-1 curl -f http://localhost:8080/healthz 2>&1
                                            echo ""
                                            print_color $YELLOW "Testing database connection..."
                                            docker exec tazama-hasura-1 psql postgres://postgres@postgres:5432/hasura -c "SELECT 1;" 2>&1
                                            echo ""
                                            read -p "Press Enter to continue..."
                                            ;;
                                        6)
                                            # Keycloak diagnostics
                                            echo ""
                                            print_color $BLUE "=== KEYCLOAK DIAGNOSTICS ==="
                                            echo ""
                                            print_color $YELLOW "--- Container Status ---"
                                            docker ps -a | grep keycloak
                                            echo ""
                                            print_color $YELLOW "--- Keycloak Logs (import messages) ---"
                                            docker logs --tail 50 tazama-keycloak-1 2>&1 | grep -i "import\|realm\|KC-SERVICES"
                                            echo ""
                                            print_color $YELLOW "--- Test Realm Endpoint ---"
                                            curl -s http://localhost:8080/realms/tazama 2>&1 | grep -i "realm\|error" | head -5
                                            echo ""
                                            print_color $YELLOW "--- Available Realms ---"
                                            echo "Visit: http://localhost:8080/admin/master/console/"
                                            echo ""
                                            read -p "Press Enter to continue..."
                                            ;;
                                        7)
                                            # Reset Keycloak
                                            echo ""
                                            print_color $YELLOW "=== RESET KEYCLOAK ==="
                                            echo "This forces a clean Keycloak reimport by:"
                                            echo "  1. Stopping Keycloak"
                                            echo "  2. Removing Keycloak container (with internal data)"
                                            echo "  3. Removing any Keycloak volumes"
                                            echo ""
                                            read -p "Continue? (y/n): " kc_confirm
                                            
                                            if [[ "$kc_confirm" == "y" || "$kc_confirm" == "Y" ]]; then
                                                print_color $BLUE "Stopping Keycloak..."
                                                docker stop tazama-keycloak-1 2>/dev/null || true
                                                
                                                print_color $BLUE "Removing Keycloak container..."
                                                docker rm -v tazama-keycloak-1 2>/dev/null || true
                                                
                                                print_color $BLUE "Removing Keycloak volumes..."
                                                docker volume ls -q | grep keycloak | xargs -r docker volume rm 2>/dev/null || true
                                                
                                                echo ""
                                                print_color $GREEN "✓ Keycloak reset complete!"
                                                echo "  Restart your deployment to reimport realm."
                                            else
                                                echo "Reset cancelled."
                                            fi
                                            echo ""
                                            read -p "Press Enter to continue..."
                                            ;;
                                        8)
                                            # PgBouncer stats
                                            echo ""
                                            print_color $BLUE "=== PGBOUNCER STATISTICS ==="
                                            echo ""
                                            print_color $YELLOW "--- Connection Pools ---"
                                            docker exec tazama-pgbouncer-1 psql -h localhost -p 5432 -U postgres pgbouncer -c "SHOW POOLS;" 2>/dev/null || echo "PgBouncer not running"
                                            echo ""
                                            print_color $YELLOW "--- Databases ---"
                                            docker exec tazama-pgbouncer-1 psql -h localhost -p 5432 -U postgres pgbouncer -c "SHOW DATABASES;" 2>/dev/null || echo "PgBouncer not running"
                                            echo ""
                                            print_color $YELLOW "--- Statistics ---"
                                            docker exec tazama-pgbouncer-1 psql -h localhost -p 5432 -U postgres pgbouncer -c "SHOW STATS;" 2>/dev/null || echo "PgBouncer not running"
                                            echo ""
                                            read -p "Press Enter to continue..."
                                            ;;
                                        r|R)
                                            break
                                            ;;
                                        q|Q)
                                            echo "Exiting..."
                                            exit 0
                                            ;;
                                        *)
                                            print_color $RED "Invalid choice."
                                            sleep 1
                                            ;;
                                    esac
                                done
                                ;;
                            r|R)
                                break
                                ;;
                            q|Q)
                                echo "Exiting..."
                                exit 0
                                ;;
                            *)
                                print_color $RED "Invalid choice."
                                sleep 1
                                ;;
                        esac
                    done
                    
                    exit 0
                fi
                ;;
            r|R)
                deployment_type=""
                break
                ;;
            q|Q)
                echo "Exiting..."
                exit 0
                ;;
            *)
                print_color $RED "Invalid choice."
                sleep 1
                ;;
        esac
    done
done