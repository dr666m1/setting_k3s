# 概要
oracle cloud infrastractureの無料枠でkubernetesを構築するための手順。

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

# VMの操作
## k3s-server
### k3sのインストール
以下のスクリプトを実行。

```sh
# firewall setting
sudo iptables -I FORWARD -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I FORWARD -d 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT   -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT   -d 10.0.0.0/8 -j ACCEPT
sudo /etc/init.d/netfilter-persistent save
sudo /etc/init.d/netfilter-persistent reload

# install k3s
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 640

# create k3s group
sudo groupadd k3s
sudo usermod -aG k3s `whoami`
sudo chgrp k3s /etc/rancher/k3s/k3s.yaml
sudo chgrp k3s /var/lib/rancher/k3s/server/node-token

# taint master node
sudo kubectl taint nodes server master=true:NoExecute
```

スクリプトについて何点か補足。
- [ドキュメント](https://rancher.com/docs/k3s/latest/en/installation/installation-requirements/#networking)に記載のポートを許可するだけでは不具合があったため、VCNの通信は許可している。
- グループの作成はこの[issue](https://github.com/rancher/k3s/issues/389)に従った。
- taintはserverへのスケジュールを禁止する目的で、この[issue](https://github.com/rancher/k3s/issues/389)に従っている。

### helmのインストール

```
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
sudo apt-get install apt-transport-https --yes
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
#helm repo add stable https://charts.helm.sh/stable
```

### おまけ

```
echo 'alias k="kubectl"' > $HOME/.bashrc
echo 'alias h="helm --kubeconfig=/etc/rancher/k3s/k3s.yaml"' > $HOME/.bashrc
```

## k3s-agent
**ローカルで**以下を実行。
```
K3S_SERVER_IP=`ssh -G k3s-server | grep -E 'hostname\s+[0-9.]+' | grep -o -E '[0-9.]+'`
K3S_SERVER_TOKEN=`ssh k3s-server sudo cat /var/lib/rancher/k3s/server/node-token`
ssh k3s-agent echo  "export K3S_SERVER_IP=$K3S_SERVER_IP >> /home/ubuntu/.bashrc"
ssh k3s-agent echo  "export K3S_SERVER_token=$K3S_SERVER_IP >> /home/ubuntu/.bashrc"
```

k3s-agentで以下を実行。
```
# firewall setting
sudo iptables -I FORWARD -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I FORWARD -d 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT   -s 10.0.0.0/8 -j ACCEPT
sudo iptables -I INPUT   -d 10.0.0.0/8 -j ACCEPT
sudo /etc/init.d/netfilter-persistent save
sudo /etc/init.d/netfilter-persistent reload

# install k3s
ssh k3s-agent curl -sfL https://get.k3s.io | K3S_URL=https://$K3S_SERVER_IP:6443 K3S_TOKEN=$K3S_SERVER_TOKEN sh -
```

を使えるが、[isuue]()によると推奨されておらず、taintを使うべき。


環境変数に設定するだけではなく`--kubeconfig $KUBECONFIG`のように書かないといけないので`.bashrc`にこれ書いておくとよい。

# memo
- k3sではDNSがうまく動作しない[問題](https://github.com/rancher/k3s/issues/1527)があるようだ
    - いや、以下のコマンドをインストール前に実行することで解決した。
    - 参考にしたのは[ここ](https://atelierhsn.com/2020/01/k3s-on-oracle-cloud/)
    - 永続化は[ここ](https://qiita.com/yas-nyan/items/e5500cf67236d11cce72)


- cert-managerも使いたい
    - やるなら[ここ](https://opensource.com/article/20/3/ssl-letsencrypt-k3s)参考。

- 公開方法の選択肢は[ここ](https://www.thebookofjoel.com/bare-metal-kubernetes-ingress)が詳しい。

- user group
    - 再起動の度に`chmod`が初期化されるらしい。`chgrp`は初期化されない
    - `--write-kubeconfig-mode 640`
    - `sudo`なしだと`kubectl get all`で問題が生じるが、[ここ](https://github.com/kubernetes/kubernetes/issues/94362)によると問題なさそう。
      進歩
- CI/CD
    - k3s側でGithubを監視する方法、GithubActionsからk3sにアクセスする方法の2通り考えられる
    - 前者を実現するためにArgoCDなどのツールがあるが、メモリが厳しい
    - 後者は[これ](https://github.com/rancher/k3s/issues/1381)によるとIPアドレスを指定して許可する必要があるが、GithubActions側のIPアドレスが分からないので難しそう
