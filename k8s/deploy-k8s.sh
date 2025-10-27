#!/bin/bash

# Kubernetes Deployment Script for Eagle Alert Creation System
# This script deploys all microservices with proper ordering and health checks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster."
        exit 1
    fi
    
    # Check Istio
    if ! kubectl get namespace istio-system &> /dev/null; then
        log_warning "Istio not found. Please install Istio first."
        log_info "Run: ./infra/istio/setup-istio.sh"
        exit 1
    fi
    
    log_success "Prerequisites check completed!"
}

# Deploy namespace and RBAC
deploy_namespace() {
    log_info "Deploying namespace and RBAC..."
    
    kubectl apply -f namespace/
    
    # Wait for namespace to be ready
    kubectl wait --for=condition=Active namespace/eagle-services --timeout=60s
    
    log_success "Namespace and RBAC deployed!"
}

# Deploy ConfigMaps and Secrets
deploy_configs() {
    log_info "Deploying ConfigMaps and Secrets..."
    
    kubectl apply -f configmaps/
    kubectl apply -f secrets/
    
    log_success "ConfigMaps and Secrets deployed!"
}

# Deploy Services
deploy_services() {
    log_info "Deploying Services..."
    
    kubectl apply -f services/
    
    log_success "Services deployed!"
}

# Deploy applications
deploy_applications() {
    log_info "Deploying microservices..."
    
    # Deploy in dependency order
    log_info "Deploying MS-Customer (foundational service)..."
    kubectl apply -f deployments/ms-customer.yaml
    kubectl rollout status deployment/ms-customer -n eagle-services --timeout=300s
    
    log_info "Deploying MS-Transaction..."
    kubectl apply -f deployments/ms-transaction.yaml
    kubectl rollout status deployment/ms-transaction -n eagle-services --timeout=300s
    
    log_info "Deploying MS-API..."
    kubectl apply -f deployments/ms-api.yaml
    kubectl rollout status deployment/ms-api -n eagle-services --timeout=300s
    
    log_info "Deploying MS-Alert..."
    kubectl apply -f deployments/ms-alert.yaml
    kubectl rollout status deployment/ms-alert -n eagle-services --timeout=300s
    
    log_info "Deploying MS-Enrichment..."
    kubectl apply -f deployments/ms-enrichment.yaml
    kubectl rollout status deployment/ms-enrichment -n eagle-services --timeout=300s
    
    log_info "Deploying MS-Orchestrator (main entry point)..."
    kubectl apply -f deployments/ms-orchestrator.yaml
    kubectl rollout status deployment/ms-orchestrator -n eagle-services --timeout=300s
    
    log_success "All microservices deployed!"
}

# Deploy HPA and scaling configs
deploy_scaling() {
    log_info "Deploying auto-scaling configurations..."
    
    # Check if metrics-server is available
    if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        kubectl apply -f hpa/
        log_success "HPA configurations deployed!"
    else
        log_warning "Metrics-server not found. HPA will not work without it."
    fi
    
    # Deploy VPA if available
    if kubectl get crd verticalpodautoscalers.autoscaling.k8s.io &> /dev/null; then
        kubectl apply -f vpa/
        log_success "VPA configurations deployed!"
    else
        log_warning "VPA CRDs not found. Skipping VPA deployment."
    fi
    
    # Deploy PDB
    kubectl apply -f pdb/
    log_success "Pod Disruption Budgets deployed!"
}

# Deploy deployment strategies
deploy_strategies() {
    log_info "Deploying deployment strategies..."
    
    kubectl apply -f deployment-strategies/
    
    log_success "Deployment strategies configured!"
}

# Deploy ingress
deploy_ingress() {
    log_info "Deploying ingress configurations..."
    
    kubectl apply -f ingress/
    
    log_success "Ingress configurations deployed!"
}

# Deploy monitoring
deploy_monitoring() {
    log_info "Deploying monitoring configurations..."
    
    # Check if Prometheus Operator is available
    if kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
        kubectl apply -f monitoring/
        log_success "Monitoring configurations deployed!"
    else
        log_warning "Prometheus Operator not found. Monitoring configs skipped."
    fi
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check pod status
    log_info "Checking pod status..."
    kubectl get pods -n eagle-services -o wide
    
    # Check services
    log_info "Checking services..."
    kubectl get services -n eagle-services
    
    # Check HPA status
    if kubectl get hpa -n eagle-services &> /dev/null; then
        log_info "Checking HPA status..."
        kubectl get hpa -n eagle-services
    fi
    
    # Health check
    log_info "Performing health checks..."
    for service in ms-orchestrator ms-alert ms-customer ms-transaction ms-api ms-enrichment; do
        if kubectl get deployment $service -n eagle-services &> /dev/null; then
            replicas=$(kubectl get deployment $service -n eagle-services -o jsonpath='{.status.readyReplicas}')
            desired=$(kubectl get deployment $service -n eagle-services -o jsonpath='{.spec.replicas}')
            
            if [ "$replicas" = "$desired" ]; then
                log_success "$service: $replicas/$desired replicas ready"
            else
                log_warning "$service: $replicas/$desired replicas ready"
            fi
        fi
    done
}

# Show access information
show_access_info() {
    log_info "Deployment completed! Access information:"
    
    echo ""
    echo "🌐 API Gateway:"
    echo "  External IP: $(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo 'Pending...')"
    echo "  Ports: 80 (HTTP), 443 (HTTPS)"
    echo ""
    
    echo "📊 Monitoring:"
    echo "  Grafana: kubectl port-forward -n istio-system svc/grafana 3000:3000"
    echo "  Prometheus: kubectl port-forward -n istio-system svc/prometheus 9090:9090"
    echo "  Jaeger: kubectl port-forward -n istio-system svc/jaeger 16686:16686"
    echo ""
    
    echo "🔍 Useful commands:"
    echo "  Watch pods: kubectl get pods -n eagle-services -w"
    echo "  Check logs: kubectl logs -n eagle-services deployment/<service-name> -f"
    echo "  Check HPA: kubectl get hpa -n eagle-services"
    echo "  Check metrics: kubectl top pods -n eagle-services"
    echo ""
}

# Cleanup function
cleanup() {
    log_info "Cleaning up previous deployment..."
    
    kubectl delete -f deployments/ --ignore-not-found=true
    kubectl delete -f hpa/ --ignore-not-found=true
    kubectl delete -f pdb/ --ignore-not-found=true
    kubectl delete -f services/ --ignore-not-found=true
    
    # Wait for cleanup
    sleep 10
    
    log_success "Cleanup completed!"
}

# Main deployment function
main() {
    echo "🚀 Starting Kubernetes deployment for Eagle Alert Creation System..."
    echo "=================================================================="
    
    # Parse command line arguments
    CLEANUP=false
    SKIP_APPS=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup)
                CLEANUP=true
                shift
                ;;
            --skip-apps)
                SKIP_APPS=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --cleanup     Clean up existing deployment first"
                echo "  --skip-apps   Skip application deployment (configs only)"
                echo "  --help        Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    
    if [ "$CLEANUP" = true ]; then
        cleanup
    fi
    
    deploy_namespace
    deploy_configs
    deploy_services
    
    if [ "$SKIP_APPS" = false ]; then
        deploy_applications
        deploy_scaling
        deploy_strategies
    fi
    
    deploy_ingress
    deploy_monitoring
    verify_deployment
    
    echo ""
    echo "=================================================================="
    log_success "🎉 Kubernetes deployment completed successfully!"
    echo "=================================================================="
    
    show_access_info
}

# Execute main function
main "$@"