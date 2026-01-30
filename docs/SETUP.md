# ParlaeHub Setup Guide

Complete step-by-step guide to set up ParlaeHub infrastructure from scratch.

## Prerequisites

Before starting, ensure you have:

- [x] AWS CLI installed and configured
- [x] Terraform >= 1.6.0 installed
- [x] Docker installed
- [x] Git installed
- [x] AWS account with appropriate permissions
- [x] Existing Dentia infrastructure deployed
- [x] Access to `dentia` AWS profile

## Step 1: Clone Repositories

```bash
# Clone infrastructure repository
git clone https://github.com/Dentia/parlaehub-infra.git
cd parlaehub-infra

# Clone application repository
cd ..
git clone https://github.com/Dentia/parlaehub.git
```

## Step 2: Create Terraform Backend

The backend stores Terraform state in S3 with DynamoDB locking.

```bash
cd parlaehub-infra
./scripts/create-backend-resources.sh dentia us-east-2
```

This creates:
- S3 bucket: `parlaehub-terraform-state`
- DynamoDB table: `parlaehub-terraform-locks`

## Step 3: Configure Production Secrets

### 3.1 Generate Strong Passwords

```bash
# Generate database password
openssl rand -hex 32

# Generate Discourse secret key
openssl rand -hex 64
```

### 3.2 Run Secrets Setup Script

```bash
./scripts/put-ssm-secrets-parlaehub.sh dentia us-east-2
```

Follow the prompts to enter:
- Aurora master password (from existing Dentia infrastructure)
- Discourse database password (generated above)

The script will auto-detect:
- Aurora cluster endpoint
- Cognito User Pool ID

### 3.3 Verify Secrets

```bash
aws ssm get-parameters-by-path \
  --path "/parlaehub/production" \
  --recursive \
  --with-decryption \
  --profile dentia \
  --region us-east-2
```

## Step 4: Configure Terraform

### 4.1 Create terraform.tfvars

```bash
cd environments/production
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Fill in the values:

```hcl
region  = "us-east-2"
profile = "dentia"
domain  = "dentiaapp.com"

aurora_master_username = "dentia_admin"
aurora_master_password = "YOUR_AURORA_PASSWORD"
discourse_db_password  = "YOUR_DISCOURSE_DB_PASSWORD"

discourse_image_tag = "latest"
```

### 4.2 Verify Remote State Access

```bash
# Test that Terraform can read from Dentia state
terraform init
terraform plan
```

## Step 5: Deploy Infrastructure

### 5.1 Initialize Terraform

```bash
cd environments/production
terraform init
```

### 5.2 Review Plan

```bash
terraform plan -out=tfplan
```

Review the plan carefully. It should create:
- ECR repository
- IAM roles and policies
- Cognito app client
- Database (in shared Aurora cluster)
- ElastiCache Redis cluster
- S3 buckets
- ALB target groups and listener rules
- Route53 DNS records
- ECS task definition and service
- Auto-scaling policies
- CloudWatch alarms

### 5.3 Apply Infrastructure

```bash
terraform apply tfplan
```

This takes ~15-20 minutes to complete.

### 5.4 Save Outputs

```bash
terraform output -json > outputs.json
cat outputs.json | jq
```

Save the ECR repository URL for the next step.

## Step 6: Build and Deploy Discourse

### 6.1 Build Docker Image

```bash
cd ../../../parlaehub

# Build and push to ECR
./scripts/build-and-push.sh production v1.0.0 dentia us-east-2
```

### 6.2 Update ECS Service

```bash
aws ecs update-service \
  --cluster parlaehub-production \
  --service parlaehub-production-discourse \
  --force-new-deployment \
  --profile dentia \
  --region us-east-2
```

### 6.3 Wait for Deployment

```bash
aws ecs wait services-stable \
  --cluster parlaehub-production \
  --services parlaehub-production-discourse \
  --profile dentia \
  --region us-east-2
```

## Step 7: Initialize Discourse

### 7.1 Run Database Migrations

```bash
./scripts/run-migrations.sh production dentia us-east-2
```

### 7.2 Create Admin User

```bash
# Open Rails console
./scripts/console.sh production dentia us-east-2

# In the console:
User.create!(
  email: 'admin@dentiaapp.com',
  username: 'admin',
  name: 'Admin',
  password: 'YOUR_TEMP_PASSWORD',
  approved: true,
  approved_at: Time.zone.now,
  approved_by_id: -1,
  trust_level: TrustLevel[4]
)

# Exit console
exit
```

### 7.3 Access Discourse

Visit: https://hub.dentiaapp.com

Login with the admin credentials and:
1. Change password immediately
2. Complete setup wizard
3. Configure site settings
4. Test Cognito SSO

## Step 8: Configure DNS

If using additional domains (dentia.co, dentia.app, etc.), verify DNS:

```bash
# Check DNS propagation
dig hub.dentiaapp.com
dig hub.dentia.co
dig hub.dentia.app
dig hub.dentia.ca
```

All should point to the ALB.

## Step 9: Configure SSL/TLS

SSL certificates are automatically managed by ACM. Verify:

```bash
aws acm list-certificates \
  --region us-east-2 \
  --profile dentia
```

## Step 10: Configure GitHub Actions

### 10.1 Add Repository Secrets

In both repositories, add these secrets:

**GitHub Repository Secrets:**
- `AWS_ACCESS_KEY_ID` - IAM user with deploy permissions
- `AWS_SECRET_ACCESS_KEY` - IAM user secret
- `AURORA_MASTER_PASSWORD` - Aurora master password
- `DISCOURSE_DB_PASSWORD` - Discourse database password
- `AURORA_DEV_PASSWORD` - Password for dev Aurora (generate new)
- `ECR_REPOSITORY_URL` - From Terraform output
- `INFRA_PAT` - Personal Access Token for triggering infra workflows

### 10.2 Test CI/CD

1. Create a test branch
2. Make a small change
3. Open PR
4. Verify CI builds and deploys preview environment

## Step 11: Configure Monitoring

### 11.1 CloudWatch Dashboard

Create a dashboard for ParlaeHub:

```bash
aws cloudwatch put-dashboard \
  --dashboard-name ParlaeHub-Production \
  --dashboard-body file://cloudwatch-dashboard.json \
  --profile dentia \
  --region us-east-2
```

### 11.2 SNS Alerts

Add email subscribers to alerts:

```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-2:ACCOUNT_ID:parlaehub-production-alerts \
  --protocol email \
  --notification-endpoint your-email@dentiaapp.com \
  --profile dentia \
  --region us-east-2
```

### 11.3 Verify Alarms

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "parlaehub-production" \
  --profile dentia \
  --region us-east-2
```

## Step 12: Backup Configuration

### 12.1 Enable Automatic Discourse Backups

Via Admin UI:
1. Settings > Backups
2. Enable automatic backups
3. Set frequency to daily
4. Set retention to 7 days
5. Configure S3 backup location

### 12.2 Test Backup

```bash
# Trigger manual backup
# Via Admin UI: Backups > Backup Now
```

### 12.3 Test Restore (in dev)

```bash
# Download backup
# Restore in dev environment
# Verify data integrity
```

## Step 13: Security Hardening

### 13.1 Enable MFA for Admin Users

Via Admin UI:
1. Settings > Security
2. Require 2FA for staff
3. Enable security key authentication

### 13.2 Configure Rate Limiting

Via Admin UI:
1. Settings > Rate Limiting
2. Set appropriate limits for:
   - Login attempts
   - New topics
   - New posts
   - Uploads

### 13.3 Enable WAF (Optional)

```bash
# Create WAF web ACL
# Associate with ALB
# Configure rules for:
# - SQL injection protection
# - XSS protection
# - Rate limiting
```

## Step 14: Performance Optimization

### 14.1 Configure CDN

Update Terraform with CloudFront:
- Enable CloudFront distribution
- Configure origin for ALB
- Set caching policies
- Update `DISCOURSE_CDN_URL`

### 14.2 Enable Caching

Via Admin UI:
1. Settings > Performance
2. Enable all caching options
3. Set cache durations

### 14.3 Optimize Images

Via Admin UI:
1. Settings > Files
2. Enable image compression
3. Set max image dimensions
4. Enable WebP conversion

## Verification Checklist

After setup, verify:

- [ ] Discourse loads at all configured domains
- [ ] SSL/TLS certificates are valid
- [ ] Cognito SSO login works
- [ ] Users from Dentia app can login
- [ ] File uploads work (S3)
- [ ] Email sending works (SES)
- [ ] Database connectivity is stable
- [ ] Redis connectivity is stable
- [ ] Auto-scaling triggers correctly
- [ ] Backups run successfully
- [ ] CloudWatch logs are flowing
- [ ] Alarms are configured
- [ ] CI/CD pipeline works
- [ ] PR preview environments deploy
- [ ] Blue/Green deployment works

## Troubleshooting

### Issue: ECS tasks keep restarting

```bash
# Check logs
aws logs tail /ecs/parlaehub-production/discourse \
  --follow \
  --profile dentia \
  --region us-east-2
```

Common causes:
- Database connection failure
- Redis connection failure
- Missing environment variables
- Failed health checks

### Issue: Cognito SSO not working

```bash
# Check Cognito client configuration
aws cognito-idp describe-user-pool-client \
  --user-pool-id us-east-2_xxx \
  --client-id xxx \
  --profile dentia \
  --region us-east-2

# Verify callback URLs are correct
```

### Issue: High database CPU

```bash
# Check slow queries
# Scale up Aurora capacity
# Add read replicas if needed
```

### Issue: Out of memory errors

```bash
# Increase ECS task memory
# Or increase number of tasks
# Update Terraform and apply
```

## Next Steps

1. **Configure Plugins**: Install additional Discourse plugins
2. **Customize Theme**: Apply Dentia branding
3. **Import Content**: Migrate from existing forum (if any)
4. **User Training**: Create guides for moderators
5. **Launch**: Announce to Dentia users

## Support

For issues:
- Infrastructure: parlaehub-infra GitHub Issues
- Application: parlaehub GitHub Issues
- Discourse Core: discourse/discourse GitHub

## Maintenance

Regular maintenance tasks:
- Monitor costs weekly
- Review logs daily
- Update Discourse monthly
- Test backups monthly
- Review security quarterly
- Optimize performance quarterly

