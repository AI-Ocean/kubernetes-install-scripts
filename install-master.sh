#!/bin/bash -xe

set -x

swapoff -a

function get_random_string () {
	random_string=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w $1 | head -n 1)
	echo $random_string
}

# 서버단에서 내려줘야 함.
ADVERTISE_NET_DEV=${ADVERTISE_NET_DEV:-enp0s8}
ADVERTISE_ADDR=$(ifconfig $ADVERTISE_NET_DEV | grep 'inet' | cut -d: -f2 | awk '{print $2}')
JOIN_TOKEN=${JOIN_TOKEN:-"$(get_random_string 6).$(get_random_string 16)"}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-latest}
KUBERNETES_CNI_VERSION=${KUBERNETES_CNI_VERSION:-latest}
DOCKER_VERSION=${DOCKER_VERSION:-latest}

sed -i $(eval echo 's/JOIN_TOKEN/$JOIN_TOKEN/g') master.yaml
sed -i $(eval echo 's/ADVERTISE_ADDR/$ADVERTISE_ADDR/g') master.yaml

apt-get update
apt-get install -y apt-transport-https curl

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list

wget -qO- get.docker.com | sh

if [ "$DOCKER_VERSION" != "latest" ]
then
  apt-get install -y --allow-downgrades docker-ce=$DOCKER_VERSION
  service docker restart
fi

if [ "$KUBERNETES_VERSION" = "latest" ]
then
  apt-get install -y kubelet kubeadm kubectl
else
  apt-get install -y kubelet=$KUBERNETES_VERSION \
    kubeadm=$KUBERNETES_VERSION \
    kubectl=$KUBERNETES_VERSION
fi

if [ "$KUBERNETES_CNI_VERSION" = "latest" ]
then
  apt-get install -y kubernetes-cni
else
  apt-get install -y kubernetes-cni=$KUBERNETES_CNI_VERSION
fi

# Run kubeadm
kubeadm init \
  --config master.yaml

# Prepare kubeconfig file for download to local machine
sudo mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
sudo chown root:root /root/.kube/config