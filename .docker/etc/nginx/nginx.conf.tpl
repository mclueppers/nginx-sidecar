# /etc/nginx/nginx.conf
{{/* This is a gotpl file and requires envtpl implementation in golang. */}}

user nginx;

# Set number of worker processes automatically based on number of CPU cores.
worker_processes auto;

# Enables the use of JIT for regular expressions to speed-up their processing.
pcre_jit on;

# Configures default error logger.
error_log /var/log/nginx/error.log warn;

# Includes files with directives to load dynamic modules.
include /etc/nginx/modules/*.conf;

events {
	# The maximum number of simultaneous connections that can be opened by
	# a worker process.
	worker_connections {{ default "1024" .WORKER_CONNECTIONS }};
}

http {
    # Includes mapping of file name extensions to MIME types of responses
    # and defines the default type.
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Name servers used to resolve names of upstream servers into addresses.
    # It's also needed when using tcpsocket and udpsocket in Lua modules.
    #resolver 208.67.222.222 208.67.220.220;

    # Don't tell nginx version to clients.
    server_tokens off;

    # Don't tell the world what application server we're using
    more_clear_headers Server X-Powered-By;

    # Specifies the maximum accepted body size of a client request, as
    # indicated by the request header Content-Length. If the stated content
    # length is greater than this size, then the client receives the HTTP
    # error code 413. Set to 0 to disable.
    client_max_body_size 50m;

    # Timeout for keep-alive connections. Server will close connections after
    # this time.
    keepalive_timeout 65;

    # Sendfile copies data between one FD and other from within the kernel,
    # which is more efficient than read() + write().
    sendfile on;

    # Don't buffer data-sends (disable Nagle algorithm).
    # Good for sending frequent small bursts of data in real time.
    tcp_nodelay on;

    # Causes nginx to attempt to send its HTTP response head in one packet,
    # instead of using partial frames.
    #tcp_nopush on;

    {{ if eq "true" .LOG_SAMPLING -}}
    split_clients $request_id $logme {
        {{ default "1%" .LOG_SAMPLING_RATE }}     1;
        *      0;
    }

    # map goes *outside* of the "server" block
    map $http_user_agent $ignore_ua {
        default                  0;
        "~Pingdom.*"             1;
        "~ELB-HealthChecker/.*"  1;
        "~kube-probe/.*"         1;
    }
    {{- end }}

    {{ if eq "true" .DISABLE_METRICS_LOG -}}
    map $http_user_agent $ignore_metrics_ua {
        default                  0;
        "~Prometheus.*"          1;
    }
    {{- end }}

    {{ if eq "true" (default "false" .WEBSOCKET_SUPPORT) -}}
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }
    {{- end }}

    {{ if eq "true" (default "false" .REALIP_ENABLED) -}}
    {{ range $cidr := splitList "," .REALIP_FROM }}
    set_real_ip_from  {{ $cidr }};
    {{ end }}
    real_ip_header {{ .REALIP_HEADER }};
    {{ if eq "true" (default "false" .REALIP_RECURSIVE) }}
    real_ip_recursive on;
    {{ else }}
    real_ip_recursive off;
    {{ end }}
    {{ end }}

    {{ if eq "true" (default "false" .ENABLE_OPENTRACING) -}}
    opentracing_load_tracer /usr/lib64/libdd_opentracing_plugin.so /etc/nginx/datadog.json;

    opentracing on;
    opentracing_tag http_user_agent $http_user_agent;
    opentracing_trace_locations off;
    opentracing_operation_name "$request_method $uri";

    # Propagate the active span context upstream, so that the trace can be
    # continued by the backend.
    # See http://opentracing.io/documentation/pages/api/cross-process-tracing.html
    opentracing_propagate_context;

    log_format nginx_log '$remote_addr - $http_x_forwarded_user [$time_local] "$request" '
        '$status $body_bytes_sent "$http_referer" '
        '"$http_user_agent" "$http_x_forwarded_for" '
        'dd.trace_id=$opentracing_context_x_datadog_trace_id dd.span_id=$opentracing_context_x_datadog_parent_id';

    # Sets the path, format, and configuration for a buffered log write.
    access_log /var/log/nginx/access.log nginx_log;
    {{- else }}
    # Specifies the main log format.
    log_format nginx_log '$remote_addr - $remote_user [$time_local] "$request" '
            '$status $body_bytes_sent "$http_referer" '
            '"$http_user_agent" "$http_x_forwarded_for"';

    # Sets the path, format, and configuration for a buffered log write.
    access_log /var/log/nginx/access.log nginx_log;
    {{- end }}

    {{ if eq "false" .SSL_OFFLOADING -}}
    server {
        listen {{ default "80" .LISTEN_PORT }} default_server;
        listen [::]:{{ default "80" .LISTEN_PORT }} default_server;

        error_page 502 /error-page-502.html;
        location = /error-page-502.html {
                root /var/www/errorpages;
                internal;
        }

        error_page 503 /error-page-503.html;
        location = /error-page-503.html {
                root /var/www/errorpages;
                internal;
        }

        error_page 504 /error-page-504.html;
        location = /error-page-504.html {
                root /var/www/errorpages;
                internal;
        }

        {{ if and (eq "true" (default "false" .WEBSOCKET_SUPPORT)) (not (eq (default "/" .APP_BASE_PATH) .WEBSOCKET_PATH)) }}
        location = {{ .WEBSOCKET_PATH }} {
            proxy_pass http://{{ default "127.0.0.1" .APP_IP }}:{{ default "8080" (default .APP_PORT .METRICS_PORT) }}$request_uri;
            proxy_connect_timeout       300;
            proxy_send_timeout          300;
            proxy_read_timeout          300;
            proxy_buffers               6 8192k;
            proxy_buffer_size           8192k;
            proxy_busy_buffers_size     8192k;
            proxy_http_version          1.1;
            proxy_set_header Upgrade    $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
        }
        {{ end }}

        location = {{ .METRICS_PATH }} {
            {{- if eq "true" .DISABLE_METRICS_LOG -}}
            if ($ignore_metrics_ua) {
                access_log          off;
            }
            {{- end }}
            proxy_pass              http://{{ default "127.0.0.1" .APP_IP }}:{{ default "8080" (default .APP_PORT .METRICS_PORT) }}$request_uri;
            proxy_connect_timeout   300;
            proxy_send_timeout      300;
            proxy_read_timeout      300;
            proxy_buffers           6 8192k;
            proxy_buffer_size       8192k;
            proxy_busy_buffers_size 8192k;
        }

        location = {{ .HEALTH_CHECK_PATH }} {
            {{- if and (eq "true" .LOG_SAMPLING) (not (eq .APP_BASE_PATH .HEALTH_CHECK_PATH)) -}}
            if ($ignore_ua) {
                access_log /var/log/nginx/access.log nginx_log if=$logme;
            }
            {{- end }}
            proxy_pass              http://{{ default "127.0.0.1" (default .APP_IP .HEALTH_CHECK_HOST) }}:{{ default "8080" (default .APP_PORT .HEALTH_CHECK_PORT) }}$request_uri;
            proxy_connect_timeout   300;
            proxy_send_timeout      300;
            proxy_read_timeout      300;
            proxy_buffers           6 8192k;
            proxy_buffer_size       8192k;
            proxy_busy_buffers_size 8192k;
        }

        location {{ default "/" .APP_BASE_PATH }} {
            proxy_pass              http://{{ default "127.0.0.1" .APP_IP }}:{{ default "8080" .APP_PORT }}$request_uri;
            proxy_connect_timeout   300;
            proxy_send_timeout      300;
            proxy_read_timeout      300;
            proxy_buffers           6 8192k;
            proxy_buffer_size       8192k;
            proxy_busy_buffers_size 8192k;
            {{- if and (eq "true" (default "false" .WEBSOCKET_SUPPORT)) (eq (default "/" .APP_BASE_PATH) .WEBSOCKET_PATH) }}
            proxy_set_header Upgrade    $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            {{ end }}
        }
    }
    {{ end }}

    {{ if eq "true" .SSL_OFFLOADING }}
    # Enable SSL session cache
    ssl_session_cache   shared:SSL:5m;
    ssl_session_timeout 1h;
    
    server {
        listen {{ default "443" .LISTEN_PORT_SSL }} ssl http2 default_server;
        listen [::]:{{ default "443" .LISTEN_PORT_SSL }} ssl http2 default_server;

        ssl_certificate     {{ .SSL_CRT }};
        ssl_certificate_key {{ .SSL_KEY }};
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_dhparam         /etc/nginx/dhparam.pem;
        ssl_ciphers         EECDH+CHACHA20:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5;
        
        error_page 502 /error-page-502.html;
        location = /error-page-502.html {
                root /var/www/errorpages;
                internal;
        }

        error_page 503 /error-page-503.html;
        location = /error-page-503.html {
                root /var/www/errorpages;
                internal;
        }

        error_page 504 /error-page-504.html;
        location = /error-page-504.html {
                root /var/www/errorpages;
                internal;
        }

        location = {{ .METRICS_PATH }} {
            {{ if eq "true" .DISABLE_METRICS_LOG -}}
            if ($ignore_metrics_ua) {
                access_log          off;
            }
            {{- end }}
            proxy_pass              http://{{ default "127.0.0.1" .APP_IP }}:{{ default "8080" (default .APP_PORT .METRICS_PORT) }}$request_uri;
            proxy_connect_timeout   300;
            proxy_send_timeout      300;
            proxy_read_timeout      300;
            proxy_buffers           6 8192k;
            proxy_buffer_size       8192k;
            proxy_busy_buffers_size 8192k;
        }

        location = {{ .HEALTH_CHECK_PATH }} {
            {{ if and (eq "true" .LOG_SAMPLING) (not (eq .APP_BASE_PATH .HEALTH_CHECK_PATH)) -}}
            if ($ignore_ua) {
                access_log /var/log/nginx/access.log nginx_log if=$logme;
            }
            {{- end }}
            proxy_pass              http://{{ default "127.0.0.1" (default .APP_IP .HEALTH_CHECK_HOST) }}:{{ default "8080" (default .APP_PORT .HEALTH_CHECK_PORT) }}$request_uri;
            proxy_connect_timeout   300;
            proxy_send_timeout      300;
            proxy_read_timeout      300;
            proxy_buffers           6 8192k;
            proxy_buffer_size       8192k;
            proxy_busy_buffers_size 8192k;
        }

        {{ if and (eq "true" (default "false" .WEBSOCKET_SUPPORT)) (not (eq (default "/" .APP_BASE_PATH) .WEBSOCKET_PATH)) }}
        location = {{ .WEBSOCKET_PATH }} {
            proxy_pass http://{{ default "127.0.0.1" .APP_IP }}:{{ default "8080" (default .APP_PORT .METRICS_PORT) }}$request_uri;
            proxy_connect_timeout       300;
            proxy_send_timeout          300;
            proxy_read_timeout          300;
            proxy_buffers               6 8192k;
            proxy_buffer_size           8192k;
            proxy_busy_buffers_size     8192k;
            proxy_http_version          1.1;
            proxy_set_header Upgrade    $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
        }
        {{ end }}

        location {{ default "/" .APP_BASE_PATH }} {
            proxy_pass              http://{{ default "127.0.0.1" .APP_IP }}:{{ default "8080" .APP_PORT }}$request_uri;
            proxy_connect_timeout   300;
            proxy_send_timeout      300;
            proxy_read_timeout      300;
            proxy_buffers           6 8192k;
            proxy_buffer_size       8192k;
            proxy_busy_buffers_size 8192k;
            {{- if and (eq "true" (default "false" .WEBSOCKET_SUPPORT)) (eq (default "/" .APP_BASE_PATH) .WEBSOCKET_PATH) }}
            proxy_set_header Upgrade    $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            {{ end }}
        }
    }
    {{- end }}
}
