# Lumberjack ECS Device

![Continuous Integration](https://github.com/bdurand/lumberjack_ecs_device/workflows/Continuous%20Integration/badge.svg)
[![Maintainability](https://api.codeclimate.com/v1/badges/97e98dc4d3d2565a3208/maintainability)](https://codeclimate.com/github/bdurand/lumberjack_ecs_device/maintainability)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

This gem provides a logging device that produces JSON output that matches the standard fields defined for the [Elastic Common Schema](https://www.elastic.co/guide/en/ecs/current/ecs-reference.html). This allows logs to be sent seamlessly to Kibana or other servers that expect this format.

* The time will be sent as "@timestamp" with a precision in microseconds.

* The severity will be sent as "log.level" with a string label (DEBUG, INFO, WARN, ERROR, FATAL).

* The progname will be sent as "process.name"

* The pid will be sent as "process.pid".

* The message will be sent as "message". In addition, if the message is an exception, the error message, class, and backtrace will be sent as "error.message", "error.type", and "error.stack_trace".

* If the "error" tag contains an exception, it will be sent as "error.message", "error.type", and "error.stack_trace".

* A duration can be sent as a number of seconds in the "duration" tag or as a number of milliseconds in the "duration_ms" tag or as a number of microsectons in the "duration_micros" tag or as a number of nanoseconds in the "duration_ns" tag. The value will be sent as "event.duration" and converted to nanoseconds.

* All other log tags are sent as is. If a tag name includes a dot, it will be sent as a nested JSON structure.

This device extends from [`Lumberjack::JsonDevice`](). It is not tied to ECS or Kibana in any way other than that it is opinionated about how to map and format some log tags. It can be used with other services or pipelines without issue.

## Example

You could log an HTTP request to some of the ECS standard fields like this:

```ruby
logger.tag("http.request.method" => request.method, "url.full" => request.url) do
  logger.info("#{request.method} #{request.path} finished in #{elapsed_time} seconds",
    duration: elapsed_time,
    "http.response.status_code" => response.status
  )
end
```
