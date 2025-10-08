## Microservices Stack - DevOps Implementation

A production-ready microservices application demonstrating modern DevOps practices including Docker containerization, Kubernetes orchestration, and automated CI/CD pipelines.

### Overview

This project implements a complete 3-tier microservices architecture with:
- **Containerization**: Multi-stage Docker builds with security best practices
- **Orchestration**: Kubernetes deployment with auto-scaling and persistent storage
- **Automation**: CI/CD pipeline with automated testing and rollback capabilities
- **Production Features**: Health checks, resource management, security policies, and comprehensive monitoring

### Table of Contents
- [Components](#components)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Local Development (Docker Compose)](#local-docker-compose)
- [Kubernetes Deployment](#kubernetes-deployment)
- [CI/CD Pipeline](#cicd-github-actions)
- [Production Features](#production-features)
- [Troubleshooting](#troubleshooting)
- [Architecture Overview](#architecture-overview)

---

### Components
- **api-service**: Node.js Express REST API using Postgres
- **worker-service**: Python worker polling Postgres
- **frontend-service**: Static React (CDN) served by Nginx; proxies `/api` to API
- **Database**: Postgres 16 (shared by API and worker)

---

### Prerequisites

#### Required Software
- Docker and Docker Compose
- kubectl
- minikube or kind
- Git

#### Docker Group Setup (Linux)
If you encounter Docker permission errors, add your user to the docker group:

```bash
# Add current user to docker group
sudo usermod -aG docker $USER

# Apply group changes (choose one):
# Option 1: Start new shell session
newgrp docker

# Option 2: Log out and log back in

# Verify Docker access
docker ps
```

#### For CI/CD
- GitHub repository with Actions enabled
- `KUBE_CONFIG_BASE64` secret configured in repository settings

### Quick Start
```bash
# Local development
docker compose up -d --build
# Access: http://localhost:8080 (frontend), http://localhost:3000/health (API)

# Kubernetes deployment
./deploy.sh
# Access: kubectl -n app port-forward svc/api-service 3000:3000
```

---

## Local Development (Docker Compose)
1. Build and start:
   ```bash
   docker compose up -d --build
   ```
2. Verify:
   - Frontend: `http://localhost:8080`
   - API health: `http://localhost:3000/health`
   - API time: `http://localhost:8080/api/time`
   - Worker logs: `docker compose logs worker-service`
   - Postgres persists to `db_data` volume
3. Stop:
   ```bash
   docker compose down
   # keep data
   # docker volume rm technical-assessment_db_data to purge
   ```

---

### Docker Images (manual build)
```bash
# from repo root
docker build -t api-service:local ./api-service
docker build -t worker-service:local ./worker-service
docker build -t frontend-service:local ./frontend-service
```

---

### Kubernetes Deployment
Use the deployment script for automated setup:

```bash
# Deploy to minikube (default)
./deploy.sh

# Deploy to kind
./deploy.sh -c kind

# Clean up and deploy fresh
./deploy.sh --cleanup

# Only clean up
./deploy.sh --cleanup-only

# Skip building images (use existing)
./deploy.sh --no-build

# Show all options
./deploy.sh --help
```

### Kubernetes Deployment (Manual)
1. Create cluster (choose one):
   - kind:
     ```bash
     kind create cluster --name dev-assessment
     ```
   - minikube:
     ```bash
     minikube start
     ```
2. Load or pull images:
   - Option A (local dev): build locally and use `IfNotPresent` images
     ```bash
     docker build -t api-service:latest ./api-service
     docker build -t worker-service:latest ./worker-service
     docker build -t frontend-service:latest ./frontend-service
     # for kind
     kind load docker-image api-service:latest --name dev-assessment
     kind load docker-image worker-service:latest --name dev-assessment
     kind load docker-image frontend-service:latest --name dev-assessment
     # for minikube
     minikube image load api-service:latest
     minikube image load worker-service:latest
     minikube image load frontend-service:latest
     ```
   - Option B (CI/CD): images are published to GHCR via Actions
3. Apply manifests:
   ```bash
   kubectl apply -f k8s/namespace.yaml
   kubectl apply -f k8s/secrets.yaml
   kubectl apply -f k8s/postgres.yaml
   kubectl apply -f k8s/api-deployment.yaml
   kubectl apply -f k8s/worker-deployment.yaml
   kubectl apply -f k8s/frontend-deployment.yaml
   ```
4. Wait and test:
   ```bash
   kubectl -n app get pods
   kubectl -n app rollout status deploy/api-service
   kubectl -n app rollout status deploy/worker-service
   kubectl -n app rollout status deploy/frontend-service
   ```
   - Access frontend:
     - kind: `kubectl -n app port-forward svc/frontend-service 8080:80`
     - minikube (NodePort): `minikube service -n app frontend-service --url`
   - Test API:
     - `kubectl -n app port-forward svc/api-service 3000:3000`
     - `curl http://localhost:3000/health`
     - `curl http://localhost:3000/api/time`

---

## Database Persistence Strategy
- Postgres uses a `StatefulSet` with a `PersistentVolumeClaim` (RWO)
- Data persists across pod restarts and redeploys
- For production, bind to a StorageClass and set appropriate size

---

## CI/CD (GitHub Actions)
- **Test Job**: Runs automated tests for both API and Worker services before building
- **Build Job**: On push to `main`, builds and pushes images to GHCR: `api-service`, `worker-service`, `frontend-service`
- **Deploy Job**: Applies Kubernetes manifests and substitutes image tags with rollback mechanism
- **Rollback**: If rollout status fails, workflow triggers `kubectl rollout undo` for each deployment
- **Required secrets**:
  - `KUBE_CONFIG_BASE64`: base64 kubeconfig for target cluster context
  - (Optional) `REGISTRY_USERNAME`, `REGISTRY_PASSWORD` if using a private registry other than GHCR
- **Image tags**:
  - Immutable tag: `${{ github.sha }}`
  - Floating tag: `latest`

---

### Rollback Commands (Kubernetes)
```bash
kubectl -n app rollout undo deploy/api-service
kubectl -n app rollout undo deploy/worker-service
kubectl -n app rollout undo deploy/frontend-service
```

---

### Override Images Locally (minikube/kind)
```bash
# build with a unique tag and load
docker build -t api-service:v2 ./api-service
minikube image load api-service:v2
# point deployment to the new tag
kubectl -n app set image deploy/api-service api=api-service:v2
kubectl -n app rollout status deploy/api-service
```

---

## Production Features
- **Security**:
  - Non-root containers with `securityContext` on all services
  - Network policies restricting pod-to-pod communication
  - Resource quotas and limits for namespace isolation
- **Resource Management**:
  - Resource requests/limits set for all services
  - Horizontal Pod Autoscaler (HPA) for API and Frontend services
  - ConfigMaps for externalized configuration
- **Health Checks**:
  - API: `startupProbe` `/live`, `liveness` `/live`, `readiness` `/health`
  - Worker: `startupProbe` `/live`, `liveness` `/live`, `readiness` `/health`
  - Frontend: `/` for readiness/liveness
- **Database**:
  - DB config via `Secret`; services construct `DATABASE_URL` from `POSTGRES_*`
  - `PGSSLMODE=disable` explicitly set in API/worker for in-cluster Postgres
  - Persistent storage with StatefulSet
- **Networking**:
  - Nginx reverse proxy preserves `/api` prefix; basic security headers and timeouts
  - Ingress controller for external access
  - Service mesh ready with proper service definitions
- **Reliability**:
  - Graceful shutdown handling in API and worker services
  - Connection pooling with timeouts in API service
  - Automated rollback mechanism in CI/CD

---

## Observability & Debugging
- **Logs**:
  - Docker: `docker logs <container>`
  - Kubernetes: `kubectl -n app logs deploy/<name> --tail=100`
- **Health checks**:
  - API: `/live` (no DB), `/health` (DB query)
  - Worker: `/live` (no DB), `/health` (DB query with last heartbeat)
  - Frontend: `/`
- **Monitoring**:
  - HPA metrics: `kubectl -n app get hpa`
  - Resource usage: `kubectl -n app top pods`
  - Network policies: `kubectl -n app get networkpolicies`
- **Pod shell & quick probes**:
  ```bash
  kubectl -n app exec -it deploy/api-service -- sh -lc "wget -qO- http://localhost:3000/live; echo; wget -qO- http://localhost:3000/health"
  kubectl -n app exec -it deploy/worker-service -- sh -lc "wget -qO- http://localhost:8080/live; echo; wget -qO- http://localhost:8080/health"
  kubectl -n app exec -it deploy/api-service -- sh -lc "getent hosts postgres; nc -zv postgres 5432 || true"
  ```

---

## Troubleshooting
- **DB connection failures**: ensure `db-secret` applied; verify DNS `postgres.app.svc.cluster.local`; check pod env
- **Pods pending**: check StorageClass and PVC binding: `kubectl -n app get pvc,pv`
- **Rollout stuck**: `kubectl -n app describe deploy/<name>`; undo: `kubectl -n app rollout undo deploy/<name>`
- **Port conflicts locally**: change `docker-compose.yml` host ports
- **Network issues**: check network policies: `kubectl -n app get networkpolicies`
- **HPA not scaling**: check metrics server: `kubectl top nodes`; verify resource requests/limits
- **Ingress not working**: ensure ingress controller is installed and running
- **Performance**:
  - Postgres: add CPU/memory requests/limits; tune `shared_buffers`, `work_mem`
  - API/Worker: HPA will auto-scale; enable connection pooling (e.g., pgBouncer)
  - Monitor with: `kubectl -n app get hpa` and `kubectl -n app top pods`

---

## Cleaning Up
```bash
# Kubernetes
kubectl delete namespace app

# Docker Compose
docker compose down -v

# Using deploy script
./deploy.sh --cleanup-only
```

---

### Kubernetes Features

#### Auto-scaling
- **Horizontal Pod Autoscaler (HPA)** for API and Frontend services
- Scales based on CPU and Memory utilization
- API service: 2-10 replicas, Frontend service: 2-5 replicas

#### Security
- **Network Policies** restricting pod-to-pod communication
- **Resource Quotas** limiting namespace resource consumption
- **Non-root containers** with proper security contexts

#### Configuration Management
- **ConfigMaps** for externalized application configuration
- **Secrets** for sensitive data (database credentials)
- **Resource limits** and requests for all services

#### Networking
- **Ingress** controller for external access
- **Services** with proper selectors and port mappings
- **Network policies** for micro-segmentation

---

## Architecture Overview

The application follows a microservices architecture with the following components:

- **API Service**: RESTful API built with Node.js and Express, provides endpoints for health checks and time queries
- **Worker Service**: Background job processor built with Python, polls the database at regular intervals
- **Frontend Service**: Static React application served by Nginx with reverse proxy configuration
- **Database**: PostgreSQL 16 with persistent storage for data durability

## API Endpoints

### API Service
- `GET /health` - Health check endpoint (includes database connectivity)
- `GET /api/time` - Returns current timestamp from database
- `GET /live` - Liveness probe endpoint (Kubernetes)

### Worker Service
- `GET /health` - Health check endpoint (includes database connectivity and last heartbeat)
- `GET /live` - Liveness probe endpoint (Kubernetes)

---

## Technology Stack

### Backend & Services
- **API**: Node.js 20, Express.js 4.19.2, PostgreSQL driver (pg 8.13.0)
- **Worker**: Python 3.12, psycopg 3.2.3, uvloop 0.20.0, aiohttp 3.10.11
- **Frontend**: React 18 (CDN), vanilla JavaScript
- **Web Server**: Nginx 1.27 Alpine
- **Database**: PostgreSQL 16 Alpine

### DevOps & Infrastructure
- **Containerization**: Docker with multi-stage builds
- **Orchestration**: Kubernetes with StatefulSets, Deployments, Services
- **CI/CD**: GitHub Actions
- **Monitoring**: Kubernetes probes, health endpoints
- **Automation**: Shell scripts for deployment automation

---

## Project Structure

```
.
├── api-service/
│   ├── Dockerfile              # Multi-stage Node.js build
│   ├── package.json           # Dependencies and scripts
│   └── src/server.js          # Express API server
├── worker-service/
│   ├── Dockerfile             # Multi-stage Python build
│   ├── requirements.txt       # Python dependencies
│   └── app/worker.py          # Background worker with health server
├── frontend-service/
│   ├── Dockerfile             # Nginx Alpine image
│   ├── nginx.conf             # Reverse proxy configuration
│   └── public/index.html      # React frontend
├── k8s/
│   ├── namespace.yaml         # Kubernetes namespace
│   ├── secrets.yaml           # Database credentials
│   ├── postgres.yaml          # StatefulSet with PVC
│   ├── api-deployment.yaml    # API deployment and service
│   ├── worker-deployment.yaml # Worker deployment and service
│   ├── frontend-deployment.yaml # Frontend deployment and service
│   ├── hpa.yaml              # Horizontal Pod Autoscalers
│   ├── network-policies.yaml # Network security policies
│   ├── ingress.yaml          # Ingress controller
│   ├── configmap.yaml        # Application configuration
│   └── resource-quota.yaml   # Namespace resource limits
├── .github/workflows/
│   └── cicd.yml              # GitHub Actions pipeline
├── docker-compose.yml         # Local development setup
├── deploy.sh                  # Automated deployment script
└── README.md                  # This file
```

---

## Contributing

This is a technical assessment project. For production use, consider:
- Adding comprehensive test suites (unit, integration, e2e)
- Implementing proper authentication and authorization
- Adding monitoring solutions (Prometheus, Grafana)
- Setting up log aggregation (ELK stack, Loki)
- Implementing distributed tracing (Jaeger, Zipkin)
- Adding API documentation (OpenAPI/Swagger)
- Implementing rate limiting and request throttling
- Setting up disaster recovery and backup strategies

---

## License

This project is created for educational and assessment purposes.
