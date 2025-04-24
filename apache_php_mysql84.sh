#!/bin/sh

# メッセージ表示関数
start_message() {
    echo ""
    echo "======================開始: $1 ======================"
    echo ""
}

end_message() {
    echo ""
    echo "======================完了: $1 ======================"
    echo ""
}

# 起動メッセージ
cat <<EOF
-----------------------------------------------------
Buildree Apache インストールスクリプト
-----------------------------------------------------
注意点：
  - AlmaLinux、Rocky Linux、RHEL、CentOS Stream、Oracle Linux専用
  - rootユーザーまたはsudo権限が必要
  - 新規環境での使用を推奨
  - 実行前にバックアップを推奨

目的：
  - Apache 2.4系のインストール
  - SSL設定
  - gzip圧縮の有効化
  - htaccess許可
  - PHP 8.2のインストール（remiリポジトリ使用）
  - PHP-FPMの設定
  - unicornユーザーの自動作成
  - SELinux対応の自動設定

ドキュメントルート: /var/www/html
EOF

read -p "インストールを続行しますか？ (y/n): " choice
[ "$choice" != "y" ] && { echo "インストールを中止しました。"; exit 0; }

hash_file="/tmp/hashes.txt"
expected_sha3_512="4362c6f3b097c5ad413fb78510ead25d65ba3b59437afa4a89bcd545d9761544334de40c1f33b7e82a881ce4aa04ed08e1efadba759e38131d2fe2ec4a74fc3e"

# リポジトリのシェルファイルの格納場所
repository_file_path="/tmp/repository.sh"
update_file_path="/tmp/update.sh"
useradd_file_path="/tmp/useradd.sh"
mysql_file_path="/tmp/rdbm84.sh"


# ディストリビューションとバージョンの検出
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DIST_ID=$ID
  DIST_VERSION_ID=$VERSION_ID
  DIST_NAME=$NAME
  # メジャーバージョン番号の抽出（8.10から8を取得）
  DIST_MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
elif [ -f /etc/redhat-release ]; then
  if grep -q "CentOS Stream" /etc/redhat-release; then
    DIST_ID="centos-stream"
    DIST_VERSION_ID=$(grep -o -E '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1)
    DIST_MAJOR_VERSION=$(echo "$DIST_VERSION_ID" | cut -d. -f1)
    DIST_NAME="CentOS Stream"
  else
    DIST_ID="redhat"
    DIST_VERSION_ID=$(grep -o -E '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1)
    DIST_MAJOR_VERSION=$(echo "$DIST_VERSION_ID" | cut -d. -f1)
    DIST_NAME=$(cat /etc/redhat-release)
  fi
else
  echo "サポートされていないディストリビューションです"
  exit 1
fi

echo "検出されたディストリビューション: $DIST_NAME $DIST_VERSION_ID"

# Redhat系で8または9の場合のみ処理を実行
if [ -e /etc/redhat-release ] && [[ "$DIST_MAJOR_VERSION" -eq 8 || "$DIST_MAJOR_VERSION" -eq 9 ]]; then

        # ハッシュファイルのダウンロード
        start_message
        if ! curl --tlsv1.3 --proto https -o "$hash_file" https://raw.githubusercontent.com/buildree/common/main/other/hashes.txt; then
            echo "エラー: ファイルのダウンロードに失敗しました"
            exit 1
        fi

        # ファイルのSHA3-512ハッシュ値を計算
        actual_sha3_512=$(sha3sum -a 512 "$hash_file" 2>/dev/null | awk '{print $1}')
        # sha3sumコマンドが存在しない場合の代替手段
        if [ -z "$actual_sha3_512" ]; then
            actual_sha3_512=$(openssl dgst -sha3-512 "$hash_file" 2>/dev/null | awk '{print $2}')

            if [ -z "$actual_sha3_512" ]; then
                echo "エラー: SHA3-512ハッシュの計算に失敗しました。sha3sumまたはOpenSSLがインストールされていることを確認してください。"
                rm -f "$hash_file"
                exit 1
            fi
        fi

        # ハッシュ値を比較
        if [ "$actual_sha3_512" == "$expected_sha3_512" ]; then
            echo "ハッシュ値は一致します。ファイルを保存します。"
            
            # ハッシュ値ファイルの読み込み - ダウンロード成功後に行う
            repository_hash=$(grep "^repository_hash_sha512=" "$hash_file" | cut -d '=' -f 2)
            update_hash=$(grep "^update_hash_sha512=" "$hash_file" | cut -d '=' -f 2)
            repository_hash_sha3=$(grep "^repository_hash_sha3_512=" "$hash_file" | cut -d '=' -f 2)
            update_hash_sha3=$(grep "^update_hash_sha3_512=" "$hash_file" | cut -d '=' -f 2)
            useradd_hash=$(grep "^useradd_hash_sha512=" "$hash_file" | cut -d '=' -f 2)
            useradd_hash_sha3=$(grep "^useradd_hash_sha3_512=" "$hash_file" | cut -d '=' -f 2)
            mysql_hash=$(grep "^rdbm84_hash_sha512=" "$hash_file" | cut -d '=' -f 2)
            mysql_hash_sha3=$(grep "^rdbm84_hash_sha3_512=" "$hash_file" | cut -d '=' -f 2)
        else
            echo "ハッシュ値が一致しません。ファイルを削除します。"
            echo "期待されるSHA3-512: $expected_sha3_512"
            echo "実際のSHA3-512: $actual_sha3_512"
            rm -f "$hash_file"
            exit 1
        fi
        end_message

    # Gitリポジトリのインストール
    start_message "Gitリポジトリのインストール"
    echo "Gitをインストールしています..."
    dnf -y install git
    echo "Gitのインストールが完了しました"
    end_message "Gitリポジトリのインストール"

    # EPELリポジトリとremiリポジトリのインストール
    start_message "EPELリポジトリとremiリポジトリのインストール"
    echo "EPELリポジトリとremiリポジトリをインストールします..."
    curl --tlsv1.3 --proto https -o /tmp/repository.sh https://raw.githubusercontent.com/buildree/common/main/system/repository.sh
    echo "リポジトリスクリプトをダウンロードしました"
    chmod +x /tmp/repository.sh
    echo "リポジトリスクリプトを実行します..."
    source /tmp/repository.sh
    echo "リポジトリのインストールが完了しました"
    end_message "EPELリポジトリとremiリポジトリのインストール"

        # dnf updateを実行
        start_message
        echo "システムをアップデートします"
        # アップデートスクリプトをGitHubから/tmpにダウンロードして実行
        if ! curl --tlsv1.3 --proto https -o "$update_file_path" https://raw.githubusercontent.com/buildree/common/main/system/update.sh; then
            echo "エラー: ファイルのダウンロードに失敗しました"
            exit 1
        fi

        # ファイルの存在を確認
        if [ ! -f "$update_file_path" ]; then
            echo "エラー: ダウンロードしたファイルが見つかりません: $update_file_path"
            exit 1
        fi

        # ファイルのSHA512ハッシュ値を計算
        actual_sha512=$(sha512sum "$update_file_path" 2>/dev/null | awk '{print $1}')
        if [ -z "$actual_sha512" ]; then
            echo "エラー: SHA512ハッシュの計算に失敗しました"
            exit 1
        fi

        # ファイルのSHA3-512ハッシュ値を計算
        actual_sha3_512=$(sha3sum -a 512 "$update_file_path" 2>/dev/null | awk '{print $1}')

        # システムにsha3sumがない場合の代替手段
        if [ -z "$actual_sha3_512" ]; then
            # OpenSSLを使用する方法
            actual_sha3_512=$(openssl dgst -sha3-512 "$update_file_path" 2>/dev/null | awk '{print $2}')
            
            # それでも取得できない場合はエラー
            if [ -z "$actual_sha3_512" ]; then
                echo "エラー: SHA3-512ハッシュの計算に失敗しました。sha3sumまたはOpenSSLがインストールされていることを確認してください"
                exit 1
            fi
        fi

        # 両方のハッシュ値が一致した場合のみ処理を続行
        if [ "$actual_sha512" == "$update_hash" ] && [ "$actual_sha3_512" == "$update_hash_sha3" ]; then
            echo "両方のハッシュ値が一致します。"
            echo "このスクリプトは安全のためインストール作業を実施します"
            
            # 実行権限を付与
            chmod +x "$update_file_path"
            
            # スクリプトを実行
            source "$update_file_path"
            
            # 実行後に削除
            rm -f "$update_file_path"
        else
            echo "ハッシュ値が一致しません！"
            echo "期待されるSHA512: $update_hash"
            echo "実際のSHA512: $actual_sha512"
            echo "期待されるSHA3-512: $update_hash_sha3"
            echo "実際のSHA3-512: $actual_sha3_512"
            
            # セキュリティリスクを軽減するため、検証に失敗したファイルを削除
            rm -f "$update_file_path"
            exit 1 #一致しない場合は終了
        fi
        end_message

    # SELinuxの状態確認（ツールのインストールの代わりにチェックのみ実行）
    start_message "SELinuxの状態確認"
    echo "システムのSELinux状態を確認しています..."
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
    echo "現在のSELinux状態: $SELINUX_STATUS"
    
    # SELinuxがEnforcingの場合のみ、管理ツールをインストール
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        echo "SELinuxがEnforcing状態です。必要なユーティリティがなければインストールします..."
        if ! rpm -q policycoreutils-python-utils > /dev/null 2>&1; then
            echo "SELinux管理ツールをインストールしています..."
            dnf install -y policycoreutils-python-utils
            echo "SELinux管理ツールのインストールが完了しました"
        else
            echo "SELinux管理ツールは既にインストールされています"
        fi
    else
        echo "SELinuxはEnforcing状態ではないため、追加のSELinuxツールのインストールはスキップします"
    fi
    end_message "SELinuxの状態確認"

    # Apacheのインストール
    start_message "Apacheのインストール"
    echo "Apache HTTPサーバーとSSLモジュールをインストールしています..."
    dnf install -y httpd mod_ssl
    echo "インストールされたApacheのバージョン:"
    httpd -v
    echo "Apacheのインストールが完了しました"
    end_message "Apacheのインストール"

    # gzip圧縮設定
    start_message "gzip圧縮設定"
    echo "gzip圧縮の設定ファイルを作成しています..."
    cat > /etc/httpd/conf.d/gzip.conf <<'EOF'
SetOutputFilter DEFLATE
BrowserMatch ^Mozilla/4 gzip-only-text/html
BrowserMatch ^Mozilla/4\.0[678] no-gzip
BrowserMatch \bMSI[E] !no-gzip !gzip-only-text/html
SetEnvIfNoCase Request_URI\.(?:gif|jpe?g|png)$ no-gzip dont-vary
Header append Vary User-Agent env=!dont-var
EOF
    echo "gzip圧縮の設定が完了しました"
    end_message "gzip圧縮設定"
    
    # 標準のPHPを無効化
    start_message "標準のPHPを無効化"
    echo "標準のPHPモジュールをリセットしています..."
    dnf module reset php -y
    echo "remiリポジトリのPHP8.2を有効化しています..."
    dnf module enable -y php:remi-8.2
    echo "PHP8.2モジュールの有効化が完了しました"
    end_message "標準のPHPを無効化"

    # PHP8.2をインストール
    start_message "PHP8.2をインストール"
    echo "PHPの依存ライブラリ(libzip-devel)をインストールしています..."
    dnf install -y libzip-devel
    echo "PHP8.2と必要なモジュールをインストールしています..."
    echo "インストール中のパッケージ: php php-cli php-fpm php-mbstring php-xml php-json php-mysqlnd php-zip php-gd php-curl php-openssl php-tokenizer php-xmlwriter php-common"
    dnf install -y php php-cli php-fpm php-mbstring php-xml php-json php-mysqlnd php-zip php-gd php-curl php-openssl php-tokenizer php-xmlwriter php-common
    echo "PHP8.2のインストールが完了しました"
    echo "インストールされたPHPのバージョン:"
    php -v
    end_message "PHP8.2をインストール"


    # php-fpmで動くように追記
    start_message "php-fpmで動くように追記"
    echo "Apache設定にPHP-FPM用のハンドラーを追加しています..."
    sed -i -e "357i #FastCGI追記" /etc/httpd/conf/httpd.conf
    sed -i -e "358i <FilesMatch \.php$>" /etc/httpd/conf/httpd.conf
    sed -i -e '359i     SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost/"' /etc/httpd/conf/httpd.conf
    sed -i -e "360i </FilesMatch>" /etc/httpd/conf/httpd.conf
    echo "PHP-FPM設定の追加が完了しました"
    end_message "php-fpmで動くように追記"

    # php.iniの設定変更
    start_message "php.iniの設定"
    echo "phpのバージョンを非表示にします..."
    sed -i -e "s|expose_php = On|expose_php = Off|" /etc/php.ini
    echo "phpのタイムゾーンを変更..."
    sed -i -e "s|;date.timezone =|date.timezone = Asia/Tokyo|" /etc/php.ini
    echo "PHPの実行範囲を制限..."
    sed -i -e "s|;open_basedir =|open_basedir = /var/www/html|" /etc/php.ini
    echo "ファイルアップロードサイズを設定..."
    sed -i -e "s|upload_max_filesize = 2M|upload_max_filesize = 32M|" /etc/php.ini
    sed -i -e "s|post_max_size = 8M|post_max_size = 32M|" /etc/php.ini
    echo "アップロードサイズを32MBに設定しました"
    end_message "php.iniの設定"

    # phpinfoの作成
    start_message "phpinfoの作成"
    echo "PHPの情報確認用ファイル(info.php)を作成しています..."
    touch /var/www/html/info.php
    echo '<?php phpinfo(); ?>' >> /var/www/html/info.php
    echo "info.phpの内容:"
    cat /var/www/html/info.php
    echo "info.phpの作成が完了しました"
    end_message "phpinfoの作成"

    # MySQLのインストール
    start_message "MySQLのインストール"
    echo "MySQLインストールスクリプトをダウンロードしています..."
    
    # MySQLインストールスクリプトをダウンロード
    if ! curl --tlsv1.3 --proto https -o "$mysql_file_path" https://raw.githubusercontent.com/buildree/common/main/database/rdbm84.sh; then
        echo "エラー: MySQLインストールスクリプトのダウンロードに失敗しました"
        exit 1
    fi

    # ファイルの存在を確認
    if [ ! -f "$mysql_file_path" ]; then
        echo "エラー: ダウンロードしたファイルが見つかりません: $mysql_file_path"
        exit 1
    fi

    # ファイルのSHA512ハッシュ値を計算
    actual_sha512=$(sha512sum "$mysql_file_path" 2>/dev/null | awk '{print $1}')
    if [ -z "$actual_sha512" ]; then
        echo "エラー: SHA512ハッシュの計算に失敗しました"
        exit 1
    fi

    # ファイルのSHA3-512ハッシュ値を計算
    actual_sha3_512=$(sha3sum -a 512 "$mysql_file_path" 2>/dev/null | awk '{print $1}')

    # システムにsha3sumがない場合の代替手段
    if [ -z "$actual_sha3_512" ]; then
        # OpenSSLを使用する方法
        actual_sha3_512=$(openssl dgst -sha3-512 "$mysql_file_path" 2>/dev/null | awk '{print $2}')
        
        # それでも取得できない場合はエラー
        if [ -z "$actual_sha3_512" ]; then
            echo "エラー: SHA3-512ハッシュの計算に失敗しました。sha3sumまたはOpenSSLがインストールされていることを確認してください"
            exit 1
        fi
    fi

    # 両方のハッシュ値が一致した場合のみ処理を続行
    if [ "$actual_sha512" == "$mysql_hash" ] && [ "$actual_sha3_512" == "$mysql_hash_sha3" ]; then
        echo "ハッシュ検証が成功しました。MySQLのインストールを続行します。"
        
        # 実行権限を付与
        chmod +x "$mysql_file_path"
        
        # スクリプトを実行
        bash "$mysql_file_path"
        
        # 実行後に削除
        rm -f "$mysql_file_path"
    else
        echo "エラー: MySQLインストールスクリプトのハッシュ検証に失敗しました。"
        echo "期待されるSHA512: $mysql_hash"
        echo "実際のSHA512: $actual_sha512"
        echo "期待されるSHA3-512: $mysql_hash_sha3"
        echo "実際のSHA3-512: $actual_sha3_512"
        
        # セキュリティリスクを軽減するため、検証に失敗したファイルを削除
        rm -f "$mysql_file_path"
        exit 1
    fi
    end_message "MySQLのインストール"

        # ユーザーを作成
        start_message
        echo "unicornユーザーを作成します"

        # ユーザー作成スクリプトをダウンロード
        if ! curl --tlsv1.3 --proto https -o "$useradd_file_path" https://raw.githubusercontent.com/buildree/common/main/user/useradd.sh; then
            echo "エラー: ファイルのダウンロードに失敗しました"
            exit 1
        fi

        # ファイルの存在を確認
        if [ ! -f "$useradd_file_path" ]; then
            echo "エラー: ダウンロードしたファイルが見つかりません: $useradd_file_path"
            exit 1
        fi

        # ファイルのSHA512ハッシュ値を計算
        actual_sha512=$(sha512sum "$useradd_file_path" 2>/dev/null | awk '{print $1}')
        if [ -z "$actual_sha512" ]; then
            echo "エラー: SHA512ハッシュの計算に失敗しました"
            exit 1
        fi

        # ファイルのSHA3-512ハッシュ値を計算
        actual_sha3_512=$(sha3sum -a 512 "$useradd_file_path" 2>/dev/null | awk '{print $1}')

        # システムにsha3sumがない場合の代替手段
        if [ -z "$actual_sha3_512" ]; then
            # OpenSSLを使用する方法
            actual_sha3_512=$(openssl dgst -sha3-512 "$useradd_file_path" 2>/dev/null | awk '{print $2}')
            
            # それでも取得できない場合はエラー
            if [ -z "$actual_sha3_512" ]; then
                echo "エラー: SHA3-512ハッシュの計算に失敗しました。sha3sumまたはOpenSSLがインストールされていることを確認してください"
                exit 1
            fi
        fi

        # 両方のハッシュ値が一致した場合のみ処理を続行
        if [ "$actual_sha512" == "$useradd_hash" ] && [ "$actual_sha3_512" == "$useradd_hash_sha3" ]; then
            echo "ハッシュ検証が成功しました。ユーザー作成を続行します。"
            
            # 実行権限を付与
            chmod +x "$useradd_file_path"
            
            # スクリプトを実行
            source "$useradd_file_path"
            
            # 実行後に削除
            rm -f "$useradd_file_path"
        else
            echo "エラー: ハッシュ検証に失敗しました。"
            echo "期待されるSHA512: $useradd_hash"
            echo "実際のSHA512: $actual_sha512"
            echo "期待されるSHA3-512: $useradd_hash_sha3"
            echo "実際のSHA3-512: $actual_sha3_512"
            
            # セキュリティリスクを軽減するため、検証に失敗したファイルを削除
            rm -f "$useradd_file_path"
            exit 1
        fi
        end_message

    # ドキュメントルート所有者変更
    start_message "ドキュメントルート所有者変更"
    echo "ドキュメントルートの所有者をunicorn:apacheに変更しています..."
    chown -R unicorn:apache /var/www/html
    echo "所有者の変更が完了しました"
    end_message "ドキュメントルート所有者変更"

    # unicorn.cnf所有者変更
    start_message "unicorn.cnf所有者変更"
    echo "unicornユーザーでMySQLにログインできるようにします"
    chown -R unicorn:unicorn /etc/my.cnf.d/unicorn.cnf
    echo "所有者の変更が完了しました"
    end_message "unicorn.cnf所有者変更"


    # SELinux設定
start_message "SELinux設定"
    # SELinuxの状態を確認
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
    echo "現在のSELinux状態: $SELINUX_STATUS"
    
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        echo "SELinuxがEnforcing状態のため、必要なポリシーを設定します..."
        
        # ドキュメントルートのコンテキスト設定
        echo "ドキュメントルートのSELinuxコンテキストを設定しています..."
        semanage fcontext -a -t httpd_sys_content_t "/var/www/html(/.*)?"
        restorecon -Rv /var/www/html
        
        # ウェブユーザーグループを作成（存在しない場合）
        if ! getent group webusers > /dev/null; then
            groupadd webusers
            echo "webusersグループを作成しました"
        fi
        
        # 必要なユーザーをwebusersグループに追加（unicornユーザーを例として）
        if id "unicorn" &>/dev/null; then
            usermod -a -G webusers unicorn
            echo "unicornユーザーをwebusersグループに追加しました"
            usermod -a -G webusers apache
            echo "apacheユーザーをwebusersグループに追加しました"
        fi
        
        # ドキュメントルートのパーミッション設定
        echo "ウェブルートディレクトリの所有権と権限を設定しています..."
        chown apache:webusers /var/www/html
        chmod 775 /var/www/html
        chmod g+s /var/www/html
        
        # SELinuxコンテキストとボールを設定
        echo "SELinuxのセキュリティコンテキストと追加ポリシーを設定しています..."
        semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html(/.*)?"
        restorecon -Rv /var/www/html
        
        # 必要なSELinuxボール設定
        setsebool -P httpd_can_network_connect=1
        setsebool -P httpd_read_user_content=1
        setsebool -P httpd_enable_homedirs=1
        
        echo "SELinuxのポリシー設定が完了しました"
        echo "webusersグループのメンバーは /var/www/html 配下で自由にコンテンツを作成できます"
        echo "注意: 新しいユーザーを追加する場合は 'usermod -a -G webusers ユーザー名' を実行してください"
    elif [ "$SELINUX_STATUS" = "Permissive" ]; then
        echo "SELinuxはPermissive状態です。必要に応じてEnforcing状態に変更してください。"
        echo "※Enforcing状態に変更する場合は、再度このスクリプトを実行するか、SELinuxポリシーを手動で設定してください。"
    else
        echo "SELinuxが無効またはインストールされていないため、SELinuxポリシー設定をスキップします"
    fi
    end_message "SELinux設定"

    # Apacheサービス設定
    start_message "Apacheサービス設定"
    echo "Apache HTTPサービスを起動しています..."
    systemctl start httpd.service
    echo "Apache HTTPサービスを自動起動に設定しています..."
    systemctl enable httpd
    echo "Apache HTTPサービスの状態:"
    systemctl list-unit-files --type=service | grep httpd
    echo "Apacheサービスの設定が完了しました"
    end_message "Apacheサービス設定"

    # PHP-fpmのサービス設定
    start_message "PHP-fpmのサービス設定"
    echo "PHP-FPMサービスを起動しています..."
    systemctl start php-fpm.service
    echo "PHP-FPMサービスを自動起動に設定しています..."
    systemctl enable php-fpm
    echo "PHP-FPMサービスの状態:"
    systemctl list-unit-files --type=service | grep php-fpm
    echo "PHP-FPMサービスの設定が完了しました"
    end_message "PHP-fpmのサービス設定"

# ファイアウォール設定
    start_message "ファイアウォール設定"
    echo "ファイアウォールでHTTPを許可しています..."
    firewall-cmd --permanent --add-service=http
    echo "ファイアウォールでHTTPSを許可しています..."
    firewall-cmd --permanent --add-service=https
    echo "ファイアウォール設定を再読み込みしています..."
    firewall-cmd --reload
    echo "ファイアウォールの現在の設定:"
    firewall-cmd --list-all
    echo "ファイアウォール設定が完了しました"
    end_message "ファイアウォール設定"

        # 権限設定
        start_message "権限設定"
        echo "デフォルトのumaskを0002に設定しています..."
        umask 0002
        end_message "権限設定"


cat <<EOF
LAMP環境構築完了！

アクセス方法:
- http://IPアドレス   または ドメイン名
- https://IPアドレス  または ドメイン名

設定ファイル: /etc/httpd/conf.d/ドメイン名.conf
ドキュメントルート: /var/www/html

セキュリティ設定:
- ディレクトリトラバーサル対策として、PHPの実行範囲をドキュメントルート(/var/www/html)に制限しています
- ファイルアップロード上限: 32MB

SELinux設定:
- SELinuxがEnforcing状態で稼働しています（標準設定）
- ドキュメントルート(/var/www/html)には通常のWebコンテンツ用ポリシーを適用
- PHP-FPMとの接続を許可済み
- データベースへのネットワーク接続を許可するには、以下のコマンドを実行してください:
  sudo setsebool -P httpd_can_network_connect_db=1

データベース管理:
- phpMyAdminはインストールされていません。必要な場合は別途インストールしてください
- phpMyAdminをインストールする場合、SELinuxの追加設定が必要になる場合があります
- MySQLなどのデータベースを利用する場合は、上記SELinux設定が必要となります

注意事項:
- WordPressやLaravelなどのフレームワークで大きなファイルをアップロードする場合:
  1. php.ini編集: /etc/php.ini の「upload_max_filesize」と「post_max_size」の値を変更
  2. .htaccess使用: ドキュメントルート内の.htaccessファイルに以下を追記
    php_value upload_max_filesize 64M
    php_value post_max_size 64M
    php_value memory_limit 128M
- Apache再起動は不要ですが、PHP-FPMの再起動が必要です: systemctl restart php-fpm
- HTTP/2を有効にするには、SSLの設定ファイルに「Protocols h2 http/1.1」を追記してください
- ドキュメントルートの所有者: unicorn
- ドキュメントルートのグループ: webusers
- 認証情報は /root/mysql_credentials.txt に保存されています
- セキュリティのため、重要な環境では認証情報をより安全な場所に移動することを検討してください
- mysql --defaults-file=/etc/my.cnf.d/unicorn.cnf コマンドでMySQLに接続できます
EOF

else
    echo "エラー: このスクリプトはRHEL/CentOS/AlmaLinux/Rocky Linux/Oracle Linux 8または9専用です。"
    echo "検出されたOS: $DIST_NAME"
    echo "検出されたOSバージョン: $DIST_MAJOR_VERSION"
    exit 1
fi