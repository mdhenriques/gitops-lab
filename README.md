<p align="right">
  <b>🇬🇧 English</b> • <a href="README.pt-BR.md">🇧🇷 Português</a>
</p>

# Enterprise GitOps & DevSecOps Cloud Platform

[![CI/CD - Build and GitOps Sync](https://github.com/mdhenriques/gitops-lab/actions/workflows/deploy.yaml/badge.svg)](https://github.com/mdhenriques/gitops-lab/actions/workflows/deploy.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/kubernetes-v1.30+-326ce5.svg?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Terraform](https://img.shields.io/badge/terraform-v1.11+-844fba.svg?logo=terraform&logoColor=white)](https://www.terraform.io)
[![AWS](https://img.shields.io/badge/AWS-Certified%20Architecture-232f3e.svg?logo=amazon-aws&logoColor=white)](https://aws.amazon.com)

A comprehensive continuous delivery (**GitOps**) and integrated security (**DevSecOps**) environment, engineered following least-privilege principles, ephemeral secrets, immutable image tagging, multi-tenancy governance, and continuous admission policy enforcement (*Policy-as-Code*).

---

## 🏛️ Solution Architecture

The workflow connects the public cloud (**AWS**), automation pipelines with shift-left security (**GitHub Actions**), and container orchestration with governance (**Kubernetes & ArgoCD**):

<p align="center">
  <img src="docs/assets/architecture.svg" alt="Solution Architecture" width="100%">
</p>

---

## 💡 Engineering Decisions & Security Differentiators

| Domain | Traditional Approach (Anti-pattern) | This Project's Approach (Enterprise Standard) |
| :--- | :--- | :--- |
| **CI/CD Authentication** | Static `AWS_ACCESS_KEY_ID` saved in GitHub Secrets. | **AWS IAM OIDC Federation:** Long-lived keys eliminated, authenticating via immutable repository claims. |
| **Secrets Storage** | Plain-text passwords saved in `terraform.tfstate`. | **`ephemeral` + `value_wo`:** Sensitive passwords dynamically generated into SSM without persistence in Terraform state. *(Trade-off: static IAM credential used solely to enable local Kind lab; see Trade-offs section).* |
| **ECR Token in K8s** | Manual CronJob running bash scripts or static secrets expiring after 12h. | **ESO ECRAuthorizationToken Generator:** Native operator auto-renews authentication tokens every 30m autonomously. |
| **Update Lifecycle** | CI/CD bot commits directly to `master` branch. | **Automated Pull Requests:** The pipeline opens a rolling branch with PR for auditability and merge governance. |
| **Pipeline Security** | Direct build and deploy without vulnerability scanning or unit tests. | **Shift-Left Security:** Automated unit testing via **Pytest** (fail-fast), IaC security scanning via **Checkov**, and container CVE scanning via **Aqua Trivy**. |
| **Runtime Security** | Containers running as `root` with writable root filesystem. | **CIS Hardening & Kyverno:** `readOnlyRootFilesystem: true`, numeric non-root user (UID 10001), drop all capabilities, and Admission Webhook blocking pods without CPU/memory limits. |
| **GitOps Governance** | ArgoCD deploying all applications into the `default` project. | **Dedicated ArgoCD `AppProject`:** Strict whitelist of Git source repositories, target cluster/namespace destinations (`production`), and blocking arbitrary cluster-scoped resources. |
| **Cost Optimization (FinOps)** | ECR repository retaining images indefinitely. | **ECR Lifecycle Policy:** Automatic image expiration strictly retaining the 10 most recent images, preventing uncontrolled storage costs. |
| **Observability & Health** | Blind probes or liveness probes restarting pods during dependency hiccups. | **Strict separation of Liveness (`/healthz`) vs. Readiness (`/readyz`)** + **OpenMetrics/Prometheus Metrics** (`/metrics`). |

---

## ⚖️ Architectural Trade-offs: Lab vs. Enterprise Production

This project was built to be 100% reproducible locally via **Kind** with virtually zero cloud costs. To maintain this balance, conscious engineering trade-offs were made:

| Component | Implementation in this Lab (Kind) | Enterprise Implementation (AWS EKS) | Trade-off Rationale |
| :--- | :--- | :--- | :--- |
| **K8s ➔ AWS Authentication** | Least-privilege `aws_iam_access_key` stored in local Secret. | **EKS Pod Identity** or **IRSA (IAM Roles for Service Accounts)**. | Local clusters outside AWS do not have native EKS OIDC providers. In production, ESO static keys are 100% eliminated via IRSA. |
| **Prometheus Persistence** | `persistentVolume: false` (Ephemeral in-memory storage). | **EBS CSI Driver** or **Amazon Managed Prometheus (AMP)**. | Eliminates EBS volume charges and local provisioner dependencies in Kind, keeping the lab lightweight and fast to spin up. |
| **Secrets in Terraform State** | SSM Parameters hardened via `value_wo` and ephemeral passwords. | Hardened SSM Parameters + AWS Secrets Manager with dedicated KMS CMK. | SSM Standard Parameter Store flawlessly fulfills secure variable injection at zero additional cost. |
| **DevSecOps Scans (Checkov / Trivy)** | Informative mode execution (`soft_fail: true` / `exit-code: 0`). | Strict pipeline gating (*Hard-fail*) with enforcement gates. | Allows continuous auditing without breaking builds on enterprise rules requiring extra AWS costs (e.g., dedicated KMS CMKs, S3 Cross-Region Replication, and Access Logging on lab buckets). |

> [!NOTE]
> **Pipeline Security Stance (Soft-Fail & FinOps):**
> Static security scanners (**Checkov**) and container vulnerability scanners (**Aqua Trivy**) operate intentionally in **informative mode** (`soft_fail: true`). Findings such as *S3 Access Logging*, *Cross-Region Replication*, or *dedicated KMS CMK* are conscious **FinOps** decisions: they maintain zero cloud costs on AWS without masking compliance findings.

---

## 🛠️ Technology Stack

- **Cloud Provider:** AWS (ECR with Lifecycle Policy, SSM Parameter Store, IAM OIDC, S3 Backend with Native State Locking)
- **Infrastructure as Code (IaC):** Terraform >= 1.11 (Modular HCL with parameterized `variables.tf` and isolated bootstrap stack)
- **Container & Runtime:** Docker (python:3.11-slim, non-root UID 10001, `readOnlyRootFilesystem: true`), Kubernetes v1.30+ (Kind multi-node: 1 control-plane, 2 workers)
- **GitOps Engine:** ArgoCD (AppProject with governance, isolation in `production` namespace, declarative pattern with auto-heal and prune)
- **Security & Policies:** Checkov (SAST), Aqua Trivy (CVE Scanner), Kyverno Admission Controller, External Secrets Operator (ESO)
- **Application & Quality:** Python 3.11, FastAPI, Uvicorn, Pytest (automated unit tests), Prometheus Instrumentator, Structured JSON Logs

---

## 🚀 How to Reproduce the Environment Locally

### ⚠️ Step 0: Mandatory Fork (Do not use direct `git clone`)

> [!WARNING]
> **Running `git clone` directly from this upstream repository will NOT work for your lab!**
> 
> This project operates under the **GitOps and Continuous Automation (CI/CD)** model. For the end-to-end cycle to work:
> - You need write permissions so the GitHub Actions pipeline can build container images and open automated Pull Requests.
> - The AWS IAM Role via OIDC in your AWS account will only authorize executions originating from your own repository.
> - Your local ArgoCD instance needs to monitor and reconcile a repository under your full control.
> 
> **Mandatory step-by-step:**
> 1. Click the **Fork** button (top right of this GitHub page) to create a copy in your account.
> 2. Clone **your fork** to your local machine:
>    ```bash
>    git clone https://github.com/YOUR_USER/gitops-lab.git
>    cd gitops-lab
>    ```
> 3. Update the URLs across the ArgoCD manifests to point to your fork:
>    ```bash
>    sed -i 's/mdhenriques/YOUR_USER/g' argocd/*.yaml
>    ```
> 4. Configure the OIDC claim in [terraform/variables.tf](terraform/variables.tf) (`github_oidc_sub` variable):  
>    GitHub Actions requires the immutable ID format (`repo:USER@ID/REPO@ID:ref:refs/heads/master`). To retrieve the numeric IDs of your account and forked repository, run:
>    ```bash
>    # 1. Retrieve your GitHub account numeric ID:
>    curl -s https://api.github.com/users/YOUR_USER | grep -m1 '"id":'
>    
>    # 2. Retrieve your gitops-lab repository numeric ID:
>    curl -s https://api.github.com/repos/YOUR_USER/gitops-lab | grep -m1 '"id":'
>    ```
>    Update the value in `terraform/variables.tf`:
>    ```hcl
>    variable "github_oidc_sub" {
>      default = "repo:YOUR_USER@YOUR_USER_ID/gitops-lab@YOUR_REPO_ID:ref:refs/heads/master"
>    }
>    ```

---

### 1. Prerequisites
- [Docker](https://docs.docker.com/get-docker/) and [Kind](https://kind.sigs.k8s.io/) installed
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.11
- [kubectl](https://kubernetes.io/docs/tasks/tools/) and [Helm](https://helm.sh/)
- AWS account with permissions to provision IAM, SSM, and ECR resources

---

### 2. AWS Infrastructure Provisioning
```bash
# 1. Provision S3 State Bucket with Hardening (State Bootstrap)
cd terraform/bootstrap
terraform init && terraform apply -auto-approve

# 2. Provision core resources (ECR with Lifecycle Policy, SSM, IAM OIDC Role)
cd ..
terraform init && terraform apply -auto-approve
```

> [!NOTE]
> The bootstrap stack creates the S3 bucket declaratively from scratch. If you already have an existing bucket in your AWS account that you want to reuse, run before applying: `terraform import aws_s3_bucket.terraform_state <bucket-name>`.

---

### 3. Kubernetes Cluster & Base Tooling Initialization
```bash
# 1. Create Kind multi-node cluster (1 control-plane and 2 workers)
kind create cluster --config kind-config.yaml --name gitops-lab

# 2. Install External Secrets Operator (pinned version v2.12.0)
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --version 2.12.0 \
  -n external-secrets --create-namespace \
  -f k8s/eso-values.yaml

# 3. Install Kyverno Admission Controller (pinned version 3.9.1)
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno \
  --version 3.9.1 \
  -n kyverno --create-namespace

# 4. Install ArgoCD (pinned version v3.5.5)
kubectl create namespace argocd
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.5/manifests/install.yaml
```

---

### 4. ESO Credentials Configuration (One-time Bootstrap)
Retrieve credentials generated by Terraform and create secrets in the target namespaces:
```bash
# Create application production namespace
kubectl create namespace production

# Retrieve credentials from terraform stack output
ESO_KEY=$(terraform -chdir=terraform output -raw eso_access_key_id)
ESO_SECRET=$(terraform -chdir=terraform output -raw eso_secret_access_key)

# Create the Secret in both operator and application namespaces
for ns in external-secrets production; do
  kubectl create secret generic aws-secret \
    --from-literal=access-key-id="$ESO_KEY" \
    --from-literal=secret-access-key="$ESO_SECRET" \
    -n $ns
done
```

---

### 5. Deploy ArgoCD Applications
```bash
# 1. Apply AppProject with governance and security constraints
kubectl apply -f argocd/app-project.yaml

# 2. Apply declarative applications (Workload, Policies, and Monitoring)
kubectl apply -f argocd/application.yaml
kubectl apply -f argocd/security-policies-app.yaml
kubectl apply -f argocd/monitoring-app.yaml
```

> [!TIP]
> If running for the first time in a fresh AWS account with an empty ECR repository, trigger the **CI/CD - Build and GitOps Sync** workflow in GitHub Actions to build the initial image and approve the automated Pull Request opened by the bot.

---

## 🔍 Validation & Hands-on Testing

### 1. Testing Security Policy Enforcement (Kyverno)
Attempt to run a standard container violating non-root execution or resource limits constraints:
```bash
kubectl run rogue-pod --image=nginx -n production
```
**Expected outcome (blocked by Admission Webhook):**
```text
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request: 

resource Pod/production/rogue-pod was blocked due to the following policies 

disallow-root-and-privileged:
  check-privilege-escalation: 'validation error: SECURITY ALERT: Pod blocked! Privilege escalation is forbidden (securityContext.allowPrivilegeEscalation: false).'
  check-run-as-non-root: 'validation error: SECURITY ALERT: Pod blocked! Containers must run as non-root (securityContext.runAsNonRoot: true).'
require-resources:
  validate-resources: 'validation error: SECURITY ALERT: Container blocked! CPU and Memory limits and requests are required (resources.requests and resources.limits).'
```

<p align="center">
  <img src="docs/assets/kyverno-blocking.png" alt="Kyverno Blocking Rogue Pod" width="100%">
</p>

---

### 2. Testing the API & Secure Secrets Injection
Forward the API service port in the `production` namespace:
```bash
kubectl port-forward svc/gitops-api-svc 8000:80 -n production
```

- **Root Endpoint** (`http://localhost:8000/`): Verifies that secrets were retrieved from AWS SSM via ESO without leaking plain-text passwords:
  ```json
  {
    "message": "GitOps operating in real time with AWS ECR, ArgoCD, and Observability!",
    "database_configured": true,
    "db_status": "Connected successfully (Injected via AWS SSM Parameter Store)"
  }
  ```
- **Liveness Probe** (`http://localhost:8000/healthz`): Returns `{"status": "alive"}` ensuring the process is alive.
- **Readiness Probe** (`http://localhost:8000/readyz`): Returns `{"status": "ready"}` only when dependencies are injected.
- **Prometheus Metrics** (`http://localhost:8000/metrics`): Exposes request counts and latencies in OpenMetrics format.

---

### 3. Accessing Web Dashboards

#### ArgoCD Dashboard
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
- Access: `https://localhost:8080` (Username: `admin`)
- Retrieve initial password:
  ```bash
  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d && echo ""
  ```

<p align="center">
  <img src="docs/assets/argo-applications.png" alt="ArgoCD Applications Overview" width="100%">
</p>

<p align="center">
  <img src="docs/assets/argo-tree.png" alt="ArgoCD Workload Topology Tree" width="100%">
</p>

#### Prometheus Dashboard
```bash
kubectl port-forward svc/prometheus-server -n monitoring 9090:80
```
- Access: `http://localhost:9090`
- Query the metric `sum by (status) (rate(http_requests_total[1m]))` in the **Graph** tab to visualize real-time telemetry segmented by HTTP response codes:

<p align="center">
  <img src="docs/assets/prometheus-graph-rate.png" alt="Prometheus Real-Time Metrics & Probes" width="100%">
</p>

---

### 4. Running Unit Tests Locally
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r apps/api/requirements.txt -r apps/api/requirements-dev.txt
pytest apps/api/test_main.py -v
```

---

## 📄 License
Distributed under the MIT License. See [LICENSE](LICENSE) for more details.
