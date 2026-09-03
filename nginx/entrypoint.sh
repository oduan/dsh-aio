#!/bin/sh
set -eu

: "${NGINX_SELF_SIGNED_CERT:=true}"
: "${NGINX_SERVER_NAME:=localhost}"
: "${NGINX_BASIC_AUTH_USER:=admin}"
: "${NGINX_BASIC_AUTH_HASH:?NGINX_BASIC_AUTH_HASH must be set}"
: "${NGINX_IP_ALLOWLIST_ENABLED:=false}"
: "${NGINX_IP_ALLOWLIST:=}"
: "${NGINX_CERT_DAYS:=365}"

case "$NGINX_BASIC_AUTH_HASH" in
    ""|REPLACE_WITH_APR1_HASH|CHANGE_ME*)
        printf '%s\n' 'NGINX_BASIC_AUTH_HASH must be replaced with a real hash' >&2
        exit 1
        ;;
esac

case "$NGINX_CERT_DAYS" in
    ""|0*|*[!0-9]*)
        printf '%s\n' 'NGINX_CERT_DAYS must be a positive integer' >&2
        exit 1
        ;;
esac

umask 077
printf '%s:%s\n' "$NGINX_BASIC_AUTH_USER" "$NGINX_BASIC_AUTH_HASH" > /etc/nginx/.htpasswd
chown nginx:nginx /etc/nginx/.htpasswd
chmod 0640 /etc/nginx/.htpasswd

allowlist_file=/etc/nginx/ip-allowlist.conf
: > "$allowlist_file"

case "$NGINX_IP_ALLOWLIST_ENABLED" in
    true|1|yes|on)
        allowlist_count=0
        set -f
        for entry in $(printf '%s' "$NGINX_IP_ALLOWLIST" | tr ',' ' '); do
            case "$entry" in
                *[!0-9A-Fa-f:./]*)
                    printf '%s\n' 'NGINX_IP_ALLOWLIST contains an invalid IP or CIDR' >&2
                    exit 1
                    ;;
            esac
            printf 'allow %s;\n' "$entry" >> "$allowlist_file"
            allowlist_count=$((allowlist_count + 1))
        done
        set +f
        if [ "$allowlist_count" -eq 0 ]; then
            printf '%s\n' 'NGINX_IP_ALLOWLIST must contain at least one IP or CIDR when enabled' >&2
            exit 1
        fi
        printf '%s\n' 'deny all;' 'satisfy any;' >> "$allowlist_file"
        ;;
    false|0|no|off)
        printf '%s\n' 'satisfy all;' > "$allowlist_file"
        ;;
    *)
        printf '%s\n' 'NGINX_IP_ALLOWLIST_ENABLED must be true or false' >&2
        exit 1
        ;;
esac
chmod 0644 "$allowlist_file"

case "$NGINX_SELF_SIGNED_CERT" in
    true|1|yes|on)
        case "$NGINX_SERVER_NAME" in
            ""|*[!A-Za-z0-9.:-]*)
                printf '%s\n' 'NGINX_SERVER_NAME contains unsupported characters' >&2
                exit 1
                ;;
        esac
        mkdir -p /etc/nginx/certs
        certificate_marker=/etc/nginx/certs/.server-name
        regenerate_certificate=true
        if [ -s /etc/nginx/certs/server.crt ] \
            && [ -s /etc/nginx/certs/server.key ] \
            && [ -s "$certificate_marker" ] \
            && openssl x509 -in /etc/nginx/certs/server.crt -noout -checkend 0 >/dev/null 2>&1; then
            recorded_server_name=
            IFS= read -r recorded_server_name < "$certificate_marker" || true
            if [ "$recorded_server_name" = "$NGINX_SERVER_NAME" ]; then
                regenerate_certificate=false
            fi
        fi

        if [ "$regenerate_certificate" = true ]; then
            case "$NGINX_SERVER_NAME" in
                *:*) certificate_san="IP:${NGINX_SERVER_NAME}" ;;
                *[!0-9.]*) certificate_san="DNS:${NGINX_SERVER_NAME}" ;;
                *) certificate_san="IP:${NGINX_SERVER_NAME}" ;;
            esac
            openssl req -x509 -nodes -newkey rsa:2048 -days "$NGINX_CERT_DAYS" \
                -keyout /etc/nginx/certs/server.key \
                -out /etc/nginx/certs/server.crt \
                -subj "/CN=${NGINX_SERVER_NAME}" \
                -addext "subjectAltName=${certificate_san}"
            printf '%s\n' "$NGINX_SERVER_NAME" > "$certificate_marker"
        fi
        cp /opt/dsh-nginx/https.conf /etc/nginx/conf.d/default.conf
        ;;
    false|0|no|off)
        cp /opt/dsh-nginx/http.conf /etc/nginx/conf.d/default.conf
        ;;
    *)
        printf '%s\n' 'NGINX_SELF_SIGNED_CERT must be true or false' >&2
        exit 1
        ;;
esac

exec "$@"
