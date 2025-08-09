#!/bin/bash

# Graphiti Deployment Script for Render
# This script automates the deployment of Graphiti on Render platform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RENDER_API_URL="https://api.render.com/v1"
PROJECT_NAME="graphiti-knowledge-graph"
REGION="oregon"  # or "frankfurt", "singapore"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if required environment variables are set
    if [ -z "$RENDER_API_KEY" ]; then
        print_error "RENDER_API_KEY environment variable is not set"
        print_status "Please set your Render API key: export RENDER_API_KEY=your_api_key"
        exit 1
    fi
    
    if [ -z "$OPENAI_API_KEY" ]; then
        print_error "OPENAI_API_KEY environment variable is not set"
        print_status "Please set your OpenAI API key: export OPENAI_API_KEY=your_api_key"
        exit 1
    fi
    
    # Check if required tools are installed
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. JSON responses will not be formatted."
    fi
    
    print_success "Prerequisites check completed"
}

# Function to create Neo4j database service
create_neo4j_service() {
    print_status "Creating Neo4j database service..."
    
    local neo4j_payload=$(cat <<EOF
{
  "type": "web_service",
  "name": "${PROJECT_NAME}-neo4j",
  "repo": "https://github.com/neo4j/docker-neo4j",
  "branch": "master",
  "buildCommand": "",
  "startCommand": "",
  "envVars": [
    {
      "key": "NEO4J_AUTH",
      "value": "neo4j/$(openssl rand -base64 32 | tr -d '=' | head -c 20)"
    },
    {
      "key": "NEO4J_PLUGINS",
      "value": "[\"apoc\"]"
    },
    {
      "key": "NEO4J_dbms_memory_heap_initial__size",
      "value": "512m"
    },
    {
      "key": "NEO4J_dbms_memory_heap_max__size",
      "value": "2g"
    },
    {
      "key": "NEO4J_dbms_memory_pagecache_size",
      "value": "1g"
    }
  ],
  "disk": {
    "name": "${PROJECT_NAME}-neo4j-data",
    "sizeGB": 20,
    "mountPath": "/data"
  },
  "region": "${REGION}",
  "plan": "starter"
}
EOF
    )
    
    local response=$(curl -s -X POST \
        -H "Authorization: Bearer $RENDER_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$neo4j_payload" \
        "$RENDER_API_URL/services")
    
    if command -v jq &> /dev/null; then
        echo "$response" | jq '.'
    else
        echo "$response"
    fi
    
    # Extract service ID for later use
    if command -v jq &> /dev/null; then
        NEO4J_SERVICE_ID=$(echo "$response" | jq -r '.service.id')
        print_success "Neo4j service created with ID: $NEO4J_SERVICE_ID"
    else
        print_success "Neo4j service creation request sent"
    fi
}

# Function to create Graphiti application service
create_graphiti_service() {
    print_status "Creating Graphiti application service..."
    
    local graphiti_payload=$(cat <<EOF
{
  "type": "web_service",
  "name": "${PROJECT_NAME}-app",
  "repo": "$(git config --get remote.origin.url)",
  "branch": "main",
  "buildCommand": "pip install -r requirements.txt",
  "startCommand": "python -m uvicorn main:app --host 0.0.0.0 --port \$PORT",
  "envVars": [
    {
      "key": "PORT",
      "value": "8000"
    },
    {
      "key": "ENVIRONMENT",
      "value": "production"
    },
    {
      "key": "LOG_LEVEL",
      "value": "info"
    },
    {
      "key": "NEO4J_URI",
      "value": "bolt://\${NEO4J_INTERNAL_URL}:7687"
    },
    {
      "key": "NEO4J_USER",
      "value": "neo4j"
    },
    {
      "key": "NEO4J_PASSWORD",
      "value": "\${NEO4J_PASSWORD}"
    },
    {
      "key": "NEO4J_DATABASE",
      "value": "neo4j"
    },
    {
      "key": "OPENAI_API_KEY",
      "value": "${OPENAI_API_KEY}"
    },
    {
      "key": "ANTHROPIC_API_KEY",
      "value": "${ANTHROPIC_API_KEY:-}"
    },
    {
      "key": "GOOGLE_API_KEY",
      "value": "${GOOGLE_API_KEY:-}"
    },
    {
      "key": "GROQ_API_KEY",
      "value": "${GROQ_API_KEY:-}"
    },
    {
      "key": "GRAPHITI_SEMAPHORE_LIMIT",
      "value": "10"
    },
    {
      "key": "CORS_ORIGINS",
      "value": "*"
    },
    {
      "key": "ENABLE_METRICS",
      "value": "true"
    }
  ],
  "region": "${REGION}",
  "plan": "starter",
  "healthCheckPath": "/health"
}
EOF
    )
    
    local response=$(curl -s -X POST \
        -H "Authorization: Bearer $RENDER_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$graphiti_payload" \
        "$RENDER_API_URL/services")
    
    if command -v jq &> /dev/null; then
        echo "$response" | jq '.'
        GRAPHITI_SERVICE_ID=$(echo "$response" | jq -r '.service.id')
        GRAPHITI_SERVICE_URL=$(echo "$response" | jq -r '.service.serviceDetails.url')
        print_success "Graphiti service created with ID: $GRAPHITI_SERVICE_ID"
        print_success "Service URL: $GRAPHITI_SERVICE_URL"
    else
        echo "$response"
        print_success "Graphiti service creation request sent"
    fi
}

# Function to wait for deployment completion
wait_for_deployment() {
    print_status "Waiting for deployment to complete..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_status "Checking deployment status (attempt $attempt/$max_attempts)..."
        
        if [ -n "$GRAPHITI_SERVICE_ID" ]; then
            local status_response=$(curl -s -H "Authorization: Bearer $RENDER_API_KEY" \
                "$RENDER_API_URL/services/$GRAPHITI_SERVICE_ID")
            
            if command -v jq &> /dev/null; then
                local status=$(echo "$status_response" | jq -r '.service.serviceDetails.deployStatus')
                print_status "Current status: $status"
                
                if [ "$status" = "live" ]; then
                    print_success "Deployment completed successfully!"
                    return 0
                elif [ "$status" = "build_failed" ] || [ "$status" = "deploy_failed" ]; then
                    print_error "Deployment failed with status: $status"
                    return 1
                fi
            fi
        fi
        
        sleep 30
        ((attempt++))
    done
    
    print_warning "Deployment status check timed out"
    return 1
}

# Function to run post-deployment tests
run_tests() {
    print_status "Running post-deployment tests..."
    
    if [ -n "$GRAPHITI_SERVICE_URL" ]; then
        # Test health endpoint
        print_status "Testing health endpoint..."
        local health_response=$(curl -s "$GRAPHITI_SERVICE_URL/health")
        
        if command -v jq &> /dev/null; then
            local health_status=$(echo "$health_response" | jq -r '.status')
            if [ "$health_status" = "healthy" ]; then
                print_success "Health check passed"
            else
                print_warning "Health check returned: $health_status"
            fi
        else
            print_status "Health response: $health_response"
        fi
        
        # Test API root endpoint
        print_status "Testing API root endpoint..."
        local root_response=$(curl -s "$GRAPHITI_SERVICE_URL/")
        print_status "Root response: $root_response"
        
        print_success "Basic tests completed"
    else
        print_warning "Service URL not available, skipping tests"
    fi
}

# Function to display deployment summary
show_summary() {
    print_success "=== Deployment Summary ==="
    echo ""
    print_status "Project: $PROJECT_NAME"
    print_status "Region: $REGION"
    
    if [ -n "$NEO4J_SERVICE_ID" ]; then
        print_status "Neo4j Service ID: $NEO4J_SERVICE_ID"
    fi
    
    if [ -n "$GRAPHITI_SERVICE_ID" ]; then
        print_status "Graphiti Service ID: $GRAPHITI_SERVICE_ID"
    fi
    
    if [ -n "$GRAPHITI_SERVICE_URL" ]; then
        print_status "Graphiti Service URL: $GRAPHITI_SERVICE_URL"
        print_status "API Documentation: $GRAPHITI_SERVICE_URL/docs"
        print_status "Health Check: $GRAPHITI_SERVICE_URL/health"
    fi
    
    echo ""
    print_success "Deployment completed! 🎉"
    print_status "You can now access your Graphiti knowledge graph API."
}

# Main deployment function
main() {
    print_status "Starting Graphiti deployment on Render..."
    echo ""
    
    check_prerequisites
    echo ""
    
    create_neo4j_service
    echo ""
    
    sleep 10  # Wait a bit before creating the app service
    
    create_graphiti_service
    echo ""
    
    wait_for_deployment
    echo ""
    
    run_tests
    echo ""
    
    show_summary
}

# Run main function
main "$@"

