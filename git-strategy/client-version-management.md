# Client Version Management

### **Version Matrix Example**

```
Client          | Deployment     | Current Ver   | Upgrade Policy
--------------- | -------------- | ------------- | -----------------------------
Client A        | Shared env     | v2.0.0        | Auto-upgrade (company managed)
Client B        | Shared env     | v2.0.0        | Auto-upgrade (company managed)
Client C        | Own AWS        | v1.9.0        | Manual (client controls timing)
Client D        | Own GCP        | v2.1.0        | Manual (stays current)
Client E        | Own Azure      | v1.8.0        | Manual (skips versions)

```

### **Client Decision Flow**

```mermaid
graph TD
    A[New Release v2.1.0] --> B{Client Deployment Type}

    B -->|Shared Company Env| C[Auto-upgrade<br/>All clients upgraded together]
    C --> D[Company manages<br/>rollout schedule]

    B -->|Client Own Cloud| E{Client Upgrade Decision}
    E -->|Upgrade Now| F[Create PR: main → client branch]
    F --> G[Deploy to client cloud]

    E -->|Upgrade Later| H[Client stays on current version]
    H --> I[Track in upgrade backlog]

    E -->|Skip Version| J[Client waits for v2.2.0]
    J --> K[Notify of missed features]

```
