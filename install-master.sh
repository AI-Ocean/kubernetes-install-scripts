#!/bin/bash -xe
# !! RUN AS ROOT

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
DOCKER_VERSION=${DOCKER_VERSION:-latest}

# master 파일 다운
echo [Donwload master.yaml]
curl -O https://raw.githubusercontent.com/AI-Ocean/kubernetes-install-scripts/main/master.yaml
echo Done.

sed -i $(eval echo 's/JOIN_TOKEN/$JOIN_TOKEN/g') master.yaml
sed -i $(eval echo 's/ADVERTISE_ADDR/$ADVERTISE_ADDR/g') master.yaml

echo [Install Prerequest packages]
apt-get update
apt-get install -y apt-transport-https curl

echo [Docker Install]
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list

wget -qO- get.docker.com | sh

if [ "$DOCKER_VERSION" != "latest" ]
then
  apt-get install -y --allow-downgrades docker-ce=$DOCKER_VERSION
  service docker restart
fi

echo [Kubernetes install]
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
