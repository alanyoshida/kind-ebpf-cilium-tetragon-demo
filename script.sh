#!/bin/bash
# set -x;

source _helper.sh

## CONFIGS
CLUSTER_NAME="cilium-tetragon"
CONTEXT_NAME="kind-$CLUSTER_NAME"
KIND_DNS="tetragon.cluster"

check_dependencies(){
    check go
    check yq
    check git
    check gum
    check kind
    check kubectl
    check docker
    check helm
    check dnsmasq
}

# up (){
#   check_context "$CLUSTER_NAME"
#   if ex=$(gum confirm "Quer iniciar o Tilt ?"); then
#     tilt up
#   fi
# }

create_kind (){
    # CREATE KIND CLUSTER
    if ex=$(gum confirm "Quer criar um novo cluster kind ?"); then
      bold "Creating kind cluster"
      bash ./kind-with-registry.sh "$CLUSTER_NAME" \
      kubectl wait -A --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=1m
    fi

    # gum spin --show-output --title "Waiting 10s for cluster ..." -- sleep 10
}

configure_nginx (){
    # Configure nginx ingress
    check_context "$CLUSTER_NAME"
    if [ $? -eq 0 ]; then
      if ex=$(gum confirm "Deseja configurar o nginx ingress?"); then
        # kubectl apply -f charts/nginx-ingress/
        bold "Installing nginx ingress"
        kubectl apply -f cluster-configs/nginx-ingress.yaml
        info "Waiting for ready condition"
        # kubectl wait -n ingress-nginx --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=4m
      fi
    fi
}

configure_metallb (){
    check_context "$CLUSTER_NAME"
    if [ $? -eq 0 ]; then
      if ex=$(gum confirm "Deseja configurar o metallb?"); then
          bold "Configuring metallb"
          DOCKER_CIDR=$(docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}')
          DOCKER_CIDR_2_OCTECTS=$(echo $DOCKER_CIDR | sed -E 's/([0-9]{0,3}\.[0-9]{1,3}).*/\1/')
          yq -i -y ".metallb.IPAddressPool.addresses[0]=\"$DOCKER_CIDR_2_OCTECTS.254.100-$DOCKER_CIDR_2_OCTECTS.254.250\"" charts/metallb/values.yaml
          kubectl apply -f cluster-configs/metallb.yaml
          info "Waiting for ready condition"
          kubectl wait -n metallb-system --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=1m
          helm install metallb charts/metallb/
      fi
    fi
}

configure_dnsmasq (){
    if ex=$(gum confirm "Quer configurar o dnsmasq?"); then
    sudo sed -i '1s/^/nameserver 127.0.0.1\n/' /etc/resolv.conf
    sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.$(date +"%d-%m-%y_%H-%M-%S").BAK
sudo cat <<EOF | sudo tee /etc/dnsmasq.conf
bind-interfaces
listen-address=127.0.0.1
server=8.8.8.8
server=8.8.4.4
conf-dir=/etc/dnsmasq.d/,*.conf
EOF
        check_context "$CLUSTER_NAME"
        if [ $? -eq 0 ]; then
          LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
          if [ -d "$LB_IP" ]; then
            echo -e "\n LB_IP=$LB_IP"
            gum spin --show-output --title "Waiting 10s for cluster ..." -- sleep 10
            LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
          fi
          # point kind.cluster domain (and subdomains) to our load balancer
          echo "address=/$KIND_DNS/$LB_IP" | sudo tee /etc/dnsmasq.d/$CLUSTER_NAME.k8s.conf
          # restart dnsmasq
          sudo systemctl restart dnsmasq
        fi
    fi
}

setup (){
    # DEPENDENCIES
    bold "Checking project dependencies ..."

    check_dependencies

    create_kind

    configure_nginx

    configure_metallb

    configure_dnsmasq

    # K8S CONFIG
    # up
}

install_gum() {
  read -p "Do you want to install gum? (N/y): " -n 1 -r
  echo    # move to a new line
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    go install github.com/charmbracelet/gum@latest
  fi
}

print_help(){
__usage="
${BOLD}Usage: script.sh [OPTIONS]${CLEARFORMAT}

${BOLD}Options:${CLEARFORMAT}
    setup, build   Configure everything, create cluster and start tilt
    dependencies   Check if you have the requirements
    -h, --help     Print Help
"
echo -e "$__usage"
}

print_start(){
__usage="${BOLDBLUE}
=================
# Script start  #
=================${CLEARFORMAT}
"

echo -e "$__usage"
}

print_start

case "$1" in

  # up)
  #   up
  #   ;;
  setup|build)
    setup
    ;;
  dependencies)
    check_dependencies
    ;;
  install)
    install_gum
    ;;
  metallb)
    configure_metallb
    ;;
  dnsmasq)
    configure_dnsmasq
    ;;
  context)
    check_context "$CLUSTER_NAME"
    ;;
  "--help"|"-h")
    print_help
    ;;
  *)
    echo -e "\e[31merror: Parameter not found.\e[0m"
    print_help

esac

# echo -e "\e[33mScript end\e[0m"