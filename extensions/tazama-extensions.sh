#!/bin/bash
# filepath: ./tazama-extensions.sh

cd "$(dirname "$0")"

CORE_PROJECT="tazama-core"
EXTENSIONS_PROJECT="tazama-extensions"

pause() {
    read -rp " Press Enter to continue..."
}

# ---------------------------------------------------------------
# Server A pre-flight: DEMS + DEAPI
# ---------------------------------------------------------------
deploy_apis() {
    local api_build=$1

    local running
    running=$(docker compose -p "$CORE_PROJECT" ps --status running -q 2>/dev/null)
    if [[ -z "$running" ]]; then
        echo ""
        echo " ERROR: tazama-core is not running."
        echo "        Start tazama-core.sh on this machine first, then retry."
        echo ""
        pause
        return 1
    fi

    local apicmd
    if [[ "$api_build" == "dev" ]]; then
        apicmd="docker compose -p $CORE_PROJECT -f ./docker-compose.dev.extensions.apis.yaml"
    else
        apicmd="docker compose -p $CORE_PROJECT -f ./docker-compose.hub.extensions.apis.yaml"
    fi

    echo ""
    echo " Running: $apicmd up -d"
    $apicmd up -d

    echo ""
    echo " Done."
    pause
}

# ---------------------------------------------------------------
# Server B extensions stack
# ---------------------------------------------------------------
deploy_extensions() {
    local build_type=$1

    echo ""
    echo " Optional services:"
    echo ""
    local addon
    read -rp " Include pgAdmin? [y/N]: " addon

    local pgadmin="false"
    if [[ "$addon" == "y" || "$addon" == "Y" ]]; then
        pgadmin="true"
    fi

    # Auto-copy public key for TCS/TRS volume mounts
    mkdir -p ./auth
    if [[ ! -f ./auth/test-public-key.pem ]]; then
        if [[ -f ../core/auth/test-public-key.pem ]]; then
            cp -f ../core/auth/test-public-key.pem ./auth/test-public-key.pem
            echo " Copied test-public-key.pem from core."
        else
            echo ""
            echo " ERROR: ../core/auth/test-public-key.pem not found."
            echo "        Place the public key in ./auth/ and retry."
            echo ""
            pause
            return 1
        fi
    fi

    local cmd="docker compose -p $EXTENSIONS_PROJECT"
    cmd="$cmd -f ./docker-compose.extensions.infrastructure.yaml"
    if [[ "$build_type" == "dev" ]]; then
        cmd="$cmd -f ./docker-compose.dev.extensions.yaml"
    else
        cmd="$cmd -f ./docker-compose.hub.extensions.yaml"
    fi
    if [[ "$pgadmin" == "true" ]]; then
        cmd="$cmd -f ./docker-compose.utils.pgadmin.yaml"
    fi

    echo ""
    echo " Running: $cmd up -d"
    $cmd up -d

    echo ""
    echo " Done."
    pause
}

# ---------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------
down_extensions() {
    docker compose -p "$EXTENSIONS_PROJECT" \
        -f ./docker-compose.extensions.infrastructure.yaml \
        -f ./docker-compose.dev.extensions.yaml \
        -f ./docker-compose.utils.pgadmin.yaml \
        down --volumes

    echo ""
    echo " Done."
    pause
}

down_apis() {
    docker compose -p "$CORE_PROJECT" \
        -f ./docker-compose.dev.extensions.apis.yaml \
        down --remove-orphans

    echo ""
    echo " Done."
    pause
}

down_all() {
    docker compose -p "$EXTENSIONS_PROJECT" \
        -f ./docker-compose.extensions.infrastructure.yaml \
        -f ./docker-compose.dev.extensions.yaml \
        -f ./docker-compose.utils.pgadmin.yaml \
        down --volumes
    docker compose -p "$CORE_PROJECT" \
        -f ./docker-compose.dev.extensions.apis.yaml \
        down --remove-orphans

    echo ""
    echo " Done."
    pause
}

start_pgadmin() {
    docker compose -p "$EXTENSIONS_PROJECT" \
        -f ./docker-compose.utils.pgadmin.yaml \
        up -d

    echo ""
    echo " Done."
    pause
}

utils() {
    while true; do
        clear
        echo ""
        echo " Utilities:"
        echo "   1. Tear down extensions stack  (Server B)"
        echo "   2. Remove DEMS + DEAPI         (Server A)"
        echo "   3. Tear down all"
        echo "   4. Start pgAdmin               (Server B)"
        echo "   b. Back"
        echo ""
        read -rp " Select option: " util

        case "$util" in
            b|B) return ;;
            1) down_extensions ;;
            2) down_apis ;;
            3) down_all ;;
            4) start_pgadmin ;;
        esac
    done
}

# ---------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------
menu() {
    while true; do
        clear
        echo ""
        echo "============================================================"
        echo " Tazama Extensions Launcher"
        echo "============================================================"
        echo ""
        echo " Server A pre-flight  (run on Server A before Server B):"
        echo "   1. Deploy DEMS + DEAPI  (GitHub builds)"
        echo "   2. Deploy DEMS + DEAPI  (DockerHub images)"
        echo ""
        echo " Server B extensions stack:"
        echo "   3. Deploy extensions    (GitHub builds)"
        echo "   4. Deploy extensions    (DockerHub images)"
        echo ""
        echo "   5. Utilities / teardown"
        echo ""
        read -rp " Select option (1-5), or (q)uit: " choice

        case "$choice" in
            q|Q) exit 0 ;;
            1) deploy_apis "dev" ;;
            2) deploy_apis "hub" ;;
            3) deploy_extensions "dev" ;;
            4) deploy_extensions "hub" ;;
            5) utils ;;
        esac
    done
}

menu
