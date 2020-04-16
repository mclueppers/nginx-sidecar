.PHONY: build sslcert run run_with_ssl logs sh stop

build:
	@docker build -t nginx-sidecar .

sslcert:
	@openssl req \
       -newkey rsa:2048 -nodes -keyout domain.key \
       -x509 -days 365 -out domain.crt \
	   -subj "/C=GB/ST=London/L=London/O=HM Example Copmpany/CN=172-17-0-2.nip.io"

run:
	@docker run --rm -d \
		-e APP_PORT=8080 \
		-e SSL_OFFLOADING="false" \
		-v `pwd`/domain.key:/etc/nginx/ssl/tls.key:ro \
		-v `pwd`/domain.crt:/etc/nginx/ssl/tls.crt:ro \
		--name nginx-sidecar \
		nginx-sidecar

run_with_ssl:
	@docker run --rm -d \
		-e APP_PORT=8080 \
		-e SSL_OFFLOADING="true" \
		-v `pwd`/domain.key:/etc/nginx/ssl/tls.key:ro \
		-v `pwd`/domain.crt:/etc/nginx/ssl/tls.crt:ro \
		--name nginx-sidecar \
		nginx-sidecar

sh:
	@docker exec -it nginx-sidecar sh

logs:
	@docker logs -f nginx-sidecar

stop:
	@docker stop nginx-sidecar