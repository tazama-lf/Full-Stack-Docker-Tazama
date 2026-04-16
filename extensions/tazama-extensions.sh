#!/bin/bash
# filepath: ./tazama-extensions.sh

cd "$(dirname "$0")"

PGADMIN=false
BUILD_TYPE=""
API_BUILD=""

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
            q|Q) quit ;;
            1) API_BUILD="dev"; check_core ;;
            2) API_BUILD="hub"; check_core ;;
            3) BUILD_TYPE="dev"; pgadmin_prompt ;;
            4) BUILD_TYPE="hub"; pgadmin_prompt ;;
            5) utils ;;
        esac
    done
}

# ---------------------------------------------------------------
# Server A pre-flight: DEMS + DEAPI
# ---------------------------------------------------------------
check_core() {
    if ! docker compose -p tazama-core ps --status running -q 2>/dev/null | grep -q .; then
        echo ""
        echo " ERROR: tazama-core is not running."
        echo "        Start tazama-core.sh on this machine first, then retry."
        echo ""
        read -rp " Press Enter to continue..."
        return
    fi

    if [[ "$API_BUILD" == "dev" ]]; then
        apicmd="docker compose -p tazama-core -f ./docker-compose.dev.extensions.apis.yaml"
    else
        apicmd="docker compose -p tazama-core -f ./docker-compose.hub.extensions.apis.yaml"
    fi

    echo ""
    echo " Running: $apicmd up -d"
    $apicmd up -d
    done_msg
}

# ---------------------------------------------------------------
# Server B extensions stack
# ---------------------------------------------------------------
pgadmin_prompt() {
    clear
    echo ""
    echo " Optional services:"
    echo ""
    read -rp " Include pgAdmin? [y/N]: " addon
    if [[ "${addon,,}" == "y" ]]; then
        PGADMIN=true
    else
        PGADMIN=false
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
            read -rp " Press Enter to continue..."
            return
        fi
    fi

    cmd="docker compose -p tazama-extensions"
    cmd="$cmd -f ./docker-compose.extensions.infrastructure.yaml"
    if [[ "$BUILD_TYPE" == "dev" ]]; then
        cmd="$cmd -f ./docker-compose.dev.extensions.yaml"
    else
        cmd="$cmd -f ./docker-compose.hub.extensions.yaml"
    fi
    if [[ "$PGADMIN" == "true" ]]; then
        cmd="$cmd -f ./docker-compose.utils.pgadmin.yaml"
    fi

    echo ""
    echo " Running: $cmd up -d"
    $cmd up -d
    done_msg
}

# ---------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------
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

down_extensions() {
    docker compose -p tazama-extensions \
        -f ./docker-compose.extensions.infrastructure.yaml \
        -f ./docker-compose.dev.extensions.yaml \
        -f ./docker-compose.utils.pgadmin.yaml \
        down --volumes
    done_msg
}

down_apis() {
    docker compose -p tazama-core \
        -f ./docker-compose.dev.extensions.apis.yaml \
        down --remove-orphans
    done_msg
}

down_all() {
    docker compose -p tazama-extensions \
        -f ./docker-compose.extensions.infrastructure.yaml \
        -f ./docker-compose.dev.extensions.yaml \
        -f ./docker-compose.utils.pgadmin.yaml \
        down --volumes
    docker compose -p tazama-core \
        -f ./docker-compose.dev.extensions.apis.yaml \
        down --remove-orphans
    done_msg
}

start_pgadmin() {
    docker compose -p tazama-extensions \
        -f ./docker-compose.utils.pgadmin.yaml \
        up -d
    done_msg
}

done_msg() {
    echo ""
    echo " Done."
    read -rp " Press Enter to continue..."
}

quit() {
    exit 0
}

menu
        deapi_dems="[X]"
    fi

    if has_opensearch_required_addons_enabled && [[ "$opensearch" != "[X]" ]]; then
        print_color $YELLOW "CMS/TRS/TCS require OpenSearch. Enabling OpenSearch automatically."
        opensearch="[X]"
    fi

    if has_auth_required_addons_enabled && [[ "$auth" != "[X]" ]]; then
        print_color $YELLOW "Authentication is required for CMS/TRS/TCS/DEAPI&DEMS/OpenSearch. Enabling Authentication automatically."
        auth="[X]"
    fi

    local cmd=$(build_docker_command)
    
    echo ""
    print_color $YELLOW "Command to run: $cmd -p tazama up -d"
    echo ""
    read -p "Press (e) to execute, (q) to quit or any other key to go back: " confirm
    echo ""
    
    if [[ "$confirm" == "e" || "$confirm" == "E" ]]; then
        print_color $GREEN "Stopping existing Tazama containers..."
        echo ""
        docker compose -p tazama down --volumes --remove-orphans
        echo ""
        print_color $GREEN "Deploying Tazama..."
        echo ""
        $cmd -p tazama up -d --remove-orphans --force-recreate
        
        echo ""
        print_color $GREEN "✓ Deployment complete!"
        echo ""
        read -p "Press Enter to continue..."
        return 0
    elif [[ "$confirm" == "q" || "$confirm" == "Q" ]]; then
        return 0
    else
        return 1
    fi
}

# Docker utilities menu
show_utils_menu() {
    clear
    echo ""
    print_color $BLUE "Execute some Docker commands:"
    echo ""
    echo "1. Stop and restart ED, TP and TADP (reload network configuration)"
    echo "2. Stop and remove Tazama project containers and volumes"
    echo "3. Remove all unused containers, networks, images and volumes"
    echo "4. List all images"
    echo "5. List all containers"
    echo "6. List all volumes"
    echo "7. List all networks"
    echo ""
    echo "Select function (1-7), (r)eturn or (q)uit"
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

# Consoles menu
show_consoles_menu() {
    clear
    echo ""
    print_color $BLUE "Access a service web console:"
    echo ""
    echo "1. pgAdmin - localhost:15050"
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

# Main loop
while true; do
    show_main_menu
    read -p "Enter your choice: " type
    
    case $type in
        1)
            IS_GITHUB_DEPLOYMENT=1
            IS_FULL_DEPLOYMENT=0
            IS_MULTITENANT_DEPLOYMENT=0
            relay="[X]"
            
            # Addons loop
            while true; do
                show_addons_menu
                read -p "Enter your choice: " choice
                
                case $choice in
                    a|A)
                        if apply_configuration; then
                            break
                        fi
                        ;;
                    r|R)
                        break
                        ;;
                    q|Q)
                        exit 0
                        ;;
                    1)
                        if has_auth_required_addons_enabled && [[ "$auth" == "[X]" ]]; then
                            print_color $YELLOW "Authentication is required while CMS/TRS/TCS/DEAPI&DEMS/OpenSearch is enabled."
                            sleep 1
                        else
                            [[ $IS_MULTITENANT_DEPLOYMENT -ne 1 ]] && toggle_addon "auth"
                        fi
                        ;;
                    2)
                        [[ $IS_MULTITENANT_DEPLOYMENT -ne 1 ]] && toggle_addon "relay"
                        ;;
                    3) toggle_addon "basiclogs" ;;
                    4) 
                        if [[ $IS_MULTITENANT_DEPLOYMENT -ne 1 ]]; then
                            if [[ "$ui" == "[ ]" ]] && has_auth_required_addons_enabled; then
                                print_color $YELLOW "Demo UI cannot be enabled while CMS/TRS/TCS/DEAPI&DEMS/OpenSearch is selected because those require Authentication."
                                sleep 2
                                continue
                            fi
                            if [[ "$ui" == "[ ]" ]]; then
                                ui="[X]"
                                auth="[ ]"
                                relay="[ ]"
                                echo ""
                                print_color $YELLOW "Note: Enabling the Demo UI addon will disable Authentication and Relay services."
                                print_color $YELLOW "You can re-enable these services again, but the Demo UI will not function correctly."
                                echo ""
                                read -p "Press any key to continue..."
                            else
                                ui="[ ]"
                            fi
                        fi
                        ;;
                    5) toggle_addon "natsutils" ;;
                    6) toggle_addon "batchppa" ;;
                    7) toggle_addon "pgadmin" ;;
                    8) toggle_addon "hasura" ;;
                    9)
                        toggle_addon "cms"
                        if [[ "$cms" == "[X]" ]]; then
                            auth="[X]"
                            opensearch="[X]"
                        fi
                        ;;
                    10)
                        toggle_addon "trs"
                        if [[ "$trs" == "[X]" ]]; then
                            auth="[X]"
                            opensearch="[X]"
                        fi
                        ;;
                    11)
                        if [[ "$tcs" == "[ ]" ]]; then
                            tcs="[X]"
                            deapi_dems="[X]"
                            auth="[X]"
                            opensearch="[X]"
                            print_color $YELLOW "TCS requires DEAPI & DEMS, OpenSearch, and Authentication. All were enabled automatically."
                            sleep 1
                        else
                            tcs="[ ]"
                        fi
                        ;;
                    12)
                        if [[ "$deapi_dems" == "[X]" && "$tcs" == "[X]" ]]; then
                            print_color $YELLOW "DEAPI & DEMS cannot be disabled while TCS is enabled."
                            sleep 1
                        else
                            toggle_addon "deapi_dems"
                            [[ "$deapi_dems" == "[X]" ]] && auth="[X]"
                        fi
                        ;;
                    13)
                        if [[ "$opensearch" == "[X]" ]] && has_opensearch_required_addons_enabled; then
                            print_color $YELLOW "OpenSearch cannot be disabled while CMS/TRS/TCS is enabled."
                            sleep 1
                        else
                            toggle_addon "opensearch"
                            [[ "$opensearch" == "[X]" ]] && auth="[X]"
                        fi
                        ;;
                    *)
                        print_color $RED "Invalid choice."
                        sleep 1
                        ;;
                esac
            done
            ;;
        2)
            IS_GITHUB_DEPLOYMENT=0
            IS_FULL_DEPLOYMENT=0
            IS_MULTITENANT_DEPLOYMENT=0
            relay="[X]"
            
            while true; do
                show_addons_menu
                read -p "Enter your choice: " choice
                
                case $choice in
                    a|A)
                        if apply_configuration; then
                            break
                        fi
                        ;;
                    r|R) break ;;
                    q|Q) exit 0 ;;
                    1)
                        if has_auth_required_addons_enabled && [[ "$auth" == "[X]" ]]; then
                            print_color $YELLOW "Authentication is required while CMS/TRS/TCS/DEAPI&DEMS/OpenSearch is enabled."
                            sleep 1
                        else
                            toggle_addon "auth"
                        fi
                        ;;
                    2) toggle_addon "relay" ;;
                    3) toggle_addon "basiclogs" ;;
                    4) 
                        if [[ "$ui" == "[ ]" ]] && has_auth_required_addons_enabled; then
                            print_color $YELLOW "Demo UI cannot be enabled while CMS/TRS/TCS/DEAPI&DEMS/OpenSearch is selected because those require Authentication."
                            sleep 2
                            continue
                        fi
                        if [[ "$ui" == "[ ]" ]]; then
                            ui="[X]"
                            auth="[ ]"
                            relay="[ ]"
                            echo ""
                            print_color $YELLOW "Note: Enabling the Demo UI addon will disable Authentication and Relay services."
                            print_color $YELLOW "You can re-enable these services again, but the Demo UI will not function correctly."
                            echo ""
                            read -p "Press any key to continue..."
                        else
                            ui="[ ]"
                        fi
                        ;;
                    5) toggle_addon "natsutils" ;;
                    6) toggle_addon "batchppa" ;;
                    7) toggle_addon "pgadmin" ;;
                    8) toggle_addon "hasura" ;;
                    9)
                        toggle_addon "cms"
                        if [[ "$cms" == "[X]" ]]; then
                            auth="[X]"
                            opensearch="[X]"
                        fi
                        ;;
                    10)
                        toggle_addon "trs"
                        if [[ "$trs" == "[X]" ]]; then
                            auth="[X]"
                            opensearch="[X]"
                        fi
                        ;;
                    11)
                        if [[ "$tcs" == "[ ]" ]]; then
                            tcs="[X]"
                            deapi_dems="[X]"
                            auth="[X]"
                            opensearch="[X]"
                            print_color $YELLOW "TCS requires DEAPI & DEMS, OpenSearch, and Authentication. All were enabled automatically."
                            sleep 1
                        else
                            tcs="[ ]"
                        fi
                        ;;
                    12)
                        if [[ "$deapi_dems" == "[X]" && "$tcs" == "[X]" ]]; then
                            print_color $YELLOW "DEAPI & DEMS cannot be disabled while TCS is enabled."
                            sleep 1
                        else
                            toggle_addon "deapi_dems"
                            [[ "$deapi_dems" == "[X]" ]] && auth="[X]"
                        fi
                        ;;
                    13)
                        if [[ "$opensearch" == "[X]" ]] && has_opensearch_required_addons_enabled; then
                            print_color $YELLOW "OpenSearch cannot be disabled while CMS/TRS/TCS is enabled."
                            sleep 1
                        else
                            toggle_addon "opensearch"
                            [[ "$opensearch" == "[X]" ]] && auth="[X]"
                        fi
                        ;;
                    *)
                        print_color $RED "Invalid choice."
                        sleep 1
                        ;;
                esac
            done
            ;;
        3)
            IS_GITHUB_DEPLOYMENT=0
            IS_FULL_DEPLOYMENT=1
            IS_MULTITENANT_DEPLOYMENT=0
            relay="[X]"
            
            while true; do
                show_addons_menu
                read -p "Enter your choice: " choice
                
                case $choice in
                    a|A)
                        if apply_configuration; then
                            break
                        fi
                        ;;
                    r|R) break ;;
                    q|Q) exit 0 ;;
                    1)
                        if has_auth_required_addons_enabled && [[ "$auth" == "[X]" ]]; then
                            print_color $YELLOW "Authentication is required while CMS/TRS/TCS/DEAPI&DEMS/OpenSearch is enabled."
                            sleep 1
                        else
                            toggle_addon "auth"
                        fi
                        ;;
                    2) toggle_addon "relay" ;;
                    3) toggle_addon "basiclogs" ;;
                    4) 
                        if [[ "$ui" == "[ ]" ]] && has_auth_required_addons_enabled; then
                            print_color $YELLOW "Demo UI cannot be enabled while CMS/TRS/TCS/DEAPI&DEMS/OpenSearch is selected because those require Authentication."
                            sleep 2
                            continue
                        fi
                        if [[ "$ui" == "[ ]" ]]; then
                            ui="[X]"
                            auth="[ ]"
                            relay="[ ]"
                            echo ""
                            print_color $YELLOW "Note: Enabling the Demo UI addon will disable Authentication and Relay services."
                            print_color $YELLOW "You can re-enable these services again, but the Demo UI will not function correctly."
                            echo ""
                            read -p "Press any key to continue..."
                        else
                            ui="[ ]"
                        fi
                        ;;
                    5) toggle_addon "natsutils" ;;
                    6) toggle_addon "batchppa" ;;
                    7) toggle_addon "pgadmin" ;;
                    8) toggle_addon "hasura" ;;
                    9|10|11|12|13)
                        print_color $YELLOW "These addons are currently available only for Public (GitHub) deployment."
                        sleep 1
                        ;;
                    *)
                        print_color $RED "Invalid choice."
                        sleep 1
                        ;;
                esac
            done
            ;;
        4)
            IS_GITHUB_DEPLOYMENT=0
            IS_FULL_DEPLOYMENT=0
            IS_MULTITENANT_DEPLOYMENT=1
            auth="[X]"
            relay="[X]"
            
            while true; do
                show_addons_menu
                read -p "Enter your choice: " choice
                
                case $choice in
                    a|A)
                        if apply_configuration; then
                            break
                        fi
                        ;;
                    r|R) break ;;
                    q|Q) exit 0 ;;
                    1|2)
                        print_color $YELLOW "Auth and Relay are mandatory for multitenant deployment"
                        sleep 1
                        ;;
                    3) toggle_addon "basiclogs" ;;
                    4)
                        print_color $YELLOW "Demo UI is not available for multitenant deployment"
                        sleep 1
                        ;;
                    5) toggle_addon "natsutils" ;;
                    6) toggle_addon "batchppa" ;;
                    7) toggle_addon "pgadmin" ;;
                    8) toggle_addon "hasura" ;;
                    9|10|11|12|13)
                        print_color $YELLOW "These addons are currently available only for Public (GitHub) deployment."
                        sleep 1
                        ;;
                    *)
                        print_color $RED "Invalid choice."
                        sleep 1
                        ;;
                esac
            done
            ;;
        5)
            # Docker utilities
            while true; do
                show_utils_menu
                read -p "Enter your choice: " choice
                
                case $choice in
                    r|R) break ;;
                    q|Q) exit 0 ;;
                    1)
                        print_color $GREEN "Restarting ED, TP and TADP..."
                        docker restart tazama-tp-1 tazama-tadp-1 tazama-ed-1
                        ;;
                    2)
                        print_color $YELLOW "Stopping and removing Tazama containers and volumes..."
                        docker compose -p tazama down --volumes
                        ;;
                    3)
                        print_color $YELLOW "Removing all unused Docker resources..."
                        docker system prune -a -f --volumes
                        ;;
                    4)
                        docker image ls
                        ;;
                    5)
                        docker container ls
                        ;;
                    6)
                        docker volume ls
                        ;;
                    7)
                        docker network ls
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
            ;;
        6)
            # Database utilities
            while true; do
                show_dbutils_menu
                read -p "Enter your choice: " choice
                
                case $choice in
                    r|R) break ;;
                    q|Q) exit 0 ;;
                    1)
                        print_color $GREEN "Listing PostgreSQL databases..."
                        docker exec -it tazama-postgres-1 psql -U postgres -c "\l"
                        ;;
                    2)
                        print_color $GREEN "Listing PostgreSQL tables..."
                        for db in event_history raw_history configuration evaluation; do
                            echo ""
                            print_color $CYAN "=== $db ==="
                            docker exec -it tazama-postgres-1 psql -U postgres -d $db -c "\dt" 2>/dev/null || echo "  (database not found)"
                        done
                        ;;
                    3)
                        echo ""
                        print_color $YELLOW "WARNING: This will reset all Hasura metadata!"
                        read -p "Continue? (y/n): " confirm
                        
                        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                            print_color $GREEN "Stopping Hasura containers..."
                            docker stop tazama-hasura-1 tazama-hasura-init-1 2>/dev/null || true
                            
                            print_color $GREEN "Removing Hasura containers..."
                            docker rm tazama-hasura-1 tazama-hasura-init-1 2>/dev/null || true
                            
                            print_color $GREEN "Dropping Hasura metadata database..."
                            docker exec tazama-postgres-1 psql -U postgres -c "DROP DATABASE IF EXISTS hasura;"
                            docker exec tazama-postgres-1 psql -U postgres -c "CREATE DATABASE hasura;"
                            
                            print_color $GREEN "✓ Hasura metadata reset complete!"
                        fi
                        ;;
                    4)
                        print_color $GREEN "Reinitializing Hasura..."
                        docker restart tazama-hasura-init-1
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
            ;;
        7)
            # Consoles
            while true; do
                show_consoles_menu
                read -p "Enter your choice: " choice
                
                case $choice in
                    r|R) break ;;
                    q|Q) exit 0 ;;
                    1)
                        print_color $GREEN "Opening pgAdmin..."
                        open_url "http://localhost:15050"
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
            ;;
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