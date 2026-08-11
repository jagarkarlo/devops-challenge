# Azure DevOps Challenge

<p align="center">
  <img src="https://img.shields.io/badge/Terraform-844FBA?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform">
  <img src="https://img.shields.io/badge/Microsoft_Azure-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white" alt="Microsoft Azure">
  <img src="https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes">
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker">
  <img src="https://img.shields.io/badge/License-MIT-2EA44F?style=for-the-badge" alt="MIT License">
</p>

**Reproducible Azure infrastructure and container delivery across a standalone Linux VM and Azure Kubernetes Service (AKS).** The project packages a custom nginx application as a Docker image, provisions both Azure environments with Terraform, and exposes the AKS workload through Traefik Ingress.

| Capability | Implementation |
|---|---|
| Infrastructure as Code | Independent Terraform stacks for Azure VM and AKS |
| Container delivery | Custom nginx image published to Docker Hub |
| VM deployment | Ubuntu 24.04, SSH key authentication, NSG rules, dedicated Docker disk |
| Kubernetes deployment | AKS, Azure CNI with Cilium, Deployment, ClusterIP Service, Traefik Ingress |
| Portability | Local Docker and minikube workflows plus repeatable Azure provisioning |

---

## Architecture

```mermaid
flowchart TB
  USER([Internet client])
  IMAGE[(Docker Hub<br/>karlojagar/moj-nginx)]

  subgraph AZURE[Microsoft Azure]
    direction LR

    subgraph VM_STACK[Standalone VM path]
      VM_LB[Public IP and NSG<br/>TCP 22 and 80]
      VM[Ubuntu 24.04 VM]
      DISK[(32 GiB Docker disk)]
      VM_APP[nginx container<br/>port 80]

      VM_LB --> VM --> VM_APP
      DISK --- VM
    end

    subgraph AKS_STACK[AKS path]
      ALB[Azure Load Balancer<br/>public port 80]
      TRAEFIK[Traefik<br/>Ingress controller]
      INGRESS[Ingress<br/>path /]
      SERVICE[nginx-service<br/>ClusterIP]
      POD[nginx Pod<br/>container port 80]

      ALB --> TRAEFIK --> INGRESS --> SERVICE --> POD
    end
  end

  USER --> VM_LB
  USER --> ALB
  IMAGE -. image pull .-> VM_APP
  IMAGE -. image pull .-> POD

  classDef edge fill:#E8F1FB,stroke:#0078D4,color:#172B4D
  classDef compute fill:#EAF7EE,stroke:#2E8B57,color:#172B4D
  classDef route fill:#FFF4E5,stroke:#D97706,color:#172B4D
  classDef store fill:#F4ECFA,stroke:#844FBA,color:#172B4D
  class USER,VM_LB,ALB edge
  class VM,VM_APP,POD compute
  class TRAEFIK,INGRESS,SERVICE route
  class IMAGE,DISK store
```

## Delivery Workflow

```mermaid
flowchart LR
  SOURCE[HTML and Dockerfile] --> BUILD[Build nginx image]
  BUILD --> REGISTRY[(Push to Docker Hub)]

  subgraph INFRA[Provision infrastructure]
    VM_TF[Terraform VM stack]
    AKS_TF[Terraform AKS stack]
  end

  REGISTRY --> VM_RUN[Run container on Azure VM]
  REGISTRY --> MANIFESTS[Apply Kubernetes manifests]
  VM_TF --> VM_RUN
  AKS_TF --> MANIFESTS
  MANIFESTS --> ROUTE[Traefik routes traffic to nginx]

  classDef source fill:#F4ECFA,stroke:#844FBA,color:#172B4D
  classDef build fill:#E8F1FB,stroke:#2496ED,color:#172B4D
  classDef deploy fill:#EAF7EE,stroke:#2E8B57,color:#172B4D
  class SOURCE source
  class BUILD,REGISTRY,VM_TF,AKS_TF build
  class VM_RUN,MANIFESTS,ROUTE deploy
```

## Technology Stack

| Layer | Technology |
|---|---|
| Cloud | Microsoft Azure |
| Infrastructure | Terraform and AzureRM provider |
| Compute | Azure Linux VM and Azure Kubernetes Service |
| Containers | Docker and nginx Alpine, unprivileged on port 8080 |
| Kubernetes networking | Azure CNI, Cilium, Traefik, ClusterIP Service |
| Configuration | Kubernetes manifests and Terraform variables |

---

## Repository Structure

```
devops-challenge/
├── Dockerfile
├── index.html
├── README.md
├── LICENSE
├── .gitignore
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── terraform/
│   ├── vm/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── aks/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
```

---

## Part 1 — Virtual Machine & Docker

### Azure VM

A Linux VM was provisioned on Azure with the following specifications:

| Parameter | Value |
|---|---|
| Name | devops-vm |
| Resource group | devops-vm-rg |
| Region | Switzerland North (Zone 1) |
| OS | Ubuntu Server 24.04 LTS |
| Size | Standard B2ats v2 (2 vCPU, 1 GiB RAM) |
| Public IP | Assigned dynamically by Terraform |
| Subscription | Azure for Students |

### Virtual Machines vs Containers

```mermaid
flowchart LR
  subgraph VM_MODEL[Virtual machine]
    VM_HW[Virtual hardware] --> VM_OS[Guest operating system]
    VM_OS --> VM_RUNTIME[Docker Engine]
    VM_RUNTIME --> VM_CONTAINER[nginx container]
  end

  subgraph CONTAINER_MODEL[Container]
    HOST[Host operating system] --> ENGINE[Container runtime]
    ENGINE --> APP_A[Application A]
    ENGINE --> APP_B[Application B]
  end

  classDef infra fill:#E8F1FB,stroke:#0078D4,color:#172B4D
  classDef runtime fill:#F4ECFA,stroke:#844FBA,color:#172B4D
  classDef app fill:#EAF7EE,stroke:#2E8B57,color:#172B4D
  class VM_HW,VM_OS,HOST infra
  class VM_RUNTIME,ENGINE runtime
  class VM_CONTAINER,APP_A,APP_B app
```

Containers share the host OS kernel and package only what the application needs — making them much smaller and faster to start than full VMs.

### SSH Security

The VM was hardened to use SSH key-based authentication only. Password login was completely disabled by editing `/etc/ssh/sshd_config`:

```
PasswordAuthentication no
PubkeyAuthentication yes
```

A `devops` user was created with SSH key access. The SSH service was restarted to apply the changes:

```bash
sudo systemctl restart ssh
```

### Docker on a Separate Disk

Docker was installed and configured to store all data on a dedicated data disk (`/dev/sdb`, 32 GiB) rather than the OS disk. This is a best practice that prevents Docker data from filling up the OS disk and causing system issues.

```bash
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/docker-data
sudo mount /dev/sdb /mnt/docker-data
echo '/dev/sdb /mnt/docker-data ext4 defaults 0 0' | sudo tee -a /etc/fstab
```

Docker was configured to use that disk via `/etc/docker/daemon.json`:

```json
{
  "data-root": "/mnt/docker-data"
}
```

### Custom Nginx Image

```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
```

`nginx:alpine` was chosen as the base image because it is ~5MB vs ~200MB for the full nginx image.

```bash
docker build -t moj-nginx .
docker tag moj-nginx karlojagar/moj-nginx:v1
docker push karlojagar/moj-nginx:v1
```

Docker Hub: [hub.docker.com/r/karlojagar/moj-nginx](https://hub.docker.com/r/karlojagar/moj-nginx)

### Running on the VM

```bash
docker run -d -p 80:8080 --restart always --name moj-nginx karlojagar/moj-nginx:v1
```

The `--restart always` flag ensures the container starts automatically on VM reboot.

The original demonstration endpoint has been decommissioned. Deploy the Terraform configuration to obtain a new VM address.

---

## Part 2 — Kubernetes

### Kubernetes Architecture

```mermaid
flowchart LR
  CLIENT([Client]) --> LB[Azure Load Balancer]
  LB --> TRAEFIK[Traefik Service and controller]
  TRAEFIK -->|Ingress path /| SERVICE[nginx-service<br/>ClusterIP]
  SERVICE -->|label: app=moj-nginx| POD[nginx Pod]
  DEPLOY[nginx Deployment<br/>desired replicas: 1] -. manages .-> POD
  REGISTRY[(Docker Hub)] -. image pull .-> POD

  classDef edge fill:#E8F1FB,stroke:#0078D4,color:#172B4D
  classDef route fill:#FFF4E5,stroke:#D97706,color:#172B4D
  classDef workload fill:#EAF7EE,stroke:#2E8B57,color:#172B4D
  classDef store fill:#F4ECFA,stroke:#844FBA,color:#172B4D
  class CLIENT,LB edge
  class TRAEFIK,SERVICE route
  class DEPLOY,POD workload
  class REGISTRY store
```

### AKS Cluster

| Parameter | Value |
|---|---|
| Cluster name | devops-aks |
| Region | Sweden Central |
| Kubernetes version | 1.33.7 |
| Node size | Standard_D2s_v3 |
| Node count | 1 |
| Pricing tier | Free |

```bash
az aks get-credentials --resource-group devops-aks-rg --name devops-aks
kubectl get nodes
# NAME                                STATUS   ROLES    AGE   VERSION
# aks-agentpool-29782353-vmss000000   Ready    <none>   4m    v1.33.7
```

### Deploying the Nginx Image

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: moj-nginx
  template:
    metadata:
      labels:
        app: moj-nginx
    spec:
      containers:
      - name: moj-nginx
        image: karlojagar/moj-nginx:v1
        ports:
        - containerPort: 8080
```

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: moj-nginx
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
```

### Traefik Ingress Controller

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik --namespace traefik --create-namespace
```

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
```

After deployment, use the external address assigned to the Traefik LoadBalancer.

---

## Bonus — Infrastructure as Code (Terraform)

Both the VM and AKS cluster are defined as Terraform code, making the entire infrastructure reproducible from scratch with a single command.

### VM (`terraform/vm/`)

Defines: resource group, virtual network, subnet, public IP, network security group (SSH + HTTP rules), network interface, 32GB data disk, and the Linux VM itself.

```bash
cd terraform/vm
terraform init
terraform plan -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
```

Key outputs after apply:
```
public_ip_address = "x.x.x.x"
ssh_command       = "ssh -i ~/.ssh/devops-vm-key.pem devops@x.x.x.x"
```

### AKS (`terraform/aks/`)

Defines: resource group and AKS cluster with SystemAssigned identity and Azure CNI Overlay networking.

```bash
cd terraform/aks
terraform init
terraform plan
terraform apply
```

Key outputs after apply:
```
cluster_name     = "devops-aks"
cluster_endpoint = "https://devops-aks-dns-xxx.hcp.swedencentral.azmk8s.io"
```

> **Note:** Terraform code was written and validated with `terraform plan` against real Azure credentials. Since the infrastructure was already provisioned manually beforehand, `terraform apply` was not run to avoid creating duplicate resources.

---

## Key Concepts

### What does an ingress controller do?
An ingress controller is the single entry point for all external HTTP traffic into a Kubernetes cluster. It reads Ingress rules and routes requests to the correct internal service — for example, `/api` to a backend and `/` to a frontend — all through one public IP address. Without it, every service would need its own public IP.

### What is Traefik's role?
Traefik is a concrete implementation of an ingress controller. Kubernetes defines the ingress concept but does not ship a router. Traefik handles the actual routing and automatically discovers new services in the cluster without manual reconfiguration.

### How does traffic get from the internet to the container?

```mermaid
sequenceDiagram
  autonumber
  actor Client
  participant ALB as Azure Load Balancer
  participant Traefik as Traefik Controller
  participant Service as ClusterIP Service
  participant Pod as nginx Pod

  Client->>ALB: HTTP GET /
  ALB->>Traefik: Forward TCP/80
  Traefik->>Traefik: Match Ingress path /
  Traefik->>Service: Route HTTP request
  Service->>Pod: Select app=moj-nginx
  Pod-->>Client: HTTP response
```

1. User opens the Traefik LoadBalancer address in a browser
2. Azure Load Balancer receives the request (only component with a public IP)
3. Traefik reads the path and routes according to Ingress rules
4. Kubernetes ClusterIP Service finds the correct Pod
5. nginx container responds

### What is load balancing?
Distributing incoming requests across multiple instances so no single Pod gets overwhelmed. If a Pod crashes, traffic is automatically redirected to healthy ones. In this setup Azure handles it at the infrastructure level (Load Balancer) and Kubernetes handles it at the application level (Service).

### ClusterIP vs NodePort vs LoadBalancer

```mermaid
flowchart LR
  CLUSTER[ClusterIP<br/>cluster-internal access]
  NODE[NodePort<br/>port on every node]
  LOAD[LoadBalancer<br/>external cloud endpoint]

  LOAD --> NODE --> CLUSTER

  classDef internal fill:#EAF7EE,stroke:#2E8B57,color:#172B4D
  classDef node fill:#FFF4E5,stroke:#D97706,color:#172B4D
  classDef external fill:#E8F1FB,stroke:#0078D4,color:#172B4D
  class CLUSTER internal
  class NODE node
  class LOAD external
```

In this project: `nginx-service` uses **ClusterIP** (internal), `traefik` uses **LoadBalancer** (public-facing, gets a real Azure IP).

---

## Problems & Solutions

| Problem | What happened | How it was solved |
|---|---|---|
| Azure Student subscription had 0 vCPU quota in every region | Tried West Europe, North Europe, East US — all returned quota errors when creating the AKS node pool | Systematically tried every available region; Sweden Central had quota available for Standard_D2s_v3 |
| West Europe did not support VM creation on student account | Got "Your subscription doesn't support virtual machine creation in West Europe" after filling out the entire VM form | Switched to Switzerland North which worked |
| Azure portal image dropdown only showed Windows Server images | Landed on the "Free account virtual machine" wizard which has a limited marketplace | Navigated to "Virtual machines" directly and used the full Create flow with access to the complete image marketplace |
| AKS node pool rejected all B-series VM sizes | B-series VMs cannot be scheduled in AKS node pools | Switched to D-series (Standard_D2s_v3) which is supported |
| Port 80 was blocked after container was running | Azure Network Security Group denies all inbound traffic by default — no rule for HTTP existed | Added an inbound security rule for TCP port 80 in the VM's NSG through the Azure portal |
| Terraform requires an SSH public key | Access material must not be committed to source control | Supply `ssh_public_key` at plan/apply time from a local `.pub` file |

---

## How to Run Locally

```bash
# Clone the repository
git clone https://github.com/jagarkarlo/devops-challenge.git
cd devops-challenge

# Build and run with Docker
docker build -t moj-nginx .
docker run -d -p 8080:8080 moj-nginx
# Open http://localhost:8080

# Deploy to Kubernetes locally with minikube
minikube start --driver=docker
kubectl apply -f k8s/
minikube tunnel
# Open http://127.0.0.1
```

---

## Project Links

| Environment | URL |
|---|---|
| Docker Hub | https://hub.docker.com/r/karlojagar/moj-nginx |

The Azure demonstration resources were temporary and are not expected to remain online. New endpoints are created when the Terraform configuration is deployed.

---

## License

This project is licensed under the [MIT License](LICENSE).