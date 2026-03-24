#!/usr/bin/env bash
# Example: full organisation sweep across multiple accounts

./aws-tf-reverse.sh \
  --accounts "123456789012,234567890123,345678901234" \
  --role OrganizationAccountAccessRole \
  --regions "us-east-1,eu-west-1,ap-southeast-2" \
  --state-bucket my-tf-state-org \
  --state-region us-east-1 \
  --output ./tf-output
