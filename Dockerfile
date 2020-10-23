ARG ALPINE_VERSION=3.12
FROM subfuzion/envtpl as envtpl

FROM alpine:${ALPINE_VERSION}
ARG ALPINE_VERSION=3.12
ENV \
  APP_IP="127.0.0.1" \
  APP_BASE_PATH="/" \
  ENABLE_OPENTRACING="false" \
  OPENTRACING_SERVICE_NAME="nginx" \
  DATADOG_HOST="datadog" \
  DISABLE_METRICS_LOG="false" \
  HEALTH_CHECK_PATH="/healthz" \
  LOG_SAMPLING="false" \
  LOG_SAMPLING_RATE="1%" \
  METRICS_PATH="/metrics" \
  SSL_OFFLOADING="false" \
  SSL_CRT="/etc/nginx/ssl/tls.crt" \
  SSL_KEY="/etc/nginx/ssl/tls.key" \
  WEBSOCKET_SUPPORT="false" \
  WEBSOCKET_PATH="/" \
  WORKER_CONNECTIONS="1024"

ADD https://repos.dobrev.it/alpine/dobrevit.rsa.pub /etc/apk/keys/dobrevit.rsa.pub

RUN echo "https://repos.dobrev.it/alpine/v$ALPINE_VERSION/" | tee -a /etc/apk/repositories \
    && apk --update --no-cache add nginx nginx-mod-http-headers-more nginx-mod-http-opentracing dd-opentracing-cpp runit haveged openssl libstdc++ \
    && mkdir -p /run/nginx/ /etc/nginx/ssl \
    && haveged && openssl dhparam -out /etc/nginx/dhparam.pem 2048 \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

COPY --from=envtpl /bin/envtpl /usr/bin/envtpl
COPY .docker/ /
ENTRYPOINT [ "/sbin/runit-wrapper" ]
