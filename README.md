# Graphiti Self-Hosted Deployment

This repository contains everything needed to deploy Graphiti, the temporal knowledge graph framework, on cloud platforms like Render and Railway.

## 🚀 Quick Start

### Prerequisites

1. **API Keys Required:**
   - OpenAI API key (required)
   - Anthropic API key (optional)
   - Google Gemini API key (optional)
   - Groq API key (optional)

2. **Platform Account:**
   - Render account (recommended) OR Railway account
   - Git repository for your deployment code

3. **Local Development (optional):**
   - Docker and Docker Compose
   - Python 3.11+
   - Git

## 📋 Deployment Options

### Option 1: Render Deployment (Recommended)

Render provides the best production-ready features for Graphiti deployment.

#### Automated Deployment

1. **Clone this repository:**
   ```bash
   git clone <your-repo-url>
   cd graphiti-deployment
   ```

2. **Set environment variables:**
   ```bash
   export RENDER_API_KEY="your_render_api_key"
   export OPENAI_API_KEY="your_openai_api_key"
   export ANTHROPIC_API_KEY="your_anthropic_api_key"  # optional
   export GOOGLE_API_KEY="your_google_api_key"        # optional
   export GROQ_API_KEY="your_groq_api_key"            # optional
   ```

3. **Run deployment script:**
   ```bash
   chmod +x scripts/deploy-render.sh
   ./scripts/deploy-render.sh
   ```

#### Manual Deployment

1. **Create Neo4j Service:**
   - Go to Render Dashboard
   - Click "New" → "Web Service"
   - Select "Deploy an existing image"
   - Use image: `neo4j:5.26-community`
   - Add persistent disk (20GB recommended)
   - Set environment variables:
     ```
     NEO4J_AUTH=neo4j/your_secure_password
     NEO4J_PLUGINS=["apoc"]
     NEO4J_dbms_memory_heap_initial__size=512m
     NEO4J_dbms_memory_heap_max__size=2g
     NEO4J_dbms_memory_pagecache_size=1g
     ```

2. **Create Graphiti Service:**
   - Click "New" → "Web Service"
   - Connect your Git repository
   - Set build command: `pip install -r requirements.txt`
   - Set start command: `python -m uvicorn main:app --host 0.0.0.0 --port $PORT`
   - Add environment variables from `.env.example`

### Option 2: Railway Deployment

Railway offers excellent developer experience and simpler setup.

#### Automated Deployment

1. **Install Railway CLI:**
   ```bash
   npm install -g @railway/cli
   railway login
   ```

2. **Set environment variables:**
   ```bash
   export OPENAI_API_KEY="your_openai_api_key"
   export ANTHROPIC_API_KEY="your_anthropic_api_key"  # optional
   ```

3. **Run deployment script:**
   ```bash
   chmod +x scripts/deploy-railway.sh
   ./scripts/deploy-railway.sh
   ```

#### Manual Deployment

1. **Create new project:**
   ```bash
   railway project new graphiti-knowledge-graph
   ```

2. **Add Neo4j service:**
   ```bash
   railway add --template neo4j
   ```

3. **Deploy Graphiti:**
   ```bash
   railway link
   railway up
   ```

## 🔧 Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
# Required
OPENAI_API_KEY=your_openai_api_key
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=your_password

# Optional
ANTHROPIC_API_KEY=your_anthropic_key
GOOGLE_API_KEY=your_google_key
GROQ_API_KEY=your_groq_key
```

### Database Configuration

Neo4j memory settings for different deployment sizes:

- **Small (< 1M nodes):** 512MB heap, 1GB page cache
- **Medium (1M-10M nodes):** 2GB heap, 4GB page cache  
- **Large (> 10M nodes):** 4GB heap, 8GB page cache

## 🧪 Local Development

### Using Docker Compose

1. **Start services:**
   ```bash
   cp .env.example .env
   # Edit .env with your API keys
   docker-compose up -d
   ```

2. **Access services:**
   - Graphiti API: http://localhost:8000
   - Neo4j Browser: http://localhost:7474
   - API Documentation: http://localhost:8000/docs

3. **View logs:**
   ```bash
   docker-compose logs -f graphiti
   ```

### Manual Setup

1. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

2. **Start Neo4j:**
   ```bash
   docker run -p 7474:7474 -p 7687:7687 \
     -e NEO4J_AUTH=neo4j/password \
     neo4j:5.26-community
   ```

3. **Start Graphiti:**
   ```bash
   export NEO4J_URI=bolt://localhost:7687
   export NEO4J_USER=neo4j
   export NEO4J_PASSWORD=password
   export OPENAI_API_KEY=your_key
   python main.py
   ```

## 📊 API Usage

### Health Check
```bash
curl https://your-app.onrender.com/health
```

### Create Knowledge Graph
```bash
curl -X POST https://your-app.onrender.com/graphs \
  -H "Content-Type: application/json" \
  -d '{"name": "My Graph", "description": "Test graph"}'
```

### Add Data
```bash
curl -X POST https://your-app.onrender.com/graphs/graph_001/data \
  -H "Content-Type: application/json" \
  -d '{"text": "John works at Acme Corp as a software engineer."}'
```

### Query Graph
```bash
curl -X POST https://your-app.onrender.com/graphs/graph_001/query \
  -H "Content-Type: application/json" \
  -d '{"query": "Who works at Acme Corp?", "limit": 10}'
```

## 📈 Monitoring

### Built-in Metrics

Access metrics at `/metrics` endpoint for Prometheus scraping.

### Health Monitoring

The `/health` endpoint provides:
- Service status
- Database connectivity
- LLM provider status
- Version information

### Logging

Structured JSON logs include:
- Request/response details
- Performance metrics
- Error tracking
- Database operations

## 🔒 Security

### Production Security Checklist

- [ ] Use strong, unique passwords for Neo4j
- [ ] Rotate API keys regularly
- [ ] Enable HTTPS (automatic on Render/Railway)
- [ ] Configure CORS origins appropriately
- [ ] Set up monitoring and alerting
- [ ] Regular security updates
- [ ] Backup database regularly

### Environment Security

- Store sensitive data in environment variables
- Never commit API keys to version control
- Use platform-provided secret management
- Enable audit logging where available

## 🔄 Maintenance

### Updates

1. **Update dependencies:**
   ```bash
   pip install --upgrade graphiti-core
   ```

2. **Deploy updates:**
   - Render: Push to Git repository
   - Railway: `railway up`

### Backups

1. **Neo4j backup:**
   ```bash
   # Render: Use persistent disk snapshots
   # Railway: Use volume snapshots
   ```

2. **Configuration backup:**
   - Export environment variables
   - Save deployment configurations

### Scaling

1. **Vertical scaling:**
   - Increase instance size on platform
   - Adjust Neo4j memory settings

2. **Horizontal scaling:**
   - Add read replicas for Neo4j
   - Load balance multiple Graphiti instances

## 🐛 Troubleshooting

### Common Issues

1. **Database connection failed:**
   - Check Neo4j service status
   - Verify connection credentials
   - Ensure network connectivity

2. **LLM API errors:**
   - Verify API keys are correct
   - Check rate limits and quotas
   - Monitor API provider status

3. **Memory issues:**
   - Increase instance memory
   - Optimize Neo4j memory settings
   - Monitor memory usage

### Debug Commands

```bash
# Check service status
curl https://your-app.onrender.com/health

# View logs (Railway)
railway logs

# Check Neo4j connectivity
docker exec -it neo4j cypher-shell -u neo4j -p password
```

## 📚 Additional Resources

- [Graphiti Documentation](https://help.getzep.com/graphiti/)
- [Neo4j Operations Manual](https://neo4j.com/docs/operations-manual/)
- [Render Documentation](https://render.com/docs)
- [Railway Documentation](https://docs.railway.com/)

## 🤝 Support

For issues and questions:

1. Check the troubleshooting section
2. Review platform documentation
3. Check Graphiti GitHub issues
4. Contact platform support if needed

## 📄 License

This deployment configuration is provided under the MIT License. See LICENSE file for details.

---

**Note:** This deployment setup is designed for production use but should be customized based on your specific requirements, security policies, and compliance needs.

