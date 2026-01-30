# ParlaeHub Architecture

Technical architecture documentation for self-hosted Discourse on AWS.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                ┌──────▼───────┐
                │  CloudFront  │ (Optional CDN)
                │  + Route53   │
                └──────┬───────┘
                       │
              ┌────────▼─────────┐
              │  Application     │
              │  Load Balancer   │ (Shared with Dentia)
              │  (ALB)           │
              └────────┬─────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
    ┌────▼────┐   ┌────▼────┐  ┌────▼────┐
    │ECS Task │   │ECS Task │  │ECS Task │ (Auto-scaling)
    │Fargate  │   │Fargate  │  │Fargate  │
    │         │   │         │  │         │
    │Discourse│   │Discourse│  │Discourse│
    │Container│   │Container│  │Container│
    └────┬────┘   └────┬────┘  └────┬────┘
         │             │             │
         └─────────────┼─────────────┘
                       │
         ┌─────────────┼─────────────┬──────────────┐
         │             │             │              │
    ┌────▼────┐   ┌────▼────┐  ┌────▼────┐   ┌─────▼────┐
    │Aurora   │   │  Redis  │  │   S3    │   │ Cognito  │
    │PostgreSQL│  │ElastiC. │  │ Uploads │   │  (SSO)   │
    │(Shared) │   │         │  │         │   │ (Shared) │
    └─────────┘   └─────────┘  └─────────┘   └──────────┘
```

## Network Architecture

### VPC Configuration

```
VPC: 10.0.0.0/16 (Shared with Dentia)

Public Subnets (ECS tasks):
├─ 10.0.1.0/24 (us-east-2a)
└─ 10.0.2.0/24 (us-east-2b)

Private Subnets (Aurora, Redis):
├─ 10.0.11.0/24 (us-east-2a)
└─ 10.0.12.0/24 (us-east-2b)
```

### Security Groups

**ALB Security Group** (dentia-alb-sg)
- Inbound: 443 from 0.0.0.0/0
- Inbound: 80 from 0.0.0.0/0 (redirects to 443)
- Outbound: All

**ECS Security Group** (dentia-ecs-sg)
- Inbound: 3000 from ALB SG
- Inbound: 4000 from ALB SG (Dentia backend)
- Outbound: All

**Aurora Security Group** (dentia-db-sg)
- Inbound: 5432 from ECS SG
- Inbound: 5432 from Bastion SG
- Outbound: All

**Redis Security Group** (parlaehub-redis-sg)
- Inbound: 6379 from ECS SG
- Outbound: All

## Compute Architecture

### ECS Fargate Configuration

**Cluster:** dentia (shared)

**Task Definition:**
```json
{
  "family": "parlaehub-production-discourse",
  "cpu": "1024",
  "memory": "2048",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "containers": [
    {
      "name": "discourse",
      "image": "ECR_URL:TAG",
      "portMappings": [{"containerPort": 3000}],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3000/srv/status || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3
      }
    }
  ]
}
```

**Service Configuration:**
- Desired count: 1 (production)
- Min healthy: 100%
- Max healthy: 200%
- Deployment: Blue/Green
- Health check grace: 60s

**Auto-scaling:**
- Min: 1 task
- Max: 8 tasks
- Scale up: CPU > 65% OR Memory > 75%
- Scale down: CPU < 40% AND Memory < 50%
- Scale out cooldown: 60s
- Scale in cooldown: 300s

## Data Layer Architecture

### Aurora PostgreSQL Serverless v2

**Cluster:** dentia-aurora-cluster (shared)

**Configuration:**
- Engine: aurora-postgresql 15.12
- Mode: Serverless v2
- Min capacity: 0.5 ACU
- Max capacity: 8 ACU
- Backup retention: 3 days
- Multi-AZ: Yes
- Encryption: At rest (AES-256)

**Database:**
- Name: discourse_production
- User: discourse_user
- Dedicated credentials

**Connection Pooling:**
- Managed by Discourse (built-in)
- Max connections: Scales with ACU

### ElastiCache Redis

**Replication Group:** parlaehub-production-redis

**Configuration:**
- Engine: redis 7.1
- Node type: cache.t4g.micro (production start)
- Replicas: 2 (primary + 1 replica)
- Multi-AZ: Yes (production)
- Automatic failover: Yes
- Encryption: At rest only (Discourse doesn't support TLS)
- Maintenance window: Sunday 5-6 AM UTC
- Snapshot window: 3-4 AM UTC
- Snapshot retention: 5 days

**Scaling:**
- Vertical only (manual)
- Can upgrade to cache.t4g.small/medium

### S3 Storage

**Uploads Bucket:** parlaehub-production-uploads

**Configuration:**
- Encryption: AES-256
- Versioning: Enabled
- Lifecycle:
  - Delete old versions after 30 days
  - Abort incomplete multiparts after 7 days
- Public access: Blocked
- CORS: Enabled for Discourse domains

**Backups Bucket:** parlaehub-production-backups

**Configuration:**
- Encryption: AES-256
- Versioning: Enabled
- Lifecycle:
  - Transition to Glacier after 30 days
  - Delete after 90 days

## Authentication Architecture

### Cognito Integration

**User Pool:** dentia-user-pool (shared)

**App Client:** parlaehub-production

**OAuth2 Flow:**

```
1. User clicks "Login with Dentia"
   ↓
2. Discourse redirects to Cognito
   GET /oauth2/authorize
   ↓
3. User authenticates (or already logged in)
   ↓
4. Cognito redirects back with code
   GET /auth/oauth2_basic/callback?code=XXX
   ↓
5. Discourse exchanges code for tokens
   POST /oauth2/token
   ↓
6. Discourse fetches user info
   GET /oauth2/userInfo
   ↓
7. User created/updated in Discourse
   ↓
8. Session created
```

**Token Configuration:**
- Access token: 60 minutes
- ID token: 60 minutes
- Refresh token: 30 days

**Scopes:** email, openid, profile

## Load Balancing Architecture

### Application Load Balancer

**ALB:** dentia-alb (shared)

**Listener:** HTTPS:443

**SSL/TLS:**
- Certificate: AWS Certificate Manager
- Domains:
  - hub.dentiaapp.com
  - hub.dentia.co
  - hub.dentia.app
  - hub.dentia.ca
- Protocol: TLSv1.2 minimum
- Cipher: AWS recommended

**Listener Rules:**

```
Priority 100: hub.* → parlaehub-discourse-tg
Priority 10-20: app.*, www.*, api.* → dentia services
```

**Target Group:** parlaehub-production-discourse-tg

**Health Check:**
- Path: /srv/status
- Interval: 30s
- Timeout: 5s
- Healthy threshold: 2
- Unhealthy threshold: 3
- Matcher: 200-399

**Stickiness:**
- Type: ALB cookie
- Duration: 24 hours

### Blue/Green Deployment

**Target Groups:**
- Blue: parlaehub-production-discourse-tg
- Green: parlaehub-production-discourse-tg-green

**Deployment Process:**

```
1. Build new image
2. Create new task definition (green)
3. Deploy to green target group
4. Health check green targets
5. Switch ALB listener to green
6. Drain blue targets
7. Terminate blue tasks
8. Green becomes new blue
```

## DNS Architecture

### Route53 Configuration

**Hosted Zones:**
- dentiaapp.com
- dentia.co
- dentia.app
- dentia.ca

**A Records:**

```
hub.dentiaapp.com → ALB (alias)
hub.dentia.co     → ALB (alias)
hub.dentia.app    → ALB (alias)
hub.dentia.ca     → ALB (alias)
```

**Dev Records (ephemeral):**

```
dev-{branch}.hub.dentiaapp.com → ALB (alias)
pr-{number}.hub.dentiaapp.com  → ALB (alias)
```

## Monitoring Architecture

### CloudWatch Logs

**Log Groups:**
- /ecs/parlaehub-production/discourse
- /aws/elasticache/parlaehub-production-redis

**Retention:** 30 days (production), 7 days (dev)

**Insights Queries:** Saved queries for common issues

### CloudWatch Metrics

**ECS Metrics:**
- CPUUtilization
- MemoryUtilization
- RunningTaskCount

**ALB Metrics:**
- TargetResponseTime
- RequestCount
- HTTPCode_Target_4XX_Count
- HTTPCode_Target_5XX_Count
- HealthyHostCount
- UnHealthyHostCount

**Aurora Metrics:**
- ServerlessDatabaseCapacity
- ACUUtilization
- DatabaseConnections
- ReadLatency
- WriteLatency

**Redis Metrics:**
- CacheHits
- CacheMisses
- CPUUtilization
- NetworkBytesIn
- NetworkBytesOut
- CurrConnections

### CloudWatch Alarms

**Critical Alarms:**
- CPU > 80% for 10 minutes
- Memory > 80% for 10 minutes
- Unhealthy targets < 1 for 2 minutes
- 5xx errors > 10 for 5 minutes

**Warning Alarms:**
- CPU > 60% for 30 minutes
- Memory > 60% for 30 minutes
- Response time > 1s average
- Database connections > 80%

## Security Architecture

### IAM Roles

**ECS Task Execution Role:**
- Pull images from ECR
- Write logs to CloudWatch
- Read secrets from SSM

**ECS Task Role:**
- Read/write S3 uploads bucket
- Read SSM parameters (runtime)
- ECS Exec for debugging

### Encryption

**At Rest:**
- Aurora: AES-256 (AWS managed key)
- Redis: AES-256 (AWS managed key)
- S3: AES-256 (AWS managed key)
- SSM: AWS KMS encryption

**In Transit:**
- ALB → ECS: HTTP (private VPC)
- ECS → Aurora: SSL/TLS
- ECS → Redis: Unencrypted (Discourse limitation)
- ECS → S3: HTTPS

### Secrets Management

**SSM Parameter Store:**

```
/parlaehub/production/
  ├─ DB_HOST (String)
  ├─ DB_NAME (String)
  ├─ DB_USERNAME (String)
  ├─ DB_PASSWORD (SecureString)
  ├─ REDIS_HOST (String)
  ├─ S3_BUCKET (String)
  ├─ S3_REGION (String)
  ├─ COGNITO_CLIENT_ID (String)
  ├─ COGNITO_CLIENT_SECRET (SecureString)
  └─ COGNITO_ISSUER (String)
```

**Access Control:**
- ECS execution role can read all
- No public access
- Audit logging enabled

## Disaster Recovery Architecture

### Backup Strategy

**Aurora:**
- Automated daily backups (3-day retention)
- Point-in-time recovery
- Manual snapshots before changes

**Discourse:**
- Daily automated backups to S3
- 7-day retention
- Export includes:
  - Database dump
  - Uploaded files
  - Configuration

**Redis:**
- Daily automated snapshots
- 5-day retention
- Fast restore

### Recovery Procedures

**Database Corruption:**
1. Stop ECS service
2. Restore Aurora from snapshot
3. Update connection string
4. Restart ECS service
5. Verify data integrity

**Complete Disaster:**
1. Restore Aurora cluster
2. Restore Redis cluster
3. Restore S3 buckets
4. Re-deploy infrastructure (Terraform)
5. Deploy Discourse container
6. Restore Discourse backup
7. Update DNS if needed

**RTO:** 2-4 hours
**RPO:** 24 hours (daily backups)

## Scaling Architecture

### Horizontal Scaling

**ECS Auto-scaling:**
- Automatic based on CPU/Memory
- Range: 1-8 tasks
- Smooth scaling with cooldowns

**Future: Multi-region:**
- Replicate to additional region
- Route53 latency-based routing
- Aurora Global Database
- Redis replication across regions

### Vertical Scaling

**ECS Tasks:**
- Increase CPU/Memory per task
- Deploy new task definition
- Blue/Green rollout

**Redis:**
- Modify replication group
- Upgrade node type
- Minimal downtime

**Aurora:**
- Auto-scales to 8 ACU
- Can increase max capacity
- No downtime

## Development Architecture

### Local Development

```
docker-compose up
├─ postgres (local)
├─ redis (local)
└─ discourse (local build)
```

### Dev Environments (AWS)

**Ephemeral per PR:**
- Separate Aurora Serverless cluster
- Separate Redis cluster
- Separate S3 bucket
- Separate ECS service
- Shared ALB (unique hostname)
- Shared Cognito

**Lifecycle:**
- Created on PR open
- Updated on PR push
- Destroyed on PR close

**Cost:** ~$0.55 per 4 hours

## Performance Architecture

### Caching Strategy

**Layer 1: CloudFront (Optional)**
- Static assets (images, CSS, JS)
- TTL: 7 days
- Regional edge caching

**Layer 2: Discourse (Application)**
- Page fragments
- Query results
- User sessions

**Layer 3: Redis**
- Application cache
- Job queue (Sidekiq)
- Rate limiting

**Layer 4: Aurora**
- PostgreSQL query cache
- Shared buffers: Auto-tuned

### Optimization Techniques

**Database:**
- Connection pooling
- Query optimization
- Proper indexing
- Read replicas (future)

**Application:**
- Asset precompilation
- Image compression
- Lazy loading
- Efficient queries

**Network:**
- HTTP/2
- Gzip compression
- Keep-alive connections
- CDN for static assets

## Maintenance Architecture

### Update Strategy

**Discourse Updates:**
1. Test in dev environment
2. Build new image
3. Deploy to staging (future)
4. Blue/Green to production
5. Monitor for issues
6. Rollback if needed

**Infrastructure Updates:**
1. Update Terraform code
2. Test in dev workspace
3. Plan production changes
4. Apply during maintenance window
5. Verify resources

**Maintenance Windows:**
- Preferred: Sunday 5-7 AM UTC
- Notification: 72 hours advance
- Duration: 1-2 hours typical

## Cost Architecture

See [COST-ANALYSIS.md](./COST-ANALYSIS.md) for details.

**Cost Centers:**
- Compute: 40-50%
- Data Transfer: 25-30%
- Database: 15-20%
- Storage: 5-10%
- Other: 5-10%

## Future Enhancements

### Phase 2
- CloudFront CDN
- Multi-AZ redundancy
- Additional read replicas
- Enhanced monitoring

### Phase 3
- Multi-region deployment
- Advanced caching
- Elasticsearch for search
- CDN optimization

### Phase 4
- Global distribution
- Edge computing
- Advanced analytics
- AI/ML integration

