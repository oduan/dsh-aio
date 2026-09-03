#!/bin/sh
set -eu

: "${NGINX_SELF_SIGNED_CERT:=true}"
: "${NGINX_SERVER_NAME:=localhost}"
: "${NGINX_BASIC_AUTH_USER:=admin}"
: "${NGINX_BASIC_AUTH_HASH:?NGINX_BASIC_AUTH_HASH must be set}"
: "${NGINX_IP_ALLOWLIST_ENABLED:=false}"
: "${NGINX_IP_ALLOWLIST:=}"
: "${NGINX_CERT_DAYS:=36500}"
: "${DSH_TRUSTED_HOST:=}"

case "$NGINX_BASIC_AUTH_HASH" in
    ""|REPLACE_WITH_APR1_HASH|CHANGE_ME*)
        printf '%s\n' 'NGINX_BASIC_AUTH_HASH must be replaced with a real hash' >&2
        exit 1
        ;;
esac

case "$NGINX_BASIC_AUTH_USER" in
    ""|*[!A-Za-z0-9._-]*)
        printf '%s\n' 'NGINX_BASIC_AUTH_USER contains unsupported characters' >&2
        exit 1
        ;;
esac

case "$NGINX_SERVER_NAME" in
    ""|*[!A-Za-z0-9.:-]*)
        printf '%s\n' 'NGINX_SERVER_NAME contains unsupported characters' >&2
        exit 1
        ;;
esac

if [ -n "$DSH_TRUSTED_HOST" ]; then
    case "$NGINX_SERVER_NAME" in
        *:*) expected_trusted_host="[$NGINX_SERVER_NAME]:3080" ;;
        *) expected_trusted_host="$NGINX_SERVER_NAME:3080" ;;
    esac
    if [ "$DSH_TRUSTED_HOST" != "$expected_trusted_host" ]; then
        printf 'DSH_TRUSTED_HOST must match %s\n' "$expected_trusted_host" >&2
        exit 1
    fi
fi

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
                */0*)
                    printf '%s\n' 'NGINX_IP_ALLOWLIST must not contain a universal /0 network' >&2
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
        mkdir -p /etc/nginx/certs
        certificate_marker=/etc/nginx/certs/.server-name
        certificate_file=/etc/nginx/certs/server.crt
        certificate_key=/etc/nginx/certs/server.key
        regenerate_certificate=true
        certificate_key_matches() {
            [ "$(openssl x509 -in "$certificate_file" -pubkey -noout 2>/dev/null)" = \
                "$(openssl pkey -in "$certificate_key" -pubout 2>/dev/null)" ]
        }
        certificate_matches_server_name() {
            openssl x509 -in "$certificate_file" -noout -ext subjectAltName 2>/dev/null \
                | grep -q 'Subject Alternative Name' || return 1
            case "$NGINX_SERVER_NAME" in
                *:*) openssl x509 -in "$certificate_file" -noout -checkip "$NGINX_SERVER_NAME" >/dev/null 2>&1 ;;
                *[!0-9.]*) openssl x509 -in "$certificate_file" -noout -checkhost "$NGINX_SERVER_NAME" >/dev/null 2>&1 ;;
                *) openssl x509 -in "$certificate_file" -noout -checkip "$NGINX_SERVER_NAME" >/dev/null 2>&1 ;;
            esac
        }
        if [ -s "$certificate_file" ] \
            && [ -s "$certificate_key" ] \
            && [ -s "$certificate_marker" ] \
            && openssl x509 -in "$certificate_file" -noout -checkend 0 >/dev/null 2>&1 \
            && certificate_key_matches \
            && certificate_matches_server_name; then
            recorded_server_name=
            recorded_cert_days=
            recorded_server_name=$(sed -n '1p' "$certificate_marker")
            recorded_cert_days=$(sed -n '2p' "$certificate_marker")
            if [ "$recorded_server_name" = "$NGINX_SERVER_NAME" ] \
                && [ "$recorded_cert_days" = "$NGINX_CERT_DAYS" ]; then
                regenerate_certificate=false
            fi
        fi

        if [ "$regenerate_certificate" = true ]; then
            case "$NGINX_SERVER_NAME" in
                *:*) certificate_san="IP:${NGINX_SERVER_NAME}" ;;
                *[!0-9.]*) certificate_san="DNS:${NGINX_SERVER_NAME}" ;;
                *) certificate_san="IP:${NGINX_SERVER_NAME}" ;;
            esac
            temporary_key="${certificate_key}.tmp"
            temporary_certificate="${certificate_file}.tmp"
            rm -f "$temporary_key" "$temporary_certificate"
            openssl req -x509 -nodes -newkey rsa:2048 -days "$NGINX_CERT_DAYS" \
                -keyout "$temporary_key" \
                -out "$temporary_certificate" \
                -subj "/CN=${NGINX_SERVER_NAME}" \
                -addext "subjectAltName=${certificate_san}"
            mv -f "$temporary_key" "$certificate_key"
            mv -f "$temporary_certificate" "$certificate_file"
            printf '%s\n%s\n' "$NGINX_SERVER_NAME" "$NGINX_CERT_DAYS" > "$certificate_marker"
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
