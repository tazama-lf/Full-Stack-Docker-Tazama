# Tazama Docker Compose Structure

This document outlines the structure and organization of Docker Compose files in the Tazama system.

## Core Architecture

The Tazama system is built with a modular Docker Compose architecture that allows for flexible deployment options:

1. **GitHub Development Deployment**: Builds services from GitHub repositories
2. **DockerHub Full-Service Deployment**: Uses pre-built images with all rules
3. **DockerHub Public Deployment**: Uses pre-built images with minimal configuration

## File Hierarchy

### Base Infrastructure
- **`docker-compose.infrastructure.yaml`**: Core infrastructure services
  - `valkey`: Redis-compatible key-value store
  - `arango`: ArangoDB database
  - `nats`: Messaging system

### Core Service Types

#### 1. Base Application Services
- **`docker-compose.yaml`**: Main service definitions using DockerHub images
  - `tms`: Transaction Monitoring Service
  - `ed`: Event Director
  - `tp`: Typology Processor
  - `tadp`: Transaction Aggregation and Decisioning Processor
  - `admin-service`: Administration interface
  - `ef`: Event Flow
  
- **`docker-compose.dev.yaml`**: Development version building from GitHub repositories
  - Same services as above, but built from source code

#### 2. Database Configuration
- **`docker-compose.db.yaml`**: Full service database setup
  - Configures ArangoDB for full deployment
  
- **`docker-compose.dev.db.yaml`**: Development database setup
  - Configures ArangoDB with standard test data

#### 3. Rules Processing
- **`docker-compose.full.yaml`**: All production rules (001-091)
  - Includes 30+ rule services for transaction monitoring
  
- **`docker-compose.rule.yaml`**: Minimal rule setup for DockerHub deployments
  - Only includes rule-901
  
- **`docker-compose.dev.rule.yaml`**: GitHub version of minimal rule setup
  - Builds rule-901 from source

#### 4. Relay Configuration
- **`docker-compose.relay.yaml`**: Relay services for DockerHub
  - `rs1`: Relay service for typology processor
  - `rs2`: Relay service for transaction aggregation
  
- **`docker-compose.dev.relay.yaml`**: GitHub version of relay services
  - Same services built from source

### Optional Addons

#### 1. Authentication
- **`docker-compose.auth.base.yaml`**: Common authentication configuration
  - `keycloak`: Authentication provider
  - Adds auth configuration to TMS and admin service
  
- **`docker-compose.auth.yaml`**: DockerHub version
  - Adds `auth` service using DockerHub image
  
- **`docker-compose.dev.auth.yaml`**: GitHub version
  - Builds `auth` service from source

#### 2. Logging
- **`docker-compose.logs-base.yaml`**: Basic logging infrastructure
  - `event-sidecar`: Event logging service
  - `lumberjack`: Log processing service
  
- **`docker-compose.logs.yaml`**: Logging configuration for services
  - Configures all services to use the event sidecar
  
- **`docker-compose.dev.logs-base.yaml`**: Development version of logging
  - Builds logging services from source
  
- **`docker-compose.logs-elastic.yaml`**: Elastic logging for DockerHub
  - Configures lumberjack to send logs to Elasticsearch
  
- **`docker-compose.logs-elastic.base.yaml`**: Common Elastic logging config
  - Base setup for Elasticsearch integration
  
- **`docker-compose.dev.logs-elastic.yaml`**: GitHub version of Elastic logging
  - Builds services from source with Elasticsearch integration

#### 3. Monitoring
- **`docker-compose.dev.elastic.yaml`**: Elasticsearch and Kibana setup
  - `elasticsearch`: Search and analytics engine
  - `kibana`: Visualization platform
  
- **`docker-compose.dev.apm-elastic.yaml`**: APM monitoring
  - `apm-server`: Application Performance Monitoring
  - Configures services to use APM

#### 4. UI
- **`docker-compose.dev.ui.yaml`**: Demo UI interface
  - `ui`: Frontend interface for the system
  
#### 5. Utilities
- **`docker-compose.dev.nats-utils.yaml`**: NATS utilities
  - `nats-utilities`: Tools for working with NATS

### Common Configurations

- **`docker-compose.override.yaml`**: Port mappings for local development
  - Maps container ports to host ports for local access

## Deployment Patterns

### 1. GitHub Development Deployment
