# Crego Platform Tech Stack

## crego-web

| Category | Technology |
|----------|------------|
| Language | TypeScript |
| Framework | React 19 |
| Build Tool | Vite |
| Package Manager | pnpm (monorepo) |
| Styling | Tailwind CSS v4 |
| UI Components | Radix UI / shadcn |
| State Management | TanStack Query |
| Routing | React Router v7 |
| Forms | React Hook Form + Zod |
| Charts | Recharts |
| Flow Diagrams | xyflow |
| Code Editor | Monaco Editor |

## crego-flow

| Category | Technology |
|----------|------------|
| Language | Python 3.13 |
| Framework | FastAPI |
| Database | MongoDB |
| ODM | MongoEngine |
| Cache | Redis |
| Task Queue | Celery + RabbitMQ |
| Auth | JWT |
| Templating | Jinja2, Mako |
| PDF Generation | WeasyPrint, PyMuPDF |

## crego-omni

| Category | Technology |
|----------|------------|
| Language | Python 3.13 |
| Framework | Django 5.2 + DRF |
| Database | PostgreSQL |
| Cache | Redis |
| Task Queue | Celery + RabbitMQ |
| Auth | JWT, OIDC |
| Storage | S3, Azure Blob, GCS |
| PDF Generation | WeasyPrint, ReportLab |
| Monitoring | Sentry |

## crego-app

| Category | Technology |
|----------|------------|
| Language | TypeScript |
| Framework | React Native 0.81 + React 19 |
| Platform | Expo SDK 54 (New Architecture) |
| Routing | Expo Router v6 |
| Package Manager | pnpm |
| Styling | Tailwind CSS v4 via Uniwind |
| UI Components | RN Primitives / RN Reusables (shadcn-ui port) |
| State Management | TanStack Query |
| Forms | AJV (JSON Schema validation) + Zod |
| Internationalization | i18next + react-i18next |
| Camera / Vision | react-native-vision-camera |
| Notifications | expo-notifications (FCM/APNs) |
| Auth Storage | expo-secure-store |

## crego-infra

| Category | Technology |
|----------|------------|
| Orchestration | Kubernetes |
| GitOps | ArgoCD |
| Config Management | Kustomize |
| Cloud Platforms | GCP, AWS |
| Ingress | NGINX, AWS ALB |
| Secrets | External Secrets Operator |
| Autoscaling | KEDA, HPA |
| Monitoring | Prometheus, Grafana |
| Tracing | OpenTelemetry |
| TLS | cert-manager |
