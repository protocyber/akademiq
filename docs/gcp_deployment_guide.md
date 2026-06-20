# AcademiQ Backend Deployment Guide (Google Cloud Platform)

This guide walks you through deploying the AcademiQ backend services to a **Google Compute Engine (GCE)** instance using Docker Compose, with external managed databases and message brokers.

---

## 🏗️ Deployment Architecture

In production, the application is divided into:
1. **Application Layer (VM)**: A single lightweight GCP VM (e.g., `e2-micro` or `e2-medium`) running the 5 Rust services inside Docker containers. An edge reverse proxy (such as Caddy or Traefik) handles SSL termination (Let's Encrypt) and routes traffic.
2. **Data Layer (External)**: An external PostgreSQL instance (such as Supabase Free Tier) using a **schema-per-service** configuration.
3. **Broker Layer (External)**: An AMQPS message broker (such as CloudAMQP Free Tier "Little Lemur").
4. **CI/CD Pipeline (GitHub Actions)**: Builds production images and pushes them to the **GitHub Container Registry (GHCR)**. The VM only pulls these pre-built images, eliminating high compiler CPU/RAM usage on the host.

```mermaid
flowchart TD
    Client[Web Browser / Client]
    
    subgraph GCP VM [Google Compute Engine VM]
        Proxy[Caddy or Traefik SSL Proxy]
        IAM[iam-service :8081]
        BILL[billing-service :8082]
        ACFG[academic-config-service :8083]
        AOPS[academic-ops-service :8084]
        GRD[grading-service :8086]
    end

    subgraph External_Services [Managed Infra]
        DB[(Supabase PostgreSQL)]
        Broker{CloudAMQP RabbitMQ}
    end

    Client -- HTTPS (443) --> Proxy
    Proxy -- Route /api/v1/iam --> IAM
    Proxy -- Route /api/v1/billing --> BILL
    Proxy -- Route /api/v1/academic-config --> ACFG
    Proxy -- Route /api/v1/academic-ops --> AOPS
    Proxy -- Route /api/v1/grading --> GRD

    IAM & BILL & ACFG & AOPS & GRD -. SSL SQL .-> DB
    IAM & BILL & ACFG & AOPS & GRD -. AMQPS .-> Broker
```

---

## 1. Google Cloud Infrastructure Setup

### A. Create Compute Engine Instance
1. Go to the **Google Cloud Console** > **Compute Engine** > **VM Instances**.
2. Click **Create Instance**.
3. Configure the VM to fit the **GCP Always Free Tier**:
   - **Name**: `akademiq-backend-prod`
   - **Region/Zone**: You **MUST** choose one of these US regions:
     * `us-central1` (Iowa)
     * `us-west1` (Oregon)
     * `us-east1` (South Carolina)
     *(Choosing any other region will incur monthly VM charges).*
   - **Machine type**: `e2-micro` (2 vCPU, 1 GB RAM — Free Tier eligible).
   - **Boot disk**: Click **Change**:
     * Operating System: **Ubuntu**
     * Version: **Ubuntu 24.04 LTS (x86_64)**
     * Boot disk type: Select **Standard Persistent Disk** (HDD). *(Do NOT select Balanced or SSD, as they are not free-tier eligible).*
     * Size: **10 GB to 30 GB** (GCP allows up to 30 GB of Standard Persistent Disk for free).
   - **Firewall**: Check both **Allow HTTP traffic** and **Allow HTTPS traffic**.
4. Click **Create**.

### B. Reserve a Static External IP Address
By default, GCP VM external IPs are ephemeral. To reserve a static IP:
1. Navigate to **VPC Network** > **IP addresses**.
2. Locate the ephemeral IP assigned to `akademiq-backend-prod`.
3. Click the three dots next to it and select **Promote to static IP address**.
4. Give it a name (e.g., `akademiq-backend-static-ip`).
5. **Free Tier Rule**: GCP only charges for static IP addresses if they are **unused** (unattached). As long as your static IP is attached to a running VM, it is covered under the Free Tier. (Remember to release it if you ever delete the VM).
6. Point your API address (e.g., `<YOUR_VM_IP>.nip.io`) to this static IP.

---

## 2. External Services Provisioning

### A. Database (Supabase)
To run all 5 services using one Free-Tier Supabase project, we use a **schema-per-service** model to maintain isolation without paying for multiple database instances:
1. Create a Supabase project and get the Postgres connection string.
2. Connect to the database using your preferred client (e.g., `psql` or DBeaver) and run the following commands to create the isolated schemas:
   ```sql
   CREATE SCHEMA IF NOT EXISTS iam;
   CREATE SCHEMA IF NOT EXISTS billing;
   CREATE SCHEMA IF NOT EXISTS academic_config;
   CREATE SCHEMA IF NOT EXISTS academic_ops;
   CREATE SCHEMA IF NOT EXISTS grading;
   ```
3. Update connection URLs in your production environment variables to use `search_path`:
   - **IAM**: `postgres://postgres.xxxx:password@aws-0-xx.pooler.supabase.com:6543/postgres?sslmode=require&options=-c%20search_path%3Diam`
   - **Billing**: `postgres://postgres.xxxx:password@aws-0-xx.pooler.supabase.com:6543/postgres?sslmode=require&options=-c%20search_path%3Dbilling`
   - **Academic Config**: `postgres://postgres.xxxx:password@aws-0-xx.pooler.supabase.com:6543/postgres?sslmode=require&options=-c%20search_path%3Dacademic_config`
   - **Academic Ops**: `postgres://postgres.xxxx:password@aws-0-xx.pooler.supabase.com:6543/postgres?sslmode=require&options=-c%20search_path%3Dacademic_ops`
   - **Grading**: `postgres://postgres.xxxx:password@aws-0-xx.pooler.supabase.com:6543/postgres?sslmode=require&options=-c%20search_path%3Dgrading`

### B. Message Broker (CloudAMQP)
1. Sign up on **CloudAMQP** and create a free "Little Lemur" instance.
2. Note your **AMQPS Connection URL** (starts with `amqps://`).
3. Set this URL as the `RABBITMQ_URL` environment variable.

---

## 3. GitHub Actions Setup (CI/CD)

The backend submodule already contains `.github/workflows/build-images.yml`. Images are pushed to `ghcr.io/protocyber/akademiq-*`.

### A. Repository Configuration
1. Go to your repository settings under **Settings** > **Actions** > **General**.
2. Scroll to **Workflow permissions** and ensure it is set to **Read and write packages** (so the CI run can push images to GHCR).

### B. Generate GitHub Personal Access Token (PAT)
To pull private Docker images from GHCR, the deployment VM requires a PAT with read permissions:
1. Go to your GitHub account **Settings** (click your profile photo).
2. Click **Developer settings** at the bottom of the left sidebar.
3. Click **Personal access tokens** > **Tokens (classic)**.
4. Click **Generate new token** > **Generate new token (classic)**.
5. Configure the token:
   - **Note**: `GCP VM Pull Packages` (or any description).
   - **Expiration**: Select your preferred expiry (e.g., 90 days or No expiration).
   - **Select scopes**: Check the **`read:packages`** scope.
6. Click **Generate token**.
7. **Copy the token (`ghp_...`) immediately!** It will not be shown again.

---

## 4. Setting Up the VM

SSH into your VM instance via GCP Console or terminal (`gcloud compute ssh akademiq-backend-prod`) and complete the following setup:

### A. Install Docker and Docker Compose

**Option 1: For Debian (including Debian 13 / Trixie)**
Run the following commands:
```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo usermod -aG docker $USER
newgrp docker
```

**Option 2: For Ubuntu**
Run the following commands:
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
```

### B. Login to GHCR (GitHub Container Registry)
Authenticate Docker with GHCR using your GitHub Username and the PAT you generated:
```bash
docker login ghcr.io -u <YOUR_GITHUB_USERNAME>
```
*(Enter your PAT as the password).*

### C. Create Deployment Directory
Set up a clean directory for your deployment configuration:
```bash
mkdir -p ~/akademiq-deploy
cd ~/akademiq-deploy
```

---

## 5. Deployment Configuration Files

Copy these files to your VM at `~/akademiq-deploy`:

### A. `compose.prod.yml`
This configuration runs the services plus an automated **Caddy** instance that acts as our TLS router/reverse proxy.

```yaml
name: akademiq-prod

networks:
  akademiq:
    name: akademiq

x-service-base: &service-base
  pull_policy: always
  restart: unless-stopped
  networks:
    - akademiq

services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - akademiq
    depends_on:
      - iam-service
      - billing-service
      - academic-config-service
      - academic-ops-service
      - grading-service

  iam-service:
    <<: *service-base
    image: ghcr.io/protocyber/akademiq-iam-service:${IMAGE_TAG:-latest}
    container_name: akademiq-iam-service
    environment:
      RUST_LOG: ${RUST_LOG:-info}
      IAM_PORT: 8081
      IAM_DATABASE_URL: ${IAM_DATABASE_URL}
      IAM_PUBLIC_KEY: ${IAM_PUBLIC_KEY}
      IAM_PRIVATE_KEY: ${IAM_PRIVATE_KEY}
      IAM_INTERNAL_SERVICE_TOKEN: ${IAM_INTERNAL_SERVICE_TOKEN}
      RABBITMQ_URL: ${RABBITMQ_URL}
      PUBLIC_WEB_BASE_URL: ${PUBLIC_WEB_BASE_URL}
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET}
      GOOGLE_REDIRECT_URI: ${GOOGLE_REDIRECT_URI}
      EMAIL_PROVIDER: ${EMAIL_PROVIDER}
      EMAIL_FROM: ${EMAIL_FROM}
      RESEND_API_KEY: ${RESEND_API_KEY}
      RESEND_ENDPOINT: ${RESEND_ENDPOINT}
      CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS}

  billing-service:
    <<: *service-base
    image: ghcr.io/protocyber/akademiq-billing-service:${IMAGE_TAG:-latest}
    container_name: akademiq-billing-service
    depends_on:
      - iam-service
    environment:
      RUST_LOG: ${RUST_LOG:-info}
      BILLING_PORT: 8082
      BILLING_DATABASE_URL: ${BILLING_DATABASE_URL}
      RABBITMQ_URL: ${RABBITMQ_URL}
      IAM_BASE_URL: http://iam-service:8081
      IAM_INTERNAL_SERVICE_TOKEN: ${IAM_INTERNAL_SERVICE_TOKEN}
      IAM_PUBLIC_KEY: ${IAM_PUBLIC_KEY}
      FEATURES_TOML_PATH: /app/features.toml
      CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS}

  academic-config-service:
    <<: *service-base
    image: ghcr.io/protocyber/akademiq-academic-config-service:${IMAGE_TAG:-latest}
    container_name: akademiq-academic-config-service
    environment:
      RUST_LOG: ${RUST_LOG:-info}
      ACADEMIC_CONFIG_PORT: 8083
      ACADEMIC_CONFIG_DATABASE_URL: ${ACADEMIC_CONFIG_DATABASE_URL}
      RABBITMQ_URL: ${RABBITMQ_URL}
      IAM_PUBLIC_KEY: ${IAM_PUBLIC_KEY}
      FEATURES_TOML_PATH: /app/features.toml
      CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS}

  academic-ops-service:
    <<: *service-base
    image: ghcr.io/protocyber/akademiq-academic-ops-service:${IMAGE_TAG:-latest}
    container_name: akademiq-academic-ops-service
    environment:
      RUST_LOG: ${RUST_LOG:-info}
      ACADEMIC_OPS_PORT: 8084
      ACADEMIC_OPS_DATABASE_URL: ${ACADEMIC_OPS_DATABASE_URL}
      RABBITMQ_URL: ${RABBITMQ_URL}
      IAM_PUBLIC_KEY: ${IAM_PUBLIC_KEY}
      FEATURES_TOML_PATH: /app/features.toml
      CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS}

  grading-service:
    <<: *service-base
    image: ghcr.io/protocyber/akademiq-grading-service:${IMAGE_TAG:-latest}
    container_name: akademiq-grading-service
    environment:
      RUST_LOG: ${RUST_LOG:-info}
      GRADING_PORT: 8086
      GRADING_DATABASE_URL: ${GRADING_DATABASE_URL}
      RABBITMQ_URL: ${RABBITMQ_URL}
      IAM_PUBLIC_KEY: ${IAM_PUBLIC_KEY}
      FEATURES_TOML_PATH: /app/features.toml
      CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS}

volumes:
  caddy_data:
  caddy_config:
```

### B. `Caddyfile`
Caddy handles automatic HTTPS provisioning (using the free `nip.io` resolver since you do not have a custom domain) and clean proxy routing:
```caddy
# Replace <YOUR_VM_IP> with the actual static external IP of your VM (e.g., 35.240.12.34.nip.io).
# Caddy will automatically fetch a Let's Encrypt SSL certificate for this domain.
# Alternatively, if you want to use plain HTTP, you can write `:80` instead.
<YOUR_VM_IP>.nip.io {
    # Route API paths to respective internal backend services
    reverse_proxy /api/v1/iam/* iam-service:8081
    reverse_proxy /api/v1/billing/* billing-service:8082
    reverse_proxy /api/v1/academic-config/* academic-config-service:8083
    reverse_proxy /api/v1/academic-ops/* academic-ops-service:8084
    reverse_proxy /api/v1/grading/* grading-service:8086

    # Return 404 for any other path
    respond "Not Found" 404
}
```

### C. Generation of Keys & Secrets
To generate a production-ready RS256 key pair for JWT signing:
```bash
# Generate private key
openssl genpkey -algorithm RSA -out rsa_private.pem -pkeyopt rsa_keygen_bits:2048

# Derive public key
openssl rsa -pubout -in rsa_private.pem -out rsa_public.pub

# Convert to single line with \n for env use:
cat rsa_private.pem | awk '{printf "%s\\n", $0}'
cat rsa_public.pub | awk '{printf "%s\\n", $0}'
```

Generate a random internal service token:
```bash
openssl rand -hex 32
```

### D. `.env`
Create `.env` inside `~/akademiq-deploy/` and fill in the details (naming it `.env` allows Docker Compose to load it automatically without needing to specify `--env-file` for every command):
```ini
IMAGE_TAG=latest

# Database configuration (Supabase schema-per-service)
IAM_DATABASE_URL="postgres://postgres.xxx:password@aws-0-xx.pooler.supabase.com:6543/postgres?sslmode=require&options=-c%20search_path%3Diam"
BILLING_DATABASE_URL="postgres://postgres.xxx:password@aws-0-xx.pooler.supabase.com:6543/postgres?sslmode=require&options=-c%20search_path%3Dbilling"
ACADEMIC_CONFIG_DATABASE_URL="postgres://postgres.xxx:password@aws-0-xx.pooler.supabase.com:6543/postgres?sslmode=require&options=-c%20search_path%3Dacademic_config"
ACADEMIC_OPS_DATABASE_URL="postgres://postgres.xxx:password@aws-0-xx.pooler.supabase.com:6543/postgres?sslmode=require&options=-c%20search_path%3Dacademic_ops"
GRADING_DATABASE_URL="postgres://postgres.xxx:password@aws-0-xx.pooler.supabase.com:6543/postgres?sslmode=require&options=-c%20search_path%3Dgrading"

# Message Broker configuration
RABBITMQ_URL="amqps://xxx:yyy@cloudamqp.com/vhost"

# IAM Key materials (Use \n for line endings)
IAM_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
IAM_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----"
IAM_INTERNAL_SERVICE_TOKEN="<your-generated-token>"

# Google OAuth Setup
GOOGLE_CLIENT_ID="<your-client-id>"
GOOGLE_CLIENT_SECRET="<your-client-secret>"
GOOGLE_REDIRECT_URI="https://<YOUR_VM_IP>.nip.io/api/v1/iam/auth/google/callback"

# Web Origin and Email Setup
PUBLIC_WEB_BASE_URL="https://your-frontend-domain.app"
CORS_ALLOWED_ORIGINS="https://your-frontend-domain.app"
EMAIL_PROVIDER="resend"
EMAIL_FROM="AcademiQ <onboarding@resend.dev>"
RESEND_API_KEY="re_xxx"
RESEND_ENDPOINT="https://api.resend.com/emails"
```

---

## 6. Running the Stack

Once your files are configured on the VM:

1. **Pull Images**:
   ```bash
   docker compose -f compose.prod.yml pull
   ```
2. **Start Services**:
   ```bash
   docker compose -f compose.prod.yml up -d
   ```
3. **Verify running containers**:
   ```bash
   docker compose -f compose.prod.yml ps
   ```

Each microservice runs its refinery database migrations automatically on boot against its respective schema in Supabase.

---

## 7. Operational & Troubleshooting Commands

- **Check logs**:
  ```bash
  docker compose -f compose.prod.yml logs -f --tail=100
  ```
- **Inspect individual service logs**:
  ```bash
  docker compose -f compose.prod.yml logs iam-service -f
  ```
- **Restart the Stack**:
  ```bash
  docker compose -f compose.prod.yml restart
  ```
- **Check VM resources (RAM / CPU)**:
  Since we're on a small/free tier VM, it's important to monitor resources:
  ```bash
  free -h
  docker stats --no-stream
  ```
