# codeshell

Custom image for the browser IDE (code-server) on the demo cluster:
code-server plus the shell tools used in the demo, preinstalled.

| Tool | Auth (environment variables set by the code-server deployment) |
|---|---|
| `git` | credential helper via `GIT_CONFIG_*` -> `$GITLAB_TOKEN` |
| `glab` | `GITLAB_HOST`, `GITLAB_TOKEN` |
| GitLab Workflow extension | `GITLAB_WORKFLOW_INSTANCE_URL`, `GITLAB_WORKFLOW_TOKEN` |
| `kubectl`, `argocd` | added in a later step |

## Build

Every push to `main` builds the image with rootless BuildKit and pushes it to
this project's container registry as `:<short-sha>` and `:latest`.

Tool versions are pinned as build args in the `Dockerfile`.
