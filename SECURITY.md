# Security Guidelines for parlaehub-infra

## 🔒 Files That Must NEVER Be Committed

### Never commit:
- ✅ **Blocked by `.gitignore`**
  - `terraform.tfvars` (contains passwords, AWS keys)
  - `*.tfstate` (contains infrastructure data with secrets)
  - `*.tfplan` (can contain plaintext passwords)
  - `*.pem`, `*.key` (SSH/SSL keys)
  - `client_secret_*.json` (OAuth credentials)
  - `*_accessKeys.csv` (AWS access keys)

### What's safe to commit:
- ✅ `terraform.tfvars.example` (template without real values)
- ✅ Terraform `.tf` files (as long as no hardcoded secrets)
- ✅ Documentation files
- ✅ Scripts (as long as they don't contain hardcoded secrets)

## 🔍 Before Pushing to GitHub

Run this check:
```bash
cd /Users/shaunk/Projects/Dentia/parlaehub-infra
git status

# Look for sensitive files:
git ls-files | grep -E "(tfvars|tfstate|tfplan|secret|key|password|credential|\.pem|accessKeys)"

# Should only show:
# - terraform.tfvars.example (safe - no real values)
# - scripts with "secret" in name (safe - they just manage secrets, don't contain them)
```

## 🚨 If You Accidentally Commit Sensitive Data

### Terraform State Files
**⚠️ CRITICAL: `.tfstate` files contain ALL resource data including passwords in plaintext!**

If committed:
1. **Immediately** rotate ALL credentials:
   - Aurora master password
   - Discourse DB password
   - AWS access keys
   - Cognito client secrets

2. Remove from git history:
```bash
git filter-repo --path terraform.tfstate --invert-paths --force
git filter-repo --path terraform.tfstate.backup --invert-paths --force
git push origin --force --all
```

### Terraform Variables Files
If `terraform.tfvars` is committed:
1. Remove immediately
2. Rotate all passwords stored in it
3. Update SSM Parameter Store with new values

## 🔐 Secure Credential Management

### terraform.tfvars Structure (NEVER COMMIT)
```hcl
# This file is gitignored - it's safe to store passwords here locally
aurora_master_password = "ACTUAL_PASSWORD_HERE"
discourse_db_password  = "ACTUAL_PASSWORD_HERE"
```

### Getting Credentials

```bash
# From SSM Parameter Store
aws ssm get-parameter \
  --name /parlaehub/production/AURORA_MASTER_PASSWORD \
  --with-decryption \
  --query Parameter.Value \
  --output text \
  --profile dentia \
  --region us-east-2

# Use in Terraform (via variable, not hardcoded)
TF_VAR_aurora_master_password=$(aws ssm get-parameter --name ... --with-decryption)
terraform plan
```

### Storing New Credentials

```bash
# Put in SSM Parameter Store
aws ssm put-parameter \
  --name /parlaehub/production/MY_SECRET \
  --value "secret_value_here" \
  --type SecureString \
  --overwrite \
  --profile dentia \
  --region us-east-2
```

## 🎯 Terraform Best Practices

### DO:
```hcl
# Good: Use variables
variable "db_password" {
  type      = string
  sensitive = true
}

resource "aws_db_instance" "db" {
  password = var.db_password
}
```

### DON'T:
```hcl
# Bad: Hardcoded password
resource "aws_db_instance" "db" {
  password = "MyP@ssw0rd123"  # NEVER DO THIS!
}
```

## 🔍 Audit Committed Files

```bash
# Check what's actually committed
cd /Users/shaunk/Projects/Dentia/parlaehub-infra
git ls-tree -r main --name-only

# Verify no sensitive files
git ls-files | grep -E "(\.tfvars$|\.tfstate|\.tfplan|\.pem|\.key)"
# Should return NOTHING (or only .tfvars.example)
```

## 📊 State Management

### Current Setup: S3 Backend (Secure)
```hcl
terraform {
  backend "s3" {
    bucket         = "parlaehub-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "parlaehub-terraform-locks"
  }
}
```

- ✅ State stored in encrypted S3
- ✅ NOT in git repository
- ✅ Access controlled via IAM

## 🚨 Incident Response

If sensitive data is exposed:

1. **Immediately** notify team lead
2. **Rotate credentials** (don't wait!)
3. **Check AWS CloudTrail** for unauthorized access
4. **Remove from git history** using git-filter-repo
5. **Force push** to overwrite remote history
6. **Document incident** and update procedures

## 📧 Reporting Security Issues

If you find sensitive data exposed:
1. **DO NOT** create a public GitHub issue
2. Immediately contact security team privately
3. Follow the credential rotation process
4. Document lessons learned

