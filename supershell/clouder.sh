#!/bin/bash
. /etc/init.d/functions
shopt -s extglob
clear
stty erase ^H

APPDIR=$(whiptail --title "An application directory" \
    --inputbox "Which directory do you want to create?" \
    10 60 /silis 3>&1 1>&2 2>&3)
: ${APPDIR:="/silis"} && mkdir -p ${APPDIR}
: ${RAWURL:="https://raw.githubusercontent.com/musisanDev/The-Beauty-of-Terminal/master/"}


# change hostname & write into hosts
config::hostname(){
    local HN=$(whiptail --title "New HostName" --inputbox "Specify an hostname"\
        10 60 3>&1 1>&2 2>&3)
    /usr/bin/hostnamectl set-hostname ${HN}
    local innerIp=$(hostname -I)
    echo -n "$innerIp $HN" >> /etc/hosts
}

# change ssh port & banned root login with password
config::sshd(){
    local sshConfig=/etc/ssh/sshd_config
    local SP=$(whiptail --title "New SSHPort" --inputbox "Specify an valid port"\
        10 30 3>&1 1>&2 2>&3)
    sed -i "/22/aPort ${SP}" ${sshConfig}
    sed -i '/^Pass/s/yes/no/' ${sshConfig}
    service sshd restart
}

# generate ssh key for login into server
new::sshkey(){
    local outFile=/root/.ssh/id_rsa
    /usr/bin/ssh-keygen -t rsa -b 4096 -N '' -f ${outFile}
}

# delete hosteye & bcm-agent
remove::hostapp(){
    {
        service hosteye stop
        service bcm-agent stop
        service aegis stop
        /usr/sbin/chkconfig --del hosteye
        /usr/sbin/chkconfig --del bcm-agent
        /usr/sbin/chkconfig --del aegis
        service aegis uninstall
        rm -f /etc/init.d/{hosteye,bcm-agent,aegis}
        rm -rf /opt/{avalokita,bcm-agent,hosteye,rh}
        rm -rf /usr/local/aegis
    } &>/dev/null
    test $? -eq 0 && action "uninstall host service"
}

# stop & disable rpcbind
remove::service(){
    {
        systemctl stop rpcbind.service
        systemctl disable rpcbind.service
        systemctl mask rpcbind.service
        systemctl stop rpcbind.socket
        systemctl disable rpcbind.socket
        systemctl mask rpcbind.socket
    } &> /dev/null
    {
        systemctl stop aliyun
        systemctl disable aliyun
        rm -rf /usr/sbin/aliyun-*
        rm -rf /etc/systemd/system/aliyun.service
        rm -rf /usr/local/share/aliyun-assist/
    } &> /dev/null
    echo > /etc/motd && return 0
}

# update tsinghua mirrors
config::repo(){
    if ! ping -W 2 -c 3 www.google.com &>/dev/null ; then
        baseRepo=/etc/yum.repos.d/CentOS-Base.repo
        cd `echo ${baseRepo%C*}` && \
            action "remove origin base.repo" rm -f !(CentOS-Base.repo|epel.repo) && \
            cd -
        for repoFile in `echo ${baseRepo%C*}`/*;do
            sed -i '/baseurl/s/baidubce.com/tuna.tsinghua.edu.cn/' ${repoFile} &>/dev/null
            sed -i '/baseurl/s/cloud.aliyuncs.com/tuna.tsinghua.edu.cn/' ${repoFile} &>/dev/null
            sed -i '/mirrors/s/http/https/' ${repoFile}
        done
    fi
    /bin/yum makecache
}

# written .vimrc & .bashrc
append::rc(){
    vimStr="set nocompatible\nset backspace=2\nset nu\nset encoding=utf-8\nset ts=4\nset sw=4\nset smarttab\nset ai\nset si\nset hlsearch\nset incsearch\nset expandtab\nsyntax on\nautocmd FileType yaml setlocal ai ts=2 sw=2 expandtab\nfiletype plugin indent on"
    echo -e ${vimStr} > ${HOME}/.vimrc
cat >> ${HOME}/.bashrc <<'EOF'
    export PS1="[\[\e[37m\]\h\[\e[m\] \[\e[33m\]\W\[\e[m\]]\[\e[32m\]\\$\[\e[m\] "
EOF
}

# go env
new::goenv(){
    goFile=go1.12.7.linux-amd64.tar.gz
    if wget https://studygolang.com/dl/golang/${goFile};then
        tar zxf ${goFile} -C . && rm -f ${goFile} && mv go /usr/local/golang &>/dev/null
    fi
cat >> ${HOME}/.bashrc <<'EOF'
    export PATH=$PATH:/usr/local/golang/bin:$HOME/go/bin
    export GOBIN="${HOME}/go/bin"
    # export GOPROXY=https://goproxy.io
EOF
}

pre::package(){
    yum -y install net-snmp sendmail openssl-devel gcc gcc-c++ vim tmux lsof lrzsz yum-utils
}

new::iptables(){
    systemctl stop firewalld
    systemctl disable firewalld
    yum -y update
    yum -y install iptables-services
    systemctl enable iptables.service
    systemctl start iptables.service
    {
        iptables -R INPUT 4 -m state --state NEW -p tcp --dport ${SP} -j ACCEPT
        iptables -D INPUT 5
        iptables -P INPUT DROP
        service iptables save
    }
}

new::mysql(){
    local repoRPM='mysql57-community-release-el7-10.noarch.rpm'
    wget https://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/${repoRPM}
    rpm -ivh ${repoRPM} 
    yum -y install mysql mysql-server
    rm -f $repoRPM
}

new::nginx(){
    wget ${RAWURL}/repos/nginx.repo -P /etc/yum.repos.d/
    yum install nginx -y
    enen(){
        ( cd /tmp && \
            nginxTar='nginx-1.16.0.tar.gz' && \
            wget http://nginx.org/download/${nginxTar} && \
            tar zxf $nginxTar && \
            mkdir -p ~/.vim &>/dev/null && \
            cp -rf ${nginxTar%.tar.gz}/contrib/vim/* ~/.vim && \
            rm -rf ${nginxTar%.tar.gz}* )
        systemd enable nginx
    }
    if (whiptail --title "Yes/No" --yesno "Do you need a color matching nginx configuration file?" 10 60) then
        enen
    else
        echo "Skipping it..." && sleep 1
    fi
}

new::prometheus(){
    prometheusTar='prometheus-2.11.1.linux-amd64.tar.gz'
    mkdir -p ${APPDIR}/prometheus/data
    useradd -r -d ${APPDIR}/prometheus -c "Prometheus Server" -s /sbin/nologin prometheus
    wget https://github.com/prometheus/prometheus/releases/download/v2.11.1/${prometheusTar}
    tar zxvf ${prometheusTar} && \
        mv ${prometheusTar%.tar.gz}/* ${APPDIR}/prometheus && \
        rm -rf ${prometheusTar%.tar.gz}
    chown -R prometheus:prometheus ${APPDIR}/prometheus
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/prometheus.service && \
        sed -i "/apps/s/apps/${APPDIR#/}/g" prometheus.service && \
        systemctl daemon-reload && systemctl enable prometheus.service )
}

new::alertmanager(){
    amTar='alertmanager-0.18.0.linux-amd64.tar.gz'
    mkdir -p ${APPDIR}/alertmanager/data
    useradd -r -d ${APPDIR}/alertmanager -c "Alert Server" -s /sbin/nologin alertmanager
    wget https://github.com/prometheus/alertmanager/releases/download/v0.18.0/${amTar}
    tar zxvf ${amTar} && \
        mv ${amTar%.tar.gz}/* ${APPDIR}/alertmanager && \
        rm -rf ${amTar%.tar.gz}
    chown -R alertmanager:alertmanager ${APPDIR}/alertmanager
    # 需要替换
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/alertmanager.service && \
        sed -i "/apps/s/apps/${APPDIR#/}/g" alertmanager.service && \
        systemctl daemon-reload && systemctl enable alertmanager.service )
}

new::node(){
    nodeTar='node_exporter-0.18.1.linux-amd64.tar.gz'
    mkdir -p ${APPDIR}/node_exporter
    useradd -r -d ${APPDIR}/node_exporter -c "Node Check Server" -s /sbin/nologin nodeexporter
    wget https://github.com/prometheus/node_exporter/releases/download/v0.18.1/$nodeTar
    tar zxvf ${nodeTar} && \
        mv ${nodeTar%.tar.gz}/* ${APPDIR}/node_exporter && \
        rm -rf ${nodeTar%.tar.gz}
    chown -R nodeexporter:nodeexporter ${APPDIR}/node_exporter
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/node_exporter.service && \
        sed -i "/apps/s/apps/${APPDIR#/}/g" node_exporter.service && \
        systemctl daemon-reload && systemctl enable node_exporter.service )
}

new::redis(){
    redisTar='redis-4.0.14.tar.gz'
    useradd -r -d ${APPDIR}/redis -c "Redis Server" -s /sbin/nologin redis
    mkdir -p ${APPDIR}/redis/6379/{log,conf,data,var}
    wget http://download.redis.io/releases/redis-4.0.14.tar.gz
    tar zxvf $redisTar
    ( cd ${redisTar%.tar.gz} && make PREFIX=${APPDIR}/redis MALLOC=libc install )
    ( cd ${APPDIR}/redis/6379/conf && \
        wget ${RAWURL}/conf/redis.conf && \
        sed -i "/apps/s/apps/${APPDIR#/}/g" redis.conf )
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/redis@.service && \
        sed -i "/apps/s/apps/${APPDIR#/}/g" redis@.service && \
        systemctl daemon-reload && systemctl enable redis@6379.service )
    chown -R redis:redis ${APPDIR}/redis
}

new::mongod(){
    mongoTar='mongodb-linux-x86_64-rhel70-4.0.11.tgz'
    useradd -r -d ${APPDIR}/mongodb -c "Mongodb Server" -s /sbin/nologin mongod
    mkdir -p ${APPDIR}/mongodb/27017/{conf,data,log}
    wget https://fastdl.mongodb.org/linux/${mongoTar}
    tar zxvf ${mongoTar} && mv ${mongoTar%.tgz}/bin ${APPDIR}/mongodb
    ( cd ${APPDIR}/mongodb/27017/conf && \
        wget ${RAWURL}/conf/mongod.yml && \
        sed -i "/apps/s/apps/${APPDIR#/}/g" mongod.yml )
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/mongod@.service && \
        sed -i "/apps/s/apps/${APPDIR#/}/g" mongod@.service && \
        systemctl daemon-reload && systemctl enable mongod@27017.service )
    chown -R mongod:mongod ${APPDIR}/mongodb
}

SSR(){
    local libsodium='libsodium-1.0.18.tar.gz'
    local master='shadowsocks-master.zip'
    local sspwd=$(whiptail --title "Shadowsocks Passwd" --passwordbox "Specify an passwd"\
        10 40 3>&1 1>&2 2>&3)
    local dport=$(shuf -i 9000-20000 -n 1)
    local sscipher='aes-256-cfb'
    local service='shadowsocks'
    yum install -y python python-devel python-setuptools openssl openssl-devel unzip gcc automake autoconf make libtool
    cat > /etc/shadowsocks.json <<-EOF
{
    "server":"0.0.0.0",
    "server_port":${dport},
    "local_address":"127.0.0.1",
    "local_port":1080,
    "password":"${sspwd}",
    "timeout":300,
    "method":"${sscipher}",
    "fast_open":false
}
EOF
    iptables -I INPUT 3 -m state --state NEW -m tcp -p tcp --dport ${dport} -j ACCEPT
    iptables -I INPUT 3 -m state --state NEW -m udp -p udp --dport ${dport} -j ACCEPT
    service iptables save
    #----------------------
    if [ ! -f /usr/lib/libsodium.a ]; then
        wget https://github.com/musisanDev/The-Beauty-of-Terminal/raw/master/packages/${libsodium}
        tar zxvf ${libsodium} -C .
        ( cd ${libsodium%.tar.gz} && \
            ./configure --prefix=/usr && \
            make && make install )
    fi
    ldconfig

    if [ ! -f ${master} ];then
        wget https://github.com/musisanDev/The-Beauty-of-Terminal/raw/master/packages/${master}
    fi
    unzip ${master} 
    ( cd shadowsocks-master && python setup.py install )

    if [ -f /usr/bin/ssserver ] || [ -f /usr/local/bin/ssserver ]; then
        wget -P /etc/init.d/ https://raw.githubusercontent.com/musisanDev/The-Beauty-of-Terminal/master/systemd/${service}
        chmod +x /etc/init.d/shadowsocks
        chkconfig --add shadowsocks
        chkconfig shadowsocks on
        /etc/init.d/shadowsocks start
    fi
}

# result color
color::result(){
    echo -e "\e[32m✔   " $1 "\e[m"
}

main(){
    config::hostname && color::result "Config Hostname Done."
    config::sshd && color::result "Config Sshd Done."
    new::sshkey && color::result "New Sshkey Done."
    remove::hostapp && color::result "Remove hostapp Done."
    remove::service  && color::result "Remove service of Baidu/Aliyun Cloud Done."
    config::repo  && color::result "Config Repo Done."
    append::rc  && color::result "Append Bashrc Done."
    pre::package && color::result "Package yum Done."
    new::goenv  && color::result "New GO env Done."
    new::iptables && color::result "Firewall Done."
    new::mysql && color::result "MySQL 5.7 Done."
    new::nginx && color::result "Nginx Done."
    new::prometheus && color::result "Prometheus Done."
    new::alertmanager && color::result "Alertmanager Done."
    new::node && color::result "Node Exporter Done."
    new::redis && color::result "Redis Done."
    new::mongod && color::result "Mongodb Done."
    SSR && color::result "SSR Done."
}

main "$@"
