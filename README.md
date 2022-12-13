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

注） docker-compose.sample (拡張子が「sample」のもの）は雛形のファイル、触る必要はありません。チューナーデバイスの手設定をさせたくなかったので無理やりシェル芸しているだけです。

### 以降の起動

```
docker-compose up -d
```

自動起動設定はなし。

設定したい場合は docker-compose.yml にある「restart:」に「always」を指定します（二箇所）。その後 `docker-compose up -d` を実行のこと。

## はじめからやり直したい

```
docker-compose down
docker volume prune -f
docker rmi `docker image ls | grep -e "epgrec-app" | awk '{print $3}'`
docker system prune -f

rm -Rf epgrec/files
```

を実行後


```
./standby.sh
```

を実行してください。

ただし、使用中のマシンで別コンテナを動かしたり停止している場合は惨事になるかもしれません。prune してるので消えてはいけないボリュームの消滅などがあり得ます。

* epgrec-db-vol
* epgrec-app-vol
* epgrec-schedule-vol

を手動で消すなどのご対応をお願いします。

## 一部だけやり直したい

Docker ボリュームを個別にどうにかする必要があります。

### epgrec-db

epgrec-db-vol (コンテナの /var/lib/mysql にマウント）を削除し（`docker volume rm epgrec-db-vol`)、コンテナを再作成(`docker-compose -up -d –force-recreate` など)。

mysql のイメージは所定の Docker ボリュームが空か否かで挙動が変わるため、コンテナとボリュームを潰せば初期化可能です。

### epgrec-app

epgrec-app-vol (コンテナの /var/www/html にマウント）を削除後に同名のボリュームを作成し epgrecUNA のファイルをコピーします。

ただし at / cron のジョブが保存されている epgrec-schedule-vol がそのままなので、後日変なジョブが走る可能性があります。

* epgrec-app-vol と epgrec-schedule-vol の 2 ボリュームを消して `docker build` でイメージごと作りなおす

という手が楽かと思われます。

## 構成を教えて

### lighttpd + php-7.4(fastcgi) + mysql 

http://[your_machine_ip_addr]:8080/

あるいは

http://localhost:8080/

で画面が表示されるように設定しております。マシンに依存する設定のため、デフォルトではトラコン設定なし。

Raspberry pi 4 等での使用も想定、メモリやディスク消費量が小さい lighttpd を使用。nginx や apache2 を使用したい場合は各自で Dockerfile を修正してください。

http://localhost:8080/ でブラウザが真っ白になった場合は http://localhost:8080/install/step1.php のアドレスで画面が表示されるか確認してください。

### どこに録画されますか

録画ファイルはホストの「/var/recv」に保存されます。保存先を変えたい場合は docker-compose.yml を修正してください。

「/var/recv:/var/www/html/video」( : 区切り) の左側がホスト側ディレクトリです。 

### 例のカードはどうすればいいですか

あのカードは必要です。カードがなければ録画は失敗しますのでご注意ください。

docker-compose.yml の「devices:」にある「/dev/bus/usb」は USB カードリーダーをコンテナで使用するための設定ですから削除しないようご注意ください。

## 注意点など

### 1 : バッドプラクティスあり

at / cron などのコマンド実行に混乱を来すこと、k8s での使用は想定していないことから 1 プロセス 1 コンテナ構成は放棄。とにかく動かすことを最優先とした構成です。

最悪は強引な落とし方も起こり得る（「SIGKILL」で強制停止）ので「バッド」なのですが http サーバ等であれば耐えられます。

ですがデータベースには不都合な落とし方のため DB コンテナを別途用意。

### 2 : 変なエラーが出ました -> TS ファイルの保存先に index.html はありますか

ボリュームマウントに絡む問題として、録画ファイル保存先のディレクトリに index.html がないとエラーになることがあります。

もし何らかのエラーが出た場合は TS ファイルの保存先を確認し index.html があるか否かを確認してください。

ない場合は index.html ファイルを作ってしまうこと（`echo "<html><html>" > /your/save/path/index.html`)。

### 3 : 最低限の設定のみ、ノー設定でいきなり！　トラコンなどは期待しないでください

別の録画システムが使えない場合に備え epgrecUNA のコンテナ化ができるようにしました。

ですが最低限の設定のみ。たとえば HW エンコード設定などは行いませんし、設定準備を行うスクリプトも簡易的に作成したもの。

epgrec/config.php や epgrec/setting/trans_config.php （トランスコード設定）の設定や ffmpeg のセルフビルドなど、より高機能な epgrecUNA を目指すのも一つの手です。

### 4 : Docker イメージのビルド中にコケた！　助けろ！

おそらく Rasberry pi 4 の 64bit 版ではないでしょうか？

epgrec/Dockerfile に対策を記載しておりますのでご参照ください。

## モチベらしきもの

サーバサイド javascript 系の録画システムがうまく動かないこともあるとかないとか、その辺りの事情。

すでに開発が止まって久しい epgrecUNA を使うより別のシステムを使うほうがいいとは思いますが。

「需要があるかどうか分からないため一時的に公開する」「Dockerの使い方が適当だったからマジメに練習したい、モチベが出るものを探していた、epgrecUNAはモチベ出そう」程度のもの。

後日（epgrecUNA のリポジトリともども）削除するかもしれません。

## 別の手段

epgrecUNA と相性がいいのは LXC です。KVM などを使うと速度低下が困りもの（録画系はそれなりにマシンパワーを要します）。

やっておいて何ですが epgrecUNA と Docker との相性については疑問です。at / cron 周りが特に。

## 参考サイト：

以下の Dockerfile や docker-compose.yml を参考にしました。mysql 周りはほぼそのまま。マルチステージビルドへの対応や debian 11 への更新が相違点です。

https://github.com/l3tnun/docker-epgrec-una
