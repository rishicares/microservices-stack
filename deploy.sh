#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="app"
CLUSTER_TYPE="minikube"  # or "kind"
PROJECT_NAME="deployment"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    if [[ "$CLUSTER_TYPE" == "minikube" ]]; then
        if ! command -v minikube &> /dev/null; then
            log_error "minikube is not installed"
            exit 1
        fi
        if ! minikube status &> /dev/null; then
            log_warning "minikube is not running, starting it..."
            minikube start
        fi
    elif [[ "$CLUSTER_TYPE" == "kind" ]]; then
        if ! command -v kind &> /dev/null; then
            log_error "kind is not installed"
            exit 1
        fi
    fi
    
    log_success "Prerequisites check passed"
}

build_images() {
    log_info "Building Docker images..."
    
    local services=("api-service" "worker-service" "frontend-service")
    
    for service in "${services[@]}"; do
        log_info "Building $service..."
        if docker build -t "$service:latest" "./$service"; then
            log_success "Built $service:latest"
        else
            log_error "Failed to build $service"
            exit 1
        fi
    done
}

load_images() {
    log_info "Loading images into cluster..."
    
    local services=("api-service" "worker-service" "frontend-service")
    
    for service in "${services[@]}"; do
        log_info "Loading $service into $CLUSTER_TYPE..."
        if [[ "$CLUSTER_TYPE" == "minikube" ]]; then
            if minikube image load "$service:latest"; then
                log_success "Loaded $service into minikube"
            else
                log_error "Failed to load $service into minikube"
                exit 1
            fi
        elif [[ "$CLUSTER_TYPE" == "kind" ]]; then
            if kind load docker-image "$service:latest"; then
                log_success "Loaded $service into kind"
            else
                log_error "Failed to load $service into kind"
                exit 1
            fi
        fi
    done
}

apply_manifests() {
    log_info "Applying Kubernetes manifests..."
    
    local manifests=(
        "k8s/namespace.yaml"
        "k8s/resource-quota.yaml"
        "k8s/secrets.yaml"
        "k8s/configmap.yaml"
        "k8s/postgres.yaml"
        "k8s/api-deployment.yaml"
        "k8s/worker-deployment.yaml"
        "k8s/frontend-deployment.yaml"
        "k8s/hpa.yaml"
        "k8s/network-policies.yaml"
        "k8s/ingress.yaml"
    )
    
    for manifest in "${manifests[@]}"; do
        if [[ -f "$manifest" ]]; then
            log_info "Applying $manifest..."
            if kubectl apply -f "$manifest"; then
                log_success "Applied $manifest"
            else
                log_error "Failed to apply $manifest"
                exit 1
            fi
        else
            log_error "Manifest file $manifest not found"
            exit 1
        fi
    done
}

wait_for_rollouts() {
    log_info "Waiting for deployments to roll out..."
    
    local deployments=("api-service" "worker-service" "frontend-service")
    
    for deployment in "${deployments[@]}"; do
        log_info "Waiting for $deployment rollout..."
        if kubectl -n "$NAMESPACE" rollout status "deploy/$deployment" --timeout=300s; then
            log_success "$deployment rolled out successfully"
        else
            log_error "$deployment rollout failed"
            log_warning "Attempting rollback for $deployment..."
            kubectl -n "$NAMESPACE" rollout undo "deploy/$deployment" || true
            exit 1
        fi
    done
}

show_access_info() {
    log_info "Deployment completed! Access information:"
    
    if [[ "$CLUSTER_TYPE" == "minikube" ]]; then
        local frontend_url
        frontend_url=$(minikube service -n "$NAMESPACE" frontend-service --url 2>/dev/null || echo "http://$(minikube ip):30080")
        echo -e "${GREEN}Frontend:${NC} $frontend_url"
        echo -e "${GREEN}API Health:${NC} kubectl -n $NAMESPACE port-forward svc/api-service 3000:3000"
    elif [[ "$CLUSTER_TYPE" == "kind" ]]; then
        echo -e "${GREEN}Frontend:${NC} kubectl -n $NAMESPACE port-forward svc/frontend-service 8080:80"
        echo -e "${GREEN}API Health:${NC} kubectl -n $NAMESPACE port-forward svc/api-service 3000:3000"
    fi
    
    echo -e "${GREEN}Check pods:${NC} kubectl -n $NAMESPACE get pods"
    echo -e "${GREEN}View logs:${NC} kubectl -n $NAMESPACE logs deploy/api-service"
}

cleanup() {
    log_info "Cleaning up..."
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
    log_success "Cleanup completed"
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --cluster TYPE  Cluster type: minikube (default) or kind"
    echo "  -n, --namespace NS  Kubernetes namespace (default: app)"
    echo "  --cleanup           Clean up existing deployment before deploying"
    echo "  --cleanup-only      Only clean up, don't deploy"
    echo "  --no-build          Skip building images (use existing ones)"
    echo "  --no-load           Skip loading images into cluster"
    echo ""
    echo "Examples:"
    echo "  $0                           # Deploy to minikube"
    echo "  $0 -c kind                   # Deploy to kind"
    echo "  $0 --cleanup                 # Clean up and deploy"
    echo "  $0 --cleanup-only            # Only clean up"
}

# Parse command line arguments
CLEANUP_BEFORE=false
CLEANUP_ONLY=false
NO_BUILD=false
NO_LOAD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--cluster)
            CLUSTER_TYPE="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --cleanup)
            CLEANUP_BEFORE=true
            shift
            ;;
        --cleanup-only)
            CLEANUP_ONLY=true
            shift
            ;;
        --no-build)
            NO_BUILD=true
            shift
            ;;
        --no-load)
            NO_LOAD=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting deployment to $CLUSTER_TYPE cluster..."
    
    check_prerequisites
    
    if [[ "$CLEANUP_BEFORE" == true || "$CLEANUP_ONLY" == true ]]; then
        cleanup
    fi
    
    if [[ "$CLEANUP_ONLY" == true ]]; then
        log_success "Cleanup completed. Exiting."
        exit 0
    fi
    
    if [[ "$NO_BUILD" != true ]]; then
        build_images
    fi
    
    if [[ "$NO_LOAD" != true ]]; then
        load_images
    fi
    
    apply_manifests
    wait_for_rollouts
    show_access_info
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"
NAME                                READY   STATUS             RESTARTS      AGE
api-service-fdcf45986-2njjn         1/1     Running            0             2m28s
api-service-fdcf45986-zg5h7         1/1     Running            0             2m28s
frontend-service-7cbf68bb8c-5wqnr   0/1     CrashLoopBackOff   4 (46s ago)   2m28s
frontend-service-7cbf68bb8c-k8wk9   0/1     CrashLoopBackOff   4 (55s ago)   2m28s
postgres-0                          1/1     Running            0             2m29s
worker-service-57d64984dc-gcnfm     1/1     Running            0             2m28s