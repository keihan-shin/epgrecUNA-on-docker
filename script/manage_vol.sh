#!/bin/bash

target_volumes=(epgrec-db-vol epgrec-app-vol epgrec-schedule-vol)

function print_usage () {
    script_base=`basename $0`
    
    echo ""
    echo "epgrec 関連コンテナが使用するデータのバックアップ・リストアを行うスクリプトです。"
    echo "docker-compose.yml があるディレクトリから script/$script_base の形で実行してください。"
    echo ""
    echo "本スクリプトは書き込みロックを「行いません」。"
    echo "変なタイミングでバックアップを実行するとファイル破損などがありえます。"
    echo "安全を期す場合は docker-compose down を実行後に本スクリプトを実行してください。"
    echo ""
    echo "Usage:"
    echo "script/$script_base backup"
    echo "    backup ディレクトリ以下に epgrec 関連ファイルのバックアップを取得します。"
    echo "    ファイルがすでにある場合は上書きします。"
    echo ""    
    echo "script/$script_base restore"
    echo "    backup ディレクトリのファイルを元に Docker ボリュームをリストアします。"
    echo "    docker-compose up -d などで予め使用予定のコンテナを作成してください。"
    echo ""
    echo "注意）"
    echo "docker-compose は [現在の親ディレクトリ]_volume という名前のボリュームを作ります。"
    echo "ボリュームのマウントも [現在の親ディレクトリ名]_volume というボリュームがあると仮定します。"
    echo ""
    echo "バックアップ・リストア時や docker-compose 実行後に親ディレクトリ名を変えると"
    echo "まずいことになるかもしれませんので、ご注意ください。"
    echo ""
}

function print_vol_missing_error () {
    echo "epgrec 関連の Docker ボリュームが見つかりませんでした。"
    echo ""
    echo "${target_volumes[@]} という文言を含むボリュームがすべて揃っていることを"
    echo "    docker volume ls"
    echo "コマンドにて確認してください。"
    echo ""
    echo "処理を中断します。"
}

# docker-compose は 「[parent-dir]_volname」という形でボリュームを作るため
# docker-compose.yml の親フォルダがわかる位置にいないと困る
function is_suitable_dir () {
    if [ ! -f docker-compose.yml ]; then
        return 1
    fi
    
    return 0
}

function is_exist_volume () {
    docker volume ls | grep -e "$1" > /dev/null 2>&1
}

function is_exist_all_volumes () {
    for vol in "${target_volumes[@]}"; do
        is_exist_volume $vol
        
        if [ $? -ne 0 ]; then
            return 1
        fi
    done
    
    return 0
}


function backup_volume () {
    base_vol_name=$1

    if [ ! -d backup ]; then
        mkdir backup
    fi
    
    is_exist_volume $base_vol_name
    if [ $? -ne 0 ]; then
        echo "バックアップ対象のボリュームが見つかりませんでした。処理を中断します。"
        echo ""
        echo "名前に ${base_vol_name} を含むボリュームがあることを"
        echo "    docker volume ls"
        echo "コマンドで確認してください。"

        exit 1
    fi
    
    full_vol_name=`docker volume ls | grep -e "$base_vol_name" | awk '{print $2}'`

    docker run --rm \
        -v $full_vol_name:/tmp/src \
        -v "$(pwd)/backup":/tmp/dst \
        debian:bullseye \
        tar -C /tmp/src -cpzf /tmp/dst/${base_vol_name}.tar.gz .
}

function restore_volume () {
    base_vol_name=$1
    parent_dir_name=`basename $(pwd) | tr A-Z a-z`
    full_vol_name=${parent_dir_name}_${base_vol_name}

    if [ ! -f backup/${base_vol_name}.tar.gz ]; then
        echo "リストア対象のファイルが見つかりませんでした。処理を中断します。"
        echo "(${base_vol_name}.tar.gz のリストアに失敗）"
        exit 1
    fi
   
    # ディレクトリ名変えられてボリューム名が変わる場合、古いボリュームには何もしない
    is_exist_volume $full_vol_name   
    if [ $? -eq 0 ]; then
        docker volume rm `docker volume ls | grep -e "$full_vol_name" | awk '{print $2}'`  > /dev/null 2>&1
        docker volume create $full_vol_name > /dev/null 2>&1
    fi
    
    docker run --rm \
        -v "$(pwd)/backup":/tmp/src \
        -v $full_vol_name:/tmp/dst \
        debian:bullseye \
        tar -C /tmp/dst -xpzf /tmp/src/${base_vol_name}.tar.gz .
}


### Main ###

is_suitable_dir
if [ $? -ne 0 ]; then
    echo "本スクリプトは docker-compose.yml があるディレクトリから実行してください。"
    echo "script/`basename $0` の形で実行します。"  
    exit 1
fi

if [ "$1" == "backup" ]; then
    is_exist_all_volumes

    if [ $? -ne 0 ]; then
        print_vol_missing_error
        exit 1
    fi

    for vol in "${target_volumes[@]}"; do
        backup_volume $vol
    done
elif [ "$1" == "restore" ]; then
    for vol in "${target_volumes[@]}"; do
        restore_volume $vol
    done
else
    print_usage
fi

