# Security

This project runs DeepSeek Harness with access to a local workspace and persistent credentials. Treat the host and the `.dsh/` directory as sensitive.

## Deployment requirements

- Keep `.env`, `.dsh/`, `workspace/`, and `nginx/certs/` out of version control.
- Keep HTTPS enabled for any network that is not fully trusted.
- Use a strong Basic Auth password even when an IP allowlist is enabled.
- Keep `DSH_ALLOW_REMOTE_PRIVILEGED=true` behind Nginx authentication and do not publish dsh's internal port directly.
- Do not use `0.0.0.0/0` or `::/0` as an IP allowlist entry.

The default self-signed certificate is valid for approximately 100 years and encrypts traffic, but it is not trusted by browsers or public certificate authorities. It is checked when the container starts and is not automatically renewed. For public deployments, use a trusted certificate at the TLS termination point.

## Reporting a vulnerability

Please do not publish credentials, private keys, session data, or a working exploit in a public issue. Use GitHub's private security reporting feature for this repository when available; otherwise contact the repository owner privately before disclosure.
