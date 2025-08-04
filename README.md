<!-- SPDX-License-Identifier: Apache-2.0 -->

<a id="top"></a>

- [FULL STACK DOCKER DEPLOYMENT](#full-stack-docker-deployment)
  - [1. INTRODUCTION](#1-introduction)
  - [2. PRE-REQUISITES](#2-pre-requisites)
  - [3. INSTALLATION STEPS](#3-installation-steps)
    - [3.1. Clone the Full-Stack-Docker-Tazama Repository to Your Local Machine](#31-clone-the-full-stack-docker-tazama-repository-to-your-local-machine)
    - [3.2. Update the Full-Stack-Docker-Tazama Configuration Files (optional)](#32-update-the-full-stack-docker-tazama-configuration-files-optional)
    - [3.3. Deploy the services via script](#33-deploy-the-services-via-script)
    - [3.4. Access deployed components](#34-access-deployed-components)
    - [3.5. Overview of services](#35-overview-of-services)
  - [4. TESTING THE END-TO-END DEPLOYMENT](#4-testing-the-end-to-end-deployment)
  - [5. TROUBLESHOOTING TIPS](#5-troubleshooting-tips)
  - [6. APPENDIX](#6-appendix)

#### $\color{red}{\text{WARNING - THIS TAZAMA REPOSITORY IS TO BE USED FOR DEMONSTRATION, EXPLORATION AND TESTING PURPOSES ONLY.}}$

For production deployment instructions:

 - [On-Premise Detailed Installation Guide](https://github.com/tazama-lf/On-Prem-helm)
 - [AWS Detailed Installation Guide](https://github.com/tazama-lf/EKS-helm)
 - [Google Cloud Detailed Installation Guide](https://github.com/tazama-lf/GKE-helm)
 - [Azure Detailed Installation Guide](https://github.com/tazama-lf/AKS-helm)

# FULL STACK DOCKER DEPLOYMENT

## 1. INTRODUCTION

This guide will show you how to install the Tazama system, using only the publicly available open source software components, in a Docker container on a single local Windows machine. This is a multi-layered docker compose stack which spins up Tazama components. A Windows [batch script](start.bat) and a Unix [shell script](start.sh) have been provided which may be used to start containers that are usually used together in Tazama.

## 2. PRE-REQUISITES

The pre-requisites that are essential to be able to follow this guide to the letter are:

- Git
- Code editor (this guide will assume you are using VS Code)
- Docker Desktop for Windows (and WSL)
- GitHub personal access token

> **Notes on GitHub personal access token**
> - A GitHub personal access token must be created with `packages:write` and `read:org` permissions
> - Ensure that your GitHub Personal Access Token is added as a Windows Environment Variable called "`GH_TOKEN`"
> - We will be referencing your GitHub Personal Access Token throughout the installation process as your `GH_TOKEN`. It is not possible to retrieve the token from GitHub after you initially created it, but if the token had been set in Windows as an environment variable, you can retrieve it with the following command from a Windows Command Prompt: `set GH_TOKEN`

Instructions for installing the dependencies and setting up the GH_TOKEN environment variable can be found in the [Development Environment Set up Guide](https://github.com/tazama-lf/docs/blob/dev/Guides/dev-set-up-environment.md)

<div style="text-align: right"><a href="#top">Top</a></div>

## 3. INSTALLATION STEPS

### 3.1. Clone the Full-Stack-Docker-Tazama Repository to Your Local Machine  

In a Windows Command Prompt, navigate to the folder where you want to store a copy of the source code. For example, the source code root folder path I have been using to compile this guide is C:\Tazama\GitHub. Once in your source code root folder, clone (copy) the repository with the following command:

```
git clone https://github.com/tazama-lf/Full-Stack-Docker-Tazama -b main
```

If you would like to deploy the system from the `dev` branch, replace `main` above with `dev`. The `main` branch is the most recent official release of the system, while `dev` will be new features not yet released to the main branch

**Output:**

![clone-the-repo](/images/full-stack-docker-tazama-clone-the-repo.png)

<div style="text-align: right"><a href="#top">Top</a></div>

### 3.2. Update the Full-Stack-Docker-Tazama Configuration Files (optional)  

**3.2.1. Optional updates to .env file**

This optional step is only applicable to Option 1 (Deployment from GitHub) and allows editing of the basic environment variables to guide the Docker Compose installation.

Navigate to the Full-Stack-Docker-Tazama folder and launch VS Code:

**Output:**

![launch-code](/images/full-stack-docker-tazama-launch-code.png)

In VS Code, open the .env file in the Full-Stack-Docker-Tazama folder and update the `.env` file as follows:

 - (Optional) If your GitHub Personal Access Token had not been added as a Windows Environment Variable, you would need to specify the token at the top of the file next to the GH_TOKEN key. If you had specified the GH_TOKEN as an environment variable, you can leave the `${GH_TOKEN}` shell variable in place to retrieve it automatically.
 - (Optional) If you prefer an alternative port for the Transaction Monitoring Service API, you can update the `TMS_PORT` environment variable.
 - (Optional) If you would like to deploy from the `dev` branch, replace `main` with `dev` in the `#Branches` section

The current unaltered `.env` file will look as follows:

```javascript
# SPDX-License-Identifier: Apache-2.0
TAZAMA_VERSION=2.1.0

# Authentication
GH_TOKEN=${GH_TOKEN}

# Docker CLI settings
COMPOSE_BAKE=false

# Branches
TMS_BRANCH=main
ED_BRANCH=main
RULE_901_BRANCH=main
TP_BRANCH=main
TADP_BRANCH=main
NATS_UTILITIES_BRANCH=main
CMS_BRANCH=main
BATCH_PPA_BRANCH=main
RELAY_BRANCH=main

SIDECAR_BRANCH=main
LUMBERJACK_BRANCH=main

ADMIN_BRANCH=main
AUTH_SERVICE_BRANCH=main
EVENT_FLOW_BRANCH=main

# Ports
TMS_PORT=5000
ADMIN_PORT=5100

# TLS
NODE_TLS_REJECT_UNAUTHORIZED='0'

EVENT_SIDECAR_PORT=15000
ELASTIC_STACK_VERSION=8.15.1
ES_PORT=9200
KIBANA_PORT=5601
APMSERVER_PORT=8200
ES_MEM_LIMIT=1073741824
KB_MEM_LIMIT=1073741824
LS_MEM_LIMIT=1073741824
```
<div style="text-align: right"><a href="#top">Top</a></div>

**3.2.2 Optional steps for deploying the demo UI**

One of the optional items in the deployment step below, is to deploy the demo UI.  In order to successfully deploy the demo, the following 2 files `ui.env` and `docker-compose.dev.ui.yaml` must be created or updated before the deployment step (start.bat/ start.sh) below. The demo will not deploy successfully without them.  

##### FILE 1: ui.env <!-- omit in toc -->

The `ui.env` file should exist in the following location (as shown below in a code editor such as VSCode)

![location of ui.env file](/images/demo-uienv-location.png)

The `ui.env` file should contain the following contents

```javascript
# SPDX-License-Identifier: Apache-2.0

NEXT_PUBLIC_URL="http://localhost:3001"
PORT="3001"
NEXT_PUBLIC_TMS_SERVER_URL="http://localhost:5000"
NEXT_PUBLIC_TMS_KEY="no_key_set"
NEXT_PUBLIC_CMS_NATS_HOSTING="nats://nats:4222"
NEXT_PUBLIC_NATS_USERNAME=""
NEXT_PUBLIC_NATS_PASSWORD=""
NEXT_PUBLIC_ARANGO_DB_HOSTING="http://localhost:18529"
NEXT_PUBLIC_ADMIN_SERVICE_HOSTING="http://localhost:5100"
NEXT_PUBLIC_DB_USER="root"
NEXT_PUBLIC_DB_PASSWORD=""
NEXT_PUBLIC_WS_URL="http://localhost:3001"
NEXT_PUBLIC_NATS_SUBSCRIPTIONS="['connection', '>', 'typology-999@1.0.0']"
NEXT_PUBLIC_CONDITION_TYPES="['non-overridable-block', 'overridable-block', 'override']"
NEXT_PUBLIC_EVENT_TYPES="['pacs.008.001.10', 'pacs.002.001.12', 'pain.001.001.11', 'pain.013.001.09']"
NEXT_PUBLIC_CONDITION_REASONS="['Suspicion of Money Laundering', 'Violation of KYC/AML Requirements', 'Suspicion of Terrorist Financing', 'Tax Evasion Concerns', 'Regulatory Reporting Thresholds', 'Unusual Transaction Patterns', 'High-Risk Countries', 'Multiple Failed Login Attempts', 'Fraudulent Activity', 'Phishing or Account Takeover', 'Suspicious Beneficiaries', 'System Errors', 'Exceeding Limits', 'Legal Holds or Court Orders', 'Adverse media reports', 'Dormant or Inactive Accounts', 'Internal Bank Policies']"
```

##### FILE 2: docker-compose.dev.ui.yaml  <!-- omit in toc -->

The `docker-compose.dev.ui.yaml` file should exist in the following location (as shown below in a code editor such as VSCode)

![location of ui.env file](/images/demo-ui-yaml-location.png)

The `docker-compose.dev.ui.yaml` file should contain the following contents

```javascript
services:
  ui:
    image: tazamaorg/demo-ui:v2.1.0
    restart: always
    env_file:
      - env/ui.env
    depends_on:
      - tms
      - arango
      - nats
    ports:
      - "3001:3001"
  tms:
    environment:
      - CORS_POLICY=demo
  admin-service:
      environment:
      - CORS_POLICY=demo
```

<div style="text-align: right"><a href="#top">Top</a></div>

### 3.3. Deploy the services via script  

First, start the Docker Desktop for Windows application.

With Docker Desktop running: from your Windows Command Prompt and from inside the `Full-Stack-Docker-Tazama` folder, execute the following command and follow the prompts:

**Windows**  
Command Prompt: `start.bat` 
Powershell: `.\start.bat`

**Unix (Linux/MacOS)**
Any terminal: `./start.sh`

> !!!IMPORTANT
> Ensure the script has the correct permissions to run. You may need to run `chmod +x start.sh` beforehand.

**Output:**

![start-services-1](/images/full-stack-docker-tazama-start-bat-1.png)

The installation script provides 3 docker deployment options
1. Public deployment is a basic rule sample where the system is built from the source code in GitHub (this option is most useful for developers to explore the system). By changing the branches in the `.env` file it is possible to deploy from branches other than main e.g. dev or a feature branch
2. Full service deployment using pre-built images published on DockerHub from the main branch.  Full service includes deploying all the current Tazama rules
3. Public deployment using pre-built images published on DockerHub from the main branch. This option is similar to option 1 but instead of building the images from source code, the deployment is from pre-built images on DockerHub

![select-option](/images/full-stack-docker-tazama-select-option.png)

Enter your choice, type `1`, `2` or `3` and press enter.

**PUBLIC DEPLOYMENT**

For options 1 and 3 (Public deployment), the following optional add-ons will appear as per the screen below

> NOTE: It is currently not possible to select `Authentication` and `Demo UI` at the same time.

![start-services-2](/images/full-stack-docker-tazama-start-bat-2.png)

Once you have selected optional configuration add-ons (by toggling options on/off by selecting 1 through 6), apply the configuration by entering your choice: type `a` and press enter

![start-services-3](/images/full-stack-docker-tazama-start-bat-3.png)

**FULL SERVICE DEPLOYMENT**

For option 2 (Full service deployment) select `2` from the start.bat docker deployment menu option

![start-services-4](/images/full-stack-docker-tazama-start-bat-4.png)

For option 2 (Full service deployment) the output will be as follows:

![full-service-deployed](/images/full-stack-docker-tazama-full-service-option.png)

### 3.4. Access deployed components  

You'll be able to access the web interfaces for the deployed components through their respective TCP/IP ports on your local machine as defined in the `docker-compose.yaml` file.

 - ArangoDB: <http://localhost:18529>
 - NATS: <http://localhost:18222>

If your machine is open to your local area network, you will also be able to access these services from other computers on your network via your local machine's IP address.

<div style="text-align: right"><a href="#top">Top</a></div>

### 3.5. Overview of services

Tazama core services provides the foundational infrastructure components for the system and includes the ArangoDB, NATS and valkey services: ArangoDB provides the database infrastructure, NATS provides the pub/sub functionality and valkey provides for fast in-memory processor data caching.

Tazama is configured by loading the network map, rules and typology configurations required to evaluate a transaction via the ArangoDB API. The steps above have already loaded the default configuration into the database.

For an optional step to load the Tazama configuration manually, follow the instructions in the [Appendix](#appendix)

Now that the platform is configured, core processors should be running without problems. The main reason the configuration is required is that the processors read the network map at startup to set up the NATS pub/sub routes for the evaluation flow. If some services are still in a restart loop it means that the network map is either not configured correctly, they cannot communicate with the infrastructure or a required piece of infrastructure is not running.

The core processors include:

 - The Transaction Monitoring Service API at `<https://localhost:5000>`, where messages will be sent for evaluation. (Port configured in .env file under `TMS_PORT`)
 - The Event Director that will handle message routing based on the network map
 - The Typology Processor that will summarise rule results into scenarios according to individual typology configurations
 - The Transaction Aggregation and Decisioning Processor that will wrap up the evaluation of a transaction and publish any alerts for breached typologies

You can test that the TMS API was successfully deployed with the following command from the Command Prompt:

```
curl localhost:5000
```

**Output:**

![execute-config](./images/full-stack-docker-tazama-curl.png)

<div style="text-align: right"><a href="#top">Top</a></div>

## 4. TESTING THE END-TO-END DEPLOYMENT

Now, if everything went according to plan, you'll be able to submit a test transaction to the Transaction Monitoring Service API and then be able to see the result of a complete end-to-end evaluation in the database. 

If you have not already done so, clone the postman repository. In a Windows Command Prompt, navigate to the source code root folder. Then clone the postman repository with the following command:
```
git clone https://github.com/tazama-lf/postman -b main
```

**Output:**

![clone-config](/images/full-stack-docker-tazama-clone-postman.png)


We can run the following Postman test via Newman to see if our deployment was successful:

```
newman run collection-file -e environment-file --timeout-request 10200 --delay-request 500
```

- Select one of the following `collection file` options:
   - For options 1 & 3, If the authentication option has not been selected, then the `collection-file` is the full path to the location on your local machine where the `postman\1.1. (NO-AUTH) Rule-901 End-to-End test - pain001-013 disabled.postman_collection.json` file is located.  
   - For options 1 & 3, If authentication is deployed, use `postman\1.2. (AUTH) Rule-901 End-to-End test - pain001-013 disabled.postman_collection.json`.
   - For options 1 & 3, If the demo UI is selected (which must be without Authentication) use `postman\1.3. (NO-AUTH-DEMO) Rule-901 End-to-End test - pain001-013 disabled.postman_collection.json` 
   - For options 1 & 3, If the relay service is selected (which must be without Authentication) use `postman\1.4. (NO-AUTH-RELAY) Rule-901 End-to-End test - pain001/013 disabled.postman_collection.json` 
   - For option 2 (Full Service deployment), use `postman\2. Full-service-test.postman_collection.json`
 - The `environment-file` is the full path to the location on your local machine where the `postman\environments\Tazama-Docker-Compose-LOCAL.postman_environment.json` file is located.
 - If the path contains spaces, wrap the string in double-quotes.
 - We add the `--delay-request` option to delay each individual test by 500 milliseconds to give them evaluation time to complete before we look for the result in the database.

For this example, where the source code and test scripts are located in the C:\Tazama\GitHub folder, the newman command will look like this `newman run "C:\Tazama\GitHub\postman\1.1. (NO-AUTH) Rule-901 End-to-End test - pain001-013 disabled.postman_collection.json" -e "C:\Tazama\GitHub\postman\environments\Tazama-Docker-Compose-LOCAL.postman_environment.json" --timeout-request 10200 --delay-request 500`

**Output:**

![success](./images/full-stack-docker-tazama-success.png)

<div style="text-align: right"><a href="#top">Top</a></div>

## 5. TROUBLESHOOTING TIPS

The services are split up in multiple yamls, 

| Docker-Compose File               | Services                                                    |
| --------------------------------- | ----------------------------------------------------------- |
| docker-compose                    | tms, ed, tp, tadp, admin, ef                                |
| docker-compose.override           | rule-901, set up all services                               |
| docker-compose.infrastructure     | arango, nats, valkey                                        |
| docker-compose.(dev.)nats-utils   | nats-utilities                                              |
| docker-compose.(dev.)auth         | keycloak, auth-service, tms changes                         |
| docker-compose.(dev.)logs-base    | event-sidecar, lumberjack, all service changes              |
| docker-compose.(dev.)logs-elastic | event-sidecar, lumberjack, elasticsearch, kibana            |
| docker-compose.(dev.)apm-elastic  | event-sidecar, lumberjack, elasticsearch, kibana, apmserver |
| docker-compose.(dev.)relay        | relay-service                                               |

> !!!Note
> Turn off `tms` API authentication for the `Demo UI` to work.

> !!!Note
> Compose files without (.dev.) will pull pre-built images from DockerHub

If you want to restart or alter certain processors - 

Start/Restart individual services with
`docker compose up -p tazama -d --force-recreate <service>`    

Try running following if changes are not reflecting  
`docker compose up -p tazama -d --build --force-recreate`  

You can trash your container followed by deleting the image in docker if none of the above works.  

Stopping individual (or multiple) services  
`docker compose down <service> <service2> <service3>`

List of \<services\>  
- arango  
- nats  
- tms   
- ed  
- tadp  
- tp  
- relay-service
- rule-901  
- ef
- valkey
- auth
- keycloak
- event-sidecar
- lumberjack
- elasticsearch
- kibana
- apm-server

<div style="text-align: right"><a href="#top">Top</a></div>

**Docker Compose YAML structure** 

View this file for additional detail about the various Docker Compose YAML files and how they are structured and related: [Docker Compose YAML Structure Overview](./docker-yaml-structure.md)

## 6. APPENDIX 

This appendix will show you how to manually load the configuration and environment files in the Tazama full stack docker deployment for the public deployment option.

In a Windows Command Prompt, navigate to the source code root folder. Then clone the following repository with the following command:
```
git clone https://github.com/tazama-lf/postman -b main
```

**Output:**

![clone-config](/images/full-stack-docker-tazama-clone-postman.png)

Perform the following Newman command to load the configuration into the ArangoDB databases and collections:

```
newman run collection-file -e environment-file --timeout-request 10200
```

 - The `collection-file` is the full path to the location on your local machine where the `postman\Configuration - Rule 901.postman_collection.json` file is located.
 - The `environment-file` is the full path to the location on your local machine where the `postman\environments\Tazama-Docker-Compose-LOCAL.postman_environment.json` file is located.
 - If the path contains spaces, wrap the string in double-quotes.

**Output:**

![execute-config](/images/full-stack-docker-tazama-load-config.png) 

<div style="text-align: right"><a href="#top">Top</a></div>