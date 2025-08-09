"""
Simplified Graphiti Deployment for Render
A minimal FastAPI application with Graphiti integration
"""

import os
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
import structlog

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
graphiti_instance = None

# Pydantic models
class HealthResponse(BaseModel):
    status: str
    message: str
    version: str
    database_connected: bool

class EpisodeRequest(BaseModel):
    content: str
    episode_type: str = "text"

class SearchRequest(BaseModel):
    query: str
    limit: int = 10

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    global graphiti_instance
    
    logger.info("Starting simplified Graphiti application")
    
    try:
        # Import Graphiti here to avoid import issues during startup
        from graphiti_core import Graphiti
        
        # Get environment variables
        neo4j_uri = os.getenv("NEO4J_URI", "bolt://localhost:7687")
        neo4j_username = os.getenv("NEO4J_USERNAME", "neo4j")
        neo4j_password = os.getenv("NEO4J_PASSWORD", "password")
        
        logger.info("Initializing Graphiti", 
                   neo4j_uri=neo4j_uri, 
                   neo4j_user=neo4j_username)
        
        # Initialize Graphiti with positional arguments
        graphiti_instance = Graphiti(neo4j_uri, neo4j_username, neo4j_password)
        
        # Initialize the graph database with graphiti's indices
        logger.info("Building indices and constraints")
        await graphiti_instance.build_indices_and_constraints()
        
        logger.info("Graphiti initialized successfully")
        
        yield
        
    except Exception as e:
        logger.error("Failed to initialize Graphiti", error=str(e), exc_info=True)
        # Don't raise here - let the app start without Graphiti for debugging
        yield
    finally:
        logger.info("Shutting down Graphiti application")

# Create FastAPI application
app = FastAPI(
    title="Graphiti Knowledge Graph API",
    description="A simplified Graphiti deployment for building and querying knowledge graphs",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/", response_model=Dict[str, str])
async def root():
    """Root endpoint"""
    return {
        "message": "Graphiti Knowledge Graph API",
        "version": "1.0.0",
        "status": "running",
        "docs": "/docs"
    }

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    global graphiti_instance
    
    database_connected = graphiti_instance is not None
    
    return HealthResponse(
        status="healthy" if database_connected else "degraded",
        message="Graphiti service is running" if database_connected else "Graphiti not initialized",
        version="1.0.0",
        database_connected=database_connected
    )

@app.post("/episodes")
async def add_episode(episode: EpisodeRequest):
    """Add an episode to the knowledge graph"""
    global graphiti_instance
    
    if not graphiti_instance:
        raise HTTPException(status_code=503, detail="Graphiti not initialized")
    
    try:
        logger.info("Adding episode", content_length=len(episode.content))
        
        # Add episode to Graphiti
        result = await graphiti_instance.add_episode(
            name=f"episode_{len(episode.content)}",
            episode_body=episode.content,
            source_description="API submission"
        )
        
        logger.info("Episode added successfully", episode_uuid=str(result))
        
        return {
            "status": "success",
            "message": "Episode added to knowledge graph",
            "episode_uuid": str(result)
        }
        
    except Exception as e:
        logger.error("Failed to add episode", error=str(e), exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to add episode: {str(e)}")

@app.post("/search")
async def search_knowledge_graph(search: SearchRequest):
    """Search the knowledge graph"""
    global graphiti_instance
    
    if not graphiti_instance:
        raise HTTPException(status_code=503, detail="Graphiti not initialized")
    
    try:
        logger.info("Searching knowledge graph", query=search.query, limit=search.limit)
        
        # Search using Graphiti
        results = await graphiti_instance.search(
            query=search.query,
            limit=search.limit
        )
        
        # Convert results to serializable format
        search_results = []
        for result in results:
            search_results.append({
                "uuid": str(result.uuid),
                "fact": result.fact,
                "score": getattr(result, 'score', 0.0)
            })
        
        logger.info("Search completed", results_count=len(search_results))
        
        return {
            "status": "success",
            "query": search.query,
            "results_count": len(search_results),
            "results": search_results
        }
        
    except Exception as e:
        logger.error("Search failed", error=str(e), exc_info=True)
        raise HTTPException(status_code=500, detail=f"Search failed: {str(e)}")

@app.get("/stats")
async def get_stats():
    """Get knowledge graph statistics"""
    global graphiti_instance
    
    if not graphiti_instance:
        raise HTTPException(status_code=503, detail="Graphiti not initialized")
    
    try:
        # This is a placeholder - implement actual stats if available in Graphiti
        return {
            "status": "success",
            "message": "Knowledge graph is operational",
            "graphiti_initialized": True
        }
        
    except Exception as e:
        logger.error("Failed to get stats", error=str(e), exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to get stats: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)

