# 概要
oracle cloud infrastractureの無料枠でkubernetes（[k3s](https://rancher.com/docs/k3s/latest/en/)）を構築するための手順。

# コンソールの操作
## VMの作成
同じスペックのサーバーを2台用意する。
デフォルトからの変更点は以下。

- VMの名称は`server`・`agent`（任意だが後段で区別しやすいように）
- OSはUbuntu18.04
- NetworkSecurityGroupを指定（事前に適切に作成する必要あり）
- 公開キー・ファイルの選択からローカルの`id_rsa.pub`をアップロード

# ローカルでの操作
## sshの設定
`~/.ssh/config`を以下のようにするれば、`ssh k3s-server`だけでssh接続できる。

```
Host k3s-server
    HostName xxx.xxx.xx.xx
    User ubuntu

Host k3s-agent
    HostName yyy.yyy.yy.yy
    User ubuntu
    ProxyCommand ssh -W %h:%p k3s-server
```

## ロードバランサの作成
デフォルトからの変更点は以下。

- AlwaysFreeの構成オプションを表示
- バックエンドの追加でagentを選択
- ヘルスチェックポリシーは緩和してもよい（k3s側でlivenessProbeなどを設定する前提）

# VMの操作
## k3s-server
k3s-serverで以下を実行（`k3s_server.sh`）。

```sh
# firewall setting
sudo iptables -I FORWARD -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I FORWARD -d 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT   -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT   -d 10.0.0.0/8 -j ACCEPT
sudo /etc/init.d/netfilter-persistent save
sudo /etc/init.d/netfilter-persistent reload # may not be necessary

# install k3s
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 640

# create k3s group
sudo groupadd k3s
sudo usermod -aG k3s `whoami`
sudo chgrp k3s /etc/rancher/k3s/k3s.yaml
sudo chgrp k3s /var/lib/rancher/k3s/server/node-token

# taint master node
sudo kubectl taint nodes server master=true:NoExecute

# install helm
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
sudo apt-get install apt-transport-https --yes
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
#helm repo add stable https://charts.helm.sh/stable

# environment variable
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> $HOME/.bashrc
```

スクリプトについて何点か補足。
- [ドキュメント](https://rancher.com/docs/k3s/latest/en/installation/installation-requirements/#networking)に記載のポートを許可するだけでは不具合があったため、VCNの通信は許可している。
- グループの作成はこの[issue](https://github.com/rancher/k3s/issues/389)に従った（helmからinsecureだと警告されるが無視）。`sudo`なしの`kubectl get all`でエラーを確認したが[ここ](https://github.com/kubernetes/kubernetes/issues/94362)によると問題ない。
- taintはserverへのスケジュールを禁止する目的で、この[issue](https://github.com/rancher/k3s/issues/389)に従っている。

## k3s-agent
**ローカルで**以下を実行（`k3s_agent_local.sh`）。

```sh
K3S_SERVER_IP=`ssh -G k3s-server | grep -E 'hostname\s+[0-9.]+' | grep -o -E '[0-9.]+'`
K3S_SERVER_TOKEN=`ssh k3s-server sudo cat /var/lib/rancher/k3s/server/node-token`
ssh k3s-agent echo  "export K3S_SERVER_IP=$K3S_SERVER_IP >> /home/ubuntu/.bashrc"
ssh k3s-agent echo  "export K3S_SERVER_TOKEN=$K3S_SERVER_TOKEN >> /home/ubuntu/.bashrc"
```

k3s-agentで以下を実行（`k3s_agent.sh`）。

```sh
# firewall setting
sudo iptables -I FORWARD -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I FORWARD -d 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT   -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT   -d 10.0.0.0/8 -j ACCEPT
sudo /etc/init.d/netfilter-persistent save
sudo /etc/init.d/netfilter-persistent reload

# install k3s
curl -sfL https://get.k3s.io | K3S_URL=https://$K3S_SERVER_IP:6443 K3S_TOKEN=$K3S_SERVER_TOKEN sh -
```

# メモ
- k3sのアンインストール方法は[こちら](https://rancher.com/docs/k3s/latest/en/installation/uninstall/)
- NodePort・LoadBalancerなどの比較は[この記事](https://www.thebookofjoel.com/bare-metal-kubernetes-ingress)が詳しい。
- CI/CDについても検討したが、以下の理由から無料枠での実装は厳しい。
    - k3s側でGithubを監視する方法、GithubActionsからk3sにアクセスする方法の2通りが考えられる
    - 前者の方向性だと[ArgoCD](https://argoproj.github.io/argo-cd/)などのツールは存在するがメモリ不足
    - 後者はIPアドレスを指定する必要があるが、GithubActionsのIPアドレスが分からないため難しい（[参考](https://github.com/rancher/k3s/issues/1381)）
- https対応も検討したが、[cert-manager](https://cert-manager.io/)の起動がメモリ不足で難しい
    - もし実装するなら[この記事](https://opensource.com/article/20/3/ssl-letsencrypt-k3s)が参考になりそう。
