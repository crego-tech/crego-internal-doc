## **🧾 Overview**

This guide outlines the deployment requirements for **Crego Platform**, a comprehensive financial platform consisting of backend services and frontend applications:

**Omni Backend Services (Containerized)**:

- **omni-api** - REST API Service (Port 8000)
- **omni-worker** - Background Task Processor
- **omni-scheduler** - Task Scheduler

**Flow Services (Containerized)**:

- **flow-api** - FastAPI Workflow Engine (Port 8000)
- **flow-worker** - Background Workflow Task Processor
- **flow-web** - React SPA (Static files)

**Frontend Applications**:

- **omni-web** - React SPA (Static files)
- **flow-web** - React SPA for workflow management (Static files)

**Docker Images**: Provided by Crego (credentials/registry access will be shared separately)
**Frontend Bundle**: Pre-built React application provided as ZIP file

---

## **🏗️ Network Architecture**

```json
┌─────────────────────────────────────────────────────────────────────────────┐
│                                CLIENTS                                      │
│    (Web Browsers, Mobile Apps, API Clients)                                 │
│                                                                             │
│   Single Domain: crego[-preprod].yourdomain.com                             │
│   CloudFront Distribution + Multiple S3 Origins                             │
│   Path-based Routing:                                                       │
│   • /           → omni-web (S3 Origin A)                                    │
│   • /flow       → flow-web (S3 Origin B)                                    │
│   • /api        → omni-api (via ALB)                                        │
│   • /flow/api   → flow-api (via ALB)                                        │
└─────────────────────────────┬───────────────────────────────────────────────┘
                              │ HTTPS (Single TLS Certificate)
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CLOUDFRONT DISTRIBUTION                                  │
│              (Cache Behaviors + Path-based Routing)                         │
└─────────────────────────────┬───────────────────────────────────────────────┘
                              │ HTTP/HTTPS
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    APPLICATION LOAD BALANCER (ALB)                          │
│                     (Target Groups + Health Checks)                         │
└─────────────────────────────┬───────────────────────────────────────────────┘
                              │ HTTP
                              ▼
              ┌───────────────────────────────┬───────────────────────────────┐
              │                               │                               │
              ▼                               ▼                               │
┌─────────────────────────────────┐   ┌─────────────────────────────────┐     │
│       OMNI-API (Port 8000)      │   │       FLOW-API (Port 8000)      │     │
│     Replicas: 2+ instances      │   │     Replicas: 2+ instances      │     │
│                                 │   │                                 │     │
│ Target Group: /api/*            │   │ Target Group: /flow/api/*       │     │
│ • /api/health/                  │   │ • /flow/api/health/             │     │
│ • /api/admin/                   │   │ • /flow/api/health/detailed/    │     │
│ • /api/health/detailed/         │   │                                 │     │
│ • Authentication Provider       │◄──┤ • Uses Omni for JWT Auth        │     │
│ • Django REST API               │   │ • FastAPI Workflow Engine       │     │
│ • Resources: 1 vCPU, 2 GB RAM   │   │ • Resources: 1 vCPU, 2 GB RAM   │     │
└─────────┬───────────┬───────────┘   └─────────────┬───────────────────┘     │
          │           │                             │                         │
          │           │                             │                         │
          │   ┌───────▼─────────┐           ┌───────▼─────────┐               │
          │   │  POSTGRESQL     │           │   MONGODB v8    │               │
          │   │  (Port 5432)    │           │  (Port 27017)   │               │
          │   │                 │           │                 │               │
          │   │ • Primary DB    │           │ • Flow Data     │               │
          │   │ • Celery Results│           │ • Workflows     │               │
          │   │ • SSL Required  │           │ • Documents     │               │
          │   └─────────────────┘           └─────────────────┘               │
          │                                                                   │
          │   ┌─────────────────┐           ┌─────────────────┐               │
          │   │  REDIS          │           │  RABBITMQ       │               │
          │   │ (Port 6379)     │           │   (AMQP)        │               │
          │   │                 │           │                 │               │
          │   │ • Cache         │           │ • Message       │               │
          │   │ • Session       │           │   Broker        │               │
          │   │ • JSON Serial   │           │ • Durable       │               │
          │   └────┬────────────┘           │   Queues        │               │
          │        │                        └────┬────────────┘               │
          │        │                             │                            │
          │        │        ┌────────────────────│                            │
          │        │        │                    │                            │
          │        ▼        ▼                    ▼                            │
          │   ┌────-────────────────────┐   ┌──────────────────────────┐      │
          │   │     OMNI-WORKER         │   │     FLOW-WORKER          │      │
          │   │   Replicas: 2+ inst.    │   │   (1 instance)           │      │
          │   │                         │   │                          │      │
          │   │ • Background Tasks      │   │ • Workflow Processing    │      │
          │   │ • Celery Worker         │   │ • Celery Worker          │      │
          │   │ • Resources: 1 vCPU,    │   │ • Resources: 1 vCPU,     │      │
          │   │   2 GB RAM per instance │   │   2 GB RAM               │      │
          │   └─────────────────────────┘   └──────────────────────────┘      │
          │                                                                   │
          │   ┌─────────────────────────────┐                                 │
          │   │      OMNI-SCHEDULER         │                                 │
          │   │      Replica: 1 instance    │                                 │
          │   │                             │                                 │
          │   │ • Periodic Task Scheduling  │                                 │
          │   │ • Celery Beat               │                                 │
          │   │ • Resources: 0.5 vCPU, 1 GB │                                 │
          │   └─────────────────────────────┘                                 │
          │───────────────────────────────────────────────────────────────────┘
          ▼
External Services (Optional):
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐
│   FILE STORAGE  │  │ AUTHENTICATION  │  │    MONITORING   │  │ CREGO LICENSE  │
│                 │  │                 │  │                 │  │    SERVER      │
│ • Amazon S3     │  │ • OIDC Providers│  │ • Sentry        │  │                │
│ • Google Cloud  │  │ • AWS Cognito   │  │ • Remote Syslog │  │ • License      │
│                 │  │ • Okta/Auth0    │  │                 │  │   Verification │
│                 │  │                 │  │                 │  │ • Feature Flags│
└─────────────────┘  └─────────────────┘  └─────────────────┘  └────────────────┘
```

---

## **🌐 Single Domain Architecture**

The entire Crego Platform (frontend applications AND backend APIs) is deployed using a single domain architecture (`crego[-preprod].yourdomain.com`) through CloudFront distribution with path-based routing.

### **Complete Application Routing**

All services are accessible from the same domain using path-based routing:

- **Frontend Applications**:
  - `/` → omni-web (React SPA)
  - `/flow/*` → flow-web (React SPA for workflow management)
- **Backend APIs**:
  - `/api/*` → omni-api (Django REST API)
  - `/flow/api/*` → flow-api (FastAPI Workflow Engine)

### **Architecture Benefits**

1. **Unified Access**: Single domain for all application components
2. **Single TLS Certificate**: One SSL certificate covers entire application
3. **Simplified CORS**: No cross-origin issues between frontend and backend
4. **Centralized CDN**: Global performance for both static assets and API responses
5. **Single DNS Management**: Simplified domain and routing configuration
6. **Cost Optimization**: Shared CloudFront distribution and load balancer

### **Technical Implementation**

- **CloudFront Distribution**: Acts as the single entry point
- **Multiple Origins**: S3 buckets for static assets, ALB for dynamic APIs
- **Cache Behaviors**: Optimized caching strategies per content type
- **SSL Termination**: Handled at CloudFront level for entire application

---

## **🐳 Container Services**

### **omni-api**

- **Port**: 8000
- **Health Check**: `GET /api/health/` (lightweight) or `GET /api/health/detailed/` (comprehensive)
- **Resources**: 1 vCPU, 2 GB RAM
- **Replicas**: 2+ (scale based on traffic)

### **omni-worker**

- **Purpose**: Background task processing
- **Health Check**: Container-level ping check
- **Resources**: 1 vCPU, 2 GB RAM
- **Replicas**: 2+ (scale based on task volume)

### **omni-scheduler**

- **Purpose**: Periodic task scheduling
- **Health Check**: Database connectivity check
- **Resources**: 0.5 vCPU, 1 GB RAM
- **Replicas**: 1 only (single scheduler instance required)

### **flow-api**

- **Port**: 8000
- **Purpose**: FastAPI-based workflow execution engine with MongoDB integration
- **Health Check**: `GET /flow/api/health/` (lightweight) or `GET /flow/api/health/detailed/` (comprehensive)
- **Resources**: 1 vCPU, 2 GB RAM
- **Replicas**: 2+ (scale based on workflow volume)
- **Dependencies**: MongoDB, RabbitMQ, Omni API (for JWT authentication)
- **Authentication**:
  - **Method**: JWT tokens issued by Omni service
  - **Validation**: Flow service validates tokens via JWKS endpoint from Omni
  - **Flow**: User → Omni (auth) → JWT token → Flow API (validate via JWKS)
  - **Configuration**: `JWT_VERIFICATION_KEY` must match Omni’s signing key

### **flow-worker**

- **Purpose**: Background workflow task processing using Celery
- **Working Directory**: `$PROJECT_DIR/project`
- **Health Check**: `pipenv run celery -A celery_config:celery_app inspect ping`
- **Resources**: 1 vCPU, 2 GB RAM
- **Replicas**: 1 (default instance)
- **Dependencies**: MongoDB, RabbitMQ

### **flow-web**

- **Purpose**: React SPA for workflow management interface
- **Deployment**: Static file hosting (web server, CDN, or cloud storage)
- **Resources**: Minimal (static files only)
- **Dependencies**: Flow API for backend communication

---

## **🌐 Frontend Deployment (S3 based Artifact)**

Both frontend applications are deployed as part of the Single Domain Architecture (see above section) using static file hosting with CloudFront distribution and S3 origins.

### **omni-web**

- **Type**: React Single Page Application (SPA)
- **Path**: `/` (root path)
- **Delivery**: Pre-built production bundle (ZIP file provided by Crego)
- **Deployment**: S3 Origin A + CloudFront cache behavior
- **Resources**: Minimal (static files only)

### **flow-web**

- **Type**: React Single Page Application (SPA) for workflow management
- **Path**: `/flow/*`
- **Delivery**: Pre-built production bundle (ZIP file provided by Crego)
- **Deployment**: S3 Origin B + CloudFront cache behavior
- **Resources**: Minimal (static files only)
- **API Integration**: Connects to Flow API via `/flow/api/*` path

### **CloudFront Distribution Setup**

**Step-by-Step CloudFront Setup**

1. **Create S3 Buckets**:

   ```bash
   # Create buckets for static assetsaws s3 mb s3://omni-web-bucket --region us-east-1
   aws s3 mb s3://flow-web-bucket --region us-east-1
   # Configure bucket policies for CloudFront accessaws s3api put-bucket-policy --bucket omni-web-bucket --policy file://omni-bucket-policy.json
   aws s3api put-bucket-policy --bucket flow-web-bucket --policy file://flow-bucket-policy.json
   ```

2. **Deploy Static Assets**:

   ```bash
   # Upload omni-web buildaws s3 sync ./omni-web-build/ s3://omni-web-bucket --delete# Upload flow-web buildaws s3 sync ./flow-web-build/ s3://flow-web-bucket --delete
   ```

3. **Create CloudFront Distribution**:
   - **Origins**:
     - **Origin A**: S3 bucket for omni-web (`omni-web-bucket.s3.amazonaws.com`)
     - **Origin B**: S3 bucket for flow-web (`flow-web-bucket.s3.amazonaws.com`)
     - **Origin C**: Application Load Balancer for backend APIs (`your-alb.region.elb.amazonaws.com`)
4. **Configure Cache Behaviors** (order is critical - first match wins):

   **Behavior 1: Omni API**

   ```
   Path Pattern: /api/*
   Origin: Origin C (Load Balancer)
   Viewer Protocol Policy: Redirect HTTP to HTTPS
   Cache Policy: Caching Disabled
   Origin Request Policy: CORS-S3Origin
   ```

   **Behavior 2: Flow API**

   ```
   Path Pattern: /flow/api/*
   Origin: Origin C (Load Balancer)
   Viewer Protocol Policy: Redirect HTTP to HTTPS
   Cache Policy: Caching Disabled
   Origin Request Policy: CORS-S3Origin
   ```

   **Behavior 3: Flow Web Assets**

   ```
   Path Pattern: /flow/*
   Origin: Origin B (S3 flow-web)
   Viewer Protocol Policy: Redirect HTTP to HTTPS
   Cache Policy: Caching Optimized
   Custom Error Pages: 404 → /flow/index.html (200 response)
   ```

   **Behavior 4: Default (Omni Web Assets)**

   ```
   Path Pattern: Default (*)
   Origin: Origin A (S3 omni-web)
   Viewer Protocol Policy: Redirect HTTP to HTTPS
   Cache Policy: Caching Optimized
   Custom Error Pages: 404 → /index.html (200 response)
   ```

5. **Configure Custom Error Pages**:
   - **404 Errors for Omni**: Return `/index.html` with 200 status (for React SPA routing)
   - **404 Errors for Flow**: Return `/flow/index.html` with 200 status (for React SPA routing)
   - **403 Errors**: Same as 404 errors (CloudFront may return 403 for missing S3 objects)
   - **Response Code**: Always return 200 to allow client-side routing to handle the path
6. **Benefits**:
   - Single TLS certificate for entire domain
   - Single DNS name management
   - Centralized CDN distribution
   - Cost-effective routing solution

---

## **☁️ Environment Configuration Requirements**

### **Web Environment Variables (Build Time)**

<aside>
💡

⚠️ **IMPORTANT**: All environment variables must be provided during build time for web services, as they are compiled into the static bundles.

</aside>

**Required during React build process:**

- `VITE_API_ROOT_FLOW=/flow/api`
- `VITE_API_ROOT_OMNI=/api`
- `VITE_BASE_URL_FLOW=/flow`
- `VITE_BASE_URL_OMNI=/`
- `VITE_SENTRY_DSN=sentry-dsn` (optional)

### **Build-Time vs Runtime Configuration**

- **Frontend (React)**: Environment variables are **build-time only** and become part of the static bundle
- **Backend (APIs)**: Environment variables are **runtime** and can be changed without rebuilding
- **Deployment**: Frontend bundles must be rebuilt if API URLs change

### **Setup Steps**

1. **Obtain Build Files**:
   - **Direct Delivery**: Download and extract the provided omni-web ZIP package, OR
   - **S3 Replication**: Crego can sync ZIP files directly to your S3 bucket via replication
2. **Configure API URLs**: Update configuration files with your backend URLs
3. **Deploy Static Files**: Upload to your chosen hosting platform
4. **Configure Routing**: Set up server rules for SPA routing (fallback to index.html)
5. **Enable HTTPS**: Configure SSL certificate for secure connections
6. **Test Connectivity**: Verify frontend can communicate with backend APIs

### **Backend Variables Configuration**

- **Environment File**: `env_file="/path/to/env/file"`
- **System Environment Variables**: Direct environment variable injection

| **Variable**                              | Required | Default                                         | Description                                                                            | Example                                                   |
| ----------------------------------------- | -------- | ----------------------------------------------- | -------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| **`ENV`**                                 | Yes      | `preprod`                                       | Environment type (preprod, prod) where preprod similar to UAT env.                     | `prod`                                                    |
| **`TIMEZONE`**                            | No       | `Asia/Kolkata`                                  | Application timezone for datetime operations and user display                          | `UTC`                                                     |
| **`SERVICE_NAME`**                        | Yes      | `omni`                                          | Primary service identifier used for logging, queues, and database naming               | `omni`                                                    |
| **`SERVICE_HOST`**                        | Yes      | `http://127.0.0.1:8000`                         | Primary service URL where application is hosted - used for JWT issuer and redirects    | `https://crego.yourdomain.com`                            |
| **`OMNI_ENDPOINT_PREFIX`**                | No       | _(empty)_                                       | Alternative way to set ENDPOINT_PREFIX specifically for Omni service                   | `api`                                                     |
| **`FLOW_ENDPOINT_PREFIX`**                | No       | _(empty)_                                       | Flow API path prefix (for multi-service deployments)                                   | `flow/api`                                                |
| **`OMNI_INTERNAL_HOST`**                  | No       | [`http://omni-api:8000`](http://omni-api:8000/) | Internal load balancer DNS for omni-api service (for service-to-service communication) | `http://omni-api:8000`                                    |
| **`SECRET_KEY`**                          | Yes      | Generated                                       | Base64-encoded Fernet key for Django encryption and security                           | `strong-encryption-key`                                   |
| **`JWT_SIGNING_KEY`**                     | Yes      | Generated                                       | Base64-encoded JWT signing key for token creation                                      | `your_jwt_signing_key_here`                               |
| **`JWT_VERIFICATION_KEY`**                | Yes      | Generated                                       | Base64-encoded JWT verification key for token validation                               | `your_jwt_verification_key_here`                          |
| **`DEFAULT_POSTGRES_DB_HOST`**            | Yes      | `localhost`                                     | PostgreSQL database host                                                               | `your-db.rds.yourdomain.com`                              |
| **`DEFAULT_POSTGRES_DB_PORT`**            | Yes      | `5432`                                          | PostgreSQL database port                                                               | `5432`                                                    |
| **`DEFAULT_POSTGRES_DB_NAME`**            | Yes      | `omni_default_db`                               | PostgreSQL database name                                                               | `omni_production_db`                                      |
| **`DEFAULT_POSTGRES_DB_USERNAME`**        | Yes      | `postgres`                                      | PostgreSQL database username                                                           | `omni_user`                                               |
| **`DEFAULT_POSTGRES_DB_PASSWORD`**        | Yes      | `postgres`                                      | PostgreSQL database password                                                           | `secure_password`                                         |
| **`DEFAULT_POSTGRES_DB_SSLMODE`**         | Yes      | `disable`                                       | PostgreSQL SSL mode (use `require` for production)                                     | `require`                                                 |
| **`DEFAULT_POSTGRES_DB_CONNECT_TIMEOUT`** | Yes      | `10`                                            | PostgreSQL connection timeout in seconds                                               | `30`                                                      |
| **`DEFAULT_POSTGRES_DB_CONN_MAX_AGE`**    | No       | `120`                                           | PostgreSQL connection reuse duration in seconds                                        | `300`                                                     |
| **`DEFAULT_MONGODB_URI`**                 | No       | `mongodb://localhost:27017`                     | MongoDB connection URI (for future Flow services integration)                          | `mongodb+srv://user:pass@cluster.mongodb.net`             |
| **`DEFAULT_MONGODB_NAME`**                | No       | `default-flow-db`                               | MongoDB database name (for future Flow services integration)                           | `flow_production_db`                                      |
| **`REDIS_HOST`**                          | Yes      | `localhost`                                     | Redis cache host (shared by all services)                                              | `your-redis.cache.yourdomain.com`                         |
| **`REDIS_PORT`**                          | Yes      | `6379`                                          | Redis cache port                                                                       | `6379`                                                    |
| **`RABBITMQ_URI`**                        | Yes      | `amqp://guest:*****@localhost:5672/`            | RabbitMQ connection URI for Celery task queue (shared by all services)                 | `amqps://user:pass@your-rabbitmq:5671/`                   |
| **`CORS_ALLOWED_ORIGINS`**                | Yes      | `http://localhost:8080,http://127.0.0.1:8080`   | Comma-separated list of allowed CORS origins                                           | `https://crego.yourdomain.com,https://app.yourdomain.com` |
| **`ALLOWED_HOSTS`**                       | Yes      | `localhost,127.0.0.1`                           | Comma-separated list of allowed hosts for Django                                       | `crego.yourdomain.com,*.yourdomain.com`                   |
| **`ALLOWED_CIDR_NETS`**                   | No       | _(empty)_                                       | Comma-separated list of CIDR networks for internal access (K8s/ECS health checks)      | `10.0.0.0/8,172.16.0.0/12`                                |
| **`ADMIN_USERNAME`**                      | Yes      | `admin`                                         | Default admin user username                                                            | `admin`                                                   |
| **`ADMIN_PASSWORD`**                      | Yes      | `admin123`                                      | Default admin user password                                                            | `secure_admin_password`                                   |
| **`ADMIN_EMAIL`**                         | Yes      | `admin@localhost`                               | Default admin user email                                                               | `admin@yourdomain.com`                                    |
| **`RATE_LIMIT_ENABLED`**                  | No       | _(empty)_                                       | Enable API rate limiting (for future Flow services integration)                        | `false`                                                   |
| **`RATE_LIMIT_REQUESTS`**                 | No       | _(empty)_                                       | Rate limit requests per minute (for future Flow services integration)                  | `500`                                                     |
| **`OMNI_SENTRY_DSN`**                     | No       | _(empty)_                                       | Sentry error tracking DSN for Omni service                                             | `https://key@org.ingest.sentry.io/project`                |
| **`FLOW_SENTRY_DSN`**                     | No       | _(empty)_                                       | Sentry error tracking DSN for Flow service                                             | `https://key@org.ingest.sentry.io/project`                |
| **`LOG_BACKENDS`**                        | No       | `console`                                       | Comma-separated logging backends (console, rsys)                                       | `console,rsys`                                            |
| **`RSYS_HOST`**                           | No       | _(empty)_                                       | Remote syslog host for structured logging                                              | `rsyslog.yourdomain.com`                                  |
| **`RSYS_PORT`**                           | No       | `514`                                           | Remote syslog port                                                                     | `514`                                                     |

---

## **🚀 Deployment Steps**

### **1. Infrastructure Setup**

1. Deploy required infrastructure services:
   - **Omni Services**: PostgreSQL, Redis, RabbitMQ
   - **Flow Services**: MongoDB, RabbitMQ (shared), Redis (shared)
2. Configure shared environment variables using your secrets management solution:
   - All environment variables are shared across services (see Environment Variables section)
   - Configure authentication and database connections
   - Set up cross-service JWT authentication
3. Set up networking and security groups for service communication
4. Configure load balancer routing for prefix-based service routing

### **2. Service Deployment**

Deploy all services with the shared environment configuration. All services are stateless and can be deployed using your preferred orchestration platform (Kubernetes, ECS, Docker Swarm).

### **Deployment Order:**

1. **Infrastructure Services**: PostgreSQL, MongoDB, Redis, RabbitMQ
2. **Core API Services**: omni-api (required for authentication across all services)
3. **Background Workers**: omni-worker, omni-scheduler, flow-worker
4. **API Services**: flow-api (depends on omni-api for authentication)
5. **Frontend Applications**: omni-web, flow-web (static file deployment)

**Service Dependencies:**

- **flow-api**: Requires omni-api for JWT token validation
- **flow-worker**: Requires MongoDB and RabbitMQ for task processing
- **omni-worker/omni-scheduler**: Require PostgreSQL and RabbitMQ
- **All services**: Share Redis for caching and session management

### **3. Post-Installation Configuration**

After successful deployment, configure application settings via the admin interface:

1. **Access Admin Interface**: Navigate to `https://crego.yourdomain.com/api/admin/`
2. **Login**: Use the admin credentials from environment variables (`ADMIN_USERNAME`, `ADMIN_PASSWORD`)
3. **Configure Settings**: Go to Core > Settings to configure:
   - **Authentication Methods**: OIDC, SMS OTP, Email OTP
   - **OIDC Settings**: Configure identity providers (issuer, client credentials, JWKS endpoint)
   - **SMS Service**: Kaleyra configuration for OTP delivery
   - **Email Service**: SMTP configuration for notifications
   - **JWT Settings**: Token lifetimes and custom claims
   - **Login Settings**: Authentication methods per user type (staff/customer/partner)

**Example Login Configuration:**

```json
{
  "staff": ["oidc_username_password"],
  "customer": ["username_password", "otp_email", "otp_sms"],
  "partner": ["username_password"]
}
```

### **Cross-Service Authentication (Flow ↔︎ Omni)**

Flow services depend on Omni for authentication. Here’s how it works:

1. **User Authentication**: Users authenticate with Omni service
2. **JWT Token Issuance**: Omni issues JWT tokens with shared signing key
3. **Token Validation**: Flow API validates tokens using the same `JWT_VERIFICATION_KEY`
4. **JWKS Endpoint**: Flow service can optionally fetch public keys from Omni’s JWKS endpoint

**Required Configuration**:

- Both services must share the same `JWT_SIGNING_KEY` and `JWT_VERIFICATION_KEY`
- Flow service must have network access to Omni service for token validation
- `SIMPLE_JWT` settings must be identical across both services

---

## **📊 Monitoring & Health Checks**

### **Health Check Endpoints**

| Service     | Endpoint                                                             | Purpose              | Components Checked                     |
| ----------- | -------------------------------------------------------------------- | -------------------- | -------------------------------------- |
| omni-api    | `GET /api/health/`                                                   | Load balancer health | Django app status                      |
| omni-api    | `GET /api/health/detailed/`                                          | Comprehensive health | Django + PostgreSQL + Redis + RabbitMQ |
| flow-api    | `GET /flow/api/health/`                                              | Load balancer health | FastAPI app status                     |
| flow-api    | `GET /flow/api/health/detailed/`                                     | Comprehensive health | FastAPI + MongoDB + Redis + RabbitMQ   |
| omni-worker | `pipenv run celery -A project.celery_config:celery_app inspect ping` | Worker status        | Celery worker process                  |
| flow-worker | `pipenv run celery -A celery_config:celery_app inspect ping`         | Worker status        | Celery worker process                  |

### **Access URLs**

**Single Domain**: `https://crego[-preprod].yourdomain.com`

### **Frontend Applications**

- **Omni Web Application**: `https://crego.yourdomain.com/` (React SPA)
- **Flow Web Application**: `https://crego.yourdomain.com/flow/` (React SPA)

### **API Endpoints**

- **Omni API Base**: `https://crego.yourdomain.com/api/` (Backend API)
- **Flow API Base**: `https://crego.yourdomain.com/flow/api/` (Workflow API)

### **Health Checks**

- **Omni Health Check**: `https://crego.yourdomain.com/api/health/`
- **Flow Health Check**: `https://crego.yourdomain.com/flow/api/health/`

### **Admin Interfaces**

- **Omni Admin Interface**: `https://crego.yourdomain.com/api/admin/`

### **Log Destinations**

- **Console**: Default output (captured by container orchestration)
- **Syslog**: Optional remote logging (`LOG_BACKENDS=console,rsys`)
- **Sentry**: Error tracking and performance monitoring

---

## **💰 Production Cost Analysis**

### **Minimum Production Deployment**

**Total Monthly Cost: $427.39**

| Service Category              | Cost    | Configuration                                  |
| ----------------------------- | ------- | ---------------------------------------------- |
| **Compute (ECS Fargate)**     | $198.22 | 5 containers: 5.5 vCPUs, 11 GB RAM             |
| **RDS PostgreSQL**            | $14.81  | db.t3.micro (1 vCPU, 1 GB RAM) + 20 GB storage |
| **MongoDB Atlas**             | $57.00  | M10 cluster (2 vCPUs, 2 GB RAM)                |
| **ElastiCache Redis**         | $15.84  | cache.t3.micro (2 vCPUs, 0.5 GB RAM)           |
| **Amazon MQ RabbitMQ**        | $23.04  | mq.t3.micro (1 vCPU, 1 GB RAM)                 |
| **Application Load Balancer** | $21.20  | Standard ALB with basic LCU usage              |
| **CloudFront CDN**            | $85.75  | 1TB data transfer + 1M requests                |
| **S3 Storage**                | $0.63   | 10 GB standard storage for static assets       |
| **Route 53 DNS**              | $0.90   | Hosted zone + 1M queries                       |
| **CloudWatch Monitoring**     | $10.00  | Basic logs and metrics                         |

### **Container Resource Allocation**

| Service        | Instances | CPU      | Memory | Purpose                 |
| -------------- | --------- | -------- | ------ | ----------------------- |
| omni-api       | 1         | 1 vCPU   | 2 GB   | Django REST API         |
| omni-worker    | 1         | 1 vCPU   | 2 GB   | Background tasks        |
| omni-scheduler | 1         | 0.5 vCPU | 1 GB   | Celery Beat scheduler   |
| flow-api       | 1         | 1 vCPU   | 2 GB   | FastAPI workflow engine |
| flow-worker    | 1         | 1 vCPU   | 2 GB   | Workflow processing     |

### **Cost Optimization Opportunities**

### **Immediate Savings (10-20% reduction):**

1. **Reserved Instances (1-year terms):**
   - RDS: Save 30% = $4.44/month
   - ElastiCache: Save 25% = $3.96/month
   - **Total Savings**: $8.40/month
2. **Compute Savings Plans:**
   - ECS Fargate: Save 20% = $39.64/month
   - **Total Savings**: $39.64/month

### **Medium-term Optimizations:**

1. **Auto-scaling Configuration:**
   - Scale down during off-peak hours (12 hours/day)
   - **Potential Savings**: $60-80/month
2. **MongoDB Atlas Optimization:**
   - Use M5 cluster for lower traffic: Save $27/month
   - **Note**: Only if workflow volume is low
3. **CDN Usage Optimization:**
   - Better caching strategies: Save 15-20%
   - **Potential Savings**: $12-17/month

### **Scaling Cost Impact**

| Traffic Level   | Additional Monthly Cost | Notes                                        |
| --------------- | ----------------------- | -------------------------------------------- |
| **2x traffic**  | +$80-120                | Requires scaling to 2 instances each         |
| **5x traffic**  | +$250-350               | Multiple instance scaling + larger databases |
| **10x traffic** | +$500-700               | Full high-availability deployment            |

### **High Availability Upgrade**

**Additional Cost: +$180/month**

- **Multi-instance deployment**: +$108/month (duplicate containers)
- **RDS Multi-AZ**: +$15/month
- **MongoDB Atlas cluster**: +$57/month (M10 → M20)

**Total HA Cost: $607.39/month**

### **Cost Considerations**

### **Trade-offs of Minimum Configuration:**

- **Single Point of Failure**: No instance redundancy
- **Limited Scalability**: Manual intervention required for traffic spikes
- **Performance Constraints**: Smaller database instances may impact performance

### **Recommended Production Upgrades:**

1. **High Availability**: Add instance redundancy (+$180/month)
2. **Database Scaling**: Upgrade to larger instances as usage grows
3. **Monitoring Enhancement**: Add comprehensive observability tools
4. **Backup Strategy**: Implement automated backup solutions

### **Annual Cost Planning:**

- **Minimum Production**: $5,128/year
- **High Availability**: $7,289/year
- **Reserved Instance Savings**: $500-1,000/year

---

## **🔗 Container Networking & Ports**

### **Port Configuration**

| Service     | Internal Port | Load Balancer Port | Protocol   | Purpose                     |
| ----------- | ------------- | ------------------ | ---------- | --------------------------- |
| omni-api    | 8000          | 80/443             | HTTP/HTTPS | Django REST API             |
| flow-api    | 8000          | 80/443             | HTTP/HTTPS | FastAPI Workflow Engine     |
| omni-worker | N/A           | N/A                | N/A        | Background processing       |
| flow-worker | N/A           | N/A                | N/A        | Background processing       |
| omni-web    | N/A           | 80/443             | HTTP/HTTPS | Static files via CloudFront |
| flow-web    | N/A           | 80/443             | HTTP/HTTPS | Static files via CloudFront |

### **Container Networking Requirements**

- **API Services**: Both `omni-api` and `flow-api` expose port 8000 internally
- **Load Balancer**: Routes to services based on path prefix (`/api/*` → omni-api, `/flow/api/*` → flow-api)
- **Service Communication**:
  - Flow services must reach Omni API for JWT validation
  - All services need access to shared infrastructure (Redis, RabbitMQ)
- **Security Groups**: Configure ingress rules for container-to-container communication
- **DNS**: Use service discovery or internal DNS for service-to-service communication

---

## **☁️ Infrastructure Requirements**

### **1. PostgreSQL Database**

- **Purpose**: Primary database for application data and Celery results
- **Deployment**: Amazon RDS (recommended) or self-managed
- **Version**: PostgreSQL 14.x or 16.x
- **Configuration**:
  - SSL required (`POSTGRES_DB_SSLMODE=require`)
  - Connection timeout: 10 seconds
  - Connection pooling recommended
- **Required Extensions**: None (uses standard PostgreSQL features)

### **2. Redis/Valkey Cache**

- **Purpose**: Django caching layer and session storage
- **Deployment**: Amazon ElastiCache or self-managed
- **Versions**: Redis 6.2.6+ or Valkey 8.0+
- **Configuration**:
  - Max connections: 100
  - JSON serialization
  - Connection retry on timeout

### **3. RabbitMQ Message Broker**

- **Purpose**: Celery task message broker
- **Deployment**: AWS MQ (recommended) or self-managed
- **Features Required**:
  - Message priorities (1-10 range)
  - Message TTL (24 hours)
  - Durable queues
  - Dead letter exchanges
- **Queue Configuration**:
  - Default queue: `omni-default-queue`
  - Dead letter queue: `omni-dead-letter-queue`

### **4. MongoDB Database**

- **Purpose**: Flow service data storage for workflows, documents, and execution history
- **Deployment**: MongoDB Atlas (recommended) or self-managed
- **Version**: MongoDB 8.x
- **Configuration**:
  - SSL/TLS enabled (`mongodb+srv://` or `ssl=true`)
  - Connection timeout: 10 seconds
  - Connection pooling recommended
  - Authentication required for production
- **Storage Requirements**:
  - Workflow definitions and execution history
  - Document storage and metadata
  - User session data (if not using Redis)
- **High Availability**: Replica set configuration recommended for production

### **5. File Storage**

- **Purpose**: Document and file storage
- **Supported Backends**:
  - Amazon S3 (recommended)
  - Google Cloud Storage
- **Configuration**: Managed through Django admin interface

### **6. Authentication**

- **Default**: Username/password authentication
- **Configurable Methods**:
  - **OIDC**: OpenID Connect providers (AWS Cognito, Okta, Auth0, Azure AD)
  - **OTP SMS**: SMS-based one-time passwords via Kaleyra
  - **OTP Email**: Email-based one-time passwords
- **User Types**: Staff, Customer, Partner (each with configurable login methods)
- **Token Types**: JWT with HS256/RS256 algorithms

### **7. External Services (Optional)**

### **Crego License Server**

- **Purpose**: License verification and feature flag management
- **Integration**: Connected via omni-api service only
- **Configuration**: Managed through Core > Settings in Django admin
- **Features**:
  - License validation and verification
  - Feature flag toggles and URL pattern control
  - Automated license status checking
- **Middleware**: LicenseMiddleware enforces license verification for API calls
- **Bypass**: Health check endpoints bypass license verification

### **Authentication Services**

- **Purpose**: External identity providers for OIDC authentication
- **Integration**: Connected via omni-api service only
- **Supported Providers**:
  - AWS Cognito
  - Okta
  - Auth0
  - Azure AD
  - Custom OIDC providers
- **Configuration**: OIDC settings configured in Django admin
- **Features**:
  - Single Sign-On (SSO)
  - Multi-factor authentication
  - User provisioning and deprovisioning

### **File Storage Services**

- **Purpose**: Document and file storage for omni services
- **Integration**: Connected via omni-api service only
- **Supported Backends**:
  - Amazon S3 (recommended)
  - Google Cloud Storage
  - Azure Blob Storage
- **Configuration**: Storage backends configured through Django admin
- **Usage**: Document uploads, file attachments, bulk operations

### **Monitoring Services**

- **Purpose**: Application monitoring and logging
- **Integration**: All services can connect
- **Supported Services**:
  - **Sentry**: Error tracking and performance monitoring
  - **Remote Syslog**: Centralized log aggregation
- **Configuration**:
  - Sentry DSN configured via service-specific environment variables (`OMNI_SENTRY_DSN`, `FLOW_SENTRY_DSN`)
  - Syslog configured via `RSYS_HOST` and `RSYS_PORT` variables

---

## **🔒 Security Considerations**

1. **Environment Variables**: Store sensitive values securely using your preferred secrets management solution
2. **SSL/TLS**: Enable SSL for all database connections (`POSTGRES_DB_SSLMODE=require`)
3. **CORS Configuration**:
   - Set `CORS_ALLOWED_ORIGINS` to your exact domain: `https://crego.yourdomain.com`
   - Never use wildcards (\*) in production
   - Single domain architecture simplifies CORS configuration
4. **JWT Keys**: Use strong, unique base64-encoded keys for production

---

## **🔧 Container Resource Recommendations**

### **Production Environment**

| Service        | CPU      | Memory | Replicas | Notes                        |
| -------------- | -------- | ------ | -------- | ---------------------------- |
| omni-api       | 1 vCPU   | 2 GB   | 2+       | Scale based on traffic       |
| omni-worker    | 1 vCPU   | 2 GB   | 2+       | Scale based on task volume   |
| omni-scheduler | 0.5 vCPU | 1 GB   | 1        | Single instance only         |
| flow-api       | 1 vCPU   | 2 GB   | 2+       | Scale based on workflow load |
| flow-worker    | 1 vCPU   | 2 GB   | 1        | Default single instance      |

### **Development Environment**

| Service        | CPU       | Memory | Replicas |
| -------------- | --------- | ------ | -------- |
| omni-api       | 0.5 vCPU  | 1 GB   | 1        |
| omni-worker    | 0.5 vCPU  | 1 GB   | 1        |
| omni-scheduler | 0.25 vCPU | 512 MB | 1        |
| flow-api       | 0.5 vCPU  | 1 GB   | 1        |
| flow-worker    | 0.5 vCPU  | 1 GB   | 1        |

---

## **🆘 Troubleshooting**

### **Common Issues**

1. **Database Connection Failed**
   - Check `POSTGRES_DB_*` environment variables
   - Verify database server accessibility
   - Confirm SSL configuration
2. **Celery Tasks Not Processing**
   - Verify RabbitMQ connectivity (`RABBITMQ_URI`)
   - Check worker health: `pipenv run celery -A project.celery_config:celery_app inspect ping`
   - Review worker logs for task failures
3. **Health Check Failures**
   - Use `/health/detailed/` for component-specific status
   - Check individual service connectivity (PostgreSQL, Redis, RabbitMQ)
   - Review application logs for specific error messages
4. **MongoDB Connection Issues (Flow Service)**
   - Check `DEFAULT_MONGODB_URI` and `DEFAULT_MONGODB_NAME` environment variables
   - Verify MongoDB server accessibility and authentication
   - Confirm SSL configuration for MongoDB Atlas connections
   - Check database user permissions
5. **Flow Authentication Issues**
   - Verify Flow service can reach Omni API (`OMNI_INTERNAL_HOST`)
   - Check JWT token validation between services
   - Ensure Omni service is running and accessible
   - Review OIDC issuer configuration
6. **General Authentication Issues**
   - Verify OIDC configuration if using SSO
   - Check JWT key configuration
   - Ensure admin user creation was successful

### **Diagnostic Commands**

### **Omni Service Diagnostics**

```bash
# Check Omni service status via health endpointscurl https://crego.yourdomain.com/api/health/
curl https://crego.yourdomain.com/api/health/detailed/
# Check Celery worker statusdocker exec <omni-worker-container> pipenv run celery -A project.celery_config:celery_app inspect active
# Access Django admin# Navigate to https://crego.yourdomain.com/api/admin/
```

### **Flow Service Diagnostics**

```bash
# Check Flow service status via health endpointscurl https://crego.yourdomain.com/flow/api/health/
curl https://crego.yourdomain.com/flow/api/health/detailed/
# Check Flow service logsdocker logs <flow-api-container>docker logs <flow-worker-container>
```

---

## **🔑** Secret Key Rotation

The section provides comprehensive validation, corruption detection, and verification to ensure safe key rotation without data loss.

### Command Usage

```bash
# Basic rotation with interactive confirmationpipenv run python manage.py rotate_secret_key
# Generate and use a new key automatically
pipenv run python manage.py rotate_secret_key --new-key "$(python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")"

# Dry run to see what would be rotated
pipenv run python manage.py rotate_secret_key --dry-run

# Skip corrupted data and continue with valid records
pipenv run python manage.py rotate_secret_key --skip-corrupted

# Create backup before rotation
pipenv run python manage.py rotate_secret_key --backup

# Detailed reporting
pipenv run python manage.py rotate_secret_key --report-only -v 2
```

### Command Options

| Option             | Description                                                      |
| ------------------ | ---------------------------------------------------------------- |
| `--dry-run`        | Show what would be rotated without making changes                |
| `--backup`         | Create backup of encrypted data before rotation                  |
| `--force`          | Skip confirmation prompts (for automation)                       |
| `--new-key KEY`    | Use specific new key (base64 encoded Fernet key)                 |
| `--skip-corrupted` | Skip corrupted/undecryptable data and continue with valid data   |
| `--report-only`    | Only report data status without performing rotation              |
| `-v 2`             | Verbose output showing detailed breakdown and corruption details |

### Pre-Rotation Assessment

Before rotating keys, assess your encrypted data:

```bash
# Check what encrypted data exists
pipenv run python manage.py rotate_secret_key --report-only
# Get detailed breakdown including corrupted records
pipenv run python manage.py rotate_secret_key --report-only -v 2
```

Example output:

```
Found 9 encrypted records:
  - 8 records can be rotated
  - 1 records are corrupted/undecryptable

Rotatable records by type:
  - 8 EncryptedJSONField instances

Rotatable records by model:
  - docs.storage: 8 records (EncryptedJSONField)

Corrupted records details:
  - workflow.workflow ID 01K8N4TRS9NFR5HW82MH0R22RH field secret: Decryption failed
```
