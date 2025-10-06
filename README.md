## DevOps Deployment  - Microservices Stack

### Components
- **api-service**: Node.js Express REST API using Postgres
- **worker-service**: Python worker polling Postgres
- **frontend-service**: Static React (CDN) served by Nginx; proxies `/api` to API
- **Database**: Postgres 16 (shared by API and worker)

### Prerequisites
- Docker and Docker Compose
- kubectl and minikube
- GitHub repo (for CI/CD, with `KUBE_CONFIG_BASE64` secret)

---

### Local (Docker Compose)
1. Build and start:
   ```bash
   docker compose up -d --build
   ```
2. Verify:
   - Frontend: `http://localhost:8080`
   - API health: `http://localhost:3000/health`
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

### Kubernetes Deployment (kind or minikube)
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

---

### Persistence Strategy (DB)
- Postgres uses a `StatefulSet` with a `PersistentVolumeClaim` (5Gi, RWO)
- Data persists across pod restarts and redeploys
- For production, bind to a StorageClass (e.g., gp2, pd-ssd) and set size

---

### CI/CD (GitHub Actions)
- On push to `main`, builds and pushes images to GHCR: `api-service`, `worker-service`, `frontend-service`
- Deploy job applies Kubernetes manifests and substitutes image tags
- Rollback: if rollout status fails, workflow triggers `kubectl rollout undo` for each deployment
- Required secrets:
  - `KUBE_CONFIG_BASE64`: base64 kubeconfig for target cluster context
  - (Optional) `REGISTRY_USERNAME`, `REGISTRY_PASSWORD` if using a private registry other than GHCR
- Image tags:
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

### Production Hardening Highlights
- Non-root containers with `securityContext` on all services
- Resource requests/limits set for API, worker, frontend, and Postgres
- Probes:
  - API: `startupProbe` `/live`, `liveness` `/live`, `readiness` `/health`
  - Frontend: `/` for readiness/liveness
- DB config via `Secret`; services construct `DATABASE_URL` from `POSTGRES_*`
- `PGSSLMODE=disable` explicitly set in API/worker for in-cluster Postgres
- Nginx reverse proxy preserves `/api` prefix; basic security headers and timeouts

---

### Observability & Debugging
- Logs:
  - Docker: `docker logs <container>`
  - Kubernetes: `kubectl -n app logs deploy/<name> --tail=100`
- Health checks:
  - API: `/live` (no DB), `/health` (DB query)
  - Frontend: `/`
- Pod shell & quick probes:
  ```bash
  kubectl -n app exec -it deploy/api-service -- sh -lc "wget -qO- http://localhost:3000/live; echo; wget -qO- http://localhost:3000/health"
  kubectl -n app exec -it deploy/api-service -- sh -lc "getent hosts postgres; nc -zv postgres 5432 || true"
  ```

---

### Troubleshooting
- **DB connection failures**: ensure `db-secret` applied; verify DNS `postgres.app.svc.cluster.local`; check pod env
- **Pods pending**: check StorageClass and PVC binding: `kubectl -n app get pvc,pv`
- **Rollout stuck**: `kubectl -n app describe deploy/<name>`; undo: `kubectl -n app rollout undo deploy/<name>`
- **Port conflicts locally**: change `docker-compose.yml` host ports
- **Performance**:
  - Postgres: add CPU/memory requests/limits; tune `shared_buffers`, `work_mem`
  - API/Worker: scale replicas; enable connection pooling (e.g., pgBouncer)

---

### Cleaning Up
```bash
kubectl delete namespace app
# or
docker compose down -v
```
