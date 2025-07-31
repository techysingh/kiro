# Backend Service Examples

This directory contains example configurations for integrating backend services with the HAProxy wildcard SSL proxy.

## Quick Start

1. **Ensure HAProxy stack is running**:
   ```bash
   cd demo.colakdo.com
   ./scripts/deploy.sh
   ```

2. **Start example services**:
   ```bash
   cd examples
   docker-compose -f example-backend-service.yml up -d
   ```

3. **Test the services**:
   ```bash
   # Test WWW service
   curl -k https://www.colakdo.com
   
   # Test API service
   curl -k https://api.colakdo.com/api/health
   
   # Test App service
   curl -k https://app.colakdo.com
   
   # Test Admin service
   curl -k https://admin.colakdo.com
   
   # Test Demo service (load balanced)
   curl -k https://demo.colakdo.com
   ```

## Service Examples

### 1. WWW Service (www.colakdo.com)
- **Purpose**: Main website
- **Port**: 80
- **Health Check**: `/health`
- **Features**: Static HTML content

### 2. API Service (api.colakdo.com)
- **Purpose**: REST API endpoints
- **Port**: 8080
- **Health Check**: `/api/health`
- **Features**: JSON responses, API routing

### 3. App Service (app.colakdo.com)
- **Purpose**: Web application
- **Port**: 3000
- **Health Check**: `/app/health`
- **Features**: HTML application interface

### 4. Admin Service (admin.colakdo.com)
- **Purpose**: Administrative interface
- **Port**: 8443 (HTTPS)
- **Health Check**: `/admin/health`
- **Features**: SSL-enabled, self-signed certificate

### 5. Demo Service (demo.colakdo.com)
- **Purpose**: Load balancing demonstration
- **Instances**: 2 (demo-service-1, demo-service-2)
- **Port**: 80
- **Health Check**: `/demo/health`
- **Features**: Multiple instances for load balancing

## Integration Patterns

### Basic Service Integration

```yaml
services:
  your-service:
    image: your-app:latest
    container_name: your-service-1
    restart: unless-stopped
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=your-service
      - SERVICE_TYPE=app
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

networks:
  proxy-network:
    external: true
```

### Service with Environment Variables

```yaml
services:
  api-service:
    image: your-api:latest
    networks:
      - proxy-network
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/mydb
      - REDIS_URL=redis://redis:6379
      - API_KEY=${API_KEY}
      - DEBUG=${DEBUG:-false}
```

### Service with Volumes

```yaml
services:
  app-service:
    image: your-app:latest
    networks:
      - proxy-network
    volumes:
      - ./app-data:/app/data
      - ./app-config:/app/config:ro
      - app-logs:/app/logs
    
volumes:
  app-logs:
    driver: local
```

### Service with Dependencies

```yaml
services:
  web-service:
    image: your-web:latest
    networks:
      - proxy-network
    depends_on:
      - database
      - redis
    
  database:
    image: postgres:13
    networks:
      - proxy-network
    environment:
      - POSTGRES_DB=myapp
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=password
    volumes:
      - db-data:/var/lib/postgresql/data
  
  redis:
    image: redis:alpine
    networks:
      - proxy-network

volumes:
  db-data:
    driver: local
```

## Service Discovery

The HAProxy setup includes automatic backend discovery. Services are automatically detected and added to HAProxy configuration based on:

1. **Network Membership**: Services must be on the `proxy-network`
2. **Environment Variables**: Use `SERVICE_NAME` and `SERVICE_TYPE` for identification
3. **Health Checks**: Services should implement health check endpoints

### Automatic Discovery Labels

Add these environment variables to enable automatic discovery:

```yaml
environment:
  - SERVICE_NAME=my-service        # Service identifier
  - SERVICE_TYPE=api              # Service type (api, app, www, admin)
  - SERVICE_PORT=8080             # Service port (optional, defaults to 80)
  - SERVICE_HEALTH_PATH=/health   # Health check path (optional)
  - SERVICE_SUBDOMAIN=my-service  # Custom subdomain (optional)
```

## Health Check Patterns

### Simple Health Check
```bash
# Return 200 OK with plain text
location /health {
    return 200 'healthy';
    add_header Content-Type text/plain;
}
```

### JSON Health Check
```bash
# Return JSON status
location /health {
    return 200 '{"status":"ok","timestamp":"$(date -Iseconds)"}';
    add_header Content-Type application/json;
}
```

### Detailed Health Check
```bash
# Check dependencies and return detailed status
location /health {
    # Add your health check logic here
    # Check database connectivity, external services, etc.
    return 200 'all_systems_operational';
}
```

## Load Balancing

For services that need multiple instances:

```yaml
services:
  app-service-1:
    image: your-app:latest
    container_name: app-service-1
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=app-service
      - INSTANCE_ID=1
  
  app-service-2:
    image: your-app:latest
    container_name: app-service-2
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=app-service
      - INSTANCE_ID=2
  
  app-service-3:
    image: your-app:latest
    container_name: app-service-3
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=app-service
      - INSTANCE_ID=3
```

## SSL/TLS Considerations

### Backend SSL
If your backend service uses SSL:

```yaml
services:
  secure-service:
    image: your-secure-app:latest
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=secure-service
      - SERVICE_PORT=8443
      - SERVICE_PROTOCOL=https
```

### SSL Passthrough
For services that need end-to-end SSL:

```yaml
environment:
  - SERVICE_SSL_PASSTHROUGH=true
```

## Monitoring Integration

### Prometheus Metrics
```yaml
services:
  monitored-service:
    image: your-app:latest
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=monitored-service
      - METRICS_ENABLED=true
      - METRICS_PORT=9090
      - METRICS_PATH=/metrics
```

### Custom Monitoring
```yaml
services:
  custom-service:
    image: your-app:latest
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=custom-service
      - MONITORING_ENDPOINT=/status
      - MONITORING_FORMAT=json
```

## Troubleshooting

### Service Not Accessible
1. Check if service is on proxy-network:
   ```bash
   docker network inspect proxy-network
   ```

2. Verify service health:
   ```bash
   docker-compose ps
   ```

3. Check HAProxy backend status:
   ```bash
   curl http://localhost:8404/stats
   ```

### Service Discovery Issues
1. Check backend discovery logs:
   ```bash
   docker-compose logs backend-discovery
   ```

2. Verify environment variables:
   ```bash
   docker inspect <container-name> | grep -A 10 Env
   ```

3. Test service health endpoint:
   ```bash
   docker exec <container-name> curl http://localhost:8080/health
   ```

### Performance Issues
1. Monitor HAProxy stats:
   ```bash
   curl http://localhost:8404/stats
   ```

2. Check service resource usage:
   ```bash
   docker stats
   ```

3. Review service logs:
   ```bash
   docker-compose logs <service-name>
   ```

## Best Practices

1. **Always implement health checks** - Essential for load balancing and monitoring
2. **Use meaningful service names** - Helps with debugging and monitoring
3. **Set resource limits** - Prevents services from consuming all system resources
4. **Implement graceful shutdown** - Handle SIGTERM signals properly
5. **Use structured logging** - Makes debugging easier
6. **Monitor service metrics** - Track performance and errors
7. **Test service isolation** - Ensure services work independently
8. **Document service APIs** - Include endpoint documentation
9. **Version your services** - Use specific image tags, not 'latest'
10. **Secure sensitive data** - Use Docker secrets or environment files

## Advanced Patterns

### Blue-Green Deployment
```yaml
# Blue version
services:
  app-blue:
    image: your-app:v1.0
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=app-service
      - SERVICE_VERSION=blue

# Green version  
  app-green:
    image: your-app:v2.0
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=app-service
      - SERVICE_VERSION=green
      - SERVICE_WEIGHT=0  # Start with 0 traffic
```

### Canary Deployment
```yaml
services:
  app-stable:
    image: your-app:stable
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=app-service
      - SERVICE_WEIGHT=90  # 90% of traffic
  
  app-canary:
    image: your-app:canary
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=app-service
      - SERVICE_WEIGHT=10  # 10% of traffic
```

### Multi-Environment Support
```yaml
services:
  app-dev:
    image: your-app:dev
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=app-service
      - SERVICE_SUBDOMAIN=dev-app
      - ENVIRONMENT=development
  
  app-staging:
    image: your-app:staging
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=app-service
      - SERVICE_SUBDOMAIN=staging-app
      - ENVIRONMENT=staging
```

## Support

For issues with backend service integration:

1. Check the main HAProxy documentation
2. Review HAProxy configuration in `config/haproxy.cfg`
3. Monitor logs in `logs/` directory
4. Use the monitoring tools in `scripts/` directory
5. Test with the provided example services first