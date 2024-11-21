<!-- SPDX-License-Identifier: Apache-2.0 -->

## Table of Contents

  - [INTRODUCTION](#introduction)
  - [Pre-requisites:](#pre-requisites)
  - [INSTALLATION STEPS](#installation-steps)
  - [1. Clone the Full-Stack-Docker-Tazama Repository to Your Local Machine](#1-clone-the-full-stack-docker-tazama-repository-to-your-local-machine)
  - [2. Update the Full-Stack-Docker-Tazama Configuration Files](#2-update-the-full-stack-docker-tazama-configuration-files)
  - [3. Deploy the Core Services](#3-deploy-the-core-services)
  - [4. Configure Tazama](#4-configure-tazama)
  - [5. Deploy core processors](#5-deploy-core-processors)
  - [6.  Compose the rule processor](#6--compose-the-rule-processor)
  - [TESTING THE END-TO-END DEPLOYMENT](#testing-the-end-to-end-deployment)
  - [TROUBLESHOOTING TIPS](#troubleshooting-tips)
  - [Appendix](#appendix)
 

## INTRODUCTION

This guide will show you how to install the platform using only the publicly available open source software components, in a Docker container on a single local Windows machine via Docker Compose.

This guide is specific to the Windows 10 or 11 operating system.

## Pre-requisites:

Set up your development environment as recommended in the [Tazama Contribution Guide](https://github.com/tazama-lf/.github/blob/main/CONTRIBUTING.md#32-setting-up-the-development-environment) section 3.2.1.

The pre-requisites that are essential to be able to follow this guide to the letter are:

 - Docker Desktop for Windows (and WSL)
 - Git
 - Newman
 - A code editor (this guide will assume you are using VS Code)
  - A GitHub personal access token with `packages:write` and `read:org` permissions
   - Ensure that your GitHub Personal Access Token is added as a Windows Environment Variable called "`GH_TOKEN`".
   - Instructions for creating the GH_TOKEN environment variable can be found in the [Tazama Contribution Guide (A. Preparation)](https://github.com/tazama-lf/.github/blob/main/CONTRIBUTING.md#a-preparation-)

     - We will be referencing your GitHub Personal Access Token throughout the installation process as your `GH_TOKEN`. It is not possible to retrieve the token from GitHub after you initially created it, but if the token had been set in Windows as an environment variable, you can retrieve it with the following command from a Windows Command Prompt:

        ```
        set GH_TOKEN
        ```

## INSTALLATION STEPS

## 1. Clone the Full-Stack-Docker-Tazama Repository to Your Local Machine

In a Windows Command Prompt, navigate to the folder where you want to store a copy of the source code. For example, the source code root folder path I have been using to compile this guide is C:\Tazama\GitHub. Once in your source code root folder, clone the repository with the following command:

```
git clone https://github.com/tazama-lf/Full-Stack-Docker-Tazama -b main
```

**Output:**

![clone-the-repo](/images/full-stack-docker-tazama-clone-the-repo.png)

## 2. Update the Full-Stack-Docker-Tazama Configuration Files

First, we want to create the basic environment variables to guide the Docker Compose installation.

Navigate to the Full-Stack-Docker-Tazama folder and launch VS Code:

**Output:**

![launch-code](/images/full-stack-docker-tazama-launch-code.png)

In VS Code, open the .env file in the Full-Stack-Docker-Tazama folder and update the `.env` file as follows:

 - (Optional) If your GitHub Personal Access Token had not been added as a Windows Environment Variable, you would need to specify the token at the top of the file next to the GH_TOKEN key. If you had specified the GH_TOKEN as an environment variable, you can leave the `${GH_TOKEN}` shell variable in place to retrieve it automatically.
 - (Optional) If you prefer an alternative port for the Transaction Monitoring Service API, you can update the `TMS_PORT` environment variable.

The current unaltered `.env` file will look as follows:

```javascript
# Authentication
GH_TOKEN=${GH_TOKEN}

# Branches
TMS_BRANCH=main
ED_BRANCH=main
RULE_901_BRANCH=main
TP_BRANCH=main
TADP_BRANCH=main
NATS_UTILITIES_BRANCH=main
CMS_BRANCH=main
BATCH_PPA_BRANCH=main
ADMIN_BRANCH=main
AUTH_SERVICE_BRANCH=main
EVENT_FLOW_BRANCH=main
SIDECAR_BRANCH=main
LUMBERJACK_BRANCH=main

# Ports
TMS_PORT=5000
ADMIN_PORT=5100
EVENT_SIDECAR_PORT=15000
ES_PORT=9200
KIBANA_PORT=5601
APMSERVER_PORT=8200

# Memory Limits
ES_MEM_LIMIT=1073741824
KB_MEM_LIMIT=1073741824
LS_MEM_LIMIT=1073741824

# TLS
NODE_TLS_REJECT_UNAUTHORIZED='0'
```

## 3. Deploy the services via script

First, start the Docker Desktop for Windows application.

With Docker Desktop running: from your Windows Command Prompt and from inside the `Full-Stack-Docker-Tazama` folder, execute the following command and follow the prompts:

#### Windows
Command Prompt: `start.bat` 
Powershell: `.\start.bat`

#### Unix (Linux/MacOS)
Any terminal: `./start.sh`

> [!IMPORTANT]  
> Ensure the script has the correct permissions to run. You may need to run `chmod +x start.sh` beforehand.

**Output:**

![start-services-1](/images/full-stack-docker-tazama-start-bat-1.png)

Toggle any or no addons

> NOTE: It is currently not possible to select `Authentication` and `Demo UI` at the same time.

![start-services-2](/images/full-stack-docker-tazama-start-bat-2.png)

Apply configuration

![start-services-3](/images/full-stack-docker-tazama-start-bat-3.png)

You'll be able to access the web interfaces for the deployed components through their respective TCP/IP ports on your local machine as defined in the `docker-compose.yaml` file.

 - ArangoDB: <http://localhost:18529>
 - NATS: <http://localhost:18222>

If your machine is open to your local area network, you will also be able to access these services from other computers on your network via your local machine's IP address.

## 4. Overview of services

Tazama core services provides the foundational infrastructure components for the platform and includes the ArangoDB, NATS and valkey services: ArangoDB provides the database infrastructure, NATS provides the pub/sub functionality and valkey provides for fast in-memory processor data caching.

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


## TESTING THE END-TO-END DEPLOYMENT

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
   - If the authentication option has not been selected, then the `collection-file` is the full path to the location on your local machine where the `postman\1.1. (NO-AUTH) Rule-901 End-to-End test - pain001-013 disabled.postman_collection.json` file is located. 
   - If authentication is deployed, use `postman\1.2. (AUTH) Rule-901 End-to-End test - pain001-013 disabled.postman_collection.json`.
   - If the demo UI is selected (which must be without Authentication) use `postman\1.3. (NO-AUTH-DEMO) Rule-901 End-to-End test - pain001-013 disabled.postman_collection.json` 
 - The `environment-file` is the full path to the location on your local machine where the `postman\environments\Tazama-Docker-Compose-LOCAL.postman_environment.json` file is located.
 - If the path contains spaces, wrap the string in double-quotes.
 - We add the `--delay-request` option to delay each individual test by 500 milliseconds to give them evaluation time to complete before we look for the result in the database.

**Output:**

![success](./images/full-stack-docker-tazama-success.png)

# TROUBLESHOOTING TIPS

The services are split up in multiple yamls, 

| Docker-Compose File | Services |
| -------- | ------- |
| docker-compose | tms, ed, tp, tadp, admin, ef |
| docker-compose.override | rule-901, set up all services |
| docker-compose.infrastructure | arango, nats, valkey |
| docker-compose.dev.nats-utils | nats-utilities |
| docker-compose.dev.auth | keycloak, auth-service, tms changes |
| docker-compose.dev.logs-base | event-sidecar, lumberjack, all service changes |
| docker-compose.dev.logs-elastic | event-sidecar, lumberjack, elasticsearch, kibana |
| docker-compose.dev.apm-elastic | event-sidecar, lumberjack, elasticsearch, kibana, apmserver |

> [!IMPORTANT]  
> Turn off `tms` API authentication for the `Demo UI` to work.

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

## Appendix

This appendix will show you how to manually load the configuration and environment files in the Tazama full stack docker deployment.

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

