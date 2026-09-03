# DeepSeek Harness (dsh) all-in-one 镜像
# 基于 Debian 13，root 用户；Compose 会将 dsh 工作区切换到 /workspace
FROM debian:13@sha256:f324c7ff54321e8d9c588493a20244965938ce0aa50bbd1022d38010e9ffc4b1

USER root
WORKDIR /root

ENV DEBIAN_FRONTEND=noninteractive

# 基础工具（git 供 agent 使用）+ Node.js 22 LTS（NodeSource 仓库）
ARG NODESOURCE_SETUP_SHA256=575583bbac2fccc0b5edd0dbc03e222d9f9dc8d724da996d22754d6411104fd1
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        git \
    && curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh \
    && printf '%s  %s\n' "$NODESOURCE_SETUP_SHA256" /tmp/nodesource_setup.sh | sha256sum -c - \
    && bash /tmp/nodesource_setup.sh \
    && rm /tmp/nodesource_setup.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 固定 DeepSeek Harness CLI 版本，避免重建时 CLI 参数和依赖漂移。
# 远程管理只允许通过 Nginx Basic Auth 暴露的可信 authority。
ARG DSH_ALLOW_REMOTE_PRIVILEGED=true
COPY docker/enable-remote-privileged.js /tmp/enable-remote-privileged.js
RUN npm install -g @deepseek-ai/dsh@0.1.1-rc.2 \
    && if [ "$DSH_ALLOW_REMOTE_PRIVILEGED" = "true" ]; then \
        node /tmp/enable-remote-privileged.js; \
    fi \
    && rm /tmp/enable-remote-privileged.js \
    && npm cache clean --force

# dsh 当前版本出于安全原因不允许绑定 0.0.0.0。
# Nginx 与 dsh 共享网络命名空间，Nginx 对外监听 3080，dsh 使用内部 3081。
CMD ["dsh", "web", "--host", "127.0.0.1", "--port", "3081", "--no-open"]
