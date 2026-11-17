# GitHub-Actions-CICD

A production-style GitHub Actions CI/CD capstone demonstrating automated validation, reusable workflows, immutable artifact promotion, and staged deployments.

## Architecture

```text
Pull request / Push
        |
        v
  Reusable CI workflow
  - Checkout source
  - Python syntax validation
  - Unit tests
  - Package release archive
  - Generate SHA-256 checksum
  - Upload versioned artifact
        |
        | Push to main only
        v
  Development (dev)
        |
        v
  Staging (approval gate)
        |
        v
  Production (approval gate)
```

The same artifact, named `app-package-<commit-sha>`, is downloaded and checksum-verified in every environment. The deployment workflow is intentionally platform-neutral: it prepares a release payload and manifest. Connect the final deployment step to an actual hosting platform (for example, an EC2 host, Kubernetes cluster, or cloud deployment service) to perform a live application rollout.

## Repository structure

```text
.
├── .github/
│   └── workflows/
│       ├── ci-cd.yml
│       ├── reusable-ci.yml
│       └── reusable-deploy.yml
├── app.py
├── test_app.py
├── .gitignore
└── README.md
```

## Pipeline behavior

| Event | CI build/test | Dev | Staging | Production |
|---|---:|---:|---:|---:|
| Pull request to main | Yes | No | No | No |
| Push to non-main branch | Yes | No | No | No |
| Push to main | Yes | Yes | Yes, after dev | Yes, after staging |
| Manual run on main | Yes | Yes | Yes, after dev | Yes, after staging |

Each deployment job depends on the previous stage. A failed stage prevents later stages from running. GitHub Environment protection rules can pause a deployment until an authorized reviewer approves it.

## Initial GitHub configuration

1. Open **Settings → Environments**.
2. Create environments named exactly `dev`, `staging`, and `production`.
3. For `staging` and `production`, enable **Required reviewers** and select the authorized reviewer(s). Save the protection rules.
4. Optionally configure deployment branch restrictions so only `main` can deploy to staging and production.
5. Add non-sensitive configuration under **Settings → Secrets and variables → Actions → Variables**. Suggested variable: `DEPLOYMENT_TARGET`.
6. Add deployment credentials under **Secrets** only when integrating a real hosting platform. Suggested secret name: `DEPLOY_TOKEN`. Never commit credentials to this repository.

The workflow references GitHub Environments by name. Environment approval rules are repository settings and must be configured by a repository administrator; they cannot be enabled merely by committing YAML.

## Runners, jobs and dependencies

- Runner: `ubuntu-latest`.
- `build-test`: reusable CI workflow; validates source, runs unit tests, creates the release archive and checksum, and uploads the artifact.
- `deploy-dev`: runs after CI on pushes to main.
- `deploy-staging`: runs only after successful development deployment.
- `deploy-production`: runs only after successful staging deployment.
- Reusable logic lives in `reusable-ci.yml` and `reusable-deploy.yml`; the orchestrator lives in `ci-cd.yml`.

## Artifact and promotion strategy

The CI job creates `app-package.tar.gz` and `app-package.tar.gz.sha256`. Both are uploaded as one artifact whose name includes the triggering commit SHA. Every deployment stage downloads that same artifact and validates its checksum before preparing the release payload. The pipeline does not rebuild separately for each environment.

## Configuration and secrets

- Workflow-level permissions follow least privilege: repository contents are read-only.
- Environment-specific variables belong in GitHub Environment variables.
- Credentials belong in GitHub Environment secrets, not in YAML or source files.
- Do not print secret values in logs.
- Add only the permissions required by the selected deployment provider when connecting a real target.

## Rollback considerations

1. Identify the last known-good commit SHA and its corresponding retained artifact.
2. Re-run the deployment workflow for the affected environment using the known-good artifact, or revert the source change and promote the new commit through the normal pipeline.
3. Verify the deployment health and application logs after rollback.
4. Keep release artifacts available for the required rollback window; this example retains artifacts for 14 days.
5. For a real deployment, implement an atomic release/symlink or platform-native rollout and health check before switching traffic.

## Troubleshooting

| Symptom | Likely cause | Resolution |
|---|---|---|
| Workflow does not start | Event/branch does not match trigger | Check Actions tab and branch filters in `ci-cd.yml`. |
| Unit tests fail | Application behavior or test expectation is incorrect | Read the failing assertion and reproduce with `python -m unittest discover -v`. |
| Artifact not found | CI did not upload it, or artifact name differs | Confirm the CI job succeeded and both workflows use the same commit-SHA artifact name. |
| Checksum verification fails | Package changed or checksum file is mismatched | Rebuild from the intended commit; do not bypass checksum validation. |
| Staging/production waits | Required reviewer approval is pending | Review and approve the deployment in the GitHub Actions run, if authorized. |
| Environment has no approval gate | Required reviewers were not configured | Configure the environment protection rule in repository Settings. |
| Permission denied during real deployment | Deployment identity lacks target permissions | Grant least-privilege permissions and store credentials as environment secrets. |
| Deployment job is skipped | Previous job failed or push was not to main | Inspect job dependencies and event/ref conditions. |

## Run locally

Requires Python 3.12 or compatible.

```bash
python -m py_compile app.py test_app.py
python -m unittest discover -v
python app.py
mkdir -p dist
tar -czf dist/app-package.tar.gz app.py README.md
cd dist
sha256sum app-package.tar.gz > app-package.tar.gz.sha256
sha256sum --check app-package.tar.gz.sha256
```

## Assignment checklist

- [x] Workflow triggered by push and pull_request events
- [x] Multiple jobs with explicit dependencies and runner configuration
- [x] Automated build and unit-test stages with visible pass/fail status
- [x] Variables/secrets strategy documented; no credentials committed
- [x] Artifact published by CI and consumed by deployment stages
- [x] Reusable CI and deployment workflows
- [x] dev, staging, and production environments referenced
- [x] Approval gates supported through GitHub Environment protection rules (admin configuration required)
- [x] Same packaged artifact promoted through all stages
- [x] Pipeline behavior, assumptions, and rollback documented
- [x] Troubleshooting guide included

## Important implementation boundary

The repository contains a working CI pipeline and a platform-neutral CD demonstration. Environment reviewer rules must be configured in GitHub Settings, and a real hosting provider/target must be connected before claiming that an application has been deployed to live infrastructure.
