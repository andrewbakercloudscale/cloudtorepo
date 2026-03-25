## What does this PR do?

<!-- Brief description of the change -->

## Type of change

- [ ] Bug fix
- [ ] New service (`export_*` + `scan_*` functions)
- [ ] New feature
- [ ] Docs / website update
- [ ] Refactor / code quality

## Checklist

- [ ] `bash -n cloudtorepo.sh drift.sh run.sh reconcile.sh` passes
- [ ] ShellCheck passes locally: `shellcheck cloudtorepo.sh drift.sh run.sh reconcile.sh examples/*.sh`
- [ ] New service added to **both** `cloudtorepo.sh` (`export_*`) and `drift.sh` (`scan_*`)
- [ ] New service documented in `README.md` services table and `index.html` services grid
- [ ] `./sync.sh` run if `index.html` was changed
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
