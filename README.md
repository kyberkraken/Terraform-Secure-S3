# Terraform-Secure-S3
Creating a secure S3 bucket using Terraform Github Action

Includes:
1) Authenticating Github Actions to AWS using OIDC
2) Terraform Github Action will run whenever a code is pushed to the main branch

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

A github actions runner requests an identity token from Github. Github sends a JWT to the runner (containing repo name, branch, actor) signed using priovate key. The runner sends JWT(along with Role ARN it wants to asume) to AWS STS. AWS reads the JWT token, gets the public key from JWKS and validats the JWT. Then AWS also checks the ARN it received, see trust policy for that ARN and matches whether repo name in trust policy is same as that in JWT.

9) OIDC sets up
Provider URL for Github-  https://token.actions.githubusercontent.com
Audience: sts.amazonaws.com (if using official github action: configure-aws-credentials)

10) Create IAM role woth s3 permission with Web identity as trusted entity type and choose the OIDC provider creatd in previous step as identity provider. Ensure Github username and repo name is being mentioned in the trust policy of this role.

11) Create github action workflow in github to assume this IAM role created in AWS








