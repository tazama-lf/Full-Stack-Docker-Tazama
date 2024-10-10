#!/bin/bash

declare -A addons=(
    [1]="Authentication"
    [2]="Basic (stdout) Logging"
    [3]="[Elastic] Logging"
    [4]="[Elastic] APM"
    [5]="UI"
)

declare -A addon_files=(
    [1]="docker-compose.dev.auth.yaml"
    [2]="docker-compose.dev.logs-base.yaml"
    [3]="docker-compose.dev.logs-elastic.yaml"
    [4]="docker-compose.dev.apm-elastic.yaml"
    [5]="docker-compose.ui.yaml"
)

declare -A selected

print_menu() {
    clear
    echo "Select docker deployment type:"
    echo "1. Standard (Public)"
    # echo "2. Advanced"
    echo
    echo "Choose (1) or quit (q):"
}

handle_menu() {
    local type
    read -p "Enter your choice: " type
    case $type in
        1) 
        print_addon_menu
        ;;
        2)
        # Advanced: Not Yet Implemented
        print_menu
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
    local cmd=" -f docker-compose.yaml -f docker-compose.override.yaml"
    for key in "${!addon_files[@]}"; do
        [[ ${selected[$key]} == 1 ]] && cmd+=" -f ${addon_files[$key]}"
    done
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
    echo "Apply current selection (a), Toggle addon (1-5) or quit (q)"
    read -p "Enter your choice: " choice

    case "$choice" in
    [1-5])
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
