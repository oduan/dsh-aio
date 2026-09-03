FROM nginx:1.27-alpine

RUN apk add --no-cache openssl

COPY nginx/entrypoint.sh /usr/local/bin/dsh-nginx-entrypoint
COPY nginx/http.conf /opt/dsh-nginx/http.conf
COPY nginx/https.conf /opt/dsh-nginx/https.conf

RUN chmod 0755 /usr/local/bin/dsh-nginx-entrypoint

ENTRYPOINT ["/usr/local/bin/dsh-nginx-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
