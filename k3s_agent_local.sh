#!/bin/bash
cd $(dirname $0)

K3S_SERVER_IP=`ssh -G k3s-server | grep -E 'hostname\s+[0-9.]+' | grep -o -E '[0-9.]+'`
K3S_SERVER_TOKEN=`ssh k3s-server sudo cat /var/lib/rancher/k3s/server/node-token`
ssh k3s-agent echo  "export K3S_SERVER_IP=$K3S_SERVER_IP >> /home/ubuntu/.bashrc"
ssh k3s-agent echo  "export K3S_SERVER_TOKEN=$K3S_SERVER_TOKEN >> /home/ubuntu/.bashrc"
