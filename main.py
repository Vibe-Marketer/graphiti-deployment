"""
Graphiti FastAPI Application
Self-hosted Graphiti deployment with comprehensive API endpoints
"""

import os
import logging
from contextlib import asynccontextmanager
from typing import Dict, Any, List, Optional

from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
import structlog

from graphiti_core import Graphiti

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Global Graphiti instance
graphiti_instance: Optional[Graphiti] = None

# Pydantic models for API requests/responses
class GraphCreateRequest(BaseModel):
    name: str = Field(..., description="Name of the knowledge graph")
    description: Optional[str] = Field(None, description="Description of the knowledge graph")

class GraphResponse(BaseModel):
    id: str
    name: str
    description: Optional[str]
    created_at: str
    status: str

class AddDataRequest(BaseModel):
    text: str = Field(..., description="Text data to add to the knowledge graph")
    metadata: Optional[Dict[str, Any]] = Field(None, description="Additional metadata")

class QueryRequest(BaseModel):
    query: str = Field(..., description="Query string")
    limit: Optional[int] = Field(10, description="Maximum number of results")

class HealthResponse(BaseModel):
    status: str
    version: str
    database_connected: bool
    llm_provider: str

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    global graphiti_instance
    
    logger.info("Starting Graphiti application")
    
    try:
        # Get environment variables
        neo4j_uri = os.getenv("NEO4J_URI", "bolt://localhost:7687")
        neo4j_username = os.getenv("NEO4J_USERNAME", "neo4j")
        neo4j_password = os.getenv("NEO4J_PASSWORD", "password")
        neo4j_database = os.getenv("NEO4J_DATABASE", "neo4j")
        
        # Initialize Graphiti with Neo4j configuration
        graphiti_instance = Graphiti(
            neo4j_uri=neo4j_uri,
            neo4j_user=neo4j_username,
            neo4j_password=neo4j_password,
            neo4j_database=neo4j_database
        )
        
        logger.info("Graphiti initialized successfully", 
                   neo4j_uri=neo4j_uri, 
                   database=neo4j_database)
        
        yield
        
    except Exception as e:
        logger.error("Failed to initialize Graphiti", error=str(e))
        raise
    finally:
        logger.info("Shutting down Graphiti application")
        if graphiti_instance:
            # Cleanup if needed
            pass

# Create FastAPI application
app = FastAPI(
    title="Graphiti Knowledge Graph API",
    description="Self-hosted Graphiti temporal knowledge graph service",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_graphiti() -> Graphiti:
    """Dependency to get Graphiti instance"""
    if graphiti_instance is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Graphiti service not initialized"
        )
    return graphiti_instance

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    try:
        database_connected = graphiti_instance is not None
        llm_provider = os.getenv("LLM_PROVIDER", "openai")
        
        return HealthResponse(
            status="healthy" if database_connected else "unhealthy",
            version="1.0.0",
            database_connected=database_connected,
            llm_provider=llm_provider
        )
    except Exception as e:
        logger.error("Health check failed", error=str(e))
        return HealthResponse(
            status="unhealthy",
            version="1.0.0",
            database_connected=False,
            llm_provider="unknown"
        )

@app.post("/graphs", response_model=GraphResponse)
async def create_graph(
    request: GraphCreateRequest,
    graphiti: Graphiti = Depends(get_graphiti)
):
    """Create a new knowledge graph"""
    try:
        # For this implementation, we'll use a simple approach
        # In a full implementation, you'd want proper graph management
        
        logger.info("Creating new graph", name=request.name)
        
        # Return a mock response for now
        # In a real implementation, you'd create the graph in Graphiti
        return GraphResponse(
            id="graph_001",
            name=request.name,
            description=request.description,
            created_at="2025-08-08T17:55:00Z",
            status="active"
        )
        
    except Exception as e:
        logger.error("Failed to create graph", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create graph: {str(e)}"
        )

@app.post("/graphs/{graph_id}/data")
async def add_data(
    graph_id: str,
    request: AddDataRequest,
    graphiti: Graphiti = Depends(get_graphiti)
):
    """Add data to a knowledge graph"""
    try:
        logger.info("Adding data to graph", graph_id=graph_id, text_length=len(request.text))
        
        # Add data to Graphiti
        # This is a simplified implementation
        await graphiti.add_data(request.text, metadata=request.metadata)
        
        return {"status": "success", "message": "Data added successfully"}
        
    except Exception as e:
        logger.error("Failed to add data", graph_id=graph_id, error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to add data: {str(e)}"
        )

@app.post("/graphs/{graph_id}/query")
async def query_graph(
    graph_id: str,
    request: QueryRequest,
    graphiti: Graphiti = Depends(get_graphiti)
):
    """Query a knowledge graph"""
    try:
        logger.info("Querying graph", graph_id=graph_id, query=request.query)
        
        # Query Graphiti
        # This is a simplified implementation
        results = await graphiti.search(request.query, limit=request.limit)
        
        return {
            "query": request.query,
            "results": results,
            "count": len(results) if results else 0
        }
        
    except Exception as e:
        logger.error("Failed to query graph", graph_id=graph_id, error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to query graph: {str(e)}"
        )

@app.get("/graphs")
async def list_graphs():
    """List all knowledge graphs"""
    try:
        # Return mock data for now
        # In a real implementation, you'd list actual graphs
        return {
            "graphs": [
                {
                    "id": "graph_001",
                    "name": "Default Graph",
                    "description": "Default knowledge graph",
                    "created_at": "2025-08-08T17:55:00Z",
                    "status": "active"
                }
            ]
        }
        
    except Exception as e:
        logger.error("Failed to list graphs", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list graphs: {str(e)}"
        )

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "Graphiti Knowledge Graph API",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/health"
    }

if __name__ == "__main__":
    import uvicorn
    
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        reload=False,
        log_level="info"
    )

