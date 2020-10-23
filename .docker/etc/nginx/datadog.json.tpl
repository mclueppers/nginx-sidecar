{
  "environment": "{{ default "none" .DD_ENV }}",
  "service": "{{ default "nginx" .OPENTRACING_SERVICE_NAME }}",
  "operation_name_override": "{{ default "nginx.handle" .OPENTRACING_OPERATION_NAME }}",
  "agent_host": "{{ default "datadog" .DATADOG_HOST }}",
  "agent_port": 8126
}
