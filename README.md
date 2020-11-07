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

# ローカルPCの操作
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
以下のスクリプトを実行する。なお`init_server.sh`として保存している。

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
kubectl taint nodes worker master=true:NoExecute
```

## k3s-agent
以下を**ローカルPC**で実行。
```
K3S_SERVER_IP=`ssh -G oracle | grep -E 'hostname\s+[0-9.]+' | grep -o -E '[0-9.]+'`
K3S_SERVER_TOKEN=`ssh oracle sudo cat /var/lib/rancher/k3s/server/node-token`
ssh k3s-agent curl -sfL https://get.k3s.io | K3S_URL=https://$K3S_SERVER_IP:6443 K3S_TOKEN=$K3S_SERVER_TOKEN sh -
```

## 補足
- netfilter-persistent経由でiptablesの設定が行われているらしい。
- デフォルトの設定に以下を追記している（ドキュメントの該当部分は[ここ](https://rancher.com/docs/k3s/latest/en/installation/installation-requirements/#networking)）

# k3sの設定
[ここ](https://github.com/rancher/k3s/issues/389)のやりとり見ると推奨されていないっぽい...？
を使えるが、[isuue](https://github.com/rancher/k3s/issues/978)によると推奨されておらず、taintを使うべき。



# helm
- [ここ](https://helm.sh/docs/intro/quickstart/)見てやってみる
- `helm repo add stable ...`はどうせやらないから不要かも

```
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
sudo apt-get install apt-transport-https --yes
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

#helm repo add stable https://charts.helm.sh/stable

echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc

```

環境変数に設定するだけではなく`--kubeconfig $KUBECONFIG`のように書かないといけないので`.bashrc`にこれ書いておくとよい。


# 調べること
- コンパートメント
- VNIC
    - instanceごとにあるようだ

# 試していること
- iptablesの設定勉強した方がよさそう
- まずはk3s以外でポートがちゃんと開放されるか確認する

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
