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

## crego-app

**Mobile Application** - Cross-platform React Native app (iOS, iPadOS, Android)

### Core Framework

| Technology | Version | Purpose |
|------------|---------|---------|
| React Native | 0.81.5 | Cross-platform mobile framework |
| React | 19.1.0 | UI framework |
| Expo | ~54.0.29 | Managed workflow with New Architecture |
| Expo Router | ~6.0.19 | File-based routing |
| TypeScript | ~5.9.2 | Type-safe JavaScript |
| pnpm | - | Package manager |

### Styling & UI

| Technology | Purpose |
|------------|---------|
| Tailwind CSS v4 | Utility-first CSS framework (via Uniwind) |
| Uniwind | Tailwind CSS adapter for React Native |
| RN Primitives (@rn-primitives) | Headless UI primitives (20+ components) |
| React Native Reusables | shadcn-ui style component library for RN |
| Class Variance Authority | Component variant management |
| Lucide React Native | Icon library |
| tailwind-merge | Tailwind class merging |
| tw-animate-css | Animation utilities |

### State & Data Management

| Technology | Purpose |
|------------|---------|
| TanStack Query (React Query) | Server state management and caching |
| AJV | JSON Schema-based form validation |
| Zod | Schema validation |
| Axios | HTTP client |

### Navigation & Gestures

| Technology | Purpose |
|------------|---------|
| Expo Router v6 | File-based navigation |
| @react-navigation/native | Navigation primitives |
| react-native-gesture-handler | Touch and gesture handling |
| react-native-screens | Native screen components |
| react-native-reanimated | Performant animations |
| react-native-keyboard-controller | Keyboard interaction management |

### Device & Platform APIs

| Technology | Purpose |
|------------|---------|
| expo-camera | Camera access |
| react-native-vision-camera | Advanced camera with face detection |
| expo-location | GPS and geolocation |
| expo-contacts | Contact book access |
| expo-notifications | Push notifications (FCM/APNs) |
| expo-document-picker | File selection |
| expo-image-picker | Image selection from gallery |
| expo-file-system | Local file system access |
| expo-secure-store | Encrypted credential storage |
| expo-haptics | Haptic feedback |
| expo-device | Device information |

### Multi-Tenant Support

| Technology | Purpose |
|------------|---------|
| Tenant config system | Per-tenant branding, bundle IDs, and API URLs |
| set-tenant.js | CLI script for switching tenant context |
| EAS Build | Expo Application Services for CI/CD |
| expo-updates | OTA updates |

### Internationalization

| Technology | Purpose |
|------------|---------|
| i18next | Internationalization framework |
| react-i18next | React bindings for i18next |
| expo-localization | Device locale detection |

### Third-Party SDKs

| Technology | Purpose |
|------------|---------|
| @digiotech/react-native | Digio eSign/eKYC SDK |
| react-native-webview | Embedded web views |
| piexifjs | EXIF metadata handling |

### Date & Utilities

| Technology | Purpose |
|------------|---------|
| date-fns | Date manipulation |
| date-fns-tz | Timezone support |
| clsx | Conditional class names |
| @react-native-async-storage/async-storage | Persistent key-value storage |

### Developer Experience

| Technology | Purpose |
|------------|---------|
| Prettier | Code formatting |
| prettier-plugin-tailwindcss | Tailwind class sorting |
| Babel | JavaScript compilation |
| Metro | JavaScript bundler |
| dotenv | Environment variable management |

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
| TypeScript/JavaScript | crego-web, crego-app |
| Python 3.13 | crego-flow, crego-omni |
| YAML | crego-infra |
| Bash | crego-infra |

### Mobile / Web Frameworks

| Framework | Project |
|-----------|---------|
| React 19 | crego-web |
| React Native 0.81 + Expo 54 | crego-app |
| FastAPI | crego-flow |
| Django 5.2+ | crego-omni |

### Databases

| Database | Project | Purpose |
|----------|---------|---------|
| PostgreSQL | crego-omni, crego-infra (dev) | Relational data |
| MongoDB | crego-flow | Document storage |
| Redis | All backend services | Caching |

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

### Mobile-Specific

| Technology | Project | Purpose |
|------------|---------|---------|
| Expo SDK 54 | crego-app | Managed native workflow |
| Expo Router v6 | crego-app | File-based navigation |
| EAS Build | crego-app | CI/CD for native builds |
| expo-notifications | crego-app | Push notifications (FCM/APNs) |
| react-native-vision-camera | crego-app | Camera and face detection |
| i18next | crego-app | Internationalization |
