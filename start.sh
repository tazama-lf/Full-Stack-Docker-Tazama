#!/bin/bash

is_github_deployment=0

declare -A addons=(
    [1]="Authentication"
    [2]="Basic (stdout) Logging"
    [3]="[Elastic] Logging"
    [4]="[Elastic] APM"
    [5]="Demo UI"
    [6]="Relay"
)

declare -A addon_files_dev=(
    [1]="docker-compose.dev.auth.yaml -f docker-compose.auth.base.yaml"
    [2]="docker-compose.dev.logs-base.yaml -f docker-compose.logs.yaml"
    [3]="docker-compose.dev.logs-elastic.yaml -f docker-compose.logs-elastic.base.yaml"
    [4]="docker-compose.dev.apm-elastic.yaml"
    [5]="docker-compose.dev.ui.yaml -f docker-compose.dev.ui.override.yaml"
    [6]="docker-compose.dev.relay.yaml"
)

declare -A addon_files=(
    [1]="docker-compose.auth.yaml -f docker-compose.auth.base.yaml"
    [2]="docker-compose.logs-base.yaml -f docker-compose.logs.yaml"
    [3]="docker-compose.logs-elastic.yaml -f docker-compose.logs-elastic.base.yaml"
    [4]="docker-compose.dev.apm-elastic.yaml"
    [5]="docker-compose.dev.ui.yaml -f docker-compose.dev.ui.override.yaml"
    [6]="docker-compose.relay.yaml"
)

declare -A selected

deploy_full_service() {
    echo "stopping existing tazama containers..."
    docker compose -p tazama down > /dev/null 2>&1
    echo "deploying Tazama from docker hub..."
    docker compose -p tazama -f docker-compose.yaml -f docker-compose.override.yaml -f docker-compose.db.yaml -f docker-compose.full.yaml -f docker-compose.relay.yaml -f docker-compose.dev.ui.yaml up -d
    exit 0
}

print_menu() {
    clear
    echo "Select docker deployment type:"
    echo "1. Public - (GitHub)"
    echo "2. Full-service (DockerHub)"
    echo "3. Public (DockerHub)"
    # echo "2. Advanced"
    echo
    echo "Choose (1-3) or quit (q):"
}

handle_menu() {
    local type
    read -p "Enter your choice: " type
    case $type in
        1) 
        print_addon_menu
        is_github_deployment=1
        ;;
        2)
        deploy_full_service
        is_github_deployment=2
        # Advanced: Not Yet Implemented
#        print_menu
        ;;
        3)
        print_addon_menu
        is_github_deployment=3
        ;;
        Q | q) 
        exit 0
        ;;
        *)
        print_menu
        ;;
    esac
}

print_addon_menu() {
    clear
    echo "Enable optional docker configuration addons:"
    for ((i = 1; i <= ${#addons[@]}; i++)); do
        if [[ ${selected[$i]} == 1 ]]; then
            echo "$i. [X] ${addons[$i]}"
        else
            echo "$i. [ ] ${addons[$i]}"
        fi
    done
    echo 
}

build_command() {
    local cmd=" -f docker-compose.override.yaml -f docker-compose.dev.db.yaml"
    if [[ $is_github_deployment == 1 ]]; then
        cmd+=" -f docker-compose.dev.rule.yaml -f docker-compose.dev.yaml"
        for key in "${!addon_files_dev[@]}"; do
            [[ ${selected[$key]} == 1 ]] && cmd+=" -f ${addon_files_dev[$key]}"
        done
    else
        cmd+=" -f docker-compose.rule.yaml -f docker-compose.yaml"
        for key in "${!addon_files[@]}"; do
            [[ ${selected[$key]} == 1 ]] && cmd+=" -f ${addon_files[$key]}"
        done
    fi
    echo "$cmd"
}

apply_addon_config() {
    local confirm=""
    local compose_files=$(build_command)
    echo 
    echo "Command to run: docker compose$compose_files -p tazama up -d"
    read -p "Press (e) to execute, (q) to quit or any other key to go back: " confirm
    echo
    if [[ -z $confirm || $confirm == "e" ]]; then
        docker compose$compose_files -p tazama up -d --remove-orphans
        exit 0
    elif [[ $confirm == "q" ]]; then
        exit 0
    fi
}

print_menu
handle_menu

while true; do  
    echo "Apply current selection (a), Toggle addon (1-6) or quit (q)"
    read -p "Enter your choice: " choice

    case "$choice" in
    [1-6])
        if [[ ${selected[$choice]} == 1 ]]; then
            selected[$choice]=0
        else
            selected[$choice]=1
        fi
        ;;
    A | a)
        apply_addon_config
        ;;
    Q | q)
        exit 0
        ;;
    *)
        echo "Invalid option. Press any key to continue..."
        read -n 1
        ;;
    esac
    print_addon_menu
done
