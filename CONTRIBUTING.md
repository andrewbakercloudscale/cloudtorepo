# Contributing to Terraclaim

Thank you for your interest in contributing!

## How to contribute

### Reporting bugs

Open an issue using the **Bug report** template.  Include the output of
`--debug`, your AWS CLI version, Terraform version, OS, and Bash version.

### Requesting a new service

Open an issue using the **New service request** template.  Providing the exact
`aws` CLI commands needed to list resources and the Terraform import ID format
significantly speeds up implementation.

### Submitting a pull request

1. Fork the repository and create a branch from `main`.
2. Make your changes.
3. Ensure ShellCheck passes locally (the pre-commit hook does this automatically — install with `./scripts/install-hooks.sh`):
   ```bash
   shellcheck --severity=warning terraclaim.sh drift.sh reconcile.sh report.sh run.sh sync.sh lib/common.sh tests/*.bats
   ```
4. Run the bats test suite (requires `bats-core` — `brew install bats-core`):
   ```bash
   bats tests/
   ```
5. Open a pull request with a clear description of the change and why it is
   needed.

---

## Adding support for a new service

Each service is implemented as a single `export_<service>()` function in
`terraclaim.sh`.  Follow the pattern of an existing exporter:

1. **List resources** using the AWS CLI with `--output text`.
2. **Build `imports` and `types` arrays** — each pair is a Terraform resource
   address and its import ID.
3. **Write files** by calling `write_backend_tf`, `write_imports_tf`, and
   `write_resources_tf`.
4. **Register the function** in the `dispatch_service` case statement.
5. **Add the service name** to the `SERVICES` default at the top of the script.
6. **Add a matching `scan_<service>()` function in `drift.sh`** — same AWS CLI
   calls but populating `LIVE_PAIRS` only (no file I/O). Register it in
   `scan_service` and add to the `SERVICES` default in `drift.sh`.
7. **Add bats tests** in `tests/terraclaim.bats` — at minimum one test that
   mocks the AWS response and asserts the expected resource type appears in
   `imports.tf`.
8. **Document** the service in the README supported-services table and the
   services grid in `index.html`, then run `./sync.sh` to deploy the site.

### Services that require manual pagination

Some AWS CLI commands do not support AWS CLI's built-in auto-pagination and
require `--max-results` as a mandatory parameter (maximum 60). For these,
use a `NextToken` loop instead of a plain `while read` pipeline:

```bash
local _token="" _out
while true; do
  local _args=("myservice" "list-resources" "--max-results" "60" "--region" "${region}" "--output" "json")
  [[ -n "${_token}" ]] && _args+=("--next-token" "${_token}")
  _out=$(aws "${_args[@]}" 2>/dev/null) || break
  while IFS=$'\t' read -r id name; do
    [[ -z "${id}" ]] && continue
    local slug; slug=$(slugify "${name:-${id}}")
    imports+=("aws_myservice_resource.${slug}" "${id}")
    types+=("aws_myservice_resource.${slug}")
  done < <(echo "${_out}" | jq -r '.Resources[]? | "\(.Id)\t\(.Name)"' 2>/dev/null || true)
  _token=$(echo "${_out}" | jq -r '.NextToken // empty' 2>/dev/null) || true
  [[ -z "${_token}" ]] && break
done
```

Known services that require this pattern: `cognito-idp list-user-pools`,
`cognito-identity list-identity-pools`.

### Minimal example skeleton

```bash
export_myservice() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [myservice] listing resources..."
  while IFS=$'\t' read -r resource_id name; do
    [[ -z "${resource_id}" ]] && continue
    local slug; slug=$(slugify "${name:-${resource_id}}")
    imports+=("aws_myservice_resource.${slug}" "${resource_id}")
    types+=("aws_myservice_resource.${slug}")
  done < <(aws myservice list-resources \
    --region "${region}" \
    --query 'Resources[].[ResourceId, Name]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && return
  log "  [myservice] found $((${#imports[@]}/2)) resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "myservice"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}
```

---

## Code style

- Use `set -euo pipefail`.
- Quote all variable expansions.
- Prefer `[[ ]]` over `[ ]`.
- Use `local` for all function-scoped variables.
- Suppress expected errors with `2>/dev/null || true` rather than ignoring
  `set -e`.
- Run ShellCheck before submitting — CI will enforce it.

---

## Commit messages

Use the conventional commits format:

```
feat: add support for aws_wafv2_web_acl
fix: handle empty paginator response for SSM parameters
docs: add IAM permissions section to README
```
