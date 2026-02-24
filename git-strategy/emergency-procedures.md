# Emergency Procedures

### **Rollback by Deployment Type**

```mermaid
graph LR
    subgraph "Shared Environment Rollback"
        A1[Issue in shared env] --> B1[Checkout previous tag]
        B1 --> C1[Fast-forward env/prod]
        C1 --> D1[ArgoCD rolls back all clients]
    end

    subgraph "Client Cloud Rollback"
        A2[Issue in client cloud] --> B2[Client notifies]
        B2 --> C2[Checkout client branch at last good commit]
        C2 --> D2[Redeploy to client cloud]
        D2 --> E2[Only this client affected]
    end

```

### **Commands:**

```bash
# Shared env rollback
git checkout env/prod
git reset --hard v2.0.0
git push --force origin env/prod

# Client cloud rollback
git checkout clients/client-a/prod
git revert HEAD --no-edit  # Revert last deployment
git push origin clients/client-a/prod

```