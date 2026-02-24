# Deployment Models

### **Model 1: Shared Company Environment**

```mermaid
graph LR
    A[App Release<br/>v2.1.0] --> B[crego-infra/main]
    B --> C[env/prod branch]
    C --> D[Single Deployment<br/>All shared clients]
    D --> E[Client 1, Client 2, Client 3]

```

**Characteristics:**

- Single deployment instance
- All clients share same infrastructure
- Database: Multi-tenancy with tenant_id
- Version: All clients same version

### **Model 2: Client Cloud Deployment**

```mermaid
graph LR
    A[App Release<br/>v2.1.0] --> B[crego-infra/main]
    B --> C{Client Version Policy}

    C -->|Latest| D1[clients/client-a/prod]
    C -->|Stable| D2[clients/client-b/prod]
    C -->|Custom| D3[clients/client-c/prod]

    D1 --> E1[Client A's AWS]
    D2 --> E2[Client B's GCP]
    D3 --> E3[Client C's Azure]

```

**Characteristics:**

- Separate deployments per client
- Client controls infrastructure
- Database: Isolated per client
- Version: Can differ per client