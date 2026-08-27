terraform {
    required_providers { #downloads the binary plugin from hashicorp registry, ~tells terraform what libraries to install, similar to import
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
    bucket="unique-bucket-${random_id.bucket_suffix.hex}"
    force_destroy=false # ensuring that force destroy cannot be done meaning if thre are objects in the bucekt, you cannot delete it

    tags = {
        Environemnt = "Production"
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

