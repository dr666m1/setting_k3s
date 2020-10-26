# VMの作成
同じ設定のサーバーを2台用意する。
デフォルトからの変更点は以下。

- OSをUbuntu18.04に変更
- パブリックIPアドレスを割り当てない
- SSHは公開キー・ファイルの選択から、ローカルの`id_rsa.pub`をアップロードする

# IPアドレス
## 予約済みIPアドレスの作成
- `コア・インフラストラクチャ` > `ネットワーキング` > `IP Management` > `パブリックIPアドレスの予約`
- `IPアドレス名`は任意、`コンパートメントに作成`はいったんルート、`IPアドレス・ソース`はいったんOracleにしておく

## 予約済みIPアドレスの割り当て
2台用意したサーバーの内、片方に割り当てる。

- VMの管理画面で`リソース` > `アタッチされたVNIC` から、表示中のVNICを選択
- VNICの管理画面で`リソース` > `IPアドレス`から、表示中のIPアドレスを編集 > 既存の予約済みIPアドレスの選択で、先ほど作成したIPアドレスを選択


# ssh接続
ユーザー名が`ubuntu`（Ubuntu以外は`opc`）なので`~/.ssh/config`を以下のようにするれば、
`ssh oracle` `ssh oracle-worker`だけでssh接続できる。
なお前者は予約済みIPアドレス（`xxx.xxx.xx.xx`）を割り当てたもので、
後者はプライベートIPアドレス（`yyy.yyy.yy.yy`）しか持たない。
```
Host oracle
    HostName xxx.xxx.xx.xx
    User ubuntu

Host oracle-woker
    HostName yyy.yyy.yy.yy
    User ubuntu
    ProxyCommand ssh -W %h:%p oracle
```

# NSGの設定
NSG（Network Security Group）

- `ネットワーキング` > `仮想クラウド・ネットワーク` > 表示中のVCNを選択 > `リソース` > `ネットワーク・セキュリティ・グループ`

# iptablesの設定
- netfilter-persistent経由でiptablesの設定が行われているらしい。
- aa

```
-A INPUT -p tcp --dport 6443 -j ACCEPT
-A INPUT -p udp --dport 8472 -j ACCEPT
```


# k3sの設定
[日本語ドキュメント](https://rancher.co.jp/pdfs/K3s-eBook4Styles0507.pdf)が参考になる。
`kubeclt`で`sudo`を使わなくてすむインストール方法もあるようだが、
[ここ](https://github.com/rancher/k3s/issues/389)のやりとり見ると推奨されていないっぽい...？

```sh
# oracle
curl -sfL https://get.k3s.io | sh -

# oracle-worker
curl -sfL https://get.k3s.io | K3S_URL=https://xxx.xxx.xx.xx:6443 K3S_TOKEN=xxxxxxxxxx sh -
```

# 調べること
- コンパートメント
- VNIC
    - instanceごとにあるようだ

# 試していること
- iptablesの設定勉強した方がよさそう
- まずはk3s以外でポートがちゃんと開放されるか確認する
