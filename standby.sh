#!/bin/bash

# 既知と思われるデバイス名の先頭部、デバイス検索用
# 簡易的なやり方のため誤爆はあり得る。コンテナに余計なデバイスがマウントされ得るが、動作する（はず）
RECV_DEV=(pt1video pt3video px4video pxmlt isdb2 isdb6 asv5 pxq3pe pxw3 pxs3 px4-D px5-D)
MARKER_STR="%REPLACE_ME%"

BASE_DIR=`pwd`
FILE_DIR=${BASE_DIR}/epgrec/files

PROHIBIT_FIRST_RUN=0

function to_base_dir () {
    cd $BASE_DIR
}

function to_file_dir () {
    cd $FILE_DIR
}

function is_exist_gr_channel () {
    test -f gr_channel.php
}

function is_unfixed_gr_channel () {
    # 何もチェックせず素通しよりはよい
    grep "GRxx" gr_channel.php > /dev/null 2>&1
}

function get_param_numeric () {
    read input
    
    expr "$input" + 1  > /dev/null 2>&1
    
    if [ $? -lt 2 ]; then
        echo "$input"
        return 0
    else
        return 1
    fi
}

# Docker イメージ作成時に使うファイルを保存するためのフォルダを作る
# 他の処理を行う前にこの関数を実行すること
function create_file_dir () {
    to_base_dir
    mkdir -p $FILE_DIR
}

function print_start_message () {
    echo "-------------------------------------------------------------"
    echo ""
    echo "epgrecUNA の Docker イメージ化作業を行います。"
    echo "本スクリプトはイメージ化に必要なファイルのダウンロード、最小限の設定を実施します。"
    echo ""
    echo "epgrecUNA のカスタマイズが必要な方へ："
    echo "epgrec/config.php, Dockerfile, docker-compose.yml などの設定ファイルを修正後、以下を実行してください。イメージを再生成します。" 
    echo ""
    echo "docker-compose build --no-cache epgrec-app"
    echo "docker-compose up --force-recreate -d"
    echo ""
    echo "-------------------------------------------------------------"
}

function standby_epgrecUNA () {

    to_file_dir
    
    git clone https://github.com/keihan-shin/epgrecUNA.git

    cd epgrecUNA
    chmod 755 do_patch.sh
    ./do_patch.sh
}

function standby_epgrec_depends () {

    to_file_dir

    # libarib25, recpt1 (ともにstz2012氏版)
    git clone https://github.com/stz2012/libarib25.git
    git clone https://github.com/stz2012/recpt1.git
}

function standby_gr_channel_file () {

    to_base_dir
    
    cp gr_channel.php ${FILE_DIR}/epgrecUNA/epgrecUNA/epgrec/settings/gr_channel.php
    
    if [ $? -ne 0 ]; then
        echo "gr_channel.php のコピーに失敗しました。処理を中断します。"
        exit 1
    fi   
}


function standby_deb_multimedia_supporeted_apt () {

    to_file_dir

    # apt-line 設定ファイル + keyring
    # QSV / NVEnc 対応 ffmpeg を deb-multimedia から持ってくる設定とする
    cat <<EOF > sources.list
deb http://deb.debian.org/debian/ bullseye main non-free contrib
deb http://security.debian.org/debian-security bullseye-security main contrib non-free
deb http://deb.debian.org/debian/ bullseye-updates main contrib non-free
EOF

    wget https://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2016.8.1_all.deb
    dpkg-deb -x deb-multimedia-keyring_2016.8.1_all.deb deb-multimedia/

    cp deb-multimedia/etc/apt/trusted.gpg.d/deb-multimedia-keyring.gpg .
    rm -Rf deb-multimedia/ deb-multimedia-keyring_2016.8.1_all.deb

    # APT 2.4 以降準拠の apt-line
    #    1. /etc/apt/keyrings/xxx.gpg に 公開鍵を置く
    #    2. apt-line の書式変更( [arch=任意のアーキテクチャ signed-by=公開鍵のフルパス] の文言が要)
    # arch は `arch` で表示されるものでOK
    cat <<EOF > deb-multimedia.list
deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/deb-multimedia-keyring.gpg] https://www.deb-multimedia.org bullseye main non-free
EOF
}

function standby_cron () {

    to_file_dir

    # shepherd.php が使えない場合は「getepg.php」 https://katauna.hatenablog.com/entries/2015/05/26
    # debian系ではおそらく shepherd.php で問題なし。
    # コンテナ化の都合で /var/www/html 以下に shepherd.php がある扱い
    cat <<"EOF" > shepherd_cron
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

29 */2 * * *   www-data	/var/www/html/shepherd.php
EOF
}

function set_tuner_count () {

    to_base_dir

    echo ""
    echo "*** 入力をお願いします ***"
    echo "使用するデバイスのチューナー数を指定してください。"
    echo ""
    echo "例)" 
    echo "PT3 1枚 -> 2"
    echo "PX-W3PE4 1枚 -> 2"
    echo "PX-Q3PE4 1枚 -> 4"
    echo ""
    echo "経験者向け説明: epgrec/config.php の define('TUNER_UNIT1', x ); の x 、論理チューナー数です。"
    echo ""
    echo -n "チューナー数： "
    
    tuner_count=`get_param_numeric`
    passed=0
       
    if [ $? -eq 0 ]; then
        if [ `expr $tuner_count` -ge 1 ]; then
            sed -ie "s/TUNER_UNIT1', [0-9]*/TUNER_UNIT1', $tuner_count/" $FILE_DIR/epgrecUNA/epgrecUNA/epgrec/config.php
            passed=1
        fi
    fi

    if [ $passed -ne 1 ]; then
        PROHIBIT_FIRST_RUN=1
    fi
}

function gen_docker_compose_yml () {

    to_base_dir

    hit_dev=0

    cp docker-compose.sample docker-compose.yml

    for dev_base in ${RECV_DEV[@]}; do
    
        ls -1 /dev/$dev_base* > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            for dev_path in `ls -1 /dev/$dev_base*`; do
                line=`grep -n -e "$MARKER_STR" docker-compose.yml | cut -f 1 -d ":"`            
                sed -i "${line}i\ \ \ \ \ \ - ${dev_path}:${dev_path}" docker-compose.yml
                hit_dev=1
            done
        fi
        
    done

    line=`grep -n -e "$MARKER_STR" docker-compose.yml | cut -f 1 -d ":"`
    sed -i "${line}i\ \ \ \ \ \ - /dev/bus/usb:/dev/bus/usb" docker-compose.yml
    
    line=`grep -n -e "$MARKER_STR" docker-compose.yml | cut -f 1 -d ":"`
    sed -i "${line}d" docker-compose.yml
    
    if [ $hit_dev -eq 0 ]; then
        PROHIBIT_FIRST_RUN=1
    fi
}

function print_end_message () {

    echo ""
    echo "-------------------------------------------------------------"
    echo ""
    echo "epgrecUNA Dockerイメージ化処理を実施しました。"
    echo ""

    if [ $PROHIBIT_FIRST_RUN -eq 1 ]; then
        echo "一部、手動設定を要する箇所があります。以下のファイルを確認してください。"
        echo ""
        echo "    docker-compose.yml -> チューナーデバイスが発見できず"
        echo "    epgrec/files/epgrecUNA/epgrecUNA/epgrec/config.php -> TUNER_UNIT1 のチューナー数が未指定"
        echo ""
        echo "修正が完了したら"
        echo ""
    fi
    
    echo "docker-compose up -d "
    echo ""
    echo "を実行してください。epgrecUNA が（おそらくは）起動するはずです。"
    echo "アドレスは http://localhost:8080/ がデフォルトです。"
    echo "データベース名などがわからない場合は「docker-compose.yml」をご確認ください。"
    echo ""
    echo "-------------------------------------------------------------"
    echo ""
}


###  Main ###

create_file_dir

is_exist_gr_channel
if [ $? -ne 0 ]; then
    echo ""
    echo "gr_channel.php ファイルが見つかりませんでした。以下を実行してください。"
    echo ""
    echo "1. gr_channel.php.sample の内容を確認し、各環境に応じた内容を記載する"
    echo "(地デジのチャンネル番号指定ファイルです）。"
    echo "2. gr_channel.php.sample を gr_channel.php にリネームする。"
    echo ""
    echo "処理を中断します。"
    echo ""

    exit 1
fi

is_unfixed_gr_channel
if [ $? -eq 0 ]; then
    echo ""
    echo "gr_channel.php ファイルが修正されていない可能性があります。"
    echo ""
    echo "1. README.gr_channel を開き、書式を確認します。"
    echo "2. gr_channel.php を開き、適切な地デジチャンネル番号を指定します。"
    echo ""
    echo "処理を中断します。"
    echo ""
    
    exit 1
fi

print_start_message

standby_epgrecUNA
standby_epgrec_depends

standby_gr_channel_file

standby_deb_multimedia_supporeted_apt
standby_cron

set_tuner_count

gen_docker_compose_yml

print_end_message
