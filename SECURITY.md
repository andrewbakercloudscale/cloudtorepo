# Security Policy

## Supported versions

The latest release on the `main` branch is the only supported version.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Report privately by emailing the details to the maintainer via the contact form at
[andrewbaker.ninja](https://andrewbaker.ninja). Include:

- A description of the vulnerability and its potential impact
- Steps to reproduce
- Any suggested remediation

You can expect an acknowledgement within 72 hours and a fix or mitigation plan within
14 days for confirmed issues.

## Scope

Terraclaim is a collection of Bash scripts that call the AWS CLI and Terraform on your
local machine using your own credentials. It does not run as a service, store credentials,
or make network calls beyond what the AWS CLI and Terraform do normally.

Relevant security considerations:

- **Generated files** (`imports.tf`, `backend.tf`, `generated.tf`) may contain resource IDs,
  ARNs, and configuration details. Treat them as sensitive and do not commit them to public
  repositories without review.
- **State files** (`terraform.tfstate`) contain full resource configuration including secrets.
  Always use a private S3 backend with encryption enabled (`--state-bucket`).
- **Cross-account role assumption** (`--role`) uses short-lived STS credentials. Ensure the
  IAM role has the minimum required read-only permissions.
