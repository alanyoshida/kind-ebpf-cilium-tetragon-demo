#!/bin/sh
set -o errexit

source _helper.sh

# 1. Create registry container unless it already exists
info "1. Create registry container unless it already exists"
reg_name='kind-registry'
reg_port='5001'
if [ "$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" != 'true' ]; then
  docker run \
    -d --restart=always -p "127.0.0.1:${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

## CONFIGS
CLUSTER_NAME=$1
CONTEXT_NAME="kind-$CLUSTER_NAME"

# 2. Create kind cluster with containerd registry config dir enabled
info "2. Create kind cluster $CLUSTER_NAME with containerd registry config dir enabled"
# TODO: kind will eventually enable this by default and this patch will
# be unnecessary.
#
# See:
# https://github.com/kubernetes-sigs/kind/issues/2875
# https://github.com/containerd/containerd/blob/main/docs/cri/config.md#registry-configuration
# See: https://github.com/containerd/containerd/blob/main/docs/hosts.md
cat <<EOF | kind create --name $CLUSTER_NAME cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
    - hostPath: /proc
      containerPath: /procHost
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  # extraPortMappings:
  # - containerPort: 80
  #   hostPort: 80
  #   protocol: TCP
  # - containerPort: 443
  #   hostPort: 443
  #   protocol: TCP
# - role: worker
# - role: worker
# - role: worker
networking:
  disableDefaultCNI: true
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
EOF

# 3. Add the registry config to the nodes
info "3. Add the registry config to the nodes"
#
# This is necessary because localhost resolves to loopback addresses that are
# network-namespace local.
# In other words: localhost in the container is not localhost on the host.
#
# We want a consistent name that works from both ends, so we tell containerd to
# alias localhost:${reg_port} to the registry container when pulling images
REGISTRY_DIR="/etc/containerd/certs.d/localhost:${reg_port}"
for node in $(kind get nodes --name $CLUSTER_NAME); do
  docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
  cat <<EOF | docker exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
[host."http://${reg_name}:5000"]
EOF
done

# 4. Connect the registry to the cluster network if not already connected
info "4. Connect the registry to the cluster network if not already connected"
# This allows kind to bootstrap the network but ensures they're on the same network
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
  docker network connect "kind" "${reg_name}"
fi

# 5. Document the local registry
info "5. Document the local registry"
# https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

info "7. Install Cilium"
check_context "$CLUSTER_NAME"
cilium install --version 1.15.5
cilium status --wait
# cilium connectivity test

info "8. Install Hubble"
cilium hubble enable --ui -n kube-system
kubectl -n kube-system apply -f cluster-configs/hubble-ui-ing.yaml

info "9. Install Prometheus/Grafana"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring  --create-namespace \
  --values cluster-configs/kube-prometheus-stack-values.yaml
  # --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
kubectl wait -n monitoring --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=2m
# kubectl -n monitoring apply -f cluster-configs/prometheus-ing.yaml
# kubectl -n monitoring apply -f cluster-configs/grafana-ing.yaml

info "10. Install Tetragon"
EXTRA_HELM_FLAGS=(--set tetragon.hostProcPath=/procHost) # flags for helm install
helm repo add cilium https://helm.cilium.io
helm repo update
helm install tetragon ${EXTRA_HELM_FLAGS[@]} cilium/tetragon -n kube-system \
  --values cluster-configs/tetragon-values.yaml
  # --set tetragonOperator.prometheus.serviceMonitor.enabled=true
kubectl rollout status -n kube-system ds/tetragon -w

info "11. Install Demo APP"
check_context "$CLUSTER_NAME"
kubectl create -f https://raw.githubusercontent.com/cilium/cilium/v1.15.3/examples/minikube/http-sw-app.yaml
