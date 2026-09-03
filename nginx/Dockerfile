FROM nginx:1.27-alpine@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10

RUN apk add --no-cache openssl curl

COPY nginx/entrypoint.sh /usr/local/bin/dsh-nginx-entrypoint
COPY nginx/http.conf /opt/dsh-nginx/http.conf
COPY nginx/https.conf /opt/dsh-nginx/https.conf

RUN chmod 0755 /usr/local/bin/dsh-nginx-entrypoint

ENTRYPOINT ["/usr/local/bin/dsh-nginx-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
