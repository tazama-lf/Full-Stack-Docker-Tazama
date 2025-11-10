<!-- SPDX-License-Identifier: Apache-2.0 -->

<a id="top"></a>

<h1></h1>
<h1 style="color: red;">WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.</h1>

- [1. INTRODUCTION](#1-introduction)
- [2. PRE-REQUISITES](#2-pre-requisites)
- [3. INSTALLATION STEPS](#3-installation-steps)
  - [3.1. Clone the Full-Stack-Docker-Tazama repository to your local machine](#31-clone-the-full-stack-docker-tazama-repository-to-your-local-machine)
  - [3.2. Using the Tazama installation script for menu-driven deployment](#32-using-the-tazama-installation-script-for-menu-driven-deployment)
  - [3.3. Interacting with your deployment via Postman](#33-interacting-with-your-deployment-via-postman)
  - [3.4. Docker utilities](#34-docker-utilities)
  - [3.5. Database Utilities](#35-database-utilities)
  - [3.6. Consoles](#36-consoles)
  - [3.7. Accessing deployed components](#37-accessing-deployed-components)
- [4. OVERVIEW OF SERVICES](#4-overview-of-services)
- [5. TESTING THE END-TO-END DEPLOYMENT](#5-testing-the-end-to-end-deployment)
- [6. TROUBLESHOOTING TIPS](#6-troubleshooting-tips)
- [7. APPENDIX](#7-appendix)
  - [7.1. Manual post-deployment system configuration](#71-manual-post-deployment-system-configuration)
  - [7.2. Exporting the Keycloak Tazama realm](#72-exporting-the-keycloak-tazama-realm)
  - [7.3. Docker Compose YAML structure](#73-docker-compose-yaml-structure)

<h1></h1>
<h1 style="color: red;">WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.</h1>

For production deployment instructions:
 - [On-Premise Detailed Installation Guide](https://github.com/tazama-lf/On-Prem-helm)
 - [AWS Detailed Installation Guide](https://github.com/tazama-lf/EKS-helm)
 - [Google Cloud Detailed Installation Guide](https://github.com/tazama-lf/GKE-helm)
 - [Azure Detailed Installation Guide](https://github.com/tazama-lf/AKS-helm)

# 1. INTRODUCTION

This guide will show you how to install the Tazama system, using only the publicly available open source software components, in a collection of Docker containers on a single local machine. This is a multi-layered docker compose stack which spins up Tazama components. A Windows [batch script](tazama.bat) and a MacOS/Unix [shell script](tazama.sh) have been provided which may be used to start containers that are usually used together in Tazama.

This guide is largely written by Windows users from the perspective of a Windows user, but should be able to broadly follow the steps to implement Tazama on Linux/MacOS as well.

# 2. PRE-REQUISITES

The pre-requisites that are essential to be able to follow this guide to the letter are:

- Git
- Code editor (this guide will assume you are using VS Code)
- Docker Desktop for Windows (and WSL) (or Linux/MacOS equivalent)
- GitHub personal access token

> [!NOTE] **Notes on GitHub personal access token**
> - A GitHub personal access token must be created with `packages:write` and `read:org` permissions
> - Ensure that your GitHub Personal Access Token is added as a Windows Environment Variable called "`GH_TOKEN`"
> - We will be referencing your GitHub Personal Access Token throughout the installation process as your `GH_TOKEN`. It is not possible to retrieve the token from GitHub after you initially created it, but if the token had been set in Windows as an environment variable, you can retrieve it with the following command from a Windows Command prompt: `set GH_TOKEN`
> - If your GitHub Personal Access Token had not been added as a Windows Environment Variable, you would need to specify the token at the top of the `full-stack-docker-tazama/.env` file next to the GH_TOKEN key. If you had specified the GH_TOKEN as an environment variable, you can leave the `${GH_TOKEN}` shell variable in place to retrieve it automatically.

Instructions for installing the dependencies and setting up the GH_TOKEN environment variable can be found in the [Development Environment Set up Guide](https://github.com/tazama-lf/docs/blob/dev/Guides/dev-set-up-environment.md)

<div style="text-align: right"><a href="#top">Top</a></div>

# 3. INSTALLATION STEPS

## 3.1. Clone the Full-Stack-Docker-Tazama repository to your local machine  

In a Windows Command prompt, navigate to the folder where you want to store a copy of the source code. For example, the source code root folder path I have been using to compile this guide is `C:\Tazama\GitHub`. Once in your source code root folder, clone (copy) the repository with the following command:

```
git clone https://github.com/tazama-lf/Full-Stack-Docker-Tazama -b main
```

If you would like to deploy the system from the `dev` branch, replace `main` above with `dev`. The `main` branch is the most recent official release of the system, while `dev` will be new features not yet released to the main branch.

**Output:**

```text
C:\Tazama\GitHub>git clone https://github.com/tazama-lf/Full-Stack-Docker-Tazama
Cloning into 'Full-Stack-Docker-Tazama'...
remote: Enumerating objects: 1353, done.
remote: Counting objects: 100% (578/578), done.
remote: Compressing objects: 100% (291/291), done.
remote: Total 1353 (delta 338), reused 390 (delta 248), pack-reused 775 (from 1)
Receiving objects: 100% (1353/1353), 2.12 MiB | 2.80 MiB/s, done.
Resolving deltas: 100% (779/779), done.

C:\Tazama\GitHub>
```

## 3.2. Using the Tazama installation script for menu-driven deployment

First, start the Docker Desktop for Windows application.

With Docker Desktop running: from your Windows Command prompt and from inside the `Full-Stack-Docker-Tazama` folder, execute the following command and follow the prompts:

**Windows**  
 - Command prompt: `tazama.bat` 
 - Powershell: `.\tazama.bat`

**Unix (Linux/MacOS)**
 - Any terminal: `./tazama.sh`

> [!NOTE] IMPORTANT
> Ensure the shell script has the correct permissions to run. You may need to run `chmod +x tazama.sh` beforehand.

**Output:**

```text
Select docker deployment type:

1. Public (GitHub)
2. Public (DockerHub)
3. Full-service (DockerHub)
4. Multi-Tenant Public (DockerHub)
5. Docker Utilities
6. Database Utilities
7. Consoles

Select option (1-7), or (q)uit:
Enter your choice:
```

This menu offers a convenient way to trigger various Tazama deployment options. To make a selection to install Tazama in the specified manner, type `1`, `2`, `3`, or `4` at the "Enter your choice:" prompt and press ENTER.

We'll talk more about options `5`, `6`, and `7` a little later.

### 1. Public (GitHub)

This option deploys Tazama from publicly available repositories on the [Tazama Public GitHub](https://github.com/tazama-lf).

You can specify the specific branches for specific components you want to deploy by updating the `Full-Stack-Docker-Tazama/.env` and changing the default branch specified for the component.

Navigate to the Full-Stack-Docker-Tazama folder and launch VS Code:

**Output:**

```text
C:\Tazama\GitHub>cd Full-Stack-Docker-Tazama

C:\Tazama\GitHub\Full-Stack-Docker-Tazama>code .
```

In VS Code, open the .env file in the Full-Stack-Docker-Tazama folder and update the branches in the `.env` file for these services as required:

```ini
# Branches
ADMIN_BRANCH=main
TMS_BRANCH=main
ED_BRANCH=main
RULE_901_BRANCH=main
RULE_902_BRANCH=main
TP_BRANCH=main
TADP_BRANCH=main
NATS_UTILITIES_BRANCH=main
CMS_BRANCH=main
BATCH_PPA_BRANCH=main
RELAY_BRANCH=main

SIDECAR_BRANCH=main
LUMBERJACK_BRANCH=main

AUTH_SERVICE_BRANCH=main
EVENT_FLOW_BRANCH=main
```

The `.env` file is configured to deploy services out of the same Tazama branch as the current selected branch of the cloned `Full-Stack-Docker-Tazama` repository.

### 2. Public (DockerHub)
This option facilitates a public deployment of only the basic core services and a single sample rule-901 processor using pre-built images published on DockerHub. This option is similar to option 1 but instead of building the images from the GitHub source code that are then compiled locally, the deployment is from DockerHub images.

The [tazamaorg DockerHub](https://hub.docker.com/u/tazamaorg) contains pre-built images from both the GitHub `dev` branch as release candidate `rc` images and from the GitHub `main` branch as final release `latest` images.

To select which of these images to deploy, you can edit the `Full-Stack-Docker-Tazama/.env` file and update the `TAZAMA_VERSION` environment variable to either `rc` or `latest`, or a specific version, such as `3.0.0`.

The `.env` file is configured to deploy services out of the same images that are associated with Tazama branch as the current selected branch of the cloned `Full-Stack-Docker-Tazama` repository (`rc` for `dev` and `latest` for `main`).

### 3. Full-service (DockerHub)
This option facilitates a public "full-service" deployment of the basic core services and all Tazama rule processors using pre-built images published on DockerHub. The rule processors are configured with a basic non-descript configuration and composed into a single illustrative typology.

As with the Public (DockerHub) deployment above, you also have the ability to choose an `rc` or `latest` release deployment by updating the `Full-Stack-Docker-Tazama/.env` file.

### 4. Multi-Tenant Public (DockerHub)
This option allows the deployment of an example multi-tenant instance of Tazama based on the Public (DockerHub) deployment for two separate tenants: tenant-001 and tenant-002. Each tenant has its own separate configurations, and authentication set up via KeyCloak to access the system fully segregated.

As with the Public (DockerHub) deployment above, you also have the ability to choose an `rc` or `latest` release deployment by updating the `Full-Stack-Docker-Tazama/.env` file.

### Additional deployment options

On the selection of any of the deployment types from the main Tazama script menu, you will be presented with a number of additional options for your deployment on a new menu:

```text
Enable optional deployment configuration addons:

CORE ADDONS:

1. [ ] Authentication
2. [ ] Relay Services (NATS)
3. [ ] Basic Logs
4. [ ] Demo UI

UTILITY ADDONS:

5. [ ] NATS Utilities
6. [ ] Batch PPA
7. [X] pgAdmin for PostgreSQL
8. [X] Hasura GraphQL API for PostgreSQL

Toggle addons (1-8), (a)pply current selection, (r)eturn, or (q)uit
Enter your choice:
```

You can toggle any of the options on or off by entering the number related to the option at the "Enter your choice:" prompt and pressing ENTER. A selected option will then be tagged with an "X" and the "X" will be removed from a deselected option.

#### Authentication

This option deploys the Tazama authentication sub-system on top of the selected deployment type, including:
 - Keycloak
 - Tazama Authentication Service API

The multi-tenant deployment is dependent on this service and if you are deploying a multi-tenant instance, this service cannot be deselected.

#### Relay Services (NATS)

This option is selected by default and can be deselected for non-multi-tenant deployments.

This option deploys the Tazama results relay services on top of the selected deployment type, including:
 - a relay service for event-flow processor egress to facilitated blocking based on prevalent account or entity conditions
 - a relay service for typology processor egress to facilitate transaction interdiction based on detected fraud
 - a relay service for transaction aggregation and decisioning processor (TADProc) egress to facilitate the propagation of investigation alerts

Only NATS-to-NATS relay services are accommodated in the Tazama full-stack deployment, although other relay services are available for NATS-to-REST, NATS-to-Kafka, and NATS-to-RabbitMQ.

Most deployment test collections rely on the deployment of the  relay-services and the NATS-utilities to intercept relayed messages. It is recommended that these are toggled on by default in your deployment. If you do choose to turn these off, some of the Postman tests may fail.

The multi-tenant deployment test collection is dependent on this service and if you are deploying a multi-tenant instance, this service cannot be deselected.

#### Basic Logs

This option deploys the Tazama logging sub-system on top of the selected deployment type, including:
 - The integrated event sidecar service for all processors
 - The Tazama Lumberjack logging service for log aggregation and presentation. You will be able to view logs shipped out of your Tazama full-stack deployment processors in Lumberjack's container log in Docker.

#### Demo UI

This option will deploy the Tazama Demo User Interface contained and described in the [Demo UI repository](https://github.com/tazama-lf/tazama-demo) repository.

> [!NOTE]
> The Tazama Demo UI is being updated to support Tazama 3.0.0 and will be released shortly.

#### NATS Utilities

This option is selected by default and can be deselected.

This option will deploy the [NATS REST Proxy service](https://github.com/tazama-lf/nats-utilities) that will allow API-based access to internal Tazama processors for testing purposes.

#### Batch Payment Platform Adapter

This option will deploy the [Batch Payment Platform Adapter service](https://github.com/tazama-lf/batch-ppa) that will provide an API for batched transaction data take-on for bulk ingestion and evaluation purposes.

#### pgAdmin for PostgreSQL

This option is selected by default and can be deselected.

[pgAdmin](https://www.pgadmin.org/) provides a powerful console and user interface for PostgreSQL and can be deployed on top of your Tazama instance in support of development and testing activities.

> [!NOTE]
> **pgAdmin is not recommended for deployment as part of your production deployment of Tazama.**

#### Hasura GraphQL API for PostgreSQL

This option is selected by default and can be deselected.

PostgreSQL does not provide native API support, though API support is extremely useful for development and testing purposes. For this reason we have included [Hasura GraphQL Engine](https://hasura.io/) to provide a GraphQL overlay for PostgreSQL in your Tazama instance.

> [!NOTE]
> **Hasura is not recommended for deployment as part of your production deployment of Tazama.**

### 3.3. Interacting with your deployment via Postman

Our Postman repository offers a number of test collections to interact with the various deployment options available in the Tazama full-stack, presented here:

[Postman - The Files](https://github.com/tazama-lf/postman#the-files)

[Postman regression testing checklist](https://github.com/tazama-lf/postman#the-files) - This section describes the required deployment options that best suit each of the test collections.

### 3.4. Docker utilities

This collection of menu options provide a number of useful Docker commands as shortcuts to having to remember them yourself:

```text
Execute some Docker commands:

1. Stop and restart ED, TP and TADP (reload network configuration)
2. Stop and remove Tazama project containers and volumes
3. Remove all unused containers, networks, images and volumes
4. List all images
5. List all containers
6. List all volumes
7. List all networks

Select function (1-7), (r)eturn or (q)uit
Enter your choice:
```

The menu options are fairly self-explanatory, but the first menu option, "Stop and restart ED, TP and TADP (reload network configuration)" is worth calling out. When you deploy a new network map to Tazama, you will need to restart the Event Director, Typology, and Transaction Aggregation and Decisioning processors to adopt the new network map 

(we're working on a more elegant way to reload a configuration at startup, but until then restarting the processors is the only way to load the updated network map.)

### 3.5. Database Utilities

These commands access the Tazama PostgreSQL container directly to report on the setup of the database:

```text
Database utilities:

1. List all PostgreSQL databases
2. List all PostgreSQL tables in all databases
3. Reset Hasura metadata
4. Reinitialize Hasura

Select function (1-3), (r)eturn or (q)uit
Enter your choice:
```

Of particular note here is option 4: "Reinitialize Hasura". Occasiocally, due to some contention for database connections in PostgreSQL, Hasura does not properly expose all of its required API services. Short of reloading the entire Tazama full-stack, we find sometimes just reloading the Hasura Initialization routine is good enough to get everything working.

### 3.6. Consoles

This menu option provides shortcuts to some of the consoles we typically use for testing or development tasks:

```text
Access a service web console:

1. pgAdmin - localhost:15050
2. hasura - localhost:6100
3. Keycloak - localhost:8080
4. TMS-service Swagger - localhost:5000/documentation
5. Admin-service Swagger - localhost:5100/documentation

Select function (1-5), (r)eturn or (q)uit
Enter your choice:
```

### 3.7. Accessing deployed components

You'll be able to access the web interfaces for the deployed components through their respective default TCP/IP ports on your local machine as defined in various Docker Compose YAML files.

#### Tazama Core Processors
 - Tazama TMS API: <http://localhost:5000>
 - Tazama Admin Service API: <http://localhost:5100>
 - Tazama Authentication Service API: <http://localhost:3020>
#### Tazama Core Services
 - PostgresSQL: <http://localhost:15432>
 - NATS: <http://localhost:14222> | <http://localhost:16222> | <http://localhost:18222>
 - Valkey: <http://localhost:16379> 
#### Tazama Test Services
 - pgAdmin: <http://localhost:1050>
 - Hasura: <http://localhost:6100>

If your machine is open to your local area network, you will also be able to access these services from other computers on your network via your local machine's IP address, with the exception of KeyCloak where the console _must_ be accessed on `localhost`.

<div style="text-align: right"><a href="#top">Top</a></div>

# 4. Overview of services

Tazama core services provides the foundational infrastructure components for the system and includes the Postgres, NATS and Valkey services: Postgres provides the database infrastructure, NATS provides the pub/sub functionality and Valkey provides for fast in-memory processor data caching.

Tazama is configured by loading the network map, rules and typology configurations required to evaluate a transaction. The steps above have already loaded the appropriate configuration into the database for each selected deployment option.

For an optional step to load a Tazama configuration manually, follow the instructions in the [Appendix - Manual post-deployment system configuration](#manual-post-deployment-system-configuration).

Following the steps above, you should now have a fully-functional instance of Tazama up and running. Tazama includes the core services referenced above, as well as the core processors below, and one or more rule processors.

The core processors include:

 - The Transaction Monitoring Service API at `<https://localhost:5000>`, where messages will be sent for evaluation.
 - The Event Director that will handle message routing based on the network map.
 - The Typology Processor that will summarise rule results into scenarios according to individual typology configurations.
 - The Transaction Aggregation and Decisioning Processor that will wrap up the evaluation of a transaction and publish any alerts for breached typologies.
 - The Admin Services API that will facilitate condition management and configuration management.
 - The Event-Flow Rule Processor that implements account- and entity-specific condition handling.

You can test that the TMS API was successfully deployed with the following command from a Windows Command prompt:

```
curl localhost:5000
```

**Output:**

```text
{"status":"UP"}
```

<div style="text-align: right"><a href="#top">Top</a></div>

# 5. TESTING THE END-TO-END DEPLOYMENT

Now, if everything went according to plan, you'll be able to submit a test transaction to the Transaction Monitoring Service API and then be able to see the result of a complete end-to-end evaluation in the database. 

If you have not already done so, clone the postman repository. In a Windows Command prompt, navigate to the source code root folder. Then clone the postman repository with the following command:
```text
git clone https://github.com/tazama-lf/postman -b main
```

**Output:**

```text
C:\Tazama\GitHub>git clone https://github.com/tazama-lf/postman -b main
Cloning into 'postman'...
remote: Enumerating objects: 2240, done.
remote: Counting objects: 100% (1059/1059), done.
remote: Compressing objects: 100% (276/276), done.
remote: Total 2240 (delta 960), reused 789 (delta 783), pack-reused 1181 (from 2)
Receiving objects: 100% (2240/2240), 2.66 MiB | 2.77 MiB/s, done.
Resolving deltas: 100% (1422/1422), done.

C:\Tazama\GitHub>
```
Change directory to the `postman` folder:

```text
C:\Tazama\GitHub>cd postman

C:\Tazama\GitHub\postman>
```

We can run one of the following Postman test collections via Newman CLI from the `postman` repository folder to see if our deployment was successful:

### Basic GitHub Public deployment
```
newman run "newman/Newman - 1.1. (NO-AUTH) Public GitHub End-to-End Test.postman_collection.json" -e "environments/Tazama-Docker-Compose.postman_environment.json" --timeout-request 10200 --delay-request 500
```

### Basic DockerHub Public deployment
```
newman run "newman/Newman - 2.1. (NO-AUTH) Public DockerHub End-to-End Test.postman_collection.json" -e "environments/Tazama-Docker-Compose.postman_environment.json" --timeout-request 10200 --delay-request 500
```

### Basic Full-Service Public deployment
```
newman run "newman/Newman - 3.1. (NO-AUTH) Public DockerHub Full-Service Test.postman_collection.json" -e "environments/Tazama-Docker-Compose.postman_environment.json" --timeout-request 10200 --delay-request 500
```

### Basic Multi-Tenancy deployment
**For Tenant-001:**
```
newman run "newman/Newman - 4.1. (AUTH) Public GitHub End-to-End test - tenant-001.postman_collection.json" -e "environments/Tazama-Docker-Compose.postman_environment.json" --timeout-request 10200 --delay-request 500
```
**For Tenant-002:**
```
newman run "newman/Newman - 4.2. (AUTH) Public GitHub End-to-End test - tenant-002.postman_collection.json" -e "environments/Tazama-Docker-Compose.postman_environment.json" --timeout-request 10200 --delay-request 500
```

> [!NOTE]
>
> The Newman CLI itself cannot inherently handle the `await` keyword directly within Postman's pre-request and test scripts in the same way modern JavaScript environments, and the Postman App, do by default. The tests provided here are stripped-down basic tests specifically created for Newman, but the Postman test collections can be executed inside the Postman App for a more comprehensive test of an associated deployment.

Check the [Postman repository readme](https://github.com/tazama-lf/postman#the-files) for more test collections to find one that relates to your specific deployment options.

**Example output for the Public (DockerHub) deployment and tests:**

```text
┌─────────────────────────┬──────────────────┬──────────────────┐
│                         │         executed │           failed │
├─────────────────────────┼──────────────────┼──────────────────┤
│              iterations │                1 │                0 │
├─────────────────────────┼──────────────────┼──────────────────┤
│                requests │                4 │                0 │
├─────────────────────────┼──────────────────┼──────────────────┤
│            test-scripts │                8 │                0 │
├─────────────────────────┼──────────────────┼──────────────────┤
│      prerequest-scripts │                8 │                0 │
├─────────────────────────┼──────────────────┼──────────────────┤
│              assertions │               39 │                0 │
├─────────────────────────┴──────────────────┴──────────────────┤
│ total run duration: 2.6s                                      │
├───────────────────────────────────────────────────────────────┤
│ total data received: 5.14kB (approx)                          │
├───────────────────────────────────────────────────────────────┤
│ average response time: 26ms [min: 10ms, max: 36ms, s.d.: 9ms] │
└───────────────────────────────────────────────────────────────┘
```
<div style="text-align: right"><a href="#top">Top</a></div>

# 5. TROUBLESHOOTING TIPS

### If you want to restart or alter certain processors 

Start/Restart individual services with
`docker compose up -p tazama -d --force-recreate <service>`    

Try running following if changes are not reflecting  
`docker compose up -p tazama -d --build --force-recreate`  

You can trash your container followed by deleting the image in docker if none of the above works.  

### Stopping individual (or multiple) services  
`docker compose down <service> <service2> <service3>`

To easily idetify the name of a service, perform a

`docker container ls` command and use the part of the container name between the `tazama-` and the `-1`, for example:

If the container name is `tazama-rstadp-1`, the service name is `rstadp`.

### If Postman failing to connect to PostgreSQL when performing tests

Check the Docker container console lots for the `tazama-hasura-init-1` container.

Check for any failed initializations, for example:

```text
==========================================
Adding Data Sources
==========================================
→ Adding event_history database
  ✓ Success
→ Adding raw_history database
  ✗ Failed
→ Adding configuration database
  ✓ Success
→ Adding evaluation database
  ✓ Success
```

Here, adding the raw-history database source failed.

If there are any failures, restart the `tazama-hasura-init-1` container, either in Docker Desktop, or with:

`docker restart tazama-hasura-init-1`

<div style="text-align: right"><a href="#top">Top</a></div>

# 6. APPENDIX

## Manual post-deployment system configuration
This appendix will show you how to manually load the configuration and environment files in the Tazama full-stack Docker deployment for the deployment of the private rule and typology configurations.

This configuration is intended to override the default full-service configuration and relies on the deployment of the full-service stack (Option 3 from the Tazama script menu).

In a Windows Command prompt, navigate to your source code root folder. Then clone the `tms-config` following repository with the following command:
```
git clone https://github.com/frmscoe/tms-configuration -b main
```
> [!NOTE]
> You must be a member of the Tazama `frmscoe` organization to access this repository. If you are not yet a member, please contact the Tazama Product team.

Import the `tms-config` test collection from the `/default` folder into your Postman App. This collection interacts with the PostgreSQL database via Hasura and will not work from Newman CLI due to Newman's inability to handle `await`.

Run the `tms-config` with the Tazama Docker Compose environment selected and set up for your deployment.

The test collection will remove all current configurations and will deploy the private rule and typology configuration as a replacement.

After the deployment, you will have to restart the Event Director, Typology Processor and Transaction Aggregation and Decisioning Processor containers to load the updated network map.

The `tms-config` repository also contains a `tms-config-test` collection in the `/default` folder that you can import and run to ensure that the configuration was properly installed and activated.

<div style="text-align: right"><a href="#top">Top</a></div>

## Exporting the Keycloak Tazama realm
The Keycloak export option provided in the Keycloak Administration Console does not deliver a complete export of the Tazama realm. To export the Tazama realm completely, including all roles, users and groups, you will need to follow these steps to use the Keycloak CLI which is located in the Keycloak docker container.

To perform these steps, you must have deployed the Tazama full-stack with the Authentication services selected.

### Step 1
From your Command prompt, connect to the Keyclock container's bash with this command:

```
docker exec -it tazama-keycloak-1 bash
```

 - `tazama-keycloak-1` is the default Keycloak container name for the full-stack deployment.

### Step 2
After connecting, you must change directory to the /opt/keycloak folder:

```
cd /opt/keycloak
```

and then run the following command to export the current Tazama realm:

```
bin/kc.sh export --file tazama-realm-export.json --realm tazama --users realm_file
```

 - `tazama-realm-export.json` is the name of the file where the export will be exported to.
 - `tazama` is the name of the realm to export. You must specify the realm, otherwise all realms will be exported as an array and an import via Docker Compose will fail.
 - Set the `--users realm_file` option to embed the user information in the same file.

For help or other options, run:

```
bin/kc.sh export --help
```

### Step 3
With the realm export successfully completed, you can copy the file from inside the container to your local system.

First exit the container with:

```
exit
```

and then execute the following command from your Command prompt:

```
docker cp tazama-keycloak-1:/opt/keycloak/tazama-realm-export.json tazama-realm-export.json
```

 - `tazama-keycloak-1` is the default Keycloak container name for the full-stack deployment.
 - `/opt/keycloak/` is the folder where the export is located.
 - `tazama-realm-export.json` is the name of the file where the export was exported to.

You will now have a local copy of the entire Keycloak Tazama realm.

### Step 4 (optional)

If you want your exported realm to be loaded in the Tazama full-stack when a new stack is composed, you will need to replace the file:

`auth/keycloak/realms/00-tazama-test-realm.json`

in your `full-stack-docker-tazama` repository folder, or you must update the volume string in the `docker-compose.base.auth.yaml` file, for example:

```yaml
    volumes:
      - ./tazama-realm-export.json:/opt/keycloak/data/import/00-tazama-test-realm.json
```

(This change assumes you exported the new realm to the root of the `full-stack-docker-tazama` repository folder.)

<div style="text-align: right"><a href="#top">Top</a></div>

## Docker Compose YAML structure

View this file for additional detail about the various Docker Compose YAML files and how they are structured and related: [Docker Compose YAML Structure Overview](./docker-yaml-structure.md)

<div style="text-align: right"><a href="#top">Top</a></div>
