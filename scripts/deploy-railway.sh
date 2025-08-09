#!/bin/bash

# Graphiti Deployment Script for Railway
# This script automates the deployment of Graphiti on Railway platform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="graphiti-knowledge-graph"
RAILWAY_API_URL="https://backboard.railway.app/graphql"

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
    
    # Check if Railway CLI is installed
    if ! command -v railway &> /dev/null; then
        print_error "Railway CLI is not installed"
        print_status "Please install Railway CLI: npm install -g @railway/cli"
        print_status "Or visit: https://docs.railway.com/develop/cli"
        exit 1
    fi
    
    # Check if user is logged in to Railway
    if ! railway whoami &> /dev/null; then
        print_error "Not logged in to Railway"
        print_status "Please login: railway login"
        exit 1
    fi
    
    # Check if required environment variables are set
    if [ -z "$OPENAI_API_KEY" ]; then
        print_error "OPENAI_API_KEY environment variable is not set"
        print_status "Please set your OpenAI API key: export OPENAI_API_KEY=your_api_key"
        exit 1
    fi
    
    # Check if git repository is initialized
    if ! git rev-parse --git-dir &> /dev/null; then
        print_error "Not in a git repository"
        print_status "Please initialize git repository: git init"
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Function to create Railway project
create_project() {
    print_status "Creating Railway project..."
    
    # Create new project
    railway project new "$PROJECT_NAME" --name "$PROJECT_NAME"
    
    if [ $? -eq 0 ]; then
        print_success "Railway project created: $PROJECT_NAME"
    else
        print_error "Failed to create Railway project"
        exit 1
    fi
}

# Function to deploy Neo4j database
deploy_neo4j() {
    print_status "Deploying Neo4j database..."
    
    # Add Neo4j service from template
    railway add --template neo4j
    
    if [ $? -eq 0 ]; then
        print_success "Neo4j service added to project"
        
        # Set Neo4j environment variables
        railway variables set NEO4J_AUTH="neo4j/$(openssl rand -base64 32 | tr -d '=' | head -c 20)"
        railway variables set NEO4J_PLUGINS='["apoc"]'
        railway variables set NEO4J_dbms_memory_heap_initial__size=512m
        railway variables set NEO4J_dbms_memory_heap_max__size=2g
        railway variables set NEO4J_dbms_memory_pagecache_size=1g
        
        print_success "Neo4j environment variables configured"
    else
        print_error "Failed to add Neo4j service"
        exit 1
    fi
}

# Function to deploy Graphiti application
deploy_graphiti() {
    print_status "Deploying Graphiti application..."
    
    # Link current directory to Railway project
    railway link
    
    # Set environment variables for Graphiti
    print_status "Setting environment variables..."
    
    railway variables set PORT=8000
    railway variables set ENVIRONMENT=production
    railway variables set LOG_LEVEL=info
    railway variables set NEO4J_USER=neo4j
    railway variables set NEO4J_DATABASE=neo4j
    railway variables set OPENAI_API_KEY="$OPENAI_API_KEY"
    railway variables set GRAPHITI_SEMAPHORE_LIMIT=10
    railway variables set CORS_ORIGINS="*"
    railway variables set ENABLE_METRICS=true
    
    # Set optional API keys if available
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        railway variables set ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
    fi
    
    if [ -n "$GOOGLE_API_KEY" ]; then
        railway variables set GOOGLE_API_KEY="$GOOGLE_API_KEY"
    fi
    
    if [ -n "$GROQ_API_KEY" ]; then
        railway variables set GROQ_API_KEY="$GROQ_API_KEY"
    fi
    
    print_success "Environment variables configured"
    
    # Deploy the application
    print_status "Deploying application..."
    railway up --detach
    
    if [ $? -eq 0 ]; then
        print_success "Graphiti application deployed"
    else
        print_error "Failed to deploy Graphiti application"
        exit 1
    fi
}

# Function to configure networking
configure_networking() {
    print_status "Configuring service networking..."
    
    # Get Neo4j connection details
    local neo4j_url=$(railway variables get NEO4J_URL 2>/dev/null || echo "")
    local neo4j_password=$(railway variables get NEO4J_PASSWORD 2>/dev/null || echo "")
    
    if [ -n "$neo4j_url" ]; then
        railway variables set NEO4J_URI="$neo4j_url"
        print_success "Neo4j URI configured: $neo4j_url"
    fi
    
    if [ -n "$neo4j_password" ]; then
        railway variables set NEO4J_PASSWORD="$neo4j_password"
        print_success "Neo4j password configured"
    fi
}

# Function to wait for deployment
wait_for_deployment() {
    print_status "Waiting for deployment to complete..."
    
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_status "Checking deployment status (attempt $attempt/$max_attempts)..."
        
        # Check if service is running
        local status=$(railway status 2>/dev/null | grep -i "status" | head -1 || echo "")
        
        if echo "$status" | grep -qi "success\|running\|deployed"; then
            print_success "Deployment completed successfully!"
            return 0
        elif echo "$status" | grep -qi "failed\|error"; then
            print_error "Deployment failed"
            railway logs
            return 1
        fi
        
        sleep 15
        ((attempt++))
    done
    
    print_warning "Deployment status check timed out"
    return 1
}

# Function to run post-deployment tests
run_tests() {
    print_status "Running post-deployment tests..."
    
    # Get the deployed URL
    local app_url=$(railway domain 2>/dev/null | head -1 || echo "")
    
    if [ -n "$app_url" ]; then
        print_status "Application URL: $app_url"
        
        # Test health endpoint
        print_status "Testing health endpoint..."
        local health_response=$(curl -s "$app_url/health" 2>/dev/null || echo "")
        
        if echo "$health_response" | grep -qi "healthy"; then
            print_success "Health check passed"
        else
            print_warning "Health check failed or returned unexpected response"
            print_status "Response: $health_response"
        fi
        
        # Test API root endpoint
        print_status "Testing API root endpoint..."
        local root_response=$(curl -s "$app_url/" 2>/dev/null || echo "")
        print_status "Root response: $root_response"
        
        print_success "Basic tests completed"
    else
        print_warning "Could not determine application URL, skipping tests"
    fi
}

# Function to display deployment summary
show_summary() {
    print_success "=== Deployment Summary ==="
    echo ""
    
    local project_info=$(railway status 2>/dev/null || echo "")
    local app_url=$(railway domain 2>/dev/null | head -1 || echo "")
    
    print_status "Project: $PROJECT_NAME"
    print_status "Platform: Railway"
    
    if [ -n "$app_url" ]; then
        print_status "Application URL: $app_url"
        print_status "API Documentation: $app_url/docs"
        print_status "Health Check: $app_url/health"
    fi
    
    echo ""
    print_status "Useful Railway commands:"
    print_status "  railway logs          - View application logs"
    print_status "  railway variables     - Manage environment variables"
    print_status "  railway status        - Check deployment status"
    print_status "  railway domain        - Manage custom domains"
    print_status "  railway open          - Open application in browser"
    
    echo ""
    print_success "Deployment completed! 🎉"
    print_status "You can now access your Graphiti knowledge graph API."
}

# Function to setup monitoring (optional)
setup_monitoring() {
    print_status "Setting up monitoring..."
    
    # Enable Railway's built-in monitoring
    railway variables set ENABLE_METRICS=true
    railway variables set METRICS_PORT=9090
    
    print_success "Monitoring configured"
}

# Main deployment function
main() {
    print_status "Starting Graphiti deployment on Railway..."
    echo ""
    
    check_prerequisites
    echo ""
    
    create_project
    echo ""
    
    deploy_neo4j
    echo ""
    
    deploy_graphiti
    echo ""
    
    configure_networking
    echo ""
    
    wait_for_deployment
    echo ""
    
    setup_monitoring
    echo ""
    
    run_tests
    echo ""
    
    show_summary
}

# Handle script arguments
case "${1:-}" in
    "test")
        print_status "Running tests only..."
        run_tests
        ;;
    "status")
        print_status "Checking deployment status..."
        railway status
        ;;
    "logs")
        print_status "Showing application logs..."
        railway logs
        ;;
    "cleanup")
        print_warning "This will delete the Railway project. Are you sure? (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            railway project delete
            print_success "Project deleted"
        else
            print_status "Cleanup cancelled"
        fi
        ;;
    *)
        main "$@"
        ;;
esac

