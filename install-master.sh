#!/bin/bash -xe
# RUN AS ROOT
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 
  exit 1
fi

set -x

swapoff -a

function get_random_string () {
	random_string=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w $1 | head -n 1)
	echo $random_string
}

env

# 서버단에서 내려줘야 함.
ADVERTISE_NET_DEV=${ADVERTISE_NET_DEV:-enp0s8}
ADVERTISE_ADDR=$(ifconfig $ADVERTISE_NET_DEV | grep 'inet' | cut -d: -f2 | awk '{print $2}')
JOIN_TOKEN=${JOIN_TOKEN:-"$(get_random_string 6).$(get_random_string 16)"}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-latest}
KUBERNETES_CNI_VERSION=${KUBERNETES_CNI_VERSION:-latest}
CONTAINERD_VERSION=${CONTAINERD_VERSION:-latest}

# master 파일 다운
echo [Donwload master.yaml]
curl -O https://raw.githubusercontent.com/AI-Ocean/kubernetes-install-scripts/main/master.yaml
echo Done.

sed -i $(eval echo 's/JOIN_TOKEN/$JOIN_TOKEN/g') master.yaml
sed -i $(eval echo 's/ADVERTISE_ADDR/$ADVERTISE_ADDR/g') master.yaml

echo [Install Prerequest packages]
apt-get update
apt-get install -y apt-transport-https curl

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

echo [Kubernetes install]

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

echo [Kubernetes CNI install]
if [ "$KUBERNETES_CNI_VERSION" = "latest" ]
then
  apt-get install -y kubernetes-cni
else
  apt-get install -y kubernetes-cni=$KUBERNETES_CNI_VERSION
fi

# Run kubeadm
echo [Run kubeadm]
kubeadm init \
  --config master.yaml

# Prepare kubeconfig file for download to local machine
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config
