# ParlaeHub Cost Analysis

Detailed breakdown of AWS costs for self-hosted Discourse.

## Cost Summary by Scale

| Scale | Monthly Cost | Cost per MAU | Infrastructure |
|-------|-------------|-------------|----------------|
| **Minimal (100 users)** | $51 | $0.51 | Base setup |
| **Small (1K users)** | $125 | $0.125 | 1-2 tasks |
| **Medium (10K users)** | $300 | $0.030 | 2-4 tasks |
| **Large (100K users)** | $1,075 | $0.011 | 4-8 tasks |
| **Very Large (1M users)** | $5,000 | $0.005 | Multi-AZ, optimized |

## Detailed Cost Breakdown

### Minimal Load (~100 users)

| Service | Spec | Hours/Month | Unit Cost | Monthly Cost |
|---------|------|-------------|-----------|--------------|
| **ECS Fargate** | 1 task (1 vCPU, 2GB) | 730 | $0.04048/hr | $29.55 |
| **Aurora** | Shared, 0.5 ACU | 730 | $0.12/ACU-hr | $1.00 (allocated) |
| **ElastiCache** | cache.t4g.micro | 730 | $0.016/hr | $11.68 |
| **S3 Storage** | 10GB + 10K requests | - | - | $0.50 |
| **Data Transfer** | 50GB out | - | $0.09/GB | $4.50 |
| **ALB** | Shared, partial cost | - | - | $3.00 |
| **Route53** | 1M queries | - | $0.40/M | $0.40 |
| **CloudWatch** | 5GB logs | - | $0.50/GB | $2.50 |
| **TOTAL** | | | | **$53.13** |

### Small Load (~1K users)

| Service | Spec | Monthly Cost |
|---------|------|--------------|
| **ECS Fargate** | 2 tasks (1 vCPU, 2GB) | $59.10 |
| **Aurora** | Shared, 0.5-1 ACU | $5.00 |
| **ElastiCache** | cache.t4g.micro | $11.68 |
| **S3 Storage** | 50GB + 50K requests | $2.00 |
| **Data Transfer** | 200GB out | $18.00 |
| **ALB** | Shared | $8.00 |
| **Route53** | 5M queries | $2.00 |
| **CloudWatch** | 10GB logs | $5.00 |
| **TOTAL** | | **$110.78** |

### Medium Load (~10K users)

| Service | Spec | Monthly Cost |
|---------|------|--------------|
| **ECS Fargate** | 3 tasks (2 vCPU, 4GB) avg | $177.30 |
| **Aurora** | Shared, 1-2 ACU | $15.00 |
| **ElastiCache** | cache.t4g.small | $23.36 |
| **S3 Storage** | 200GB + 200K requests | $6.00 |
| **Data Transfer** | 1TB out | $90.00 |
| **ALB** | Shared | $20.00 |
| **Route53** | 20M queries | $8.00 |
| **CloudWatch** | 30GB logs | $15.00 |
| **TOTAL** | | **$354.66** |

### Large Load (~100K users)

| Service | Spec | Monthly Cost |
|---------|------|--------------|
| **ECS Fargate** | 4-6 tasks (2 vCPU, 4GB) avg | $473.28 |
| **Aurora** | Shared, 2-4 ACU | $50.00 |
| **ElastiCache** | cache.t4g.medium | $46.72 |
| **S3 Storage** | 1TB + 1M requests | $30.00 |
| **Data Transfer** | 5TB out | $450.00 |
| **ALB** | Shared | $50.00 |
| **Route53** | 100M queries | $40.00 |
| **CloudWatch** | 100GB logs | $50.00 |
| **TOTAL** | | **$1,190.00** |

## Cost by Environment

### Production

**Fixed Costs:**
- ElastiCache: $11.68/month (minimum)
- Route53: ~$2/month
- ALB contribution: ~$5/month

**Variable Costs:**
- ECS Fargate: $29.55 per task per month
- Aurora: $0.12 per ACU-hour
- Data transfer: $0.09 per GB
- S3: $0.023 per GB stored + requests

**Monthly Range:** $50-2,000+ depending on load

### Dev (Ephemeral)

**Per 4-hour session:**
- ECS Fargate (512m, 1GB): $0.20
- Aurora Serverless (0.5 ACU): $0.24
- ElastiCache micro: $0.06
- S3 + Transfer: $0.05
- **Total: ~$0.55 per 4 hours**

**If running 24/7:**
- ~$99/month

**Best Practice:** Destroy after each use

## Cost Optimization Strategies

### 1. Right-Size ECS Tasks

```hcl
# Start small
task_cpu    = 512
task_memory = 1024

# Scale up as needed based on CloudWatch metrics
# Monitor: CPU < 60%, Memory < 70% = oversized
```

**Savings:** 30-50%

### 2. Use Spot Instances (Advanced)

Currently using Fargate, but can migrate to EC2 Spot for 70% discount:

```hcl
# Switch to EC2 launch type with Spot instances
# Requires capacity provider setup
```

**Savings:** 70% on compute

**Trade-off:** Possible interruptions

### 3. Optimize Auto-Scaling

```hcl
# Aggressive scale-down
autoscaling_min_capacity = 1
scale_in_cooldown       = 60   # Scale down faster

# Conservative scale-up
cpu_target_value        = 70   # Higher threshold
scale_out_cooldown      = 300  # Wait longer
```

**Savings:** 20-30%

### 4. Use Reserved Capacity

For predictable loads, commit to Savings Plans:

- 1-year commitment: 30% discount
- 3-year commitment: 50% discount

**Savings:** 30-50%

### 5. Optimize Data Transfer

```hcl
# Use CloudFront CDN
# Cache static assets
# Enable compression
# Lazy load images
```

**Savings:** 40-60% on data transfer

### 6. S3 Lifecycle Policies

```hcl
# Transition old uploads to Glacier
# Delete old backups
# Use Intelligent-Tiering
```

**Savings:** 70% on storage

### 7. CloudWatch Logs Retention

```hcl
# Reduce log retention
log_retention_days = 7  # Instead of 30
```

**Savings:** 75% on logs

### 8. ElastiCache Optimization

**Option A: Use Redis Sidecar**
- Run Redis in same Fargate task
- No separate ElastiCache cost
- **Savings: $11.68/month**
- **Trade-off: Higher task CPU/memory**

**Option B: Right-size Redis**
- Monitor memory usage
- Downsize if < 50% used

**Savings:** 50%

## Cost Monitoring

### Set Up Budgets

```bash
aws budgets create-budget \
  --account-id ACCOUNT_ID \
  --budget file://budget.json
```

**budget.json:**
```json
{
  "BudgetName": "ParlaeHub-Monthly",
  "BudgetLimit": {
    "Amount": "200",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
```

### CloudWatch Cost Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "high_cost" {
  alarm_name          = "parlaehub-high-cost"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600  # 6 hours
  statistic           = "Maximum"
  threshold           = 100
  alarm_description   = "Alert when monthly cost exceeds $100"
}
```

### Cost Allocation Tags

Tag all resources:
```hcl
tags = {
  Project     = "parlaehub"
  Environment = "production"
  CostCenter  = "community"
}
```

## Cost Comparison

### Self-Hosted vs Managed Discourse

| Users | Self-Hosted | Managed | Savings |
|-------|------------|---------|---------|
| 100 | $53 | $100 | -$47 (pay more) |
| 1K | $111 | $100 | +$11 (pay more) |
| 10K | $355 | $300 | +$55 (pay more) |
| 100K | $1,190 | $2,500 | **$1,310 (52%)** |
| 1M | $5,000 | $10,000 | **$5,000 (50%)** |

**Break-even:** ~10K users

**Recommendation:** 
- < 10K users: Use managed Discourse
- > 10K users: Self-host for savings

**But consider:**
- Self-hosting requires DevOps expertise
- Add labor costs: ~$1,000-3,000/month
- Total break-even: ~50K users

## Hidden Costs

### Development Time

- Initial setup: 16-24 hours
- Monthly maintenance: 4-8 hours
- Incident response: 0-8 hours

**Value:** $100/hour = $500-2,000/month

### Opportunity Cost

- Could be building features
- Could be growing user base
- Consider team capacity

## Cost Projections

### Year 1 (Growing from 0 to 10K users)

| Month | Users | Monthly Cost | Cumulative |
|-------|-------|-------------|------------|
| 1 | 100 | $53 | $53 |
| 3 | 500 | $75 | $221 |
| 6 | 2K | $150 | $596 |
| 9 | 5K | $250 | $1,321 |
| 12 | 10K | $355 | $2,576 |

**Year 1 Total:** ~$2,576

### Year 2 (10K to 50K users)

**Average monthly:** $600
**Year 2 Total:** ~$7,200

### Year 3 (50K to 100K users)

**Average monthly:** $1,000
**Year 3 Total:** ~$12,000

## ROI Analysis

### 3-Year Comparison

**Self-Hosted:**
- Infrastructure: $21,776
- DevOps time (300 hrs): $30,000
- **Total: $51,776**

**Managed Discourse:**
- Service fees: $72,000
- **Total: $72,000**

**Savings:** $20,224 (28%)

**Break-even with DevOps:** ~50-100K users

## Recommendations

### For Startups (< 10K users)
- ❌ Don't self-host yet
- ✅ Use managed Discourse Standard ($100/mo)
- Wait until 10K+ users to reconsider

### For Growing Communities (10K-100K users)
- ✅ Self-host makes financial sense
- Ensure DevOps capacity
- Budget $300-1,000/month

### For Large Communities (100K+ users)
- ✅✅ Definitely self-host
- Significant savings
- Optimize aggressively
- Consider Reserved Capacity

## Action Items

1. **Track costs weekly**
2. **Set up budgets and alarms**
3. **Review CloudWatch metrics**
4. **Optimize based on usage**
5. **Compare with managed options quarterly**

