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

# Redhat系で8、9または10の場合のみ処理を実行
if [ -e /etc/redhat-release ] && [[ "$DIST_MAJOR_VERSION" -eq 8 || "$DIST_MAJOR_VERSION" -eq 9 || "$DIST_MAJOR_VERSION" -eq 10 ]]; then

    # Gitリポジトリのインストール
    start_message "Gitリポジトリのインストール"
    echo "Gitをインストールしています..."
    dnf -y install git
    echo "Gitのインストールが完了しました"
    end_message "Gitリポジトリのインストール"

    # EPELリポジトリとremiリポジトリ、MySQL 8.4リポジトリのインストール
    start_message "EPELリポジトリとremiリポジトリのインストール"
    echo "EPELリポジトリとremiリポジトリをインストールします..."

    case $DIST_ID in
        "almalinux")
            GPG_KEY="https://repo.almalinux.org/almalinux/RPM-GPG-KEY-AlmaLinux"
            ;;
        "rocky")
            GPG_KEY="https://download.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-$DIST_VERSION_ID"
            ;;
        "centos-stream" | "centos")
            GPG_KEY="https://www.centos.org/keys/RPM-GPG-KEY-CentOS-Official"
            ;;
        "rhel" | "redhat")
            GPG_KEY="https://www.redhat.com/security/data/fd431d51.txt"
            ;;
        "ol")
            GPG_KEY="https://yum.oracle.com/RPM-GPG-KEY-oracle-ol$DIST_VERSION_ID"
            ;;
        *)
            echo "警告: 認識されないディストリビューションですが、処理を続行します"
            GPG_KEY="https://repo.almalinux.org/almalinux/RPM-GPG-KEY-AlmaLinux"
            ;;
    esac

    rpm --import $GPG_KEY
    dnf remove -y epel-release
    dnf -y install epel-release

    if [ "$DIST_MAJOR_VERSION" = "8" ]; then
        dnf -y install https://rpms.remirepo.net/enterprise/remi-release-8.rpm
    elif [ "$DIST_MAJOR_VERSION" = "9" ]; then
        dnf -y install https://rpms.remirepo.net/enterprise/remi-release-9.rpm
    elif [ "$DIST_MAJOR_VERSION" = "10" ]; then
        dnf -y install https://rpms.remirepo.net/enterprise/remi-release-10.rpm
    fi
    rpm --import https://rpms.remirepo.net/RPM-GPG-KEY-remi

    if [ "$DIST_MAJOR_VERSION" = "8" ]; then
        rpm -ivh https://dev.mysql.com/get/mysql84-community-release-el8-1.noarch.rpm
    elif [ "$DIST_MAJOR_VERSION" = "9" ]; then
        rpm -ivh https://dev.mysql.com/get/mysql84-community-release-el9-1.noarch.rpm
    elif [ "$DIST_MAJOR_VERSION" = "10" ]; then
        rpm -ivh https://dev.mysql.com/get/mysql84-community-release-el10-2.noarch.rpm
    fi
    dnf config-manager --disable mysql84-community
    dnf config-manager --enable mysql84-community
    rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
    echo "リポジトリのインストールが完了しました"
    end_message "EPELリポジトリとremiリポジトリのインストール"

        # システムアップデート
        start_message
        echo "システムを最新版に更新します"
        dnf -y update
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

    mysql_log_message() {
      echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] $1\n"
    }
    mysql_handle_error() {
      mysql_log_message "エラーが発生しました: $1"
      exit 1
    }
    mysql_warn_message() {
      mysql_log_message "警告: $1 - 処理を続行します"
    }

    # 元のMySQLモジュールを無効化（存在する場合のみ）
    mysql_log_message "既存のMySQLモジュールの確認と無効化を試みています..."
    if dnf module list mysql &>/dev/null; then
      mysql_log_message "MySQLモジュールが存在します。無効化を試みます..."
      dnf module disable -y mysql || mysql_warn_message "MySQLモジュールの無効化に失敗しました"
    else
      mysql_log_message "システムにMySQLモジュールが見つかりません。無効化をスキップします。"
    fi

    # インストール
    mysql_log_message "MySQL Community Serverをインストールしています..."
    dnf install -y mysql-community-server || mysql_handle_error "MySQLのインストールに失敗しました"

    mysql_log_message "MySQLのバージョン確認:"
    mysqld --version || mysql_handle_error "MySQLバージョン確認に失敗しました"

    # my.cnfの設定を変える
    mysql_log_message "MySQL設定ファイルを構成しています..."
    if [ -f /etc/my.cnf ]; then
      mv /etc/my.cnf /etc/my.cnf.backup.$(date +%Y%m%d%H%M%S) || mysql_handle_error "my.cnfのバックアップに失敗しました"
    fi
    if [ -f /etc/my.cnf.d/mysql-server.cnf ]; then
      mv /etc/my.cnf.d/mysql-server.cnf /etc/my.cnf.d/mysql-server.cnf.backup.$(date +%Y%m%d%H%M%S) || mysql_handle_error "mysql-server.cnfのバックアップに失敗しました"
    fi

    mkdir -p /var/log/mysql
    chown mysql:mysql /var/log/mysql

    cat <<'MYSQLCNF' > /etc/my.cnf
# MySQL 8.4 設定ファイル
# 参考: http://dev.mysql.com/doc/refman/8.4/en/server-configuration-defaults.html

[mysqld]
# 基本設定
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid

# 文字コード設定
character-set-server = utf8mb4
collation-server = utf8mb4_bin

# セキュリティ設定
default_password_lifetime = 0
max_allowed_packet = 16M
max_connections = 151
bind-address = 127.0.0.1

# パフォーマンス設定
innodb_buffer_pool_size = 128M
join_buffer_size = 2M
sort_buffer_size = 2M
read_rnd_buffer_size = 2M

# Slowクエリログ設定
slow_query_log = ON
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 1.0
log_queries_not_using_indexes = ON

# タイムアウト設定
interactive_timeout = 28800
wait_timeout = 28800

[client]
default-character-set = utf8mb4
MYSQLCNF

    mysql_log_message "MySQLの自動起動を設定しています..."
    systemctl enable mysqld.service || mysql_handle_error "自動起動の設定に失敗しました"

    mysql_log_message "MySQLを起動しています..."
    systemctl start mysqld.service || mysql_handle_error "MySQLの起動に失敗しました"

    mysql_log_message "MySQLのセキュリティ設定を行っています..."
    DB_PASSWORD=$(grep "A temporary password is generated" /var/log/mysqld.log | sed -s 's/.*root@localhost: //')
    if [ -z "$DB_PASSWORD" ]; then
      mysql_handle_error "MySQLの一時パスワードを取得できませんでした"
    fi

    RPASSWORD=$(openssl rand -base64 16 | sed 's/[^a-zA-Z0-9]/#/g' | sed 's/^\([a-z]*\)/\u\1/g' | sed 's/$/@1A/')
    UPASSWORD=$(openssl rand -base64 16 | sed 's/[^a-zA-Z0-9]/#/g' | sed 's/^\([a-z]*\)/\u\1/g' | sed 's/$/@1A/')

    mysql_log_message "MySQLのrootパスワードを変更しています..."
    mysql -u root -p"${DB_PASSWORD}" --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${RPASSWORD}'; FLUSH PRIVILEGES;" || mysql_handle_error "rootパスワードの変更に失敗しました"

    mysql_log_message "アプリケーション用のデータベースとユーザーを作成しています..."
    cat <<SQLEOF >/tmp/createdb.sql
CREATE DATABASE IF NOT EXISTS unicorn DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'unicorn'@'localhost' IDENTIFIED BY '${UPASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES ON unicorn.* TO 'unicorn'@'localhost';
FLUSH PRIVILEGES;
SELECT user, host FROM mysql.user;
SQLEOF

    mysql -u root -p"${RPASSWORD}" -e "source /tmp/createdb.sql" || mysql_handle_error "データベースとユーザーの作成に失敗しました"
    rm -f /tmp/createdb.sql

    mysql_log_message "クライアント設定ファイルを作成しています..."
    cat <<CLIENTEOF >/etc/my.cnf.d/unicorn.cnf
[client]
user = unicorn
password = '${UPASSWORD}'
host = localhost
CLIENTEOF
    chmod 600 /etc/my.cnf.d/unicorn.cnf

    mysql_log_message "MySQLサービスを再起動しています..."
    systemctl restart mysqld.service || mysql_handle_error "MySQLの再起動に失敗しました"

    mysql_log_message "認証情報を保存しています..."
    cat <<CREDEOF >/root/mysql_credentials.txt
# MySQL認証情報 - $(date '+%Y-%m-%d %H:%M:%S')に生成
# このファイルは機密情報を含みます。適切に保護してください。
root_user = root
root_password = ${RPASSWORD}
app_user = unicorn
app_password = ${UPASSWORD}
CREDEOF
    chmod 600 /root/mysql_credentials.txt

    mysql_log_message "MySQLのセキュリティ強化を実施しています..."
    mysql -u root -p"${RPASSWORD}" <<SECEOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SECEOF

    mysql_log_message "MySQL 8.4のインストールと設定が完了しました"
    end_message "MySQLのインストール"

        # ユーザーを作成
        start_message
        echo "unicornユーザーを作成します"

        USERNAME='unicorn'
        PASSWORD=$(< /dev/urandom tr -dc '[:alnum:]' | head -c32)

        useradd -m -s /bin/bash $USERNAME
        if [ $? -ne 0 ]; then
            echo "ユーザー作成に失敗しました。"
            exit 1
        fi
        echo "$PASSWORD" | passwd --stdin $USERNAME

        mkdir -p /home/${USERNAME}/.ssh
        chmod 700 /home/${USERNAME}/.ssh
        ssh-keygen -t ed25519 -N "" -f /home/${USERNAME}/.ssh/${USERNAME}
        chmod 644 /home/${USERNAME}/.ssh/${USERNAME}.pub
        chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh
        cat /home/${USERNAME}/.ssh/${USERNAME}.pub >> /home/${USERNAME}/.ssh/authorized_keys
        chmod 600 /home/${USERNAME}/.ssh/authorized_keys
        chmod 600 /home/${USERNAME}/.ssh/${USERNAME}
        cp /home/${USERNAME}/.ssh/${USERNAME} /home/${USERNAME}/
        chown ${USERNAME}:${USERNAME} /home/${USERNAME}/${USERNAME}
        rm /home/${USERNAME}/.ssh/${USERNAME}

        echo "ed25519 SSH鍵が生成されました。"
        echo "秘密鍵: /home/${USERNAME}/${USERNAME}"
        echo "公開鍵: /home/${USERNAME}/.ssh/${USERNAME}.pub"
        echo "秘密鍵が /home/${USERNAME}/${USERNAME} に移動されました。"
        echo "秘密鍵のパーミッションは 600 に設定されています。"
        echo "このファイルを安全な方法でクライアントマシンに移動し、サーバーからは削除することを強く推奨します。"
        echo "秘密鍵はサーバー上に保管せず、使用するクライアントマシンにのみ保管してください。"
        echo "公開鍵をクライアントマシンの ~/.ssh/authorized_keys ファイルに追加してください。"
        echo "必要に応じて、秘密鍵にパスフレーズを設定してください。"
        echo "ユーザーのパスワードはランダムで生成されています。セキュリティの関係上表示したりファイルに残していないので新しく設定してください。"
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

PHPの動作確認:
- http://IPアドレス または ドメイン名/info.php にアクセスするとphpinfo()の内容が表示されます
- 確認後はセキュリティのため info.php を削除することを推奨します
  (rm -f /var/www/html/info.php)

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
    echo "エラー: このスクリプトはRHEL/CentOS/AlmaLinux/Rocky Linux/Oracle Linux 8、9または10専用です。"
    echo "検出されたOS: $DIST_NAME"
    echo "検出されたOSバージョン: $DIST_MAJOR_VERSION"
    exit 1
fi