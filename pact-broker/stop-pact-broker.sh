#!/bin/bash

# Pact Broker Stop Script
# This script stops the Pact Broker infrastructure

set -e

echo "🛑 Stopping Pact Broker Infrastructure..."
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Stop services
docker-compose down

echo ""
echo -e "${GREEN}✅ Pact Broker Infrastructure Stopped${NC}"
echo ""
echo "To remove volumes (delete all data), run:"
echo "  docker-compose down -v"
