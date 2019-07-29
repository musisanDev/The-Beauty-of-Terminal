#!/bin/bash
. /etc/init.d/functions
shopt -s extglob
stty erase ^H

read -p $'Which directory do you want to create as an application directory?\n' APPDIR
: ${APPDIR:="/silis"}
: ${RAWURL:="https://raw.githubusercontent.com/musisanDev/The-Beauty-of-Terminal/master/"}


# change hostname & write into hosts
config::hostname(){
    read -p $'Enter new hostname: \n' HN
    /usr/bin/hostnamectl set-hostname ${HN}
    local innerIp=$(hostname -I)
    echo -n "$innerIp $HN" >> /etc/hosts
}

# change ssh port & banned root login with password
config::sshd(){
    local sshConfig=/etc/ssh/sshd_config
    read -p $'Enter new port: \n' SP
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
    baseRepo=/etc/yum.repos.d/CentOS-Base.repo
    cd `echo ${baseRepo%C*}` \
        && action "remove origin base.repo" rm -f !(CentOS-Base.repo|epel.repo) \
        && cd -
    for repoFile in `echo ${baseRepo%C*}`/*;do
        sed -i '/baseurl/s/baidubce.com/tuna.tsinghua.edu.cn/' ${repoFile} &>/dev/null
        sed -i '/baseurl/s/cloud.aliyuncs.com/tuna.tsinghua.edu.cn/' ${repoFile} &>/dev/null
        sed -i '/mirrors/s/http/https/' ${repoFile}
    done
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
    yum -y install net-snmp sendmail openssl-dev gcc tmux lsof lrzsz yum-utils
}

new::iptables(){
    systemctl stop firewalld
    systemctl disable firewalld
    yum -y update
    yum -y install iptables-services
    systemctl enable iptables.service
    systemctl start iptables.service
    {
        iptables -P INPUT ACCEPT
        iptables -Z
        iptables -R INPUT -m state --state NEW -p tcp --dport ${SP} -j ACCEPT
        iptables -D INPUT 5
        service iptables save
    }
}

new::mysql(){
    repoRPM='mysql57-community-release-el7-10.noarch.rpm'
    wget https://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/${repoRPM}
    rpm -ivh ${repoRPM} 
    yum -y install mysql mysql-server
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
    }
    read -p $'Do you need a color matching nginx configuration file? [y/n]'
    case $REPLY in
        y|Y|yes)
            enen;;
        *)
            echo "skipping it...";;
    esac
}

new::prometheus(){
    prometheusTar='prometheus-2.11.1.linux-amd64.tar.gz'
    mkdir -p ${APPDIR}/prometheus/data
    useradd -r -d ${APPDIR}/prometheus -c "Prometheus Server" -s /sbin/nologin prometheus
    wget https://github.com/prometheus/prometheus/releases/download/v2.11.1/${prometheusTar}
    tar zxvf ${prometheusTar} && \
        mv ${prometheusTar%.tar.gz}/* ${APPDIR}/prometheus \
        rm -rf ${prometheusTar%.tar.gz}
    chown -R prometheus:prometheus ${APPDIR}/prometheus
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/prometheus.service && \
        sed -i "/apps/s/apps/${APPDIR}/g" prometheus.service && \
        systemctl daemon-reload && systemctl enable prometheus.service )
}

new::alertmanager(){
    amTar='alertmanager-0.18.0.linux-amd64.tar.gz'
    mkdir -p ${APPDIR}/alertmanager/data
    useradd -r -d ${APPDIR}/alertmanager -c "Alert Server" -s /sbin/nologin alertmanager
    wget https://github.com/prometheus/alertmanager/releases/download/v0.18.0/${amTar}
    tar zxvf ${amTar} && \
        mv ${amTar%.tar.gz}/* ${APPDIR}/alertmanager \
        rm -rf ${amTar%.tar.gz}
    chown -R alertmanager:alertmanager ${APPDIR}/alertmanager
    # 需要替换
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/alertmanager.service && \
        sed -i "/apps/s/apps/${APPDIR}/g" alertmanager.service && \
        systemctl daemon-reload && systemctl enable alertmanager.service )
}

new::node(){
    nodeTar='node_exporter-0.18.1.linux-amd64.tar.gz'
    mkdir -p ${APPDIR}/node_exporter
    useradd -r -d ${APPDIR}/node_exporter -c "Node Check Server" -s /sbin/nologin nodeexporter
    wget https://github.com/prometheus/node_exporter/releases/download/v0.18.1/$nodeTar
    tar zxvf ${nodeTar} && \
        mv ${nodeTar%.tar.gz}/* ${APPDIR}/node_exporter \
        rm -rf ${nodeTar%.tar.gz}
    chown -R nodeexporter:nodeexporter ${APPDIR}/nodeexporter
    # 需要替换
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/node_exporter.service && \
        sed -i "/apps/s/apps/${APPDIR}/g" node_exporter.service && \
        systemctl daemon-reload && systemctl enable node_exporter.service )
}

new::redis(){
    redisTar='redis-4.0.14.tar.gz'
    useradd -r -d ${APPDIR}/redis -c "Redis Server" -s /sbin/nologin redis
    mkdir -p ${APPDIR}/redis/6379/{log,conf,data,var}
    wget http://download.redis.io/releases/redis-4.0.14.tar.gz
    tar zxvf $redisTar
    ( cd ${redisTar%.tar.gz} && make PREFIX=${APPDIR}/redis install )
    ( cd ${APPDIR}/redis/6379/conf && \
        wget ${RAWURL}/conf/redis.conf && \
        sed -i "/apps/s/apps/${APPDIR}/g" redis.conf )
    chown -R redis:redis ${APPDIR}/redis
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/redis@.service && \
        sed -i "/apps/s/apps/${APPDIR}/g" redis@.service && \
        systemctl daemon-reload && systemctl enable redis@6379.service )
}

new::mongod(){
    mongoTar='mongodb-linux-x86_64-rhel70-4.0.11.tgz'
    useradd -r -d ${APPDIR}/mongodb -c "Mongodb Server" -s /sbin/nologin mongodb
    mkdir -p ${APPDIR}/mongodb/27017/{conf,data,log}
    wget https://fastdl.mongodb.org/linux/${mongoTar}
    tar zxvf ${mongoTar} && mv ${mongoTar%.tar.gz}/bin ${APPDIR}/mongodb
    ( cd ${APPDIR}/mongodb/27017/conf && \
        wget ${RAWURL}/conf/mongod.yml && \
        sed -i "/apps/s/apps/${APPDIR}/g" mongod.yml )
    chown -R mongod:mongod ${APPDIR}/mongodb
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/mongod@.service && \
        sed -i "/apps/s/apps/${APPDIR}/g" mongod@.service && \
        systemctl daemon-reload && systemctl enable mongod@27017.service )
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
    new::goenv  && color::result "New GO env Done."
    new::iptables && color::result "Firewall Done."
    new::mysql && color::result "MySQL 5.7 Done."
}

main "$@"
