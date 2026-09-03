# Security best practices for deploying AWS S3 bucket using Terraform and GitHub Actions CI/CD

## What you will learn:
1) Authenticating Github Actions to AWS using OIDC: short lived temporary tokens instead of access and secret keys
2) Security Best Practices in a GitHub CI/CD pipeline: Pre-Commit hooks, Secret detection using gitleaks, Branch Protection Rules and Policy-as-Code using Checkov
3) OIDC vs SAML: Theory and Use-Case
4) Secure way of deploying an S3 bucket with S3 remote backend for storing state files
5) Deploying AWS resources via Terraform CI/CD: Security Best Practices 

## Steps:

### Setting up GitHub repo access on VSCode
1) Open VSCode and click on "Clone git repo" option.
Enter your GitHub repo URL.

    This runs `git init` and `git remote add origin https://githubrepoURL` under the hood

### Setting up security configurations for your GitHub Repo
2) Add .gitignore file (Include tfstate, pem, env files that might contain configuration or secrets)

    This will ensure secrets, passwords, configuration, state files, etc are not pushed to the public GitHub repo by mistake.

    Sample:
```yaml
        # Local .terraform directories
        **/.terraform/

        # Terraform state files (crucial if storing state remotely)
        *.tfstate
        *.tfstate.*
        *.tfstate.backup

        # Crash logs
        crash.log
        crash.*.log

        # Exclude sensitive variables files containing secrets/passwords
        *.tfvars
        *.tfvars.json
        override.tf
        override.tf.json
        *_override.tf
        *_override.tf.json

        # Ignore CLI configuration files
        .terraformrc
        terraform.rc

        # Ignore plan output files
        *.tfplan

        # Operating System & IDE artifacts
        .DS_Store
        .vscode/
        .idea/

```

3) Add gitleaks GitHub Actions yaml file in .github/workflows folder (It stops secrets from being committed locally and catching them in CI/CD before PRs are merged)

`vim .github/workflows/gitleaks.yml`

```yaml
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
```

4) Create Branch Protection Rules for your GitHub repo

- Go to your GitHub repository settings
- Add a branch ruleset
- Under target branches, include default
- Add following rules:
    - Restrict deletions: 
    - Require a Pull Request before merging: Makes sure no direct pushes - happen to main branch
    - Block force pushes

### Writing Terraform code for deploying secure AWS S3 Bucket
5) Create Terraform file - main.tf

```yaml
        terraform {
            required_providers { #downloads the binary plugin from hashicorp registry, ~ tells terraform what libraries to install, similar to import
                aws = {
                    source = "hashicorp/aws"
                    version = "~>5.0"

                }
            }

            backend "s3" {

                bucket = "terraform-state-s3-bucket-084045" #created manually in AWS with S3-SSE encryption enabled
                key = "unique-bucket-33a0cf14/terraform.tfstate"
                region = "ap-south-1"
                encrypt = true #telling terraform to enforce SSE on the tfstate file before it gets saved onto remote s3 backend bucket
                use_lockfile = true # By default its false and terraform thinks maybe you're using dynamodb for storing lockfiles as done in past so it dosn't even send terraform.tfstate.tflock file to aws
            }
        }

        provider "aws" { # configures how terraform authenticates and interacts with target cloud provider
            region= "ap-south-1"
            default_tags { #used in case we forget to add tags for any resource
                tags = {
                    Environment = "Production"
                    ManagedBy = "Terraform"
                }
            }
        }

        resource "random_id" "bucket_suffix"{
            byte_length=4
        }


        resource "aws_s3_bucket" "s3_example" {
            #bucket="unique-bucket-${random_id.bucket_suffix.hex}"
            bucket="unique-bucket-da48d528"
            force_destroy=false # ensuring that force destroy cannot be done meaning if thre are objects in the bucekt, you cannot delete it

            tags = {
                Environment = "Production"
                ManagedBy = "Terraform"
            }

            lifecycle {
                prevent_destroy=true #lifecycle argument- tells tf that if someone runs terraform destroy or modifies bucket name by msitakes, do not dlete the bucket
            }
        }


        #blocking public access
        resource "aws_s3_bucket_public_access_block" "public_access" {
            bucket= aws_s3_bucket.s3_example.id

            block_public_acls=true
            block_public_policy=true
            ignore_public_acls=true
            restrict_public_buckets=true
        }

        #enabling versioning
        resource "aws_s3_bucket_versioning" "enabling_versioning" {
            bucket = aws_s3_bucket.s3_example.id

            versioning_configuration {
                status = "Enabled"
            }

        }

        #Disabling ACL use. It is disabled by default. Ensure that even if object was uplaoded by an outside entity(account/user) its ownership remains with the s3 bucket. Disabling ACLs ensure centralized access control using only IAM roles and bucket ACLs
        resource "aws_s3_bucket_ownership_controls" "ownership" {
        bucket = aws_s3_bucket.s3_example.id

        rule {
            object_ownership = "BucketOwnerEnforced"
        }
        }

        #Enabling versioning
        resource "aws_s3_bucket_versioning" "versioning" {
        bucket = aws_s3_bucket.s3_example.id

        versioning_configuration {
            status = "Enabled"
        }
        }


        #Why prevent_destroy = true is important. For production buckets have this configuration so that terraform destroy deosn't delete this bucket while terraform destroy or when the bucket name is changed.
        #If this is not included, if someone mistakenly changed the bucket name, teraform thinks they want to change the name (since the identifier aws_s3_bucket.s3_example points to single resource) and will delete and recreate the bcuekt wwith a new name

```

6) Commit these changes to remote github repo
    
    On your VSCode CLI:

        git add --all
        git commit -m "your message related to files being pushed"
        git checkout -b sidebranch-setup-security-infra
        git push origin sidebranch-setup-security-infra
        git status

    Go to Github repo->Pull requests, create pull request and merge it to the main branch once gitleaks check is done


7) Now, github action for running the terraform file needs to be created along with setting up oidc between AWS and Github Actions

### Authenticating GitHub to AWS using OIDC Provider

8) OIDC, SAML theory

- Objective: To ensure AWS trust Github as identity provider and your github repo is allowed to assume AWS IAM role permissions

- Create an IAM role with desired permissions (S3 access in our case)

- IAM->Identity Provider  (It is used when you have user identities outside AWS account and want them to use AWS resources). 

    Identity center is used if you need to provide access to multiple AWS accounts and provide SSO features providing access to human users their asssigned accoutns from one UI. You can manage these human users either in IAM identity center or else a SAML2.0 supported Identity Provider (IdP) like Okta.

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

9) Go to IAM->Identity Provider->Add Provider->OpenID Connect

    Provider URL for Github-  https://token.actions.githubusercontent.com
    Audience: sts.amazonaws.com (if using official github action: configure-aws-credentials)

10) Create IAM role with s3 permission with Web identity as trusted entity type and choose the OIDC provider creatd in previous step as identity provider. Ensure Github username and repo name is being mentioned in the trust policy of this role.

* _IMPORTANT note for repositories created after 15/07/2026: Update the Trust Policy to ensure that your repository name is following the convention:
    "token.actions.githubusercontent.com:sub": "repo:OWNER_NAME@OWNER_ID/REPO_NAME@REPO_ID:*"_

    _You can find the new subject claim by going to Settings->Actions->OIDC of your github repository._

    _OIDC token generated by Github now contains immutable string ids in the subject claim for new repos. Previously, only owner and repo names were included and if an org name and repo name are deleted, a new owner could get tokens with the same subject claim gaining unauthorized access to cloud resources that still trust original identity._

    _Reference: https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/_

### Writing GitHub Action for deploying Terraform and adding Checkov Policy-as-Code scan in the CI/CD pipeline

11) Create a github action workflow in github to run a Checkov Policy-as-Code security scan to detect security mis-configurations reading your .tf file. If no cirtical or high findigns are discovered, Github will authenticate to AWS via OIDC and Terrraform will deploy the s3 bucket in AWS.
```yaml
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
```


12) Once you add the changes to staging, commit the changes to side branch, push it and merge it to main branch an S3 bucket should've been created.
If you're using the official aws-actions/configure-aws-credentials github action, short lived creds will be created for 1 hour. It can be adjusted as follows:
```yaml
    - name: Configure AWS creds via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: "arn:aws:iam::426501511660:role/GithubAction-Assume-S3"
          aws-region: "us-east-1"
          role-duration-settings: 1800 #set to 30 mins
```
### Creating S3 remote backend with state locking

13) Terraform github action - Remote Backend - State Locking explained:

Note that whenever terraform github action is running, the tfstate file is locally inside the runner and gets deleted once github action closes. To avoid this either have tfstate file be present in your github repo but it is insecure practice because while configuring some resources like RDS, password remains in tfstate file. Secrets are stored in tfstate file sometimes, sg ip addresses can also be there so best not to have it on version control like git. 

But multiples devs working on same code still need access to tfstate file hence it can be stored in a "Remote Backend" like S3 which also provides default state locking features(from teraform 1.1+ - uses s3 conditional write capability that rpevents duplicate objects to be pushed into s3) ensuring 2 devs running terraform apply will lock tfstate file for devA until his terraform apply is finished and then release the lock and then devB can have the updated tfstate file and run apply accordingly, preventing both of them making changes to the new resources they created.

14) Adding remote backend to terraform provider block in main.tf:

```yaml
backend "s3" {

        bucket = "terraform-state-s3-bucket-084045" #created manually in AWS with S3-SSE encryption and versioning enabled 
        key = "unique-bucket-33a0cf14/terraform.tfstate"
        region = "ap-south-1"
        encrypt = true #telling terraform to enforce SSE on the tfstate file before it gets saved onto remote s3 backend bucket although happens by default if s3 bucket is sse-s3 encrypted but what if bucket name is changed in future to a bucket that's nto encrypted.
        use_clockfile = true # By default its false and terraform thinks maybe you're using dynamodb for storing lockfiles as done in past so it dosn't even send terraform.tfstate.tflock file to aws
    }
```
### Security best practices for deploying AWS resources via Terraform

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

```yaml    
    resource aws_s3_bucket legacy{

    }
```
    
AND then run a CLI command:

`terraform import aws_s3_bucket.legacy my_legacy_bucket`

This will update the state file and start tracking your manually created s3 bucket

Now (With terraform >=v1.5)

No need to run CLI, directly update your .tf file:

```yaml
    import {
        to: aws_s3_bucket.legacy
        id: my_legacy_bucket
    }


    resource aws_s3_bucket legacy {
        bucket = my_legacy_bucket
    } 
```

    In this case, .tfstate file is updated when terraform apply is run

- Renaming resources without recreating them:

Earlier:
What if you declared a resource like

```yaml
resource "aws_s3_bucket" my_exampl_bucket{ #wrote exampl instead of example
    bucket= "unique-s3-bucket
}
```
If you correct the spelling and run it again, since terraform refernce resources as aws_s3_bucket.my_exampl_bucket.unique_s3_bucket unique string in .tfstate file, it will think you want to delete exampl bucket and will recreate example bucket destroying your bucket storing production data.

Instead running this in CLI will work:

`terraform state mv aws_s3_bucket.my_exampl_bucket aws_s3_bucket.my_example_bucket`

Now:

But considering if you run such comamnds in CLI and there's a CI/CD pipelien running paralleley, you might run into race conditions. 
OR since devs should not get access to DEvOps CI/CD pipeline to run such comamnds to change the state or to the remote backend s3 bucket, better to decalre it in the code main.tf itself:

```yaml
moved {
    from = aws_s3_bucket.my_exampl_bucket
    to = aws_s3_bucket.my_example_bucket
}

resource "aws_s3_bucket" "my_example_bucket" {
    bucket=my_unique_bucket"
}

```
- Enable versioning as well for your AWS S3 buckets


### Setting up Dependabot SCA scanning

16) Enabling Dependabot: To get alerts on vulnerabilities in dependencies in my code and github actions(vulnerable package/github action) and automatic PR creation for fixing those vulnerabilities.

In you github repo, go to settings->Advanced security->Enable Dependabot alerts and Dependabot security updates. This will also enable dependency graph that checks your code package against github advisory database to check if a vuln is found.



