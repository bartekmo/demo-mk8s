# codeshell

Custom image for the browser IDE (code-server) on the demo cluster:
code-server plus the shell tools used in the demo, preinstalled.

| Tool | Auth (environment variables set by the code-server deployment) |
|---|---|
| `git` | credential helper via `GIT_CONFIG_*` -> `$GITLAB_TOKEN` |
| `glab` | `GITLAB_HOST`, `GITLAB_TOKEN` |
| GitLab Workflow extension | `GITLAB_WORKFLOW_INSTANCE_URL`, `GITLAB_WORKFLOW_TOKEN` |
| `kubectl`, `argocd` | added in a later step |

## Build and deploy

Every push to `main`:

1. **build** - builds the image with rootless BuildKit and pushes it to this
   project's container registry as `:<short-sha>` and `:latest`;
2. **deploy** - sets `image:` in [`deploy/code-server-values.yaml`](deploy/code-server-values.yaml)
   to the new tag. Argo CD reads that file for the IDE and rolls out the new
   shell (the IDE restarts; the home volume with your files is kept).

To roll back, set `image:` in that file to an earlier tag.

Tool versions are pinned as build args in the `Dockerfile`.
