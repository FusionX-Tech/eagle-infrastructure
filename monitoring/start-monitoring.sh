#!/bin/bash

# Eagle Alert System - Monitoring Stack Startup Script
# This script starts the complete monitoring and observability stack

set -e

echo "🚀 Starting Eagle Alert System Monitoring Stack..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose is not installed. Please install docker-compose first."
    exit 1
fi

# Set environment variables if not already set
export GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
export GRAFANA_SECRET_KEY=${GRAFANA_SECRET_KEY:-$(openssl rand -base64 32)}
export GRAFANA_DB_PASSWORD=${GRAFANA_DB_PASSWORD:-grafana123}
export SMTP_PASSWORD=${SMTP_PASSWORD:-}
export SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-}
export SLACK_SECURITY_WEBHOOK_URL=${SLACK_SECURITY_WEBHOOK_URL:-}
export SLACK_DEV_WEBHOOK_URL=${SLACK_DEV_WEBHOOK_URL:-}
export PAGERDUTY_INTEGRATION_KEY=${PAGERDUTY_INTEGRATION_KEY:-}
export PAGERDUTY_SECURITY_KEY=${PAGERDUTY_SECURITY_KEY:-}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

echo "📋 Environment Configuration:"
echo "  - Grafana Admin Password: ${GRAFANA_ADMIN_PASSWORD}"
echo "  - AWS Region: ${AWS_DEFAULT_REGION}"
echo "  - Slack Webhook: ${SLACK_WEBHOOK_URL:+configured}"
echo "  - PagerDuty: ${PAGERDUTY_INTEGRATION_KEY:+configured}"

# Create necessary directories
echo "📁 Creating necessary directories..."
mkdir -p ./grafana/dashboards/{system,business,infrastructure,tracing}
mkdir -p ./prometheus/rules
mkdir -p ./data/{prometheus,grafana,alertmanager,elasticsearch,loki}

# Set proper permissions
echo "🔐 Setting permissions..."
sudo chown -R 472:472 ./data/grafana 2>/dev/null || true
sudo chown -R 65534:65534 ./data/prometheus 2>/dev/null || true
sudo chown -R 1000:1000 ./data/alertmanager 2>/dev/null || true
sudo chown -R 1000:1000 ./data/loki 2>/dev/null || true

# Start the monitoring stack
echo "🐳 Starting monitoring containers..."
docker-compose -f docker-compose.monitoring.yml up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Check service health
echo "🏥 Checking service health..."

services=(
    "prometheus:9090"
    "grafana:3000"
    "jaeger:16686"
    "loki:3100"
    "alertmanager:9093"
)

for service in "${services[@]}"; do
    name=$(echo $service | cut -d: -f1)
    port=$(echo $service | cut -d: -f2)
    
    if curl -s -f "http://localhost:$port" > /dev/null; then
        echo "  ✅ $name is healthy"
    else
        echo "  ⚠️  $name might not be ready yet"
    fi
done

echo ""
echo "🎉 Monitoring stack started successfully!"
echo ""
echo "📊 Access URLs:"
echo "  - Grafana:     http://localhost:3000 (admin/${GRAFANA_ADMIN_PASSWORD})"
echo "  - Prometheus:  http://localhost:9090"
echo "  - Jaeger:      http://localhost:16686"
echo "  - Alertmanager: http://localhost:9093"
echo "  - Loki:        http://localhost:3100"
echo ""
echo "📈 Available Dashboards:"
echo "  - Eagle System Overview"
echo "  - Eagle Business Metrics"
echo "  - Eagle Infrastructure Monitoring"
echo "  - Eagle Distributed Tracing"
echo ""
echo "🔔 Alerting:"
echo "  - Prometheus rules: ./prometheus/rules/eagle-alerts.yml"
echo "  - Alertmanager config: ./alertmanager.yml"
echo ""
echo "📝 Logs:"
echo "  - View container logs: docker-compose -f docker-compose.monitoring.yml logs -f [service]"
echo "  - View all logs: docker-compose -f docker-compose.monitoring.yml logs -f"
echo ""
echo "🛑 To stop the stack: docker-compose -f docker-compose.monitoring.yml down"
echo "🗑️  To remove all data: docker-compose -f docker-compose.monitoring.yml down -v"