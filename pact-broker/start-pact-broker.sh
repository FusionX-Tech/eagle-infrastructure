#!/bin/bash

# Pact Broker Startup Script
# This script starts the Pact Broker infrastructure for Eagle

set -e

echo "🚀 Starting Pact Broker Infrastructure..."
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Check if eagle-network exists, create if not
if ! docker network inspect eagle-network > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Eagle network not found. Creating...${NC}"
    docker network create eagle-network
    echo -e "${GREEN}✅ Eagle network created${NC}"
else
    echo -e "${GREEN}✅ Eagle network exists${NC}"
fi

# Load environment variables
if [ -f "../.env" ]; then
    echo -e "${GREEN}✅ Loading environment variables from .env${NC}"
    export $(cat ../.env | grep -v '^#' | xargs)
else
    echo -e "${YELLOW}⚠️  .env file not found. Using default values.${NC}"
fi

# Start services
echo ""
echo "📦 Starting Pact Broker services..."
docker-compose up -d

# Wait for PostgreSQL to be healthy
echo ""
echo "⏳ Waiting for PostgreSQL to be healthy..."
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if docker exec postgres-pact pg_isready -U fusionx > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PostgreSQL is healthy${NC}"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    echo -n "."
done

if [ $elapsed -ge $timeout ]; then
    echo -e "${RED}❌ PostgreSQL failed to start within ${timeout} seconds${NC}"
    echo "Check logs: docker-compose logs postgres-pact"
    exit 1
fi

# Wait for Pact Broker to be healthy
echo ""
echo "⏳ Waiting for Pact Broker to be healthy..."
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if curl -s http://localhost:19292/diagnostic/status/heartbeat | grep -q '"ok":true'; then
        echo -e "${GREEN}✅ Pact Broker is healthy${NC}"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    echo -n "."
done

if [ $elapsed -ge $timeout ]; then
    echo -e "${RED}❌ Pact Broker failed to start within ${timeout} seconds${NC}"
    echo "Check logs: docker-compose logs pact-broker"
    exit 1
fi

# Display status
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Pact Broker Infrastructure Started Successfully!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Services Status:"
docker-compose ps
echo ""
echo "🌐 Access Points:"
echo "  • Pact Broker UI:  http://localhost:19292"
echo "  • PostgreSQL:      localhost:5436"
echo ""
echo "🔐 Credentials:"
echo "  • Username:        pact_user"
echo "  • Password:        (check .env file)"
echo ""
echo "📚 Quick Commands:"
echo "  • View logs:       docker-compose logs -f"
echo "  • Stop services:   docker-compose down"
echo "  • Restart:         docker-compose restart"
echo "  • Health check:    curl http://localhost:19292/diagnostic/status/heartbeat"
echo ""
echo "📖 Documentation:  ./README.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
