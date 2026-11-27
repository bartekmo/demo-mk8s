# code-server + demo shell tools
ARG CODE_SERVER_VERSION=4.146.0
FROM codercom/code-server:${CODE_SERVER_VERSION}

ARG KUBECTL_VERSION=v1.35.11
ARG ARGOCD_VERSION=v3.6.3
ARG GLAB_VERSION=1.133.0

USER root
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends ca-certificates curl jq git less vim-tiny bash-completion; \
  rm -rf /var/lib/apt/lists/*; \
  curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
  curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"; \
  curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.tar.gz" \
  | tar -xz -C /usr/local bin/glab; \
  chmod +x /usr/local/bin/kubectl /usr/local/bin/argocd /usr/local/bin/glab; \
  kubectl version --client; argocd version --client --short; glab version

RUN curl https://raw.githubusercontent.com/lacework/go-sdk/main/cli/install.sh | bash

USER coder
# extensions live in the (persistent) home volume at runtime, so they are
# installed by the deployment rather than baked in here
