# Container Security With Tetragon
This project is a demonstration for a talk called "Container Security with Tetragon"

[Talk Slides](https://alanyoshida.github.io/presentation/slides/ContainerSecurityTetragon.html#/title-slide)

## Requirements
- go
- yq
- git
- gum
- kind
- kubectl
- docker
- helm
- dnsmasq

## Setup

```bash
# Create kind cluster, and configure everything
make build
```

## Commands in the talk

```bash
# Enter Tetragon
kubectl exec -ti -n kube-system ds/tetragon -c tetragon -- bash

# Get events
tetra getevents -o compact --pods xwing

# all in one
kubectl exec -ti -n kube-system ds/tetragon -c tetragon -- tetra getevents -o compact --pods xwing

# Execute inside xwing pod
kubectl exec -ti xwing -- bash -c 'curl https://ebpf.io/applications/#tetragon'

kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing


# Trace Points
sudo ls /sys/kernel/debug/tracing/events

nm -D /bin/bash
```

## Tools

### Hubble
http://hubble.tetragon.cluster/?namespace=default

### Prometheus
Example Query:
`rate(tetragon_events_total{type="PROCESS_EXEC",namespace="default", binary="/usr/bin/bash"}[1m])`

http://prometheus.tetragon.cluster/graph?g0.expr=rate(tetragon_events_total%7Btype%3D%22PROCESS_EXEC%22%2Cnamespace%3D%22default%22%2C%20binary%3D%22%2Fusr%2Fbin%2Fbash%22%7D%5B1m%5D)&g0.tab=0&g0.display_mode=lines&g0.show_exemplars=0&g0.range_input=15m


### Grafana
Username: admin
Password: admin

http://grafana.tetragon.cluster/