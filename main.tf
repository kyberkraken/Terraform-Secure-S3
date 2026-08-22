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
    bucket="unique-bucket-${random_id.bucket_suffix.hex}"

}


