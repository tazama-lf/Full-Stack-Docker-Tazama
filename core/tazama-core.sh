#!/bin/bash
# filepath: ./tazama-core.sh

cd "$(dirname "$0")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Addon state (reset on each return to the main menu)
auth="[ ]"
basiclogs="[ ]"
relay="[ ]"
natsutils="[ ]"
# These options default to enabled
pgadmin="[X]"
hasura="[X]"

IS_GITHUB_DEPLOYMENT=0
IS_FULL_DEPLOYMENT=0
IS_MULTITENANT_DEPLOYMENT=0

# Function to toggle addon
toggle_addon() {
    local addon_name=$1
    local current_value="${!addon_name}"

    if [[ "$current_value" == "[ ]" ]]; then
        eval "$addon_name='[X]'"
    else
        eval "$addon_name='[ ]'"
    fi
}

# Reset addon selection back to defaults
reset_addons() {
    auth="[ ]"
    basiclogs="[ ]"
    relay="[ ]"
    natsutils="[ ]"
    pgadmin="[X]"
    hasura="[X]"
}

# Main menu
show_main_menu() {
    clear
    echo ""
    print_color $BLUE "Select docker deployment type:"
    echo ""
    echo "1. Public (GitHub)"
    echo "2. Public (DockerHub)"
    echo "3. Full-service (DockerHub)"
    echo "4. Multi-Tenant Public (DockerHub)"
    echo "5. Docker Utilities"
    echo "6. Database Utilities"
    echo "7. Consoles"
    echo ""
    echo "Select option (1-7), or (q)uit:"
}

# Addons menu
show_addons_menu() {
    clear
    echo ""
    print_color $BLUE "Enable optional deployment configuration addons:"
    echo ""
    print_color $CYAN "CORE ADDONS:"
    echo ""
    echo "1. $auth Authentication"
    echo "2. $relay Relay services (NATS)"
    echo "3. $basiclogs Basic Logs"
    echo ""
    print_color $CYAN "UTILITY ADDONS:"
    echo ""
    echo "4. $natsutils NATS Utilities"
    echo "5. $pgadmin pgAdmin for PostgreSQL"
    echo "6. $hasura Hasura GraphQL API for PostgreSQL"
    echo ""
    echo "Toggle addons (1-6), (a)pply current selection, (r)eturn, or (q)uit"
}

# Build docker compose command
build_docker_command() {
    local cmd="docker compose -f docker-compose.base.infrastructure.yaml -f docker-compose.base.override.yaml"

    # Add core processors and configuration
    if [[ $IS_GITHUB_DEPLOYMENT -eq 1 ]]; then
        cmd="$cmd -f docker-compose.dev.cfg.yaml -f docker-compose.dev.core.yaml"
    else
        if [[ $IS_MULTITENANT_DEPLOYMENT -eq 1 ]]; then
            cmd="$cmd -f docker-compose.multitenant.cfg.yaml"
        elif [[ $IS_FULL_DEPLOYMENT -eq 1 ]]; then
            cmd="$cmd -f docker-compose.full.cfg.yaml"
        else
            cmd="$cmd -f docker-compose.hub.cfg.yaml"
        fi

        cmd="$cmd -f docker-compose.hub.core.yaml"

        if [[ $IS_FULL_DEPLOYMENT -eq 1 ]]; then
            cmd="$cmd -f docker-compose.full.rules.yaml"
        else
            cmd="$cmd -f docker-compose.hub.rules.yaml"
        fi
    fi

    # Add authentication services
    if [[ "$auth" == "[X]" ]]; then
        cmd="$cmd -f docker-compose.base.auth.yaml"
        if [[ $IS_GITHUB_DEPLOYMENT -eq 1 ]]; then
            cmd="$cmd -f docker-compose.dev.auth.yaml"
        fi
    fi

    # Add relay services
    if [[ "$relay" == "[X]" ]]; then
        if [[ $IS_GITHUB_DEPLOYMENT -eq 1 ]]; then
            cmd="$cmd -f docker-compose.dev.relay.yaml"
        elif [[ $IS_MULTITENANT_DEPLOYMENT -eq 1 ]]; then
            cmd="$cmd -f docker-compose.multitenant.relay.yaml"
        else
            cmd="$cmd -f docker-compose.hub.relay.yaml"
        fi
    fi

    # Add basic logging
    if [[ "$basiclogs" == "[X]" ]]; then
        if [[ $IS_GITHUB_DEPLOYMENT -eq 1 ]]; then
            cmd="$cmd -f docker-compose.dev.logs.base.yaml"
        else
            cmd="$cmd -f docker-compose.hub.logs.base.yaml"
        fi
    fi

    # Add utility addons
    [[ "$natsutils" == "[X]" ]] && cmd="$cmd -f docker-compose.utils.nats-utils.yaml"
    [[ "$pgadmin" == "[X]" ]] && cmd="$cmd -f docker-compose.utils.pgadmin.yaml"
    [[ "$hasura" == "[X]" ]] && cmd="$cmd -f docker-compose.utils.hasura.yaml"

    echo "$cmd"
}

# Apply configuration and deploy
apply_configuration() {
    local cmd
    cmd=$(build_docker_command)

    echo ""
    print_color $YELLOW "Command to run: $cmd -p tazama-core up -d"
    echo ""
    read -p "Press (e) to execute, (q) to quit or any other key to go back: " confirm
    echo ""

    if [[ "$confirm" == "e" || "$confirm" == "E" ]]; then
        print_color $GREEN "Stopping existing Tazama containers..."
        echo ""
        docker compose -p tazama-biar down --volumes --remove-orphans 2>/dev/null || true
        docker compose -p tazama-extensions down --volumes --remove-orphans 2>/dev/null || true
        docker compose -p tazama-core down --volumes --remove-orphans
        echo ""
        print_color $GREEN "Deploying Tazama from Docker Hub..."
        echo ""
        $cmd -p tazama-core up -d --remove-orphans --force-recreate

        echo ""
        print_color $GREEN "Deployment complete!"
        echo ""
        read -p "Press Enter to continue..."
        return 0
    elif [[ "$confirm" == "q" || "$confirm" == "Q" ]]; then
        return 0
    else
        return 1
    fi
}

# Addons selection loop (shared by all deployment types)
run_addons_loop() {
    while true; do
        show_addons_menu
        read -p "Enter your choice: " choice

        case $choice in
            a|A)
                if apply_configuration; then
                    return 0
                fi
                ;;
            r|R) return 0 ;;
            q|Q) exit 0 ;;
            1)
                if [[ $IS_MULTITENANT_DEPLOYMENT -eq 1 ]]; then
                    print_color $YELLOW "Auth and Relay are mandatory for multitenant deployment"
                    sleep 1
                else
                    toggle_addon "auth"
                fi
                ;;
            2)
                if [[ $IS_MULTITENANT_DEPLOYMENT -eq 1 ]]; then
                    print_color $YELLOW "Auth and Relay are mandatory for multitenant deployment"
                    sleep 1
                else
                    toggle_addon "relay"
                fi
                ;;
            3) toggle_addon "basiclogs" ;;
            4) toggle_addon "natsutils" ;;
            5) toggle_addon "pgadmin" ;;
            6) toggle_addon "hasura" ;;
            *)
                print_color $RED "Invalid choice."
                sleep 1
                ;;
        esac
    done
}

# Docker utilities menu
show_utils_menu() {
    clear
    echo ""
    print_color $BLUE "Execute some Docker commands:"
    echo ""
    echo "1. Stop and restart ED, TP and EA (reload network configuration)"
    echo "2. Stop and remove Tazama project containers and volumes"
    echo "3. Remove all unused containers, networks, images and volumes"
    echo "4. List all images"
    echo "5. List all containers"
    echo "6. List all volumes"
    echo "7. List all networks"
    echo ""
    echo "Select function (1-7), (r)eturn or (q)uit"
}

docker_utils() {
    while true; do
        show_utils_menu
        read -p "Enter your choice: " choice

        case $choice in
            r|R) return 0 ;;
            q|Q) exit 0 ;;
            1)
                print_color $GREEN "Restarting ED, TP and EA..."
                docker restart typology-processor event-adjudicator event-director
                ;;
            2)
                print_color $YELLOW "Stopping and removing Tazama containers and volumes..."
                docker compose -p tazama-biar down --volumes 2>/dev/null || true
                docker compose -p tazama-extensions down --volumes 2>/dev/null || true
                docker compose -p tazama-core down --volumes
                ;;
            3)
                print_color $YELLOW "Removing all unused Docker resources..."
                docker system prune -a -f --volumes
                ;;
            4) docker image ls ;;
            5) docker container ls ;;
            6) docker volume ls ;;
            7) docker network ls ;;
            *)
                print_color $RED "Invalid choice."
                sleep 1
                continue
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

# Database utilities menu
show_dbutils_menu() {
    clear
    echo ""
    print_color $BLUE "Database utilities:"
    echo ""
    echo "1. List all PostgreSQL databases"
    echo "2. List all PostgreSQL tables in all databases"
    echo "3. Reset Hasura metadata"
    echo "4. Reinitialize Hasura"
    echo ""
    echo "Select function (1-4), (r)eturn or (q)uit"
}

database_utils() {
    while true; do
        show_dbutils_menu
        read -p "Enter your choice: " choice

        case $choice in
            r|R) return 0 ;;
            q|Q) exit 0 ;;
            1)
                print_color $GREEN "Listing PostgreSQL databases..."
                docker exec -it core-postgres psql -U postgres -c "\l"
                ;;
            2)
                print_color $GREEN "Listing PostgreSQL tables..."
                for db in event_history raw_history configuration evaluation; do
                    echo ""
                    print_color $CYAN "=== $db ==="
                    docker exec -it core-postgres psql -U postgres -d $db -c "\dt" 2>/dev/null || echo "  (database not found)"
                done
                ;;
            3)
                echo ""
                print_color $YELLOW "WARNING: This will reset all Hasura metadata!"
                read -p "Continue? (y/n): " confirm

                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    print_color $GREEN "Stopping Hasura containers..."
                    docker stop hasura hasura-init 2>/dev/null || true

                    print_color $GREEN "Removing Hasura containers..."
                    docker rm hasura hasura-init 2>/dev/null || true

                    print_color $GREEN "Dropping Hasura metadata database..."
                    docker exec core-postgres psql -U postgres -c "DROP DATABASE IF EXISTS hasura;"
                    docker exec core-postgres psql -U postgres -c "CREATE DATABASE hasura;"

                    print_color $GREEN "Hasura metadata reset complete!"
                fi
                ;;
            4)
                print_color $GREEN "Reinitializing Hasura..."
                docker restart hasura-init
                ;;
            *)
                print_color $RED "Invalid choice."
                sleep 1
                continue
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

# Consoles menu
show_consoles_menu() {
    clear
    echo ""
    print_color $BLUE "Access a service web console:"
    echo ""
    echo "1. pgAdmin - localhost:5050"
    echo "2. Hasura - localhost:6100"
    echo "3. Keycloak - localhost:8080"
    echo "4. TMS-service Swagger - localhost:5000/documentation"
    echo "5. Admin-service Swagger - localhost:5100/documentation"
    echo ""
    echo "Select function (1-5), (r)eturn or (q)uit"
}

# Open URL based on OS
open_url() {
    local url=$1

    if command -v xdg-open &> /dev/null; then
        xdg-open "$url" 2>/dev/null
    elif command -v open &> /dev/null; then
        open "$url" 2>/dev/null
    else
        echo "Please open: $url"
    fi
}

consoles() {
    while true; do
        show_consoles_menu
        read -p "Enter your choice: " choice

        case $choice in
            r|R) return 0 ;;
            q|Q) exit 0 ;;
            1)
                print_color $GREEN "Opening pgAdmin..."
                open_url "http://localhost:5050"
                ;;
            2)
                print_color $GREEN "Opening Hasura..."
                open_url "http://localhost:6100"
                ;;
            3)
                print_color $GREEN "Opening Keycloak..."
                open_url "http://localhost:8080"
                ;;
            4)
                print_color $GREEN "Opening TMS-service Swagger..."
                open_url "http://localhost:5000/documentation"
                ;;
            5)
                print_color $GREEN "Opening Admin-service Swagger..."
                open_url "http://localhost:5100/documentation"
                ;;
            *)
                print_color $RED "Invalid choice."
                sleep 1
                continue
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

# Main loop
while true; do
    reset_addons
    show_main_menu
    read -p "Enter your choice: " type

    case $type in
        1)
            IS_GITHUB_DEPLOYMENT=1
            IS_FULL_DEPLOYMENT=0
            IS_MULTITENANT_DEPLOYMENT=0
            relay="[X]"
            run_addons_loop
            ;;
        2)
            IS_GITHUB_DEPLOYMENT=0
            IS_FULL_DEPLOYMENT=0
            IS_MULTITENANT_DEPLOYMENT=0
            relay="[X]"
            run_addons_loop
            ;;
        3)
            IS_GITHUB_DEPLOYMENT=0
            IS_FULL_DEPLOYMENT=1
            IS_MULTITENANT_DEPLOYMENT=0
            relay="[X]"
            run_addons_loop
            ;;
        4)
            IS_GITHUB_DEPLOYMENT=0
            IS_FULL_DEPLOYMENT=0
            IS_MULTITENANT_DEPLOYMENT=1
            auth="[X]"
            relay="[X]"
            run_addons_loop
            ;;
        5) docker_utils ;;
        6) database_utils ;;
        7) consoles ;;
        q|Q)
            print_color $GREEN "Exiting..."
            exit 0
            ;;
        "")
            continue
            ;;
        *)
            print_color $RED "Invalid choice. Please try again."
            sleep 1
            ;;
    esac
done
