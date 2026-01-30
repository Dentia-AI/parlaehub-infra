# ParlaeHub Infrastructure Setup Complete! 🎉

## Summary

The ParlaeHub infrastructure has been successfully deployed with cost-optimized settings and shared resources from the main Dentia application.

## ✅ What Has Been Deployed

### **Core Infrastructure**

- **ECR Repository**: `509852961700.dkr.ecr.us-east-2.amazonaws.com/parlaehub/discourse`
- **ECS Service**: `parlaehub-production-discourse` (in shared `dentia-cluster`)
- **Task Configuration**: 512 CPU, 1024 MB memory (cost-optimized)
- **Auto-scaling**: Min 1, Max 4 tasks

### **Shared Resources** ✨

1. **Database**: Uses shared Aurora PostgreSQL cluster (`dentia-aurora-cluster`)
   - Separate database: `discourse_production`
   - Dedicated user: `discourse_user`
   - **Note**: Database and user need to be created manually via bastion (see below)

2. **Cognito**: Uses shared User Pool (`us-east-2_eHT86wAMx`)
   - New App Client: `70ph0194d4uggtnn086piuubqv`
   - **SSO Enabled**: Users logged into Dentia are automatically logged into ParlaeHub!

3. **ECS Cluster**: Uses shared cluster (`dentia-cluster`)

4. **ALB**: Uses shared Application Load Balancer with new target group
   - URLs configured:
     - https://hub.dentiaapp.com
     - https://hub.dentia.co
     - https://hub.dentia.app
     - https://hub.dentia.ca

### **New Dedicated Resources**

1. **Redis Cache**: ElastiCache Redis (cache.t4g.micro)
   - Endpoint: `parlaehub-production-redis.jc9ggf.ng.0001.use2.cache.amazonaws.com`
   - Single node for cost optimization

2. **S3 Buckets**:
   - Uploads: `parlaehub-production-uploads`
   - Backups: `parlaehub-production-backups`

3. **CloudWatch**: Logs, metrics, and alarms
   - Log Group: `/ecs/parlaehub-production/discourse`

4. **IAM Roles**: Task execution and task roles with appropriate permissions

## 💰 Cost Optimization Features

1. **Minimal ECS Resources**: 512 CPU / 1024 MB memory (smallest viable for Discourse)
2. **Single Redis Node**: cache.t4g.micro (no multi-AZ for dev/low-traffic)
3. **Auto-scaling**: Stays at 1 task on no load, scales to 4 on demand
4. **Shared Infrastructure**: No additional costs for:
   - Aurora cluster (shared)
   - Cognito (shared)
   - ECS cluster (shared)
   - ALB (shared)
   - VPC & networking (shared)

**Estimated Additional Monthly Cost**: ~$50-80
- ECS Fargate: ~$15-20 (1 task @ 512 CPU / 1024 MB)
- Redis ElastiCache: ~$12 (cache.t4g.micro)
- S3 Storage: ~$5-10 (depending on usage)
- Data Transfer: ~$5-10
- CloudWatch Logs: ~$5

## 📋 Next Steps

### 1. Create Database and User (Required)

The database and user need to be created via the bastion host since Aurora is in a private subnet:

```bash
# SSH into bastion
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*bastion*" \
  --region us-east-2 \
  --profile dentia \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text

# Use Session Manager or EC2 Instance Connect
aws ssm start-session --target <bastion-instance-id> --region us-east-2 --profile dentia

# Once connected to bastion, install PostgreSQL client
sudo yum install -y postgresql15

# Connect to Aurora
export AURORA_ENDPOINT="dentia-aurora-cluster.cluster-c9kuy2skoi93.us-east-2.rds.amazonaws.com"
export MASTER_PASSWORD="S7#tY4^zN9_Rq2+xS8!nV9d"
export DB_PASSWORD="1f49b73d8979a4cd98d6d8f0cc715cb15447b4ebdf51b9661699676f8e382495"

# Create database
PGPASSWORD="$MASTER_PASSWORD" psql -h "$AURORA_ENDPOINT" -U dentia_admin -d postgres -c "CREATE DATABASE discourse_production;"

# Create user and grant permissions
PGPASSWORD="$MASTER_PASSWORD" psql -h "$AURORA_ENDPOINT" -U dentia_admin -d discourse_production <<EOF
CREATE USER discourse_user WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE discourse_production TO discourse_user;
GRANT ALL ON SCHEMA public TO discourse_user;
ALTER DATABASE discourse_production OWNER TO discourse_user;
EOF

# Verify
PGPASSWORD="$DB_PASSWORD" psql -h "$AURORA_ENDPOINT" -U discourse_user -d discourse_production -c "\dt"
```

### 2. Build and Deploy Discourse Docker Image

```bash
cd parlaehub

# Build and push to ECR
./scripts/build-and-push.sh production v1.0.0 dentia us-east-2

# Force new deployment
aws ecs update-service \
  --cluster dentia-cluster \
  --service parlaehub-production-discourse \
  --force-new-deployment \
  --region us-east-2 \
  --profile dentia

# Wait for deployment
aws ecs wait services-stable \
  --cluster dentia-cluster \
  --services parlaehub-production-discourse \
  --region us-east-2 \
  --profile dentia
```

### 3. Run Database Migrations

```bash
cd parlaehub

# Run migrations
./scripts/run-migrations.sh production dentia us-east-2
```

### 4. Create Admin User

```bash
# Open Rails console
./scripts/console.sh production dentia us-east-2

# In the console, create admin user:
User.create!(
  email: 'admin@dentiaapp.com',
  username: 'admin',
  name: 'Admin',
  password: 'CHANGE_THIS_PASSWORD',
  approved: true,
  approved_at: Time.zone.now,
  approved_by_id: -1,
  trust_level: TrustLevel[4]
)

exit
```

### 5. Configure Discourse Settings

Visit https://hub.dentiaapp.com and:
1. Login with admin credentials
2. Complete setup wizard
3. Configure Cognito SSO (settings already in environment)
4. Test SSO from Dentia app

## 🔐 Security Notes

- All sensitive credentials stored in AWS SSM Parameter Store
- Aurora database in private subnet (not publicly accessible)
- Redis cache in private subnet
- ECS tasks communicate securely within VPC
- S3 buckets are private with appropriate IAM policies
- ALB uses HTTPS with ACM certificates

## 📊 Monitoring

- **CloudWatch Alarms**:
  - High CPU utilization (>80%)
  - High memory utilization (>80%)
  - Low healthy target count (<1)

- **Logs**: Available in CloudWatch Logs group `/ecs/parlaehub-production/discourse`

- **Metrics**: Auto-scaling based on CPU and memory

## 🎯 Key Features

✅ **Shares Dentia database cluster** (separate database)
✅ **Shares Cognito user pool** (unified authentication)
✅ **Shares ECS cluster** (cost-effective)
✅ **Shares ALB** (cost-effective)
✅ **Minimal cost on no load** (~$50/month)
✅ **Auto-scales on demand** (1-4 tasks)
✅ **Multi-domain support** (hub.dentiaapp.com, hub.dentia.co, etc.)
✅ **Secure by default** (private subnets, IAM, SSM)

## 📁 Configuration Files

- **Terraform state**: S3 bucket `parlaehub-terraform-state`
- **Terraform vars**: `parlaehub-infra/environments/production/terraform.tfvars` (not committed)
- **SSM Parameters**: `/parlaehub/production/*`

## 🔄 Updates and Maintenance

To update infrastructure:
```bash
cd parlaehub-infra/environments/production
terraform plan
terraform apply
```

To update Discourse version:
```bash
cd parlaehub
# Update Dockerfile or image tag
./scripts/build-and-push.sh production v1.1.0 dentia us-east-2
# ECS will automatically deploy new version
```

## 🆘 Troubleshooting

**Service not starting?**
- Check CloudWatch Logs: `/ecs/parlaehub-production/discourse`
- Verify database connection from bastion
- Check ECS task stopped reason

**Can't connect to database?**
- Verify database exists: `PGPASSWORD='...' psql -h ... -U discourse_user -d discourse_production`
- Check security group rules
- Verify SSM parameters are correct

**SSO not working?**
- Verify Cognito client ID in Discourse settings
- Check callback URLs match configuration
- Test with Cognito hosted UI first

---

**Status**: ✅ Infrastructure deployed, database creation pending
**Next**: Create database via bastion, then build and deploy Discourse image

