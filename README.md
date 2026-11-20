# GitHub-Actions-CICD

A production-style GitHub Actions CI/CD capstone that builds and tests a Python web application, publishes one immutable artifact, and promotes that exact artifact through Development, Staging, and Production with GitHub Environment approval gates and real AWS EC2 deployments.

## Architecture

```text
Pull request / Push to main
          |
          v
   Reusable CI workflow
   - Checkout source
   - Python syntax validation
   - Unit tests (including HTTP health endpoint)
   - Package app.py
   - Generate SHA-256 checksum
   - Upload app-package-<commit-sha>
          |
          | Push/manual run on main only
          v
      DEV environment
      EC2 deployment + health check
          |
          v
   STAGING environment
   Required reviewer approval
   EC2 deployment + health check
          |
          v
  PRODUCTION environment
   Required reviewer approval
   EC2 deployment + health check
```

The CI workflow builds the artifact once. Each deployment stage downloads the same commit-SHA artifact and verifies its checksum; it does not rebuild the application. The reusable deployment workflow uses SSH to copy the package to the environment's EC2 host, installs/updates a systemd service, switches the active release, and checks the `/health` endpoint. If the health check fails, the remote script attempts to restore the previous release.

## Repository structure

```text
.
├── .github/
│   └── workflows/
│       ├── ci-cd.yml
│       ├── reusable-ci.yml
│       └── reusable-deploy.yml
├── scripts/
│   └── deploy_ec2.sh
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
| Push to main | Yes | Yes | Yes, after dev approval/deploy | Yes, after staging approval/deploy |
| Manual run on main | Yes | Yes | Yes, after dev approval/deploy | Yes, after staging approval/deploy |

Each deployment job depends on the previous stage. A failed build, deployment, or health check prevents later stages from running. Staging and Production pause for their configured GitHub Environment reviewers.

## One-time AWS EC2 preparation

Prepare one EC2 instance per environment (recommended) or deliberately isolate each environment on separate ports and paths on a shared host.

1. Launch Ubuntu 22.04/24.04 EC2 instances.
2. Create/use an SSH key pair. Add the public key to the EC2 user's `~/.ssh/authorized_keys`.
3. Ensure the GitHub runner can reach the instance on the SSH port (normally TCP 22). Restrict the security-group source to trusted runner egress ranges or use a self-hosted runner/VPN; do not open SSH to the whole internet as a permanent configuration.
4. The deployment user must be able to run `sudo` without an interactive password for `apt-get`, `mkdir`, `chown`, `tee`, `ln`, and `systemctl`. The script installs Python 3, curl, and tar if needed.
5. The application listens on the configured application port (default 8000). Permit inbound application traffic only from the intended load balancer/client network if external access is required. The pipeline health check runs locally on the EC2 host.

The deployment script uses `/opt/github-actions-cicd/<environment>/releases/<commit-sha>`, a `current` symlink, and a systemd service named `github-actions-cicd-<environment>`.

## GitHub Environments, variables and secrets

Open **Settings → Environments** and create these exact environment names:

- `dev`
- `staging`
- `production`

For **each** environment, add the following Environment variables:

| Variable | Example | Purpose |
|---|---|---|
| `EC2_HOST` | `54.12.34.56` | EC2 public IP or DNS |
| `EC2_USER` | `ubuntu` | SSH login user |
| `EC2_SSH_PORT` | `22` | SSH port; optional, defaults to 22 |
| `APP_PORT` | `8000` | App listening port; optional, defaults to 8000 |
| `HEALTHCHECK_PATH` | `/health` | Local health endpoint; optional, defaults to /health |

For **each** environment, add these Environment secrets:

| Secret | Value |
|---|---|
| `EC2_SSH_KEY` | Full PEM private key contents for the matching EC2 host |
| `EC2_KNOWN_HOSTS` | Pinned SSH host-key line for that host |

Generate a known-hosts line from a trusted network/console and verify its fingerprint against the EC2 host before saving it. Example command (run from a trusted machine): `ssh-keyscan -p 22 -H EC2_PUBLIC_IP`. Do not disable host-key checking or blindly trust an unverified scan.

Use a separate host/key per environment where possible. Never commit PEM files, private keys, or secret values to the repository. The reusable deployment job declares the target environment itself, so that environment's secrets and variables are available to that job after its protection rules pass.

### Approval gates

For `staging` and `production`:

1. Open **Settings → Environments → staging**.
2. Enable **Required reviewers** and select the authorized reviewer(s).
3. Save protection rules.
4. Repeat for **production**.
5. Optionally restrict deployment branches to `main`.

The YAML references the environments, but reviewers and protection rules are configured in GitHub Settings by a repository administrator. A workflow-created environment does not automatically receive reviewer rules.

**Plan visibility note:** GitHub's current documentation says required reviewers are available for public repositories on current plans; for private repositories, availability depends on the plan. Check the repository's visibility and plan before relying on manual approval gates.

## Runners, jobs and reusable workflows

- Runner: `ubuntu-latest`.
- `build-test`: calls `reusable-ci.yml` to compile, test, package and upload the release artifact.
- `deploy-dev`: calls `reusable-deploy.yml` after CI on main pushes/manual runs.
- `deploy-staging`: runs after successful Dev deployment and its approval.
- `deploy-production`: runs after successful Staging deployment and its approval.
- `reusable-ci.yml`: shared CI logic.
- `reusable-deploy.yml`: shared EC2 deployment logic.
- `ci-cd.yml`: orchestrates triggers, dependencies and promotion order.

## Artifact integrity and promotion

CI creates `app-package.tar.gz` and `app-package.tar.gz.sha256`, then uploads them together as `app-package-<github.sha>`. Every stage downloads that exact artifact and executes `sha256sum --check` before transfer. The app is never rebuilt between Dev, Staging and Production.

Artifacts are retained for 14 days in this demo. Increase retention or publish releases to durable artifact storage if your rollback window requires it.

## Application endpoints

- `GET /`: returns a greeting.
- `GET /health`: returns JSON with `status=healthy` and the application version.

The service binds to `0.0.0.0` on the configured port and is managed by systemd on EC2.

## Rollback

The EC2 deployment script records the previous active release before switching the `current` symlink. If the new service fails its local health check, it switches the symlink back and restarts the previous release. For a manual rollback, deploy the earlier retained commit artifact through the same protected environment workflow. Keep known-good artifacts for the required rollback period and verify application logs/health after rollback.

## Troubleshooting

| Symptom | Likely cause | Resolution |
|---|---|---|
| Workflow does not start | Event/branch does not match trigger | Check Actions tab and branch filters in `ci-cd.yml`. |
| Unit tests fail | Application behavior or test expectation is incorrect | Read the assertion and reproduce with `python -m unittest discover -v`. |
| Artifact not found | CI did not upload it or artifact name differs | Confirm CI succeeded and the SHA-based name matches. |
| Checksum verification fails | Package/checksum mismatch | Rebuild from the intended commit; never bypass verification. |
| Deployment waits | Environment approval is pending | An authorized reviewer must approve the deployment. |
| EC2 variables/secrets are empty | They were added at repository level or to a different environment | Add them under the matching `dev`, `staging`, or `production` environment. |
| SSH permission denied | Wrong user/key or public key missing from `authorized_keys` | Verify matching environment key, username and EC2 authorized_keys. |
| Host key verification fails | Pinned known-hosts value is wrong/stale | Verify the host fingerprint and update `EC2_KNOWN_HOSTS`. |
| sudo asks for a password | Deployment user lacks non-interactive sudo | Configure narrowly scoped non-interactive sudo for required deployment commands. |
| Health check fails | Port conflict, service error, or app did not start | Check `sudo systemctl status github-actions-cicd-<env>` and `sudo journalctl -u github-actions-cicd-<env> -n 100`. |
| Later stage is skipped | Previous deployment failed or workflow is not on main | Inspect dependencies, event and branch conditions. |

## Run locally

Requires Python 3.12 or compatible.

```bash
python -m py_compile app.py test_app.py
python -m unittest discover -v
python app.py --host 127.0.0.1 --port 8000
curl http://127.0.0.1:8000/health
```

## Assignment checklist

- [x] Workflow triggered by push and pull_request events
- [x] Multiple jobs with explicit dependencies and runner configuration
- [x] Automated build and unit-test stages with visible pass/fail status
- [x] Environment variables and secrets consumed by deployment workflow
- [x] Artifact published by CI and consumed by all deployment stages
- [x] Reusable CI and deployment workflows
- [x] dev, staging, and production environments referenced
- [x] Approval gates supported through GitHub Environment protection rules (admin setup required)
- [x] Same packaged artifact promoted through all stages
- [x] README covers behavior, assumptions, rollback and troubleshooting
- [x] EC2 deployment, systemd service and health check implemented

## Important setup boundary

The repository now contains the EC2 deployment implementation. A successful live deployment still requires you to create/prepare the EC2 target(s), configure the per-environment variables and secrets, and configure reviewer protection rules in GitHub Settings. Those account/infra settings cannot be safely guessed or created by committing workflow YAML.
