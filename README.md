# epgrecUNA on Docker

## 忙しいのでどうしたらいいか 5 秒 で説明してください。

地デジのチャンネル設定を書いて 3 回コマンドを ッターン すれば epgrecUNA が動いて録画できる気がします。たぶん。

### 初回のみ実施

チューナーはあるものと仮定します（/dev/px4videoX など）。

* gr_channel.php に地デジのチャンネル番号を記入します。書き方がわからない場合は「README.gr_channel」をご参照ください。

* 以下を実行して epgrecUNA のコンテナ化に必要なファイルを準備します。ほとんどの作業はスクリプトがやります。

```
chmod 755 standby.sh
./standby.sh
```

途中でチューナー数を質問します。これは epgrec/config.php の `define('TUNER_UNIT1', x);` に設定するチューナー数です。

* (standby.sh 実行後に自動生成される) docker-compose.yml の中身をエディタで確認します。確認すべき理由は以下の通り。

1. チューナーデバイスの指定が正しくない「かもしれない」ため。devices: 以下の行をご確認ください。 

2. 接続先 DB に関する情報が docker-compose.yml に記載しているため。初回起動「前」であれば DB のホスト名・ユーザー名・パスワード・データベース名を変更できます。

* 以下を実行してください。

```
docker-compose up -d
```

* ブラウザのアドレスバーに http://localhost:8080 と入力してください。

* ブラウザ上で egrecpUNA の初回設定を行います。チューナー数の指定が再度必要です。

注） docker-compose.sample (拡張子が「sample」のもの）は雛形のファイル、触る必要は無いです。

### 以降の起動

```
docker-compose up -d
```

自動起動設定はなし。

設定したい場合は docker-compose.yml にある「restart:」に「always」を指定します（二箇所）。その後 `docker-compose up -d` を実行のこと。

## はじめからやり直したい

```
docker-compose down

docker volume rm epgrecuna-on-docker_epgrec-db-vol \
                 epgrecuna-on-docker_epgrec-app-vol \
                 epgrecuna-on-docker_epgrec-schedule-vol
                 
docker network rm epgrec-internal-net
docker rmi `docker image ls | grep -e "epgrec-app" | awk '{print $3}'` 

rm -Rf epgrec/files    

./standby.sh
```

あるいは

```
# 上記コマンドを叩いたのと同じ状態になります。
./standby.sh --refresh 
```

を実行してください。履歴等を思い切り処分したい場合は `docker system prune -f` でお願いします。

## 一部だけやり直したい

Docker ボリュームを個別にどうにかする必要があります。

### epgrec-db

epgrec-db-vol (コンテナの /var/lib/mysql にマウント）を削除し（`docker volume rm epgrec-db-vol`)、コンテナを再作成(`docker-compose -up -d –force-recreate` など)。

mysql のイメージは所定の Docker ボリュームが空か否かで挙動が変わるため、コンテナとボリュームを潰せば初期化可能です。

### epgrec-app

epgrecUNA は epgrec-app-vol （Web アプリ保存先）、epgrec-schedule-vol（at / cron ジョブ保存先）のボリュームを使用しています。

Web アプリ載せ替え程度であれば epgrec-app-vol の削除のみでよいですが、録画ジョブも消したい場合は epgrec-schedule-vol も削除してください。


```
docker-compose rm epgrec-app-cnt

# at / cron ジョブも消したい場合は epgrec-schedule-vol も削除
docker volume rm epgrec-app-vol

docker-compose build --no-cache epgrec-app
docker-compose up --force-recreate -d
```

これで epgrecUNA のイメージが再作成されます。

## 構成を教えて

### lighttpd + php-7.4(fastcgi) + mysql 

http://[your_machine_ip_addr]:8080/

あるいは

http://localhost:8080/

で画面が表示されるように設定しております。マシンに依存する設定のため、デフォルトではトラコン設定なし。

Raspberry pi 4 等での使用も想定、メモリやディスク消費量が小さい lighttpd を使用。nginx や apache2 を使用したい場合は各自で Dockerfile を修正してください。

http://localhost:8080/ でブラウザが真っ白になった場合は http://localhost:8080/install/step1.php のアドレスで画面が表示されるか確認してください。

### どこに録画されますか

録画ファイルはホストの「/var/recv」に保存されます。

保存先を変えたい場合は docker-compose.yml を修正してください。

「/var/recv:/var/www/html/video」( : 区切り) の左側がホスト側ディレクトリです。 

### 例のカードはどうすればいいですか

あのカードは必要です。カードがなければ録画は失敗しますのでご注意ください。

docker-compose.yml の「devices:」にある「/dev/bus/usb」は USB カードリーダーをコンテナで使用するための設定です。削除しないようご注意ください。

## 注意点など

### 1 : バッドプラクティスあり

at / cron などのコマンド実行に混乱を来すこと、k8s での使用は想定していないことから 1 プロセス 1 コンテナ構成は放棄。動かすことが最優先の構成です。

(最悪は)強引な落とし方も起こり得る（「SIGKILL」で強制停止）ので「バッド」なのですが http サーバ等であればおそらくは耐えられます。

SIGKILL はデータベースには不都合な落とし方のため DB コンテナを別途用意。

### 2 : 変なエラーが出ました -> TS ファイルの保存先に index.html はありますか

ボリュームマウントに絡む問題として、録画ファイル保存先のディレクトリに index.html がないとエラーになることがあります。

もし何らかのエラーが出た場合は TS ファイルの保存先を確認し index.html があるか否かを確認してください。

ない場合は index.html ファイルを作ってしまうこと（`echo "<html><html>" > /your/save/path/index.html`)。

### 3 : 最低限の設定のみ。ノー設定で「いきなり！　トラコン」は期待しないでください

別の録画システムが使えない場合に備え epgrecUNA のコンテナ化ができるようにしました。

ですが最低限の設定のみ。たとえば HW エンコード設定などは行いませんし、設定準備を行うスクリプトも簡易的に作成したもの。

epgrec/config.php や epgrec/setting/trans_config.php （トランスコード設定）の設定や ffmpeg のセルフビルドなど、より高機能な epgrecUNA を目指すのはいかがでしょうか。

### 4 : Docker イメージのビルド中にコケた！　助けろ！

おそらく Rasberry pi 4 の 64bit 版ではないでしょうか？　epgrec/Dockerfile に対策を記載しておりますのでご参照ください。

### 5 : Docker以外の手段はない？

epgrecUNA と相性がいいのは LXC です。KVM などを使うと速度低下が困りもの（録画系はそれなりにマシンパワーを要します）。

やっておいて何ですが epgrecUNA と Docker との相性については疑問です。at / cron 周りが特に。

もし Docker ではなく LXC で環境を構築したい場合のアドバイスですが、デバイスの使用許可絡みの設定でミスが起こりやすいです。

/var/lib/lxc/[container]/config を開き、以下のような設定を書くことになると思いますが「cgroup のバージョン」にご注意ください。

```
# ホスト側のディストリ次第ですが

# cgroup v1 使用のディストリなら lxc.cgroup.devices （cgoup1　ではなく cgroup でよいです）
lxc.cgroup.devices.allow = c *:* rwm

# ホストが cgroup2 使用なら lxc.cgroup2.devices (cgroup 2 と数字をつける必要あり）
lxc.cgroup2.devices.allow = c *:* rwm

```

### 6 : Debian で nvidia-uvm が見えないから NVENC できない問題

いずれはトラコン設定をしたくなると思いますが Debian + NVIDIA にて NVENC をしたい場合、問題が起こります。

エンコード時に必要な「nvidia-uvm」が見えないかもしれません。

Ubuntu だと問題にならないのですが Debian だと問題になります。以下を参照して「ホスト側」に設定を入れてください。

```
cat <<EOF | sudo tee /etc/modules-load.d/nvidia.conf > /dev/null
nvidia-drm
nvidia
nvidia_uvm
EOF

cat <<"EOF" | sudo tee /etc/udev/rules.d/99-nvidia-uvm.rules > /dev/null
KERNEL=="nvidia", RUN+="/bin/bash -c '/usr/bin/nvidia-smi -L && /bin/chmod 666 /dev/nvidia*'"
KERNEL=="nvidia_uvm", RUN+="/bin/bash -c '/usr/bin/nvidia-modprobe -c0 -u && /bin/chmod 0666 /dev/nvidia-uvm*'"
EOF
```

参考サイト : https://kwatanabe.hatenablog.jp/entry/2020/10/04/202409

## 7 : どこかでこの Dockerfile を見たことがあるんですが

以下の Dockerfile や docker-compose.yml を参考にしました。MITにしておきます、とのことだったのでmysql 周りはほぼそのままお借りしました。

https://github.com/l3tnun/docker-epgrec-una

マルチステージビルドへの対応や debian 11 への更新が相違点です。

気づいたんですがこの方は EPGStation の開発者なのでは。

## モチベらしきもの

サーバサイド javascript 系の録画システムがうまく動かないこともあるとかないとか、その辺りの事情。

すでに開発が止まって久しい epgrecUNA を使うより別のシステムを使うほうがいいとは思いますが。このリポジトリは後日（epgrecUNA のリポジトリともども）削除するかもしれません。
