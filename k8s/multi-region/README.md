# Multi-Region Deployment for Eagle Alert System

This directory contains the infrastructure and configuration files for deploying the Eagle Alert System across multiple regions with high availability, disaster recovery, and data synchronization capabilities.

## Overview

The multi-region deployment provides:

- **High Availability**: Automatic failover between regions
- **Data Replication**: PostgreSQL streaming replication and Redis cross-region clustering
- **Conflict Resolution**: Automated conflict detection and resolution for distributed data
- **Disaster Recovery**: Automated disaster recovery procedures with configurable RTO/RPO
- **Health Monitoring**: Cross-region health checks and automated alerting

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Primary       │    │   Secondary     │
│   Region        │    │   Region        │
│   (US-East-1)   │    │   (US-West-2)   │
├─────────────────┤    ├─────────────────┤
│ • API Gateway   │◄──►│ • API Gateway   │
│ • Microservices │    │ • Microservices │
│ • PostgreSQL    │────┤ • PostgreSQL    │
│   (Primary)     │    │   (Replica)     │
│ • Redis Master  │────┤ • Redis Replica │
│ • Monitoring    │    │ • Monitoring    │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────────────────┘
              Cross-Region
              Health Checks &
              Disaster Recovery
```

## Components

### 1. Region Configuration (`region-config.yaml`)
- Multi-region settings and endpoints
- Failover thresholds and timeouts
- Cross-region networking configuration

### 2. PostgreSQL Replication (`../database/multi-region-replication.yaml`)
- Streaming replication from primary to secondary region
- Automatic promotion of replica during failover
- Replication monitoring and alerting

### 3. Redis Cross-Region Cluster (`redis-cluster-cross-region.yaml`)
- Redis Sentinel for high availability
- Cross-region replication with conflict resolution
- Automatic failover and recovery

### 4. Conflict Resolution (`conflict-resolution.yaml`)
- Automated conflict detection between regions
- Configurable resolution strategies (last-write-wins, merge, priority-based)
- Audit trail for all conflict resolutions

### 5. Health Checks (`health-checks.yaml`)
- Cross-region connectivity monitoring
- Service health validation
- Automated failover triggers

### 6. Disaster Recovery (`disaster-recovery.yaml`)
- Automated disaster recovery procedures
- RTO/RPO monitoring and enforcement
- Manual and automatic failover capabilities

## Deployment

### Prerequisites

1. **Kubernetes Clusters**: Two Kubernetes clusters in different regions
2. **kubectl**: Configured with contexts for both regions
3. **Network Connectivity**: Cross-region VPC peering or VPN
4. **DNS**: Ability to update DNS records for failover

### Quick Start

```bash
# Deploy with default settings
./deploy-multi-region.sh

# Deploy with custom regions
./deploy-multi-region.sh --primary-region us-east-1 --secondary-region eu-west-1

# Dry run to validate configuration
./deploy-multi-region.sh --dry-run
```

### Step-by-Step Deployment

1. **Configure Kubernetes Contexts**
   ```bash
   # Add primary region context
   kubectl config set-context us-east-1 --cluster=primary-cluster --user=primary-user
   
   # Add secondary region context
   kubectl config set-context us-west-2 --cluster=secondary-cluster --user=secondary-user
   ```

2. **Deploy Infrastructure**
   ```bash
   # Deploy configuration
   kubectl apply -f region-config.yaml --context=us-east-1
   kubectl apply -f region-config.yaml --context=us-west-2
   
   # Deploy networking
   kubectl apply -f cross-region-networking.yaml --context=us-east-1
   kubectl apply -f cross-region-networking.yaml --context=us-west-2
   ```

3. **Deploy Data Layer**
   ```bash
   # Deploy PostgreSQL replication
   kubectl apply -f ../database/multi-region-replication.yaml --context=us-east-1
   kubectl apply -f ../database/multi-region-replication.yaml --context=us-west-2
   
   # Deploy Redis cluster
   kubectl apply -f redis-cluster-cross-region.yaml --context=us-east-1
   kubectl apply -f redis-cluster-cross-region.yaml --context=us-west-2
   ```

4. **Deploy Services**
   ```bash
   # Deploy conflict resolution
   kubectl apply -f conflict-resolution.yaml --context=us-east-1
   kubectl apply -f conflict-resolution.yaml --context=us-west-2
   
   # Deploy health checks (primary region only)
   kubectl apply -f health-checks.yaml --context=us-east-1
   
   # Deploy disaster recovery (primary region only)
   kubectl apply -f disaster-recovery.yaml --context=us-east-1
   ```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PRIMARY_REGION` | Primary region identifier | `us-east-1` |
| `SECONDARY_REGION` | Secondary region identifier | `us-west-2` |
| `NAMESPACE` | Kubernetes namespace | `eagle-services` |
| `RTO_TARGET` | Recovery Time Objective | `15m` |
| `RPO_TARGET` | Recovery Point Objective | `1m` |

### Conflict Resolution Strategies

1. **Last Write Wins**: Use the record with the latest timestamp
2. **Merge with Priority**: Merge records with field-level priority
3. **Source Priority**: Use source system priority
4. **Immutable Append Only**: Reject conflicts for immutable data
5. **Freshness Priority**: Use freshest data based on TTL

### Health Check Configuration

```yaml
health:
  check:
    timeout: "30s"
    interval: "10s"
    failure:
      threshold: "3"
```

## Monitoring

### Key Metrics

- **Replication Lag**: PostgreSQL and Redis replication delay
- **Cross-Region Latency**: Network latency between regions
- **Service Availability**: Uptime percentage per region
- **Failover Events**: Number and duration of failovers
- **Conflict Resolution**: Number of conflicts detected and resolved

### Dashboards

Access monitoring dashboards at:
- Grafana: `http://grafana.eagle.com:3000`
- Prometheus: `http://prometheus.eagle.com:9090`
- Jaeger: `http://jaeger.eagle.com:16686`

### Alerts

Critical alerts are sent to:
- Slack webhook (configured in secrets)
- PagerDuty (if configured)
- Email notifications (if configured)

## Disaster Recovery

### Recovery Time Objectives (RTO)

- **Critical Services**: 5 minutes
- **Non-Critical Services**: 15 minutes
- **Full System Recovery**: 30 minutes

### Recovery Point Objectives (RPO)

- **Critical Data**: 30 seconds
- **Non-Critical Data**: 5 minutes
- **Cache Data**: 15 minutes

### Failover Scenarios

1. **Automatic Failover**: Triggered by health check failures
2. **Manual Failover**: Initiated by operations team
3. **Planned Maintenance**: Scheduled region switching

### Testing

```bash
# Test automatic failover
kubectl scale deployment --replicas=0 -l app.kubernetes.io/component=microservice --context=us-east-1

# Test manual failover
kubectl patch configmap multi-region-config --type merge -p '{"data":{"active.region":"us-west-2"}}'

# Test disaster recovery
kubectl create job --from=cronjob/data-consistency-check test-consistency-$(date +%s)
```

## Troubleshooting

### Common Issues

1. **Replication Lag**
   ```bash
   # Check PostgreSQL replication status
   kubectl exec -it postgres-primary-0 -- psql -c "SELECT * FROM pg_stat_replication;"
   
   # Check Redis replication status
   kubectl exec -it redis-primary-0 -- redis-cli INFO replication
   ```

2. **Cross-Region Connectivity**
   ```bash
   # Test network connectivity
   kubectl run test-conn --rm -i --tty --image=curlimages/curl -- \
     curl -f http://service.namespace.svc.cluster.local:port
   ```

3. **Conflict Resolution Issues**
   ```bash
   # Check conflict resolution logs
   kubectl logs -l app=conflict-resolution -f
   
   # View conflict audit trail
   kubectl exec -it postgres-primary-0 -- psql -c "SELECT * FROM conflict_audit ORDER BY timestamp DESC LIMIT 10;"
   ```

### Recovery Procedures

1. **Split-Brain Resolution**
   ```bash
   # Stop services in one region
   kubectl scale deployment --replicas=0 -l app.kubernetes.io/component=microservice --context=us-west-2
   
   # Resync data
   kubectl create job --from=cronjob/data-sync-job manual-sync-$(date +%s)
   
   # Restart services
   kubectl scale deployment --replicas=3 -l app.kubernetes.io/component=microservice --context=us-west-2
   ```

2. **Data Corruption Recovery**
   ```bash
   # Restore from backup
   kubectl create job restore-job --image=postgres:16-alpine -- \
     pg_restore -h postgres-primary-service -U postgres -d eagle_db /backups/latest.dump
   ```

## Security Considerations

- All cross-region communication is encrypted
- Database replication uses SSL/TLS
- Redis authentication is enabled
- Network policies restrict cross-region access
- Secrets are managed via Kubernetes secrets and Vault

## Performance Optimization

- Connection pooling for database connections
- Redis pipelining for bulk operations
- Compression for cross-region data transfer
- CDN for static assets
- Regional load balancing

## Backup and Recovery

- Automated database backups every 15 minutes
- Cross-region backup replication
- Point-in-time recovery capability
- Backup retention: 30 days
- Backup encryption at rest and in transit

## Compliance

- SOC 2 Type II compliance
- GDPR data residency requirements
- Audit trail for all data changes
- Encryption at rest and in transit
- Access logging and monitoring

## Support

For issues and questions:
- Create an issue in the project repository
- Contact the DevOps team via Slack
- Emergency escalation via PagerDuty

## License

This project is licensed under the MIT License - see the LICENSE file for details.