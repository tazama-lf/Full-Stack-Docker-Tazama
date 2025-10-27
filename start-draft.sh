#!/bin/bash
# filepath: start.sh

# Enable error handling
set -e

menu() {
    type=""
    volumes="[ ]"
    auth="[ ]"
    basiclogs="[ ]"
    natsutils="[ ]"
    ui="[ ]"
    relay="[ ]"
    pgadmin="[ ]"
    hasura="[ ]"

    IS_GITHUB_DEPLOYMENT=0
    IS_FULL_DEPLOYMENT=0
    IS_MULTITENANT_DEPLOYMENT=0

    clear
    echo
    echo "Select docker deployment type:"
    echo
    echo "1. Public (GitHub)"
    echo "2. Public (DockerHub)"
    echo "3. Full-service (DockerHub)"
    echo "4. Multi-Tenant Public (DockerHub)"
    echo "5. General Utilities"
    echo "6. Database Utilities"
    echo
    echo "Select option (1-6), or (q)uit:"
    read -p "Enter your choice: " type

    case "$type" in
        q|Q) exit 0 ;;
        "") menu ;;
        1)
            IS_GITHUB_DEPLOYMENT=1
            IS_FULL_DEPLOYMENT=0
            IS_MULTITENANT_DEPLOYMENT=0
            addons
            ;;
        2)
            IS_GITHUB_DEPLOYMENT=0
            IS_FULL_DEPLOYMENT=0
            IS_MULTITENANT_DEPLOYMENT=0
            addons
            ;;
        3)
            IS_FULL_DEPLOYMENT=1
            IS_GITHUB_DEPLOYMENT=0
            IS_MULTITENANT_DEPLOYMENT=0
            addons
            ;;
        4)
            IS_GITHUB_DEPLOYMENT=0
            IS_FULL_DEPLOYMENT=0
            IS_MULTITENANT_DEPLOYMENT=1
            auth="[X]"
            relay="[X]"
            addons
            ;;
        5) utils ;;
        6) dbutils ;;
        *) menu ;;
    esac
}

addons() {
    while true; do
        clear
        echo
        echo "Enable optional deployment configuration addons:"
        echo
        echo "CORE ADDONS:"
        echo
        echo "1. $auth Authentication"
        echo "2. $relay Relay services (NATS)"
        echo "3. $basiclogs Basic Logs"
        echo "4. $ui Demo UI"
        echo
        echo "UTILITY ADDONS:"
        echo
        echo "5. $natsutils NATS Utilities"
        echo "6. $pgadmin pgAdmin for PostgreSQL"
        echo "7. $hasura Hasura GraphQL API for PostgreSQL"
        echo
        echo "Toggle addons (1-7), (a)pply current selection, (r)eturn, or (q)uit"
        read -p "Enter your choice: " choice

        case "$choice" in
            a|A) apply ;;
            r|R) menu ;;
            q|Q) exit 0 ;;
            1)
                if [ $IS_MULTITENANT_DEPLOYMENT -ne 1 ]; then
                    [ "$auth" == "[ ]" ] && auth="[X]" || auth="[ ]"
                fi
                ;;
            2)
                if [ $IS_MULTITENANT_DEPLOYMENT -ne 1 ]; then
                    [ "$relay" == "[ ]" ] && relay="[X]" || relay="[ ]"
                fi
                ;;
            3) [ "$basiclogs" == "[ ]" ] && basiclogs="[X]" || basiclogs="[ ]" ;;
            4) [ "$ui" == "[ ]" ] && ui="[X]" || ui="[ ]" ;;
            5) [ "$natsutils" == "[ ]" ] && natsutils="[X]" || natsutils="[ ]" ;;
            6) [ "$pgadmin" == "[ ]" ] && pgadmin="[X]" || pgadmin="[ ]" ;;
            7) [ "$hasura" == "[ ]" ] && hasura="[X]" || hasura="[ ]" ;;
        esac
    done
}

apply() {
    # Base command for all options
    cmd="docker compose -f docker-compose.base.infrastructure.yaml -f docker-compose.base.override.yaml"

    # Add core processors and configuration
    if [ $IS_GITHUB_DEPLOYMENT -eq 1 ]; then
        cmd="$cmd -f docker-compose.dev.cfg.yaml -f docker-compose.dev.core.yaml"
    else
        if [ $IS_MULTITENANT_DEPLOYMENT -eq 1 ]; then
            cmd="$cmd -f docker-compose.multitenant.cfg.yaml"
        else
            if [ $IS_FULL_DEPLOYMENT -eq 1 ]; then
                cmd="$cmd -f docker-compose.full.cfg.yaml"
            else
                cmd="$cmd -f docker-compose.hub.cfg.yaml"
            fi
        fi
        cmd="$cmd -f docker-compose.hub.core.yaml"
        if [ $IS_FULL_DEPLOYMENT -eq 1 ]; then
            cmd="$cmd -f docker-compose.full.rules.yaml"
        else
            cmd="$cmd -f docker-compose.hub.rules.yaml"
        fi
    fi

    # Add authentication services (mandatory for multitenancy)
    if [ "$auth" == "[X]" ]; then
        cmd="$cmd -f docker-compose.base.auth.yaml"
        if [ $IS_GITHUB_DEPLOYMENT -eq 1 ]; then
            cmd="$cmd -f docker-compose.dev.auth.yaml"
        else
            if [ $IS_MULTITENANT_DEPLOYMENT -eq 1 ]; then
                cmd="$cmd -f docker-compose.multitenant.auth.yaml"
            fi
        fi
    fi

    # Add relay services (mandatory for multitenancy)
    if [ "$relay" == "[X]" ]; then
        if [ $IS_GITHUB_DEPLOYMENT -eq 1 ]; then
            cmd="$cmd -f docker-compose.dev.relay.yaml"
        else
            if [ $IS_MULTITENANT_DEPLOYMENT -eq 1 ]; then
                cmd="$cmd -f docker-compose.multitenant.relay.yaml"
            else
                cmd="$cmd -f docker-compose.hub.relay.yaml"
            fi
        fi
    fi

    # Add basic logging services
    if [ "$basiclogs" == "[X]" ]; then
        if [ $IS_GITHUB_DEPLOYMENT -eq 1 ]; then
            cmd="$cmd -f docker-compose.dev.logs.base.yaml"
        else
            cmd="$cmd -f docker-compose.hub.logs.base.yaml"
        fi
    fi

    [ "$ui" == "[X]" ] && cmd="$cmd -f docker-compose.hub.ui.yaml"
    [ "$natsutils" == "[X]" ] && cmd="$cmd -f docker-compose.utils.nats-utils.yaml"
    [ "$pgadmin" == "[X]" ] && cmd="$cmd -f docker-compose.utils.pgadmin.yaml"
    [ "$hasura" == "[X]" ] && cmd="$cmd -f docker-compose.utils.hasura.yaml"

    echo
    echo "Command to run: $cmd -p tazama up -d"
    echo
    read -p "Press (e) to execute, (q) to quit or any other key to go back: " confirm
    echo

    case "$confirm" in
        e|E)
            echo "Stopping existing Tazama containers..."
            echo
            docker compose -p tazama down
            echo
            echo "Deploying Tazama..."
            echo
            $cmd -p tazama up -d --remove-orphans
            exit 0
            ;;
        q|Q) exit 0 ;;
        *) addons ;;
    esac
}

utils() {
    while true; do
        clear
        echo
        echo "Execute some Docker commands:"
        echo
        echo "1. Stop and restart ED, TP and TADP (reload network configuration)"
        echo "2. Stop and remove Tazama project containers"
        echo "3. Remove all unused containers, networks, images and volumes"
        echo "4. List all images"
        echo "5. List all containers"
        echo "6. List all volumes"
        echo "7. List all networks"
        echo
        echo "Select function (1-7), (r)eturn or (q)uit"
        read -p "Enter your choice: " choice

        case "$choice" in
            q|Q) exit 0 ;;
            r|R) menu ;;
            "") continue ;;
            1) cmd="docker restart tazama-tp-1 tazama-tadp-1 tazama-ed-1" ;;
            2) cmd="docker compose -p tazama down" ;;
            3) cmd="docker system prune -a -f --volumes" ;;
            4) cmd="docker image ls" ;;
            5) cmd="docker container ls" ;;
            6) cmd="docker volume ls" ;;
            7) cmd="docker network ls" ;;
            *) continue ;;
        esac

        echo "Executing command: $cmd"
        echo
        eval $cmd
        echo
        read -p "Press Enter to continue..."
    done
}

dbutils() {
    while true; do
        clear
        echo
        echo "Execute some Docker commands in tazama-postgres-1:"
        echo
        echo "1. List all PostgreSQL databases"
        echo "2. List all PostgreSQL tables in all databases"
        echo
        echo "Select function (1-2), (r)eturn or (q)uit"
        read -p "Enter your choice: " choice

        case "$choice" in
            q|Q) exit 0 ;;
            r|R) menu ;;
            "") continue ;;
        esac

        echo "Executing command..."
        echo

        case "$choice" in
            1)
                docker exec -it tazama-postgres-1 psql -U postgres -c "\l"
                ;;
            2)
                for db in event_history raw_history configuration evaluation; do
                    echo
                    echo "=== $db ==="
                    docker exec -it tazama-postgres-1 psql -U postgres -d $db -c "\dt"
                done
                ;;
        esac

        echo
        read -p "Press Enter to continue..."
    done
}

# Make script executable with: chmod +x start.sh
menu