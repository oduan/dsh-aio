# dsh AIO

将 [DeepSeek Harness（dsh）](https://github.com/deepseek-ai/deepseek-harness) 打包为 Docker 镜像，并通过 Nginx 反向代理提供 Web UI。

## 架构

```text
浏览器 → Nginx（HTTP 或自签 HTTPS/认证）→ 127.0.0.1:3081 → dsh
```

当前 dsh 版本出于安全原因只允许绑定 `127.0.0.1`。Compose 让 Nginx 和 dsh 共享网络命名空间：Nginx 对外发布 `3080`，dsh 只监听内部的 `3081`，dsh 服务本身没有 `ports` 映射。

## 前置条件

- Linux 主机（推荐）；macOS 或 Windows 需要 Docker Desktop 和 Bash
- Docker Engine 和 Docker Compose Plugin（启动 Compose 时需要）
- `openssl`（初始化脚本生成 Basic Auth 哈希；`--no-start` 模式也需要）
- 如果需要公网访问，确保防火墙允许宿主机 `3080/tcp`

## 启动 dsh

### 推荐：使用初始化脚本

新环境只需要：

```bash
git clone https://github.com/oduan/dsh-aio.git
cd dsh-aio
./scripts/setup.sh
```

脚本会依次询问访问用的域名/IP、Basic Auth 用户名和密码，以及是否启用 IP 白名单，然后：

- 创建 `.dsh/`、`workspace/` 和 `nginx/certs/` 本地目录
- 生成 APR1 Basic Auth 哈希，不保存明文密码
- 写入权限为 `600` 的 `.env`
- 默认启用 HTTPS 自签名证书和远程 settings API
- 构建并启动 Compose

脚本默认使用 `localhost` 和 HTTPS。远程服务器上请在提示中填写用户实际访问的域名或 IP，例如 `dsh.example.com` 或 `203.0.113.10`。

只想生成配置而暂不启动：

```bash
./scripts/setup.sh --no-start
```

`--no-start` 不会检查或调用 Docker；稍后再执行 `docker compose up -d --build` 即可启动。

使用普通 HTTP（不推荐在公网使用）：

```bash
./scripts/setup.sh --http
```

已有 `.env` 时脚本默认拒绝覆盖；确认要重新生成时才使用 `--force`。

### 手动配置

复制并编辑环境变量文件，并创建 dsh 数据目录：

```bash
cp .env.example .env
mkdir -p .dsh workspace nginx/certs
```

将 `DSH_TRUSTED_HOST` 改为浏览器访问时的 authority，必须包含外部端口 `3080`：

```dotenv
DSH_TRUSTED_HOST=dsh.example.com:3080
```

生成 Nginx Basic Auth 的 APR1 哈希并写入 `.env`（不要把密码放在命令行参数中）：

```bash
read -r -s -p 'Basic Auth password: ' password
printf '\n'
printf '%s\n' "$password" | openssl passwd -apr1 -stdin
unset password
```

将输出填入 `NGINX_BASIC_AUTH_HASH`，并保留单引号，因为哈希包含 `$` 字符：

```dotenv
NGINX_BASIC_AUTH_HASH='$apr1$...$...'
```

`.env` 已被 `.gitignore` 排除，不要提交它。

默认启用 HTTPS 自签名证书和远程特权 API。`NGINX_SELF_SIGNED_CERT=true` 时，Nginx 在首次启动时生成并保存有效期约 100 年的自签名证书；显式设为 `false` 时使用普通 HTTP。证书只在容器启动时检查，不会自动续期。`NGINX_SERVER_NAME` 只填写主机名或 IP，不要带端口；它必须与 `DSH_TRUSTED_HOST` 的主机部分一致。

远程访问设置、凭据和其他特权 API 默认由 `DSH_ALLOW_REMOTE_PRIVILEGED=true` 启用；设为 `false` 可恢复 dsh 的 loopback-only 行为。这是构建期开关，只应在 Nginx Basic Auth 已启用时使用；修改后必须重新构建镜像。

IP 白名单默认关闭。设置 `NGINX_IP_ALLOWLIST_ENABLED=true` 并在 `NGINX_IP_ALLOWLIST` 中填写逗号分隔的 IP 或 CIDR 后，白名单来源无需 Basic Auth，其他来源仍需要用户名和密码。例如：`192.0.2.10,198.51.100.0/24`。当前端口直接发布到宿主机时，Nginx 能看到真实客户端 IP；如果前面还有其他反向代理，需要额外配置真实 IP 转发，否则白名单匹配到的会是前置代理地址。

构建并启动：

```bash
docker compose up -d --build
```

检查状态和日志：

```bash
docker compose ps
docker compose logs -f dsh
```

访问地址：

```bash
# HTTP 模式
http://dsh.example.com:3080

# 自签 HTTPS 模式（浏览器会提示证书不受信任）
https://dsh.example.com:3080
```

Nginx 已在 Compose 中运行，并将唯一的宿主机端口 `3080` 反向代理到共享网络命名空间中的 dsh `3081`。Nginx 同时保留 Basic Auth 和 WebSocket 所需的代理头。

## SSL 证书

当前默认使用自签名证书，不需要在新环境手动签发。Nginx 首次启动时执行以下流程：

1. 使用 `NGINX_SERVER_NAME` 作为证书的 CN 和 SAN。
2. 域名生成 `DNS:` SAN，IPv4/IPv6 地址生成 `IP:` SAN。
3. 将 `server.crt`、`server.key` 和访问地址标记文件保存到项目目录的 `nginx/certs/`。
4. 后续重启复用通过密钥、SAN、主机名和有效期校验的证书；如果 `NGINX_SERVER_NAME` 或 `NGINX_CERT_DAYS` 改变，或证书/私钥校验失败，会重新生成。

新环境推荐直接运行 `./scripts/setup.sh`，证书由容器自动生成。浏览器第一次访问自签名证书时会显示“不受信任”提示，这是预期行为；自签名证书提供加密，但不会提供受公共 CA 信任的身份。

证书有效期默认是 36500 天（约 100 年），可通过 `NGINX_CERT_DAYS` 修改。项目不执行自动续期；需要强制重新生成时删除以下文件后重启：

```bash
rm -f nginx/certs/server.crt nginx/certs/server.key nginx/certs/.server-name
docker compose up -d --force-recreate
```

当前项目不自动申请 Let's Encrypt。需要浏览器完全信任的公网 HTTPS 时，应在前面使用带有正式证书的反向代理，或后续为 Nginx 增加 ACME/DNS-01 部署；不要把证书私钥提交到 GitHub。将 `NGINX_SELF_SIGNED_CERT=false` 只会切换为普通 HTTP，不会签发证书。

## 数据持久化

默认不创建 Docker 命名数据卷。dsh 的配置、凭据和会话保存在工程目录的 `.dsh/`，由 Compose bind mount 到容器的 `/root/.dsh`。

工作区由 `DSH_WORKSPACE_PATH` bind mount 到 `/workspace`，容器重建后代码和生成文件仍会保留。

自签名证书保存在项目目录 `nginx/certs/`；删除 `server.crt`、`server.key` 和 `.server-name` 后重启，Nginx 会重新生成证书。

`.dsh/` 可能包含凭据和会话数据，已加入 `.gitignore`，不要提交到代码仓库。

## 常用操作

```bash
# 停止并保留 .dsh 数据
docker compose down

# 重新构建并更新
docker compose up -d --build

# 查看日志
docker compose logs -f dsh
```

## 安全说明

- 不要把 dsh 改为监听 `0.0.0.0`，当前版本会拒绝该配置。
- 对外暴露的 `3080` 是 Nginx；dsh 的 `3081` 没有端口映射，仅在共享网络命名空间内可见。
- `DSH_ALLOW_REMOTE_PRIVILEGED=true` 会让特权 API 跟随 `.env` 中的可信 authority；不要绕过 Nginx Basic Auth 或直接暴露 dsh。
- `NGINX_IP_ALLOWLIST_ENABLED=true` 会让列出的来源绕过 Basic Auth；不要配置 `0.0.0.0/0` 或 `::/0`，并确保白名单本身是可信网络。
- 自签名证书只提供加密，不提供受信任的身份验证；公网生产环境应使用正式证书。
- `NGINX_CERT_DAYS` 必须是正整数；修改证书名称或有效期后，删除旧证书再重启。
- `NGINX_BASIC_AUTH_HASH` 和 `.dsh/` 可能包含敏感数据，不要提交或打印它们。
- `--trusted-host` 只负责浏览器来源信任，不是身份认证。
