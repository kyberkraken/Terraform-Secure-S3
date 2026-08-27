# Terraform-Secure-S3
Creating a secure S3 bucket using Terraform Github Action

Includes:
1) Authenticating Github Actions to AWS using OIDC: short lived temporary tokens instead of access and secret keys
2) Security Best Practices in a GitHub CI/CD pipeline: Pre-Commit hooks, Secret detection using gitleaks, Branch Protection Rules, Policy-as-Code using Checkov
3) OIDC vs SAML: Theory and Use-Case
4) Secure way of deploying an S3 bucket with another S3 bucket as remote backend for storing state files
5) Deploying AWS resources via Terraform CI/CD: Security Best Practices 

Steps:

1) clone the github repo to visual studio code (Runs git init and git remote add origin https://githubrepo under the hood)

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

5) Create Terraform file - main.tf

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


6) Commit these changes to remote github repo
    
        git add --all
        git commit -m "your message related to files being pushed"
        git checkout -b sidebranch-setup-security-infra
        git push origin sidebranch-setup-security-infra
        git status

        Go to Github repo->Pull requests, create pull request and merge it to the main branch once gitleaks check is done


7) Now, github action for running the terraform file needs to be created along with setting up oidc between AWS and Github Actions

8) OIDC, SAML theory
To ensure AWS trust Github as identity provider and your github repo is allowed to assume AWS IAM role permissions

- Create an IAM role with desired permissions (S3 access in our case)
- IAM->Identity Provider (It is used when you have user identities outside AWS account and want them to use AWS resources). Identity center is used if you need to provide access to multiple AWS accounts and provide SSO features providing access to human users their asssigned accoutns from one UI. You can manage these human users either in IAM identity center or else a SAML2.0 supported Identity Provider (IdP) like Okta.

- Identity Provider (IdP) is a system that creates, maintains and manages digital identities. It verifies who you are(authentication) via pwords, biometric or MFA and tells other apps that you are legit user. Eg Okta, MS Entra ID, Google Workspace

- When an IdP like Okta needs to tell an application(like AWS/Slack) that a user is successfully logged in, they tell that to application by using common language like SAML/OIDC protocol.
SAML- older, highly secure, XML based. usecase is SSO for human users.
Working: A trusted relationship is formed between IdP and Applicaitons before Apps can starrt trustign IdP for authentication using exchange of SAML XML metadata files.
You download a SAML metadata file from Okta and send it to AWS. It contains- 
Issuer URL: URL that AWS should send users to(if they came 1st to aws) to validate auhtenticity. It can be used to detect and malicious SAML assertions
Public certificate: AWS use this public certificate(containing public key inside) to decrypt the encrypted SAML assertion

A metadata file genrated from AWS is also sent to Okta containing-
Entitiy ID: unique string identifying your AWS account
URL: the url where okta should send the digitally signed SAML assertion once user authenticates

A human user logs into IDP (Okta). Okta generates a SAML assertion (XML based) digitally signed(hashes user data and sign with private key) with private keys, and then it passes this SAML assertion to the application(like AWS) for it to authenticate. 

OIDC- modern, lightweight, built on top of OAuth 2.0 framweork. Uses JSON (JWT) instead of XML. Usecase is modern web/mobile apps, APIs, machine to machine automation(github action runners talking to aws)
Working: 
Trust relationship (handshake): Instead of uploading metadata file(in case of SAML) containing public cert and issuer url, AWS (application) gets the public keys from the Discovery URLs (OIDC endpoint). Github shars the folllowign to AWS:
Issuer URL: unique string of github. AWS use this to identify where JWTs are coming from
JWKS (JSON web key set) URL: endpoint where public crypto keys can be found and keeps rotating. AWS dynamically geets the latest keys to verify JWT.

A github actions runner requests an OIDC token from Github. Github sends that OIDC token(JWT) to the runner (containing repo name, branch, actor) signed using priovate key. The runner sends JWT(along with Role ARN it wants to asume) to AWS STS. AWS reads the JWT token, gets the public key from JWKS and validats the JWT. Then AWS also checks the ARN it received, see trust policy for that ARN and matches whether repo name in trust policy is same as that in JWT.

9) OIDC sets up
Provider URL for Github-  https://token.actions.githubusercontent.com
Audience: sts.amazonaws.com (if using official github action: configure-aws-credentials)

10) Create IAM role with s3 permission with Web identity as trusted entity type and choose the OIDC provider creatd in previous step as identity provider. Ensure Github username and repo name is being mentioned in the trust policy of this role.

*IMPORTANT note for repositories created after 15/07/2026: Update the Trust Policy to ensure that your repository name is following the convention:
    "token.actions.githubusercontent.com:sub": "repo:OWNER_NAME@OWNER_ID/REPO_NAME@REPO_ID:*"

You can find the new subject claim by going to Settings->Actions->OIDC of your github repository.

OIDC token generated by Github now contains immutable string ids in the subject claim for new repos. Previously, only owner and repo names were included and if an org name and repo name are deleted, a new owner could get tokens with the same subject claim gaining unauthorized access to cloud resources that still trust original identity.

Reference: https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/

11) Create a github action workflow in github to run a Checkov Polic-as-Code security scan to detect security misconfigurations reading your .tf file. If no cirtical or high findigns are discovered, Github will authenticate to AWS via OIDC and Terrraform will deploy the s3 bucket in AWS.

name: Terraform Deploy S3

on:
  push:
    branches:
      - main

permissions:
  id-token: write #Required for requesting JWT from Github
  contents: read #Required to checkout code. Required explicitely because permissions block is added, otherwise repo content read is default


jobs:
    security-scan:
        name: Checkov security scan
        runs-on: ubuntu-latest

        steps:
        - name: Checkout repo
            uses: actions/checkout@v4

        - name: Run checkov action
            uses: bridgecrewio/checkov-action@master
            with:
            directory: .
            output_format: cli
            soft_fail: false #this will cause the workflow to break if crit/high findings are discovered 

    terraform:
    runs-on: ubuntu-latest
    steps:
        - name: Checkout code
        uses: actions/checkout@v4

        - name: Configure AWS creds via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
            role-to-assume: "arn:aws:iam::426501511660:role/GithubAction-Assume-S3"
            aws-region: "us-east-1"
        
        - name: Set up Terraform
        uses: hashicorp/setup-terraform@v3

        - name: Terraform init
        run: terraform init

        - name: Terraform Apply
        run: terraform apply -auto-approve


12) Once you add the changes to staging, commit the changes to side branch, push it and merge it to main branch an S3 bucket should've been created.
If you're using the official aws-actions/configure-aws-credentials github action, short lived creds will be created for 1 hour. It can be adjusted as follows:

    - name: Configure AWS creds via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: "arn:aws:iam::426501511660:role/GithubAction-Assume-S3"
          aws-region: "us-east-1"
          role-duration-settings: 1800 #set to 30 mins


13) Terraform github action - Remote Backend - State Locking explained:

Note that whenever terraform github action is running, the tfstate file is locally inside the runner and gets deleted once github action closes. To avoid this either have tfstate file be present in your github repo but it is insecure practice because while configuring some resources like RDS, password remains in tfstate file. Secrets are stored in tfstate file sometimes, sg ip addresses can also be there so best not to have it on version control like git. 

But multiples devs working on same code still need access to tfstate file hence it can be stored in a "Remote Backend" like S3 which also provides default state locking features(from teraform 1.1+ - uses s3 conditional write capability that rpevents duplicate objects to be pushed into s3) ensuring 2 devs running terraform apply will lock tfstate file for devA until his terraform apply is finished and then release the lock and then devB can have the updated tfstate file and run apply accordingly, preventing both of them making changes to the new resources they created.

14) Adding remote backend to terraform provider block in main.tf:
backend "s3" {

        bucket = "terraform-state-s3-bucket-084045" #created manually in AWS with S3-SSE encryption and versioning enabled 
        key = "unique-bucket-33a0cf14/terraform.tfstate"
        region = "ap-south-1"
        encrypt = true #telling terraform to enforce SSE on the tfstate file before it gets saved onto remote s3 backend bucket although happens by default if s3 bucket is sse-s3 encrypted but what if bucket name is changed in future to a bucket that's nto encrypted.
        use_clockfile = true # By default its false and terraform thinks maybe you're using dynamodb for storing lockfiles as done in past so it dosn't even send terraform.tfstate.tflock file to aws
    }


15) Some secure terraform+AWS security practices as referred in https://dev.to/aws-builders/practical-terraform-tips-for-secure-and-reliable-aws-environments-19n0

- S3 backend locking with use_lockfile = true to ensure lock files ar being sent to s3 to avoid race conditions between statefiles when multiple people are working
- Enable versioning on your remote s3 backend to ensure state files are secure from accidental deletion
- Use default_tags in provider configuration
- Protect critical resources with prevent_destroy = true under lifecycle block of a resource. This ensures that the resource isn't deleted by mistake using terraform_destroy or while updating the name
- ignore_changes under lifecycle block of a resource to ensure diff detection is skipped for certain attributes of a resource for eg ALB listner target group during blue/green deployment or desired_capacity in ASG. So if ALB listner targets are changed from Blue resoruces to green resources by any other github actions or pipelines, your tf code does not move them back to Blue while terraform apply
- Using terraform import:
If a resource is manually creted in AWS, it won't be tracked by terraform in tfstate file. Running terraform refresh just refreshes the tfstate file with updated live configurations ONLY of tracked resources. For terraform to track a resource created manually, use terraform import

Earlier: 

Say a manual s3 bucket my_legacy_bucket is created manually in AWS. For it to be tracked via terraform:

Create an empty block in Terraform:
resource aws_s3_bucket legacy{

}

AND then run a CLI command:
terraform import aws_s3_bucket.legacy my_legacy_bucket

This will update the state file and start tracking your manually created s3 bucket

Now (With terraform >=v1.5)

No need to run CLI, directly update your .tf file:

import {
    to: aws_s3_bucket.legacy
    id: my_legacy_bucket
}


resource aws_s3_bucket legacy {
    bucket = my_legacy_bucket
} 

In this case, .tfstate file is updated when terraform apply is run

- Renaming resources without recreating them:

Earlier:
What if you declared a resource like

resource "aws_s3_bucket" my_exampl_bucket{ #wrote exampl instead of example
    bucket= "unique-s3-bucket
}

If you correct the spelling and run it again, since terraform refernce resources as aws_s3_bucket.my_exampl_bucket.unique_s3_bucket unique string in .tfstate file, it will think you want to delete exampl bucket and will recreate example bucket destroying your bucket storing production data.

Instead running this in CLI will work:

terraform state mv aws_s3_bucket.my_exampl_bucket aws_s3_bucket.my_example_bucket

Now:

But considering if you run such comamnds in CLI and there's a CI/CD pipelien running paralleley, you might run into race conditions. 
OR since devs should not get access to DEvOps CI/CD pipeline to run such comamnds to change the state or to the remote backend s3 bucket, better to decalre it in the code main.tf itself:

moved {
    from = aws_s3_bucket.my_exampl_bucket
    to = aws_s3_bucket.my_example_bucket
}

resource "aws_s3_bucket" "my_example_bucket" {
    bucket=my_unique_bucket"
}

Enable versioning as well



