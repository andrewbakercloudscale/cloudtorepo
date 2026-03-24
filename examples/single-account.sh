#!/usr/bin/env bash
# Example: single account, specific regions and services

./aws-tf-reverse.sh \
  --regions "us-east-1,eu-west-1" \
  --services "vpc,ec2,eks,rds,s3,lambda,iam" \
  --state-bucket my-tf-state-bucket \
  --state-region us-east-1 \
  --output ./tf-output
