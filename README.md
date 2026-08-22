# Terraform-Secure-S3
Creating a secure S3 bucket using Terraform Github Action

Includes:
1) Authenticating Github Actions to AWS using OIDC
2) Terraform Github Action will run whenever a code is pushed to the main branch

Steps:

1) clone the github repo https://github.com/kyberkraken/Terraform-Secure-S3.git to visual studio code

2) Add .gitignore file (Include tfstate, pem, enc files that might contain configuration or secrets)
3) Add gitleaks GitHub Actions in .github/workflows folder (It stops secrets from being committed locally and catching them in CI/CD before PRs are merged)

vim .github/workflows/gitleaks.yml

name: Gitleaks security scan

on:
    pull_request:
    push:
        branches:
            - main
    workflow_dispatch:

jobs:
  scan:
    name: Gitleaks scan
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
        
      - name: Run Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}


4) Create Branch Protection Rules
- Go to your GitHub reporistory settings
- Add a branch ruleset
- Under target branches, include default
- Add following rules:
    - Restrict deletions: 
    - Require a Pull Request before merging: Makes sure no direct pushes - happen to main branch
    - Block force pushes

4) Create Terraform file - main.tf

terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~>5.0"
        }
    }
}

provider "aws" {
    region= "ap-south-1"
}

resource "random_id" "bucket_suffix"{
    byte_length=4
}

resource "aws_s3_bucket" "s3_example" {
    bucket="unique_bucket_${random_id.bucket_suffix.hex}"

}


5) Commit these changes to remote github repo



