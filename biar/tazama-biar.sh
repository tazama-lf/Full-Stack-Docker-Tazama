#!/bin/bash
# filepath: ./tazama-biar.sh

cd "$(dirname "$0")"

BIAR_PROJECT="tazama-biar"

pause() {
    read -rp " Press Enter to continue..."
}

check_core_reachable() {
    local server_a_host="localhost"

    if [[ -f ./.env ]]; then
        local env_host
        env_host=$(grep -E '^SERVER_A_HOST=' ./.env | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d '\r')
        if [[ -n "$env_host" ]]; then
            server_a_host="$env_host"
        fi
    fi

    if ! timeout 2 bash -c "</dev/tcp/${server_a_host}/14222" >/dev/null 2>&1; then
        echo ""
        echo " ERROR: tazama-core is not reachable at ${server_a_host}:14222"
        echo "        Ensure tazama-core is running and SERVER_A_HOST is set correctly in .env"
        echo ""
        pause
        return 1
    fi

    return 0
}

deploy_biar() {
    echo ""
    echo " Deploying BIAR stack..."
    echo ""
    docker compose -p "$BIAR_PROJECT" \
        -f ./docker-compose.base.infrastructure.yaml \
        -f ./docker-compose.dev.biar.yaml \
        -f ./docker-compose.utils.init.yaml \
        up -d

    echo ""
    echo " Done."
    pause
}

down_biar() {
    echo ""
    echo " Tearing down BIAR stack..."
    echo ""
    docker compose -p "$BIAR_PROJECT" \
        -f ./docker-compose.base.infrastructure.yaml \
        -f ./docker-compose.dev.biar.yaml \
        -f ./docker-compose.utils.init.yaml \
        down --volumes

    echo ""
    echo " Done."
    pause
}

utils() {
    while true; do
        clear
        echo ""
        echo " Utilities:"
        echo "   1. Tear down BIAR"
        echo "   b. Back"
        echo ""
        read -rp " Select option: " util

        case "$util" in
            b|B) return ;;
            1) down_biar ;;
        esac
    done
}

menu() {
    while true; do
        clear
        echo ""
        echo "============================================================"
        echo " Tazama BIAR Launcher"
        echo "============================================================"
        echo ""
        echo " Pre-requisite: tazama-core must be running on Server A"
        echo ""
        echo "   1. Deploy BIAR stack"
        echo "   2. Utilities / teardown"
        echo ""
        read -rp " Select option (1-2), or (q)uit: " choice

        case "$choice" in
            q|Q) exit 0 ;;
            1) check_core_reachable && deploy_biar ;;
            2) utils ;;
        esac
    done
}

menu
