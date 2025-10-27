#!/bin/bash
set -euo pipefail

# Multi-Region Deployment Script for Eagle Alert System
# This script deploys the multi-region infrastructure and data synchronization components

# Configuration
PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
NAMESPACE="${NAMESPACE:-eagle-services}"
DRY_RUN="${DRY_RUN:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if contexts exist
    if ! kubectl config get-contexts | grep -q "$PRIMARY_REGION"; then
        log_error "Kubernetes context for primary region ($PRIMARY_REGION) not found"
        exit 1
    fi
    
    if ! kubectl config get-contexts | grep -q "$SECONDARY_REGION"; then
        log_error "Kubernetes context for secondary region ($SECONDARY_REGION) not found"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" --context="$PRIMARY_REGION" &> /dev/null; then
        log_warning "Namespace $NAMESPACE does not exist in primary region, creating..."
        kubectl create namespace "$NAMESPACE" --context="$PRIMARY_REGION"
    fi
    
    if ! kubectl get namespace "$NAMESPACE" --context="$SECONDARY_REGION" &> /dev/null; then
        log_warning "Namespace $NAMESPACE does not exist in secondary region, creating..."
        kubectl create namespace "$NAMESPACE" --context="$SECONDARY_REGION"
    fi
    
    log_success "Prerequisites check completed"
}

# Deploy configuration
deploy_configuration() {
    log_info "Deploying multi-region configuration..."
    
    local configs=(
        "region-config.yaml"
        "cross-region-networking.yaml"
    )
    
    for config in "${configs[@]}"; do
        log_info "Deploying $config to both regions..."
        
        if [ "$DRY_RUN" = "true" ]; then
            kubectl apply -f "$config" --context="$PRIMARY_REGION" --dry-run=client
            kubectl apply -f "$config" --context="$SECONDARY_REGION" --dry-run=client
        else
            kubectl apply -f "$config" --context="$PRIMARY_REGION"
            kubectl apply -f "$config" --context="$SECONDARY_REGION"
        fi
    done
    
    log_success "Configuration deployment completed"
}

# Deploy PostgreSQL replication
deploy_postgres_replication() {
    log_info "Deploying PostgreSQL multi-region replication..."
    
    # Deploy to primary region first
    log_info "Deploying PostgreSQL primary to $PRIMARY_REGION..."
    if [ "$DRY_RUN" = "true" ]; then
        kubectl apply -f "../database/multi-region-replication.yaml" --context="$PRIMARY_REGION" --dry-run=client
    else
        kubectl apply -f "../database/multi-region-replication.yaml" --context="$PRIMARY_REGION"
        
        # Wait for primary to be ready
        log_info "Waiting for PostgreSQL primary to be ready..."
        kubectl wait --for=condition=ready pod -l app=postgres,role=primary --timeout=300s --context="$PRIMARY_REGION"
    fi
    
    # Deploy replica to secondary region
    log_info "Deploying PostgreSQL replica to $SECONDARY_REGION..."
    if [ "$DRY_RUN" = "true" ]; then
        kubectl apply -f "../database/multi-region-replication.yaml" --context="$SECONDARY_REGION" --dry-run=client
    else
        # Update replica configuration for secondary region
        sed "s/us-west-2/$SECONDARY_REGION/g" "../database/multi-region-replication.yaml" | \
        kubectl apply -f - --context="$SECONDARY_REGION"
        
        # Wait for replica to be ready
        log_info "Waiting for PostgreSQL replica to be ready..."
        kubectl wait --for=condition=ready pod -l app=postgres,role=replica --timeout=300s --context="$SECONDARY_REGION"
    fi
    
    log_success "PostgreSQL replication deployment completed"
}

# Deploy Redis cluster
deploy_redis_cluster() {
    log_info "Deploying Redis cross-region cluster..."
    
    # Deploy Redis primary to primary region
    log_info "Deploying Redis primary to $PRIMARY_REGION..."
    if [ "$DRY_RUN" = "true" ]; then
        kubectl apply -f "redis-cluster-cross-region.yaml" --context="$PRIMARY_REGION" --dry-run=client
    else
        kubectl apply -f "redis-cluster-cross-region.yaml" --context="$PRIMARY_REGION"
        
        # Wait for Redis primary to be ready
        log_info "Waiting for Redis primary to be ready..."
        kubectl wait --for=condition=ready pod -l app=redis,role=primary --timeout=300s --context="$PRIMARY_REGION"
    fi
    
    # Deploy Redis replica to secondary region
    log_info "Deploying Redis replica to $SECONDARY_REGION..."
    if [ "$DRY_RUN" = "true" ]; then
        kubectl apply -f "redis-cluster-cross-region.yaml" --context="$SECONDARY_REGION" --dry-run=client
    else
        kubectl apply -f "redis-cluster-cross-region.yaml" --context="$SECONDARY_REGION"
        
        # Wait for Redis replica to be ready
        log_info "Waiting for Redis replica to be ready..."
        kubectl wait --for=condition=ready pod -l app=redis,role=replica --timeout=300s --context="$SECONDARY_REGION"
    fi
    
    log_success "Redis cluster deployment completed"
}

# Deploy conflict resolution
deploy_conflict_resolution() {
    log_info "Deploying conflict resolution system..."
    
    if [ "$DRY_RUN" = "true" ]; then
        kubectl apply -f "conflict-resolution.yaml" --context="$PRIMARY_REGION" --dry-run=client
        kubectl apply -f "conflict-resolution.yaml" --context="$SECONDARY_REGION" --dry-run=client
    else
        kubectl apply -f "conflict-resolution.yaml" --context="$PRIMARY_REGION"
        kubectl apply -f "conflict-resolution.yaml" --context="$SECONDARY_REGION"
        
        # Wait for conflict resolution service to be ready
        log_info "Waiting for conflict resolution service to be ready..."
        kubectl wait --for=condition=ready pod -l app=conflict-resolution --timeout=300s --context="$PRIMARY_REGION"
        kubectl wait --for=condition=ready pod -l app=conflict-resolution --timeout=300s --context="$SECONDARY_REGION"
    fi
    
    log_success "Conflict resolution deployment completed"
}

# Deploy health checks
deploy_health_checks() {
    log_info "Deploying cross-region health checks..."
    
    if [ "$DRY_RUN" = "true" ]; then
        kubectl apply -f "health-checks.yaml" --context="$PRIMARY_REGION" --dry-run=client
    else
        kubectl apply -f "health-checks.yaml" --context="$PRIMARY_REGION"
        
        # The health check runs from primary region and monitors both regions
        log_info "Health check system deployed to primary region"
    fi
    
    log_success "Health checks deployment completed"
}

# Deploy disaster recovery
deploy_disaster_recovery() {
    log_info "Deploying disaster recovery automation..."
    
    if [ "$DRY_RUN" = "true" ]; then
        kubectl apply -f "disaster-recovery.yaml" --context="$PRIMARY_REGION" --dry-run=client
    else
        kubectl apply -f "disaster-recovery.yaml" --context="$PRIMARY_REGION"
        
        # Wait for disaster recovery service to be ready
        log_info "Waiting for disaster recovery service to be ready..."
        kubectl wait --for=condition=ready pod -l app=disaster-recovery --timeout=300s --context="$PRIMARY_REGION"
    fi
    
    log_success "Disaster recovery deployment completed"
}

# Validate deployment
validate_deployment() {
    log_info "Validating multi-region deployment..."
    
    # Check PostgreSQL replication
    log_info "Checking PostgreSQL replication status..."
    if [ "$DRY_RUN" = "false" ]; then
        kubectl exec -it deployment/postgres-primary --context="$PRIMARY_REGION" -- \
            psql -U postgres -d eagle_db -c "SELECT * FROM pg_stat_replication;" || log_warning "PostgreSQL replication check failed"
    fi
    
    # Check Redis replication
    log_info "Checking Redis replication status..."
    if [ "$DRY_RUN" = "false" ]; then
        kubectl exec -it deployment/redis-primary --context="$PRIMARY_REGION" -- \
            redis-cli INFO replication || log_warning "Redis replication check failed"
    fi
    
    # Check service connectivity
    log_info "Checking cross-region service connectivity..."
    if [ "$DRY_RUN" = "false" ]; then
        # Test from primary to secondary
        kubectl run test-connectivity --rm -i --tty --image=curlimages/curl --context="$PRIMARY_REGION" -- \
            curl -f "http://postgres-replica-west-service.$NAMESPACE.svc.cluster.local:5432" || log_warning "Cross-region connectivity test failed"
    fi
    
    log_success "Deployment validation completed"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary resources..."
    kubectl delete pod test-connectivity --context="$PRIMARY_REGION" --ignore-not-found=true
}

# Main deployment function
main() {
    log_info "Starting multi-region deployment for Eagle Alert System"
    log_info "Primary Region: $PRIMARY_REGION"
    log_info "Secondary Region: $SECONDARY_REGION"
    log_info "Namespace: $NAMESPACE"
    log_info "Dry Run: $DRY_RUN"
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Execute deployment steps
    check_prerequisites
    deploy_configuration
    deploy_postgres_replication
    deploy_redis_cluster
    deploy_conflict_resolution
    deploy_health_checks
    deploy_disaster_recovery
    validate_deployment
    
    log_success "Multi-region deployment completed successfully!"
    
    # Display next steps
    echo
    log_info "Next Steps:"
    echo "1. Configure DNS to point to your load balancers"
    echo "2. Set up monitoring dashboards for cross-region metrics"
    echo "3. Test disaster recovery procedures"
    echo "4. Configure backup and retention policies"
    echo
    log_info "Monitoring URLs:"
    echo "- Primary Region Health: https://api-primary.eagle.com/health"
    echo "- Secondary Region Health: https://api-secondary.eagle.com/health"
    echo "- Grafana Dashboard: http://grafana.eagle.com:3000"
    echo
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --primary-region)
            PRIMARY_REGION="$2"
            shift 2
            ;;
        --secondary-region)
            SECONDARY_REGION="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --primary-region REGION    Primary region (default: us-east-1)"
            echo "  --secondary-region REGION  Secondary region (default: us-west-2)"
            echo "  --namespace NAMESPACE      Kubernetes namespace (default: eagle-services)"
            echo "  --dry-run                  Perform a dry run without applying changes"
            echo "  --help                     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main