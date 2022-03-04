#!/bin/bash -xe
# RUN AS ROOT
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 
  exit 1
fi

set -x

swapoff -a

# 서버단에서 내려줘야 함.
if [[ -z "$API_SERVER_ADDR" ]]
then
  echo "API_SERVER_ADDR is not set. abort"
  exit 1
fi

# 서버단에서 내려줘야 함.
if [[ -z "$JOIN_TOKEN" ]]
then
  echo "JOIN_TOKEN is not set. abort"
  exit 1
fi

# 서버단에서 내려줘야 함.
KUBERNETES_VERSION=${KUBERNETES_VERSION:-latest}
KUBERNETES_CNI_VERSION=${KUBERNETES_CNI_VERSION:-latest}
CONTAINERD_VERSION=${CONTAINERD_VERSION:-latest}
NODE_HOSTNAME=$(hostname)

echo
echo ==============================
echo KUBE VERSION: $KUBERNETES_VERSION
echo KUBE CNI VERSION: $KUBERNETES_CNI_VERSION
echo CONTAINERD VERSION: $CONTAINERD_VERSION
echo ==============================
echo

# worker 파일 다운
echo "[Donwload worker.yaml]"
curl -O https://raw.githubusercontent.com/AI-Ocean/kubernetes-install-scripts/main/worker.yaml
echo "Done."

sed -i 's/JOIN_TOKEN/'"$JOIN_TOKEN"'/g' worker.yaml
sed -i 's/API_SERVER_ADDR/'"$API_SERVER_ADDR"'/g' worker.yaml
sed -i 's/NODE_HOSTNAME/'"$NODE_HOSTNAME"'/g' worker.yaml

echo "[Install Prerequest packages]"
apt-get update
apt-get install -y apt-transport-https curl nfs-common

echo "[Containerd Install]"
if [ "$CONTAINERD_VERSION" = "latest" ]
then
  apt-get install -y containerd
else
  apt-get install -y containerd=$CONTAINERD_VERSION
fi

cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
EOF

sudo sysctl --system

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd

echo "[Kubernetes install]"

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list

apt-get update

if [ "$KUBERNETES_VERSION" = "latest" ]
then
  apt-get install -y kubelet kubeadm kubectl
else
  apt-get install -y kubelet=$KUBERNETES_VERSION \
    kubeadm=$KUBERNETES_VERSION \
    kubectl=$KUBERNETES_VERSION
fi

echo "[Kubernetes CNI install]"
if [ "$KUBERNETES_CNI_VERSION" = "latest" ]
then
  apt-get install -y kubernetes-cni
else
  apt-get install -y kubernetes-cni=$KUBERNETES_CNI_VERSION
fi

echo "[Kubernetes API Server Health Check]"
until $(curl --output /dev/null --silent --fail https://$API_SERVER_ADDR:6443/healthz -k)
do
    printf '.'
    sleep 5
done

echo "API Server is running!"

echo "[Joining]"
# Run kubeadm
kubeadm join --config worker.yaml
echo "Done."
