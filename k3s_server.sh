#!/bin/bash
cd $(dirname $0)

# firewall setting
sudo iptables -I FORWARD -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I FORWARD -d 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT   -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT   -d 10.0.0.0/8 -j ACCEPT
sudo /etc/init.d/netfilter-persistent save
sudo /etc/init.d/netfilter-persistent reload

# install k3s
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 640

# taint master node
sudo kubectl taint nodes server master=true:NoExecute

# create k3s group
sudo groupadd k3s
sudo usermod -aG k3s `whoami`
sudo chgrp k3s /etc/rancher/k3s/k3s.yaml
sudo chgrp k3s /var/lib/rancher/k3s/server/node-token

# install helm
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
sudo apt-get install apt-transport-https --yes
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
#helm repo add stable https://charts.helm.sh/stable

# environment variable
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> $HOME/.bashrc

# alias
echo 'alias k="kubectl"' >> $HOME/.bashrc
echo 'alias h="helm"' >> $HOME/.bashrc
