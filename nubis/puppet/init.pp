import 'packages.pp'

import 'apt.pp'
import 'confd.pp'
import 'consul.pp'
import 'fluentd.pp'
import 'jq.pp'
import 'postfix.pp'
import 'datadog.pp'
import 'mig.pp'
import 'credstash.pp'
import 'consulate.pp'
import 'nubis_lib.pp'
import 'proxy.pp'

# Simple node liveness check
include nubis_discovery
nubis::discovery::check { 'ping':
  check => "ping -c1 google.com",
  interval => "10s",
}
