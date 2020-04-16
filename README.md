# nginx-sidecar

Container meant to run as a sidecar for exisiting application without SSL support. Ideal use case is for example acting as a reverse proxy for Nodejs application.

## Configuration

The container accepts a hanful of environment variables that will configure Nginx accordingly during boot time

| Environment variable | Required | Default value          | Description |
|:---------------------|:---------|:-----------------------|:------------|
| APP_BASE_PATH        | No       | /                      | Set the base path that will be matched in order to proxy to the backend app | 
| APP_IP               | No       | 127.0.0.1              | IP/address of the backend app. |
| APP_PORT             | No       | 8080                   | Port the backend app listens on |
| LISTEN_PORT          | No       | 80                     | Port Nginx listens to in case of no SSL offloading |
| LISTEN_PORT_SSL      | No       | 443                    | Port Nginx listens to in case of SSL offloading |
| SSL_OFFLOADING       | No       | false                  | Control SSL offloading |
| SSL_CRT              | No       | /etc/nginx/ssl/tls.crt | Path to the SSL/TLS certificate |
| SSL_KEY              | No       | /etc/nginx/ssl/tls.key | Path to the SSL/TLS private key |

This reverse proxy will listen on either `LISTEN_PORT` or `LISTEN_PORT_SSL` port depending on the value of `SSL_OFFLOADING`. You have to mount the SSL/TLS certificate pair in order to use SSL offloading. To increase entropy this container is using a pre-generated DH param file. It is strongly recommended to replace it/mount a new one when running in production. The file itself is located in `/etc/nginx/dhparam.pem`

## Building the container

This project comes with Makefile to ease building and execution of the container. Simply run

```shell
make build
```

to get a container built.

## Running the container

You can test the container by running

```shell
make run logs
```

once you have a local copy built. If you want to test SSL offloading then run 

```shell
make sslcert
make run_with_ssl logs
```

This way you're going to generate a self-signed cert for use by the container.
