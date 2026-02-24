This document contains architecture and networking diagrams for the Crego multi-cloud GitOps infrastructure deployed on GCP and AWS.

## Architecture Overview

The Crego infrastructure uses a GitOps-based Kubernetes deployment pattern with ArgoCD App-of-Apps, supporting multi-environment and multi-cloud deployments across GCP and AWS.

## **🏗️ GCP Architecture**

```
+-----------------------------------------------------------------------------+
|                             EXTERNAL USERS                                  |
|              (Web Browsers, Mobile Apps, API Clients)                       |
+-----------------------------+-----------------------------------------------+
                              | HTTPS
                              v
+-----------------------------------------------------------------------------+
|                         GCP LOAD BALANCER                                   |
|                   (SSL Termination, Static IP: crego-dev-ip)                |
|                        SSL Certificate: app-cert-dev                        |
+-----------------------------+-----------------------------------------------+
                              | HTTP/HTTPS
                              v
+-----------------------------------------------------------------------------+
|                      NGINX INGRESS CONTROLLER                               |
|                        (NodePort Services)                                  |
|                                                                             |
|  Routing:                                                                   |
|  • /omni/api/* → omni-api:8000                                              |
|  • /flow/api/* → flow-api:8000                                              |
|  • /omni/* → omni-web:8000                                                  |
|  • /flow/* → flow-web:8000                                                  |
|  • /flower/* → flower:5555                                                  |
|  • / → omni-web:8000 (default)                                              |
+-----------------------------+-----------------------------------------------+
                              |
                              v
      +-----------------------------------------------------------+
      |              APPLICATION SERVICES (Port 8000)            |
      |                                                          |
      |  +-----------+ +-----------+ +-----------+ +-----------+ |
      |  | OMNI-API  | | FLOW-API  | | OMNI-WEB  | | FLOW-WEB  | |
      |  |Django API | |Django API | |React SPA  | |React SPA  | |
      |  |Replicas: 1| |Replicas: 1| |Replicas: 1| |Replicas: 1| |
      |  |           | |           | |           | |           | |
      |  |Resources: | |Resources: | |Resources: | |Resources: | |
      |  |1 vCPU     | |1 vCPU     | |1 vCPU     | |1 vCPU     | |
      |  |2 GB RAM   | |2 GB RAM   | |1 GB RAM   | |1 GB RAM   | |
      |  +-----+-----+ +-----+-----+ +-----------+ +-----------+ |
      +--------+---------------+-----------------------------------+
               |               |
               |               |
      +--------+---------------+-----------------------------------+
      |        |   BACKGROUND PROCESSING                          |
      |        |               |                                  |
      |  +-----v--------+ +----v-------+ +---------------------+ |
      |  |OMNI-CELERY-  | |OMNI-CELERY-| |  FLOW-CELERY-WORKER | |
      |  |WORKER        | |BEAT        | |     Replicas: 1     | |
      |  |Replicas: 1   | |Scheduler   | |                     | |
      |  |              | |Replica: 1  | |  Resources:         | |
      |  |Resources:    | |            | |  1 vCPU, 2 GB RAM   | |
      |  |1 vCPU, 2GB   | |Resources:  | +-----------+---------+ |
      |  |RAM           | |0.5vCPU,1GB | |           |           |
      |  +-------+------+ +------+-----+ |           |           |
      +----------+---------------+-------+-----------+-----------+
                 |               |       |           |
                 |               |       |           |
      +----------+---------------+-------+-----------+-----------+
      |          |      MONITORING (Port 5555)      |           |
      |          |               |       |           |           |
      |  +-------v--------+      |       |           |           |
      |  | FLOWER         |      |       |           |           |
      |  | DASHBOARD      |      |       |           |           |
      |  |Celery Monitor  |      |       |           |           |
      |  |Replica: 1      |      |       |           |           |
      |  |                |      |       |           |           |
      |  |Resources:      |      |       |           |           |
      |  |0.5 vCPU,0.5 GB |      |       |           |           |
      |  +----------------+      |       |           |           |
      +---------------------------+-------+-----------+-----------+
                                  |       |           |
                                  |       |           |
              +-------------------+-------+-----------+-----------+
              |     INFRASTRUCTURE SERVICES (Dev Only)           |
              |                   |       |           |           |
              |  +-----------------v--+ +-v---------+ +-v---------+ |
              |  |   POSTGRESQL       | |   REDIS   | | RABBITMQ  | |
              |  | Primary Database   | |Cache &    | |Message    | |
              |  |Persistent Storage  | |Sessions   | |Broker     | |
              |  |                    | |           | |           | |
              |  |Resources:          | |Resources: | |Resources: | |
              |  |1 vCPU, 2 GB RAM    | |0.5 vCPU   | |0.5 vCPU   | |
              |  |20 GB Storage       | |1 GB RAM   | |1 GB RAM   | |
              |  +--------------------+ +-----------+ +-----------+ |
              +-------------------------------------------------------+

External Services:
+---------------+ +---------------+ +---------------+
| SECRET        | |ARTIFACT       | | CLOUD NAT GW  |
| MANAGER       | |REGISTRY       | |               |
|               | |               | |               |
|• app-dev      | |• Docker Images| |• Regional IP  |
|  secrets      | |• asia-south1- | |• Outbound     |
|               | |  docker.pkg.dev| |  Internet     |
+---------------+ +---------------+ +---------------+

GitOps & CI/CD:
+---------------+ +---------------+ +---------------+
|    ARGOCD     | | GIT           | | CI/CD         |
|               | | REPOSITORY    | | PIPELINE      |
|               | |               | |               |
|• GitOps       |<|• crego-infra  | |• Image Builds |
|  Controller   | |• App-of-Apps  | |• Auto Deploy  |
+---------------+ +---------------+ +---------------+

Secret Management:
+-------------------------------------------------------------+
|              EXTERNAL SECRETS OPERATOR                     |
|                   (Workload Identity)                      |
|                                                             |
|• Syncs secrets from GCP Secret Manager                     |
|• Creates Kubernetes secrets automatically                  |
|• Uses Workload Identity for authentication                 |
+-------------------------------------------------------------+
```

## **☁️ AWS Architecture**

```
+-----------------------------------------------------------------------------+
|                             EXTERNAL USERS                                 |
|              (Web Browsers, Mobile Apps, API Clients)                      |
+-----------------------------+-----------------------------------------------+
                              | HTTPS
                              v
+-----------------------------------------------------------------------------+
|                    AWS APPLICATION LOAD BALANCER                           |
|                   (SSL Termination, AWS Certificate Manager)               |
|                        Internet-facing, Multi-AZ                           |
+-----------------------------+-----------------------------------------------+
                              | HTTP/HTTPS
                              v
+-----------------------------------------------------------------------------+
|                      ALB INGRESS CONTROLLER                                |
|                        (Target Groups, Health Checks)                      |
|                                                                             |
|  Routing:                                                                   |
|  • /omni/api/* → omni-api:8000                                             |
|  • /flow/api/* → flow-api:8000                                             |
|  • /omni/* → omni-web:8000                                                 |
|  • /flow/* → flow-web:8000                                                 |
|  • /flower/* → flower:5555                                                 |
|  • / → omni-web:8000 (default)                                             |
+-----------------------------+-----------------------------------------------+
                              |
                              v
      +-----------------------------------------------------------+
      |              APPLICATION SERVICES (Port 8000)            |
      |                                                           |
      |  +-----------+ +-----------+ +-----------+ +-----------+ |
      |  | OMNI-API  | | FLOW-API  | | OMNI-WEB  | | FLOW-WEB  | |
      |  |Django API | |Django API | |React SPA  | |React SPA  | |
      |  |Replicas: 1| |Replicas: 1| |Replicas: 1| |Replicas: 1| |
      |  |           | |           | |           | |           | |
      |  |Resources: | |Resources: | |Resources: | |Resources: | |
      |  |1 vCPU     | |1 vCPU     | |1 vCPU     | |1 vCPU     | |
      |  |2 GB RAM   | |2 GB RAM   | |1 GB RAM   | |1 GB RAM   | |
      |  +-----+-----+ +-----+-----+ +-----------+ +-----------+ |
      +--------+---------------+-----------------------------------+
               |               |
               |               |
      +--------+---------------+-----------------------------------+
      |        |   BACKGROUND PROCESSING                          |
      |        |               |                                  |
      |  +-----v--------+ +----v-------+ +---------------------+ |
      |  |OMNI-CELERY-  | |OMNI-CELERY-| |  FLOW-CELERY-WORKER | |
      |  |WORKER        | |BEAT        | |     Replicas: 1     | |
      |  |Replicas: 1   | |Scheduler   | |                     | |
      |  |              | |Replica: 1  | |  Resources:         | |
      |  |Resources:    | |            | |  1 vCPU, 2 GB RAM   | |
      |  |1 vCPU, 2GB   | |Resources:  | +-----------+---------+ |
      |  |RAM           | |0.5vCPU,1GB | |           |           |
      |  +-------+------+ +------+-----+ |           |           |
      +----------+---------------+-------+-----------+-----------+
                 |               |       |           |
                 |               |       |           |
      +----------+---------------+-------+-----------+-----------+
      |          |      MONITORING (Port 5555)      |           |
      |          |               |       |           |           |
      |  +-------v--------+      |       |           |           |
      |  | FLOWER         |      |       |           |           |
      |  | DASHBOARD      |      |       |           |           |
      |  |Celery Monitor  |      |       |           |           |
      |  |Replica: 1      |      |       |           |           |
      |  |                |      |       |           |           |
      |  |Resources:      |      |       |           |           |
      |  |0.5 vCPU,0.5 GB |      |       |           |           |
      |  +----------------+      |       |           |           |
      +---------------------------+-------+-----------+-----------+
                                  |       |           |
                                  |       |           |
              +-------------------+-------+-----------+-----------+
              |     INFRASTRUCTURE SERVICES (Dev Only)           |
              |                   |       |           |           |
              |  +-----------------v--+ +-v---------+ +-v---------+ |
              |  |   POSTGRESQL       | |   REDIS   | | RABBITMQ  | |
              |  | Primary Database   | |Cache &    | |Message    | |
              |  |  gp3 Storage       | |Sessions   | |Broker     | |
              |  |                    | |           | |           | |
              |  |Resources:          | |Resources: | |Resources: | |
              |  |1 vCPU, 2 GB RAM    | |0.5 vCPU   | |0.5 vCPU   | |
              |  |20 GB gp3 Storage   | |1 GB RAM   | |1 GB RAM   | |
              |  +--------------------+ +-----------+ +-----------+ |
              +-------------------------------------------------------+

External Services:
+---------------+ +---------------+ +---------------+
| SECRETS       | |     ECR       | | NAT GATEWAY   |
| MANAGER       | |               | |               |
|               | |               | |               |
|• app/dev      | |• Docker Images| |• Multi-AZ     |
|• app/prod     | |• ap-south-1   | |• Elastic IPs  |
|• ap-south-1   | |               | |• Outbound     |
+---------------+ +---------------+ +---------------+

GitOps & CI/CD:
+---------------+ +---------------+ +---------------+
|    ARGOCD     | | GIT           | | CI/CD         |
|               | | REPOSITORY    | | PIPELINE      |
|               | |               | |               |
|• GitOps       |<|• crego-infra  | |• Image Builds |
|  Controller   | |• App-of-Apps  | |• Auto Deploy  |
+---------------+ +---------------+ +---------------+

Secret Management:
+-------------------------------------------------------------+
|              EXTERNAL SECRETS OPERATOR                     |
|                 (JWT/IAM Authentication)                    |
|                                                             |
|• Syncs secrets from AWS Secrets Manager                    |
|• Creates Kubernetes secrets automatically                  |
|• Uses JWT tokens with IAM service accounts                 |
+-------------------------------------------------------------+
```

## **🌐 GCP Networking Diagram**

```
+-----------------------------------------------------------------------------+
|                               INTERNET                                     |
|                    (Users & API Clients Traffic)                           |
+-----------------------------+-----------------------------------------------+
                              | HTTPS/443
                              v
+-----------------------------------------------------------------------------+
|                      GLOBAL LOAD BALANCER                                  |
|                   Static IP: crego-dev-ip                                  |
|                   SSL Certificate: app-cert-dev                            |
+-----------------------------+-----------------------------------------------+
                              | Backend Service
                              v
+-----------------------------------------------------------------------------+
|                        REGIONAL LAYER - asia-south1                        |
|                                                                             |
|  +-----------------------------------------------------------------------+  |
|  |                          VPC NETWORK                                 |  |
|  |                                                                      |  |
|  |  +-----------------------------------------------------------------+  |  |
|  |  |                  GKE PRIVATE CLUSTER SUBNET                   |  |  |
|  |  |                                                                |  |  |
|  |  |  +---------------------------------------------------------+   |  |  |
|  |  |  |            GKE CONTROL PLANE                          |   |  |  |
|  |  |  |         (Google Managed)                              |   |  |  |
|  |  |  |                                                       |   |  |  |
|  |  |  |• Private IP Range                                     |   |  |  |
|  |  |  |• Master Authorized Networks                           |   |  |  |
|  |  |  |• Regional High Availability                           |   |  |  |
|  |  |  +--------------------+----------------------------------+   |  |  |
|  |  |                       | Private IP Communication            |  |  |
|  |  |                       v                                     |  |  |
|  |  |  +---------------------------------------------------------+   |  |  |
|  |  |  |              WORKER NODES (Private)                   |   |  |  |
|  |  |  |                                                       |   |  |  |
|  |  |  |  +------------+ +------------+ +------------+         |   |  |  |
|  |  |  |  |Worker Node1| |Worker Node2| |Worker NodeN|         |   |  |  |
|  |  |  |  |            | |            | |     ...    |         |   |  |  |
|  |  |  |  |• No Ext IP | |• No Ext IP | |• No Ext IP |         |   |  |  |
|  |  |  |  |• Private IP| |• Private IP| |• Private IP|         |   |  |  |
|  |  |  |  |• Cost Saved| |• Cost Saved| |• Cost Saved|         |   |  |  |
|  |  |  |  |~$1.46/month| |~$1.46/month| |~$1.46/month|         |   |  |  |
|  |  |  |  +------+-----+ +------+-----+ +------+-----+         |   |  |  |
|  |  |  +---------+----------------+----------------+-------------+   |  |  |
|  |  |            |                |                |                 |  |  |
|  |  |  +---------v----------------v----------------v-------------+   |  |  |
|  |  |  |            LOAD BALANCER SERVICES                     |   |  |  |
|  |  |  |                                                       |   |  |  |
|  |  |  |  +--------------------------------------------------+  |   |  |  |
|  |  |  |  |        NGINX Ingress Controller                 |  |   |  |  |
|  |  |  |  |                                                 |  |   |  |  |
|  |  |  |  |• NodePort Services                              |  |   |  |  |
|  |  |  |  |• External IP via Load Balancer                  |  |   |  |  |
|  |  |  |  |• Internal Routing to Worker Nodes               |  |   |  |  |
|  |  |  |  +--------------------------------------------------+  |   |  |  |
|  |  |  +---------------------------------------------------------+   |  |  |
|  |  +-----------------------------------------------------------------+  |  |
|  |                                                                      |  |
|  |  +-----------------------------------------------------------------+  |  |
|  |  |                   CLOUD NAT & ROUTER                          |  |  |
|  |  |                                                                |  |  |
|  |  |  +----------------+    +------------------------------+        |  |  |
|  |  |  |  Cloud Router  |    |        Cloud NAT             |        |  |  |
|  |  |  |                |    |                              |        |  |  |
|  |  |  |• Regional      |<---|• Regional External IP        |        |  |  |
|  |  |  |• BGP Enabled   |    |• Outbound Only               |        |  |  |
|  |  |  |                |    |• Shared Across All Nodes     |        |  |  |
|  |  |  +----------------+    +------------+-----------------+        |  |  |
|  |  +---------------------------------------------+-------------------+  |  |
|  +------------------------------------------------+----------------------+  |
+-------------------------------------------------+-------------------------+
                                                  | To Internet
                                                  v
                          +---------------------------------------+
                          |              INTERNET                |
                          |        (Outbound Traffic Only)       |
                          +---------------------------------------+

+-----------------------------------------------------------------------------+
|                           MANAGED SERVICES                                 |
|                      (Private Google Access)                               |
|                                                                             |
|  +---------------------------+    +-----------------------------------+     |
|  |      SECRET MANAGER       |    |        ARTIFACT REGISTRY          |     |
|  |                           |    |                                   |     |
|  |• Private Google Access    |    |• Private Google Access            |     |
|  |• No Internet Routing      |    |• asia-south1-docker.pkg.dev       |     |
|  |• Secure Communication     |    |• Container Images                 |     |
|  |                           |    |• No Internet Routing              |     |
|  +---------------------------+    +-----------------------------------+     |
+-----------------------------------------------------------------------------+

Network Flow Summary:
+-----------------------------------------------------------------------------+
|                             TRAFFIC FLOWS                                  |
|                                                                             |
| INBOUND:                                                                    |
| Internet → Global LB → NGINX Ingress → Worker Nodes → Application Pods     |
|                                                                             |
| OUTBOUND:                                                                   |
| Application Pods → Worker Nodes → Cloud Router → Cloud NAT → Internet      |
|                                                                             |
| PRIVATE SERVICES:                                                           |
| Worker Nodes → Private Google Access → Secret Manager/Artifact Registry    |
|                                                                             |
| COST OPTIMIZATION FEATURES:                                                 |
|• No external IPs on worker nodes (~$1.46/month saved per node)             |
|• Single shared NAT IP for all outbound traffic                             |
|• Private Google Access eliminates internet routing for GCP services        |
|• Reduced attack surface with private-only worker nodes                     |
+-----------------------------------------------------------------------------+
```

## **🌐 AWS Networking Diagram**

```
+-----------------------------------------------------------------------------+
|                               INTERNET                                     |
|                    (Users & API Clients Traffic)                           |
+-----------------------------+-----------------------------------------------+
                              | HTTPS/443
                              v
+-----------------------------------------------------------------------------+
|                   AWS APPLICATION LOAD BALANCER                            |
|                     Internet-facing, SSL/TLS Certificate                   |
|                           Path-based routing                               |
+-----------------------------+-----------------------------------------------+
                              | Target Groups & Health Checks
                              v
+-----------------------------------------------------------------------------+
|                        REGION: ap-south-1                                 |
|                           Multi-AZ VPC                                     |
|                                                                             |
|  +-----------------------------------+ +-----------------------------------+  |
|  |        AVAILABILITY ZONE A        | |        AVAILABILITY ZONE B        |  |
|  |                                   | |                                   |  |
|  |  +-----------------------------+  | |  +-----------------------------+  |  |
|  |  |        PUBLIC SUBNET A      |  | |  |        PUBLIC SUBNET B      |  |  |
|  |  |                             |  | |  |                             |  |  |
|  |  |  +--------------------+     |  | |  |  +--------------------+     |  |  |
|  |  |  |     ALB TARGET     |     |  | |  |  |     ALB TARGET     |     |  |  |
|  |  |  |   External IP      |     |  | |  |  |   External IP      |     |  |  |
|  |  |  +--------------------+     |  | |  |  +--------------------+     |  |  |
|  |  |                             |  | |  |                             |  |  |
|  |  |  +--------------------+     |  | |  |  +--------------------+     |  |  |
|  |  |  |   NAT GATEWAY A    |     |  | |  |  |   NAT GATEWAY B    |     |  |  |
|  |  |  |   Elastic IP       |     |  | |  |  |   Elastic IP       |     |  |  |
|  |  |  | High Availability  |     |  | |  |  | High Availability  |     |  |  |
|  |  |  +---------+----------+     |  | |  |  +---------+----------+     |  |  |
|  |  +------------+---------------+  | |  +------------+---------------+  |  |
|  |               |                  | |               |                  |  |
|  |  +------------v---------------+  | |  +------------v---------------+  |  |
|  |  |       PRIVATE SUBNET A     |  | |  |       PRIVATE SUBNET B     |  |  |
|  |  |                            |  | |  |                            |  |  |
|  |  |  +----------------------+  |  | |  |  +----------------------+  |  |  |
|  |  |  | EKS Worker Node A1   |  |  | |  |  | EKS Worker Node B1   |  |  |  |
|  |  |  |                      |  |  | |  |  |                      |  |  |  |
|  |  |  |• Private IP Only     |  |  | |  |  |• Private IP Only     |  |  |  |
|  |  |  |• No Direct Internet  |  |  | |  |  |• No Direct Internet  |  |  |  |
|  |  |  |• High Availability   |  |  | |  |  |• High Availability   |  |  |  |
|  |  |  +----------------------+  |  | |  |  +----------------------+  |  |  |
|  |  |                            |  | |  |                            |  |  |
|  |  |  +----------------------+  |  | |  |  +----------------------+  |  |  |
|  |  |  | EKS Worker Node A2   |  |  | |  |  | EKS Worker Node B2   |  |  |  |
|  |  |  |                      |  |  | |  |  |                      |  |  |  |
|  |  |  |• Private IP Only     |  |  | |  |  |• Private IP Only     |  |  |  |
|  |  |  |• No Direct Internet  |  |  | |  |  |• No Direct Internet  |  |  |  |
|  |  |  |• High Availability   |  |  | |  |  |• High Availability   |  |  |  |
|  |  |  +----------------------+  |  | |  |  +----------------------+  |  |  |
|  |  +----------------------------+  | |  +----------------------------+  |  |
|  +-----------------------------------+ +-----------------------------------+  |
|                                                                             |
|  +-----------------------------------------------------------------------+  |
|  |                        EKS CONTROL PLANE                             |  |
|  |                         (AWS Managed)                                |  |
|  |                                                                       |  |
|  |• Private API Endpoint                                                 |  |
|  |• Regional High Availability                                           |  |
|  |• Secure Communication to Worker Nodes                                |  |
|  |• Automatic Updates and Patches                                        |  |
|  +-----------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------+

+-----------------------------------------------------------------------------+
|                           MANAGED SERVICES                                 |
|                          (VPC Endpoints)                                   |
|                                                                             |
|  +-------------------------------+  +-----------------------------------+   |
|  |       AWS SECRETS MANAGER     |  |    ELASTIC CONTAINER REGISTRY    |   |
|  |                               |  |                                   |   |
|  |• VPC Endpoint Access          |  |• VPC Endpoint Access              |   |
|  |• No Internet Routing          |  |• No Internet Routing              |   |
|  |• ap-south-1 Region            |  |• Container Images                 |   |
|  |• Secure Private Communication |  |• Secure Private Communication     |   |
|  +-------------------------------+  +-----------------------------------+   |
+-----------------------------------------------------------------------------+

Network Flow Summary:
+-----------------------------------------------------------------------------+
|                             TRAFFIC FLOWS                                  |
|                                                                             |
| INBOUND TRAFFIC:                                                            |
| Internet → ALB → Target Groups → Private Subnets → EKS Worker Nodes        |
|                                                                             |
| OUTBOUND TRAFFIC:                                                           |
| EKS Worker Nodes → Private Subnets → NAT Gateways → Internet               |
|                                                                             |
| VPC ENDPOINT COMMUNICATION:                                                 |
| EKS Worker Nodes → VPC Endpoints → AWS Services (Secrets Manager, ECR)    |
|                                                                             |
| CLUSTER COMMUNICATION:                                                      |
| EKS Control Plane ↔ Worker Nodes (Private API Endpoint)                   |
|                                                                             |
| HIGH AVAILABILITY FEATURES:                                                 |
|• Multi-AZ deployment across 2+ availability zones                          |
|• Multiple NAT Gateways for redundancy                                      |
|• Private worker nodes with no direct internet access                       |
|• VPC endpoints eliminate internet routing for AWS services                 |
|• ALB with automatic failover and health checks                             |
+-----------------------------------------------------------------------------+
```

## Key Architectural Differences

### GCP vs AWS Infrastructure

| Component | GCP | AWS |
| --- | --- | --- |
| **Kubernetes** | GKE Private Cluster | EKS with Private Worker Nodes |
| **Load Balancer** | Global Load Balancer + NGINX Ingress | Application Load Balancer (ALB) |
| **Ingress** | GCE Ingress Controller (NodePort) | ALB Ingress Controller |
| **Secret Management** | Secret Manager + Workload Identity | Secrets Manager + JWT/IAM |
| **Container Registry** | Artifact Registry (asia-south1) | Elastic Container Registry |
| **Networking** | Single NAT Gateway (Regional IP) | Multi-AZ NAT Gateways (Elastic IPs) |
| **Storage** | Standard Storage Class | gp3 Storage Class |

### Cost Optimization Strategies

### GCP Private Node Architecture

- **No External IPs**: Worker nodes use private IPs only, saving ~$1.46/month per node
- **Single NAT Gateway**: Regional IP for all outbound traffic, shared across nodes
- **Reduced Attack Surface**: Nodes not directly accessible from internet

### AWS Multi-AZ Design

- **High Availability**: Resources distributed across multiple availability zones
- **VPC Endpoints**: Private access to AWS services without internet routing
- **Elastic Load Balancing**: Automatic traffic distribution and health checking

### Service Configuration Standards

- **Port Standardization**: All application services run on port 8000 (except Flower on 5555)
- **Path-Based Routing**: Services handle full URL paths with prefixes (`/omni/api/*`, `/flow/api/*`)
- **No URL Rewriting**: Applications are responsible for handling their assigned path prefixes
- **Environment Consistency**: Same service architecture across dev and prod environments

### GitOps & Security

- **ArgoCD App-of-Apps**: Centralized application deployment management
- **External Secrets Operator**: Cloud-native secret synchronization
- **Network Policies**: Kubernetes-level network segmentation
- **RBAC**: Role-based access control for service accounts
- **Private Clusters**: All worker nodes isolated from direct internet access