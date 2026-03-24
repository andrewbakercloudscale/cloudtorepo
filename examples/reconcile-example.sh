#!/usr/bin/env bash
# Example: reconcile an existing output directory against Resource Explorer

# Dry run first to preview what will be checked
./reconcile.sh \
  --output ./tf-output \
  --dry-run

# Full reconciliation
./reconcile.sh \
  --output ./tf-output \
  --index-region us-east-1
