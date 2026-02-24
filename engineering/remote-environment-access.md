Author: Abhishek Sharma
Status: Published
Category: Guide
Last edited time: January 8, 2026 6:46 PM
Summary: Ensure prerequisites like GCP project access and IAM permissions before accessing environments. Install necessary CLI tools, authenticate, and use Google Cloud Console or Lens for cluster management. Utilize port forwarding for service access and follow cleanup procedures for troubleshooting.

## **Prerequisites**

Before you begin, ensure you have:

- Access to the relevant **GCP project** (Dev or Preprod)
- IAM permissions:
    - **Kubernetes Engine Developer** (or higher)
    - **Viewer** access to the project at minimum
- A **company Google account** added to the organization
- (Optional but recommended) **Lens Desktop**

👉 https://k8slens.dev/

---

## **Environment Details**

| **Environment** | **Project Name** | **Project ID** | **Cluster Name** | **Region** |
| --- | --- | --- | --- | --- |
| Dev | crego-app-dev | crego-app-dev | crego-app-dev-cluster | asia-south1-a |
| Preprod | crego-app-preprod | gold-blueprint-451210-q1 | crego-app-preprod | asia-south1-a |

---

## **Step 0: Install Required CLI Tools (Local Machine)**

> Skip this step if using
> 
> 
> **Cloud Shell only**
> 

---

### **0.1 Install Google Cloud SDK (gcloud)**

### **macOS (Homebrew)**

```bash
brew install --cask google-cloud-sdk
gcloud init
```

### **Windows**

👉 https://cloud.google.com/sdk/docs/install

After install:

```bash
gcloud init
```

---

### **0.2 Install kubectl**

```bash
kubectl version --client
```

If missing:

```bash
gcloud components install kubectl
```

---

### **0.3 Install GKE Authentication Plugin (Required)**

```bash
gcloud components install gke-gcloud-auth-plugin
```

```bash
gke-gcloud-auth-plugin --version
```

Enable plugin:

```bash
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
```

(Add to shell config for persistence)

---

### **0.4 Authenticate**

```bash
gcloud auth login
gcloud auth application-default login
```

Verify:

```bash
gcloud projects list
```

---

## **Step 1: Access Google Cloud Console (Cloud Shell)**

1. Go to 👉 https://console.cloud.google.com
2. Log in with your company account
3. Click **Cloud Shell**
4. Wait for initialization

---

## **Step 2: Select the Target Environment**

### **Check active project**

```bash
gcloud config list project
```

### **Set project**

### **Dev**

```bash
gcloud config set project crego-app-dev
```

### **Preprod (Corrected)**

```bash
gcloud config set project gold-blueprint-451210-q1
```

---

## **Step 3: Get GKE Cluster Credentials**

### **Dev Cluster**

```bash
gcloud container clusters get-credentials crego-app-dev-cluster \
  --region asia-south1-a \
  --project crego-app-dev
```

### **Preprod Cluster (Corrected)**

```bash
gcloud container clusters get-credentials crego-app-preprod \
  --region asia-south1-a \
  --project gold-blueprint-451210-q1
```

---

### **Verify Access**

```bash
kubectl get nodes
```

---

## **Step 4: Access Services via Port Forwarding**

> Port-forwarding works only while the terminal is open.
> 

---

### **PostgreSQL**

```bash
kubectl port-forward -n preprod svc/postgresql 15432:5432
```

```
psql -h localhost -p 5432 -U <username> -d <database>
```

### **RabbitMQ**

```bash
kubectl port-forward -n dev svc/rabbitmq 15672:5672 &
```

Access:

- Cloud Shell → **Web Preview → Port 15672**
- Or http://localhost:15672

Credentials:

- Username: guest
- Password: guest

---

### **Redis**

```bash
kubectl port-forward -n dev svc/redis 16379:6379 &
```

```bash
redis-cli -h localhost -p 6379
```

---

---

## **Step 5: Access Services Using Web Preview**

1. Ensure port-forward is running
2. Click **Web Preview**
3. Select **Preview on port**
4. Browser opens the UI

---

## **Step 6: Access the Cluster Using Lens**

### **Install Lens**

👉 https://k8slens.dev/

---

### **Configure kubeconfig**

```
gcloud auth login
gcloud auth application-default login
gcloud container clusters get-credentials ...
```

---

### **Connect in Lens**

1. Open **Lens**
2. Go to **Catalog → Clusters**
3. Select the cluster
4. Click **Connect**

---

### **What You Can Do in Lens**

- Browse pods, deployments, services
- View logs & events
- Exec into containers
- Monitor resources

---

## **Cleanup / Troubleshooting**

Stop port-forwards:

```
pkill -f "kubectl port-forward"
```

---

## **Summary**

- **Cloud Shell** → fastest access
- **Local CLI** → full workflow
- **kubectl** → cluster interaction
- **Port-forwarding** → internal services
- **Lens** → visibility & debugging