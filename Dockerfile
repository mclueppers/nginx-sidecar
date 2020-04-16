FROM subfuzion/envtpl as envtpl

FROM alpine:3.11

ENV \
  APP_IP="127.0.0.1" \
  APP_BASE_PATH="/" \
  SSL_OFFLOADING="false" \
  SSL_CRT="/etc/nginx/ssl/tls.crt" \
  SSL_KEY="/etc/nginx/ssl/tls.key"

RUN apk --update --no-cache add nginx nginx-mod-http-headers-more runit haveged openssl \
    && mkdir -p /run/nginx/ /etc/nginx/ssl \
    && haveged && openssl dhparam -out /etc/nginx/dhparam.pem 2048 \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

COPY --from=envtpl /bin/envtpl /usr/bin/envtpl
COPY .docker/ /
ENTRYPOINT [ "/sbin/runit-wrapper" ]