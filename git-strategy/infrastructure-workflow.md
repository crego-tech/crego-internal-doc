# Infrastructure Structure & Workflow

### **Directory Layout**

> **Note:** The actual directory layout of `crego-infra` is shown below. See `crego-infra/CLAUDE.md` for detailed structure guidance.

```
crego-infra/
├── apps/                    # Kubernetes app definitions
├── argocd-apps/             # ArgoCD application manifests
├── base/                    # Base K8s resources
├── components/              # Reusable Kustomize components
├── config/                  # Configuration files
├── overlays/                # Environment-cloud overlays (dev-gcp, prod-aws, etc.)
├── scripts/                 # Deployment and management scripts
└── terraform/               # Terraform modules

```

### **Update Flow for Mixed Deployment**

```mermaid
graph LR
    subgraph "New Release v2.1.0"
        A[App Tag Created] --> B[Update base templates<br/>in crego-infra/main]
    end

    subgraph "Shared Environment Path"
        B --> C[Fast-forward merge<br/>main → env/prod]
        C --> D[ArgoCD auto-deploys<br/>to shared cluster]
        D --> E[All shared clients<br/>get v2.1.0]
    end

    subgraph "Client Cloud Path"
        B --> F[Client decides to upgrade]
        F --> G[Create PR: main → clients/client-x]
        G --> H[Add client-specific configs]
        H --> I[Squash & Merge]
        I --> J[Manual deployment<br/>to client's cloud]
    end

    subgraph "Client Stays on Old Version"
        B --> K[No action needed]
        K --> L[Client remains on<br/>v2.0.0]
    end

```
