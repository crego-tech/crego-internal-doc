# Crego Platform Tech Stack

This document provides an overview of the technologies used across all Crego projects.

---

## crego-web

**Frontend Monorepo** - React-based web applications (flow-web, omni-web)

### Core Framework

| Technology | Version | Purpose |
|------------|---------|---------|
| React | 19.2.3 | UI Framework |
| TypeScript | ^5.5.3 | Type-safe JavaScript |
| Vite | - | Build tool |
| pnpm | - | Package manager with workspaces |

### Styling & UI

| Technology | Purpose |
|------------|---------|
| Tailwind CSS v4 | Utility-first CSS framework |
| Radix UI | Headless UI primitives (20+ components) |
| shadcn/ui | Component library built on Radix |
| Class Variance Authority | Component variant management |
| Lucide React | Icon library |
| tailwind-merge | Tailwind class merging |
| tailwindcss-animate | Animation utilities |

### State & Data Management

| Technology | Purpose |
|------------|---------|
| TanStack Query (React Query) | Server state management |
| React Hook Form | Form state management |
| Zod | Schema validation |
| Axios | HTTP client |

### Specialized Libraries

| Technology | Purpose |
|------------|---------|
| @xyflow/react | Flow/node-based diagrams |
| Monaco Editor | Code editor |
| Recharts | Charts and data visualization |
| RJSF (React JSON Schema Form) | Dynamic form generation |
| React Router v7 | Client-side routing |
| dnd-kit | Drag and drop |
| date-fns | Date utilities |
| mathjs | Math operations |

### Developer Experience

| Technology | Purpose |
|------------|---------|
| Husky | Git hooks |
| lint-staged | Pre-commit linting |
| Prettier | Code formatting |
| Sentry | Error monitoring |

---

## crego-infra

**Infrastructure as Code** - GitOps-based Kubernetes infrastructure

### Core Technologies

| Technology | Purpose |
|------------|---------|
| Kubernetes | Container orchestration |
| ArgoCD | GitOps CD (App-of-Apps pattern) |
| Kustomize | Kubernetes configuration management |

### Cloud Platforms

| Platform | Purpose |
|----------|---------|
| Google Cloud Platform (GCP) | Primary cloud (GKE, Secret Manager) |
| Amazon Web Services (AWS) | Secondary cloud (EKS, Secrets Manager) |

### Infrastructure Services

| Technology | Purpose |
|------------|---------|
| NGINX Ingress | Ingress controller (GCP) |
| AWS Load Balancer Controller | Ingress controller (AWS) |
| External Secrets Operator | Cloud secret synchronization |
| cert-manager | TLS certificate management |
| External DNS | Automated DNS management |

### Autoscaling & Processing

| Technology | Purpose |
|------------|---------|
| KEDA | Event-driven autoscaling (Celery workers) |
| HPA | Horizontal Pod Autoscaler (APIs) |

### Monitoring & Observability

| Technology | Purpose |
|------------|---------|
| Prometheus | Metrics collection |
| Grafana | Dashboards and visualization |
| OpenTelemetry | Distributed tracing |

### Development Services (Dev Environment)

| Technology | Purpose |
|------------|---------|
| PostgreSQL | Primary database |
| Redis | Cache and session store |
| RabbitMQ | Message broker |

### Configuration & Validation

| Technology | Purpose |
|------------|---------|
| yamllint | YAML validation |
| shellcheck | Shell script linting |
| cspell | Spell checking |
| Make | Build automation |

---

## crego-flow

**Workflow Engine** - FastAPI-based workflow execution engine

### Core Framework

| Technology | Version | Purpose |
|------------|---------|---------|
| Python | 3.13 | Runtime |
| FastAPI | Latest | Async web framework |
| Uvicorn | Latest | ASGI server |
| Gunicorn | Latest | Production server |

### Database & Storage

| Technology | Purpose |
|------------|---------|
| MongoDB | Document database |
| MongoEngine | MongoDB ODM |
| Redis | Caching and session storage |
| boto3 (S3) | Cloud file storage |
| Google Cloud Storage | Document storage |

### Background Processing

| Technology | Purpose |
|------------|---------|
| Celery | Distributed task queue |
| RabbitMQ | Message broker |
| Flower | Celery monitoring |

### Authentication & Security

| Technology | Purpose |
|------------|---------|
| PyJWT | JWT token handling |
| jwcrypto | JWT cryptographic operations |
| google-auth | Google OAuth integration |

### Document Processing

| Technology | Purpose |
|------------|---------|
| WeasyPrint | PDF generation |
| PyMuPDF (fitz) | PDF manipulation |
| python-docx | Word document generation |
| pdfkit | HTML to PDF conversion |
| Mako | Template engine |

### Data Processing

| Technology | Purpose |
|------------|---------|
| pandas | Data manipulation |
| openpyxl | Excel file handling |
| jsonschema | JSON validation |
| Jinja2 | Template rendering |
| jsonpath-ng | JSON path queries |

### Utilities

| Technology | Purpose |
|------------|---------|
| Hashids | ID obfuscation |
| num2words | Number to word conversion |
| humanize | Human-readable formatting |
| xmltodict | XML parsing |
| python-json-logger | Structured logging |

---

## crego-omni

**Main Platform API** - Django-based multi-tenant REST API

### Core Framework

| Technology | Version | Purpose |
|------------|---------|---------|
| Python | 3.13 | Runtime |
| Django | >=5.2.8 | Web framework |
| Django REST Framework | Latest | REST API toolkit |
| Gunicorn | Latest | Production server |

### Database & Storage

| Technology | Purpose |
|------------|---------|
| PostgreSQL | Primary relational database |
| psycopg | PostgreSQL adapter |
| django-redis | Redis cache backend |
| django-storages | Multi-cloud storage abstraction |
| boto3 | AWS S3 storage |
| azure-storage-blob | Azure Blob storage |
| google-cloud-storage | GCP Cloud Storage |

### Background Processing

| Technology | Purpose |
|------------|---------|
| Celery | Distributed task queue |
| django-celery-beat | Periodic task scheduler |
| django-celery-results | Task result backend |
| Flower | Celery monitoring |

### Authentication & Security

| Technology | Purpose |
|------------|---------|
| djangorestframework-simplejwt | JWT authentication |
| mozilla-django-oidc | OpenID Connect integration |
| python-jose | JWT/JWS/JWE handling |
| PyNaCl | Cryptographic operations |
| cryptography | Cryptographic recipes |

### API Extensions

| Technology | Purpose |
|------------|---------|
| django-filter | Queryset filtering |
| drf-flex-fields | Dynamic field expansion |
| drf-nested-routers | Nested API routes |
| drf-extensions | Additional DRF utilities |
| django-cors-headers | CORS handling |
| django-allow-cidr | CIDR-based access control |

### Document Processing

| Technology | Purpose |
|------------|---------|
| WeasyPrint | PDF generation |
| ReportLab | PDF creation |
| Mako | Template engine |
| Jinja2 | Template rendering |
| pdfkit | HTML to PDF |
| openpyxl | Excel handling |

### Data Processing

| Technology | Purpose |
|------------|---------|
| pandas | Data manipulation |
| numpy-financial | Financial calculations |
| jsonschema | JSON validation |
| pydantic | Data validation |
| python-dateutil | Date parsing |

### Monitoring & Logging

| Technology | Purpose |
|------------|---------|
| Sentry SDK | Error tracking |
| python-json-logger | Structured logging |
| whitenoise | Static file serving |

### Development Tools

| Technology | Purpose |
|------------|---------|
| pytest | Testing framework |
| pytest-django | Django test integration |
| coverage | Code coverage |
| black | Code formatting |
| flake8 | Linting |
| isort | Import sorting |
| pylint-django | Django-specific linting |
| pre-commit | Git hooks |
| ipython | Enhanced REPL |

### Utilities

| Technology | Purpose |
|------------|---------|
| Hashids | ID obfuscation |
| ulid-py | ULID generation |
| cachetools | Caching utilities |
| django-user-agents | User agent parsing |
| django-extensions | Django utilities |

---

## Summary by Category

### Languages

| Language | Projects |
|----------|----------|
| TypeScript/JavaScript | crego-web |
| Python 3.13 | crego-flow, crego-omni |
| YAML | crego-infra |
| Bash | crego-infra |

### Web Frameworks

| Framework | Project |
|-----------|---------|
| React 19 | crego-web |
| FastAPI | crego-flow |
| Django 5.2+ | crego-omni |

### Databases

| Database | Project | Purpose |
|----------|---------|---------|
| PostgreSQL | crego-omni, crego-infra (dev) | Relational data |
| MongoDB | crego-flow | Document storage |
| Redis | All | Caching |

### Message Queues

| Technology | Project |
|------------|---------|
| RabbitMQ | crego-flow, crego-omni |
| Celery | crego-flow, crego-omni |

### Cloud Providers

| Provider | Services Used |
|----------|---------------|
| GCP | GKE, Secret Manager, Cloud Storage |
| AWS | EKS, Secrets Manager, S3 |
| Azure | Blob Storage |

### Monitoring

| Technology | Project |
|------------|---------|
| Sentry | crego-web, crego-omni |
| Prometheus | crego-infra |
| Grafana | crego-infra |
| OpenTelemetry | crego-infra |
| Flower | crego-flow, crego-omni |
