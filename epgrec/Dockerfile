##############################
# epgrec UNA 環境構築用 Dockerfile
##############################

##############################
# マルチステージビルド 1/2
# epgrecUNA が必要とするファイルのビルド
##############################

FROM debian:bullseye As build-cmd

RUN apt-get update && \
    apt-get -y --no-install-recommends install \
    build-essential \
    git \
    cmake \
    pkg-config \
    autoconf \
    automake \
    libpcsclite-dev

WORKDIR /usr/local/src

COPY ./files/libarib25 /usr/local/src/libarib25
RUN mkdir -p /usr/local/src/libarib25/build && \
    cd /usr/local/src/libarib25/build && \
    cmake ../ && \
    make && \
    make install

COPY ./files/recpt1 /usr/local/src/recpt1
RUN cd /usr/local/src/recpt1/recpt1 && \
    chmod 755 ./autogen.sh && \
    ./autogen.sh && \
    ./configure --enable-b25 && \
    make && \
    make install
     
COPY ./files/epgrecUNA/epgdumpUNA /usr/local/src/epgdump
RUN cd /usr/local/src/epgdump && \
    make && \
    make install

##############################
# マルチステージビルド 2/2
# epgrecUNA のイメージ作成
# 
# コンテナのマウントポイントは以下を想定する。バックアップ時などは以下を参照のこと。
# 
# Webアプリ本体：
# (Docker ボリューム) epgrec-app-vol ->（コンテナ側）/var/www/html
#
# 録画先：
# (ホスト側) /var/recv -> (コンテナ側) /var/www/html/video
##############################

FROM debian:bullseye

# 事前準備
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    gnupg2 && \
    update-ca-certificates

# マルチステージ 1 段目でビルドしたファイル、準備した設定ファイルのコピーと
# シンボリックリンクの追加

# 注1. ARM系などでは /usr/local/lib/aarch64-linux-gnu など別パスに libarib25 が入る
#    COPY に失敗してエラー止まった場合はコピー元・コピー先のパスを確認する
#
# 注2. recpt1ctl は COPY を忘れがちだが、必要
#    recpt1ctl を忘れたら予約キャンセルができなくなる（録画は可能なため気づきにくい） 
COPY --from=build-cmd /usr/local/lib/libarib25.so.0.2.5 /usr/local/lib
COPY --from=build-cmd /usr/local/bin/recpt1 /usr/local/bin/
COPY --from=build-cmd /usr/local/bin/recpt1ctl /usr/local/bin/
COPY --from=build-cmd /usr/local/bin/epgdump /usr/local/bin/

COPY ./files/sources.list /etc/apt/sources.list

COPY ./files/deb-multimedia.list /etc/apt/sources.list.d/deb-multimedia.list
COPY ./files/deb-multimedia-keyring.gpg /etc/apt/keyrings/deb-multimedia-keyring.gpg

COPY ./files/shepherd_cron /etc/cron.d/shepherd

RUN ln -s  /usr/local/lib/libarib25.so.0.2.5 /usr/local/lib/libarib25.so.0 && \
    ln -s  /usr/local/lib/libarib25.so.0.2.5 /usr/local/lib/libarib25.so

# deb-multimedia.org 由来のパッケージに更新
RUN apt-get update && \
    apt-get -y dist-upgrade && \
    apt-get autoremove && \
    apt-get autoclean

# sury.org 由来の php を使いたい場合（2022 年 12 月現在 php 5.6 - 8.2 まで使用可）
#COPY ./files/sury.list /etc/apt/sources.list.d/sury.list
#COPY ./files/sury-keyring.gpg /etc/apt/keyrings/sury-keyring.gpg
#RUN apt-get update 

# サーバ構築開始
#
# 予約キャンセル時に ps -u www-data -f を使っているので procps ( ps コマンド ) は必須。
#
# 設定的には deb-multimedia.org の ffmpeg を使用できるようにしているため HWエンコード前提のトラコンも可能。
# 2022年12月現在、QSVとNVEncが使える。
#
# トラコン設定を入れる場合は ffmpeg を以下に追加した後 settings/trans_config.php を修正すること。
# QSV でトラコンを行うならば「intel-media-va-driver-non-free」も追加する。デフォルトのドライバはNG。
# その他ハードウェアエンコードにてコンテナに渡すデバイスについては各人で調査し docker-compose.yml に追記。
RUN apt-get  -y --no-install-recommends install \
    at \
    cron \
    ffmpeg \
    locales \
    libpcsclite1 \
    lighttpd \
    pcscd \
    procps \
    php7.4 \
    php7.4-cgi \
    php7.4-mysql \
    php7.4-mbstring \
    php7.4-xml  && \
    apt-get -y autoremove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#  httpd や php 関連の設定を実行
#
# 注1. timezone：
#    php 側が LTC ( Asia/Tokyo ) 前提、 UTC 不可、環境変数 TZ のみでは at の動作に支障あり。
#
# 注2. locales: 
#    ファイル名は主に日本語、念の為 locale 設定を入れる(locale-gen + ENV LANG=ja_JP.UTF-8)
#
# 注3. php.ini:
#    cli / cgi の両者の php.ini を修正しないと epgrec の初回起動時にエラーとなったため、2つ修正している。
#
RUN lighttpd-enable-mod fastcgi-php && \
    mkdir /run/lighttpd/ && \
    chown root:www-data /run/lighttpd/ && \
    chmod 774 /run/lighttpd/ && \  
    sed -i '/^www-data/g' /etc/at.deny && \
    sed -i 's/disable_functions/;disable_functions/g' /etc/php/7.4/cli/php.ini && \
    sed -i 's/disable_functions/;disable_functions/g' /etc/php/7.4/cgi/php.ini && \
    sed -i 's/;date.timezone =/date.timezone = "Asia\/Tokyo"/g' /etc/php/7.4/cli/php.ini && \
    sed -i 's/;date.timezone =/date.timezone = "Asia\/Tokyo"/g' /etc/php/7.4/cgi/php.ini && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    sed -i -E 's/# (ja_JP.UTF-8)/\1/' /etc/locale.gen && \
    locale-gen

ENV LANG=ja_JP.UTF-8

# epgrecUNA の設置
#
# lighttpd のデフォルト DocumentRoot を使用している。
# /var/www/epgrec ではなく /var/www/html が epgrecUNA のファイル置き場。

RUN rm -Rf /var/www/html
COPY ./files/epgrecUNA/epgrecUNA/epgrec/ /var/www/html

RUN cd /var/www/html && \
    chmod 755 *.php && \
    chmod 755 *.sh

# docker-compose.yml や docker run -p でのポートフォワード時に必要、消さないこと
EXPOSE 80

# イメージ実行（コンテナ化）時のコマンド指定
# どうされるのか想定しにくいため ENTRYPOINT は未指定。 docker run でコマンドを通せるように。
#
# 注1. バッドプラクティス構成
# at / cron がないと epgrecUNA は動作しないため 1 プロセス 1 コンテナの原則を無視。
# 
# 注2. chown や chmod は必要
# /var/www/html は run 後に mount される前提(docker ボリュームにより永続化される）。
# 権限などはマウント時に自動決定されるも、特定のディレクトリは権限が 777 でなければ
# epgrec は動作しない。
#
# 注3. 最後の tail -f はフォアグラウンドでの実行状態を作っているだけ。
# lighttpd の起動は /etc/init.d/lighttpd に任せている。
CMD chown -R www-data:www-data /var/www/html && \
    chmod 777 /var/www/html/templates_c && \
    chmod 777 /var/www/html/video && \
    chmod 777 /var/www/html/thumbs && \
    chmod 777 /var/www/html/settings && \
    chmod 777 /var/www/html/cache && \
    /etc/init.d/atd start && \
    /etc/init.d/cron start && \
    /etc/init.d/pcscd start && \
    /etc/init.d/lighttpd start && \
    tail -f /dev/null
