terraform {
    required_providers {
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

provider "aws" {
    region= "ap-south-1"
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

#Why prevent_destroy = true is important. For production buckets have this configuration so that terraform destroy deosn't delete this bucket while terraform destroy or when the bucket name is changed.
#If this is not included, if someone mistakenly changed the bucket name, teraform thinks they want to change the name (since the identifier aws_s3_bucket.s3_example points to single resource) and will delete and recreate the bcuekt wwith a new name

