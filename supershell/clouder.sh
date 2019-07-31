#!/bin/bash
. clouder.conf.sh

shopt -s extglob
PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
export $PATH

clear && SELF_DIR=$(cd $(mktemp -d /tmp/tmp.XXXXX) && pwd -P)
trap "rm -rf ${SELF_DIR:?}/*" EXIT ERR

fb(){
    : ${1:?}
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[0;33m'
    local PLAIN='\033[0m'
    case $1 in
        's')
            echo -e $"${GREEN}✓ $2${PLAIN}"
            sleep 0.5
            return 0
            ;;
        'e')
            echo -e $"${RED}✘ $2${PLAIN}"
            sleep 0.5
            return 1
            ;;
        'w')
            echo -e $"${YELLOW}✻ $2${PLAIN}"
            sleep 0.5
            return 0
            ;;
    esac
}

app_dir(){
    RAWURL="https://raw.githubusercontent.com/musisanDev/The-Beauty-of-Terminal/master/"
    APPDIR=$(whiptail --title "An application directory" --inputbox "Which directory do you want to create?" 10 60 3>&1 1>&2 2>&3)
    [[ ! -z ${APPDIR} && ${APPDIR:0:1} == '/' ]] && {
        fb s "Valid Appdir."
        mkdir -p $APPDIR &>/dev/null
    } || fb e "Invalid Appdir."
}

generate(){
    echo -e "# host_name\nhn_f=1\nhostname=dev.cloud.earth\ninner_ip=172.31.197.71\n# ssh_port_pass\nspp_f=1\nssh_config=/etc/ssh/sshd_config\nssh_port=2268\n# ssh_key\nsk_f=1\nssh_key_file=/root/.ssh/id_rsa\n# host_app\nha_f=1\n# mirrors\nms_f=1\n# vim_bash_rc\nvbr_f=1\n# golang\ng_f=1\ngoDir=/usr/local/golang\n# mysql\nml_f=1\n# nginx\nnx_f=1\ncolorNginx=true\n# nvm\nnm_f=1\n# jenkins\njs_f=1\n# grafana\nga_f=1\n# prometheus\nps_f=1\n# alertmanager\nar_f=1\n# node\nne_f=1\n# redis\nrs_f=1\n# mongod\nmd_f=1\n# ssr\nsr_f=1\n# iptable\nie_f=1\n" > clouder.conf
    test $? -eq 0 && fb s "Generated Config File." || fb e "Generated File Failed."
}

host_name(){
    #local HN=$(whiptail --title "New HostName" --inputbox "Specify an hostname"\
    #    10 60 3>&1 1>&2 2>&3)
    hostnamectl set-hostname ${hostname}
    echo -n "$inner_ip $hostname" >> /etc/hosts
    if [[ `hostname -f` == "$hostname" ]];then
        fb s "Hostname Modified."
    else
        fb e "Hostname Modified Failed."
    fi
}

ssh_port_pass(){
    #local SP=$(whiptail --title "New SSHPort" --inputbox "Specify an valid port"\
    #    10 30 3>&1 1>&2 2>&3)
    sed -i "/22/aPort ${ssh_port}" ${ssh_config}
    sed -i '/^Pass/s/yes/no/' ${ssh_config}
    service sshd restart
    test $? -eq 0 && fb s "SshPort Modified." || fb e "SshPort Modified Failed."
}

ssh_key(){
    ssh-keygen -t rsa -b 4096 -N '' -f ${ssh_key_file}
    test $? -eq 0 && fb s "Sshkey Generated." || {
        fb e "Sshkey Generated Failed."
    }
}

host_app(){
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
        systemctl stop rpcbind.service
        systemctl disable rpcbind.service
        systemctl mask rpcbind.service
        systemctl stop rpcbind.socket
        systemctl disable rpcbind.socket
        systemctl mask rpcbind.socket
        systemctl stop aliyun
        systemctl disable aliyun
        rm -rf /usr/sbin/aliyun-*
        rm -rf /etc/systemd/system/aliyun.service
        rm -rf /usr/local/share/aliyun-assist/
    } &>/dev/null
    test $? -eq 0 && fb s "Host App uninstalled." || {
        fb w "Something was wrong about host-app."
    }
}

mirrors(){
    if ! ping -W 2 -c 3 www.google.com &>/dev/null ; then
        local baseRepo=/etc/yum.repos.d/CentOS-Base.repo
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
    yum -y install net-snmp sendmail openssl-devel gcc gcc-c++ vim tmux lsof lrzsz yum-utils
    test $? -eq 0 && fb s "Yum Mirrors." || {
        fb e "Yum Mirrors Failed."
    }
}

vim_bash_rc(){
    local vimStr="set nocompatible\nset backspace=2\nset nu\nset encoding=utf-8\nset ts=4\nset sw=4\nset smarttab\nset ai\nset si\nset hlsearch\nset incsearch\nset expandtab\nsyntax on\nautocmd FileType yaml setlocal ai ts=2 sw=2 expandtab\nfiletype plugin indent on"
    echo -e ${vimStr} > ${HOME}/.vimrc
cat >> ${HOME}/.bashrc <<'EOF'
    export PS1="[\[\e[37m\]\h\[\e[m\] \[\e[33m\]\W\[\e[m\]]\[\e[32m\]\\$\[\e[m\] "
EOF
    source ${HOME}/.bashrc && fb s "Vim and Bashrc Done." || fb e "Vim and Bashrc Failed."
}

golang(){
    local goFile=go1.12.7.linux-amd64.tar.gz
    if wget https://studygolang.com/dl/golang/${goFile};then
        tar zxf ${goFile} -C . && rm -f ${goFile} && mv go ${goDir} &>/dev/null
    fi
cat >> ${HOME}/.bashrc <<'EOF'
    export PATH=$PATH:/usr/local/golang/bin:$HOME/go/bin
    export GOBIN="${HOME}/go/bin"
    # export GOPROXY=https://goproxy.io
EOF
    source ${HOME}/.bashrc && command -v go
    test $? -eq 0 && fb s "Golang Done." || fb e "Golang Failed."
}


mysql(){
    local repoRPM='mysql57-community-release-el7-10.noarch.rpm'
    wget https://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/${repoRPM}
    rpm -ivh ${repoRPM} && rm -f $repoRPM
    yum -y install mysql mysql-server &> /dev/null
    test $? -eq 0 && fb s "MySQL Server Done." || fb e "MySQL Server Failed."
}

nginx(){
    wget -q ${RAWURL}/repos/nginx.repo -P /etc/yum.repos.d/
    yum install nginx -y &> /dev/null
    systemctl enable nginx
    enen(){
        ( cd /tmp && \
            nginxTar='nginx-1.16.0.tar.gz' && \
            wget http://nginx.org/download/${nginxTar} && \
            tar zxf $nginxTar && \
            mkdir -p ~/.vim &>/dev/null && \
            cp -rf ${nginxTar%.tar.gz}/contrib/vim/* ~/.vim && \
            rm -rf ${nginxTar%.tar.gz}* )
    }
    if [[ $colorNginx == "true" ]];then
        enen
    fi
    command -v nginx &>/dev/null && fb s "Nginx Done." || fb e "Nginx Failed."
}

nvm(){
    wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.34.0/install.sh | bash
    source ~/.bashrc
    nvm install 10.16.0
    command -v npm &>/dev/null && fb s "Npm Done." || fb e "Npm Failed."
}

jenkins(){
    wget -qO /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
    yum install jenkins -y
    if ! which java > /dev/null 2>&1; then
        yum install java-1.8.0-openjdk -y
    fi
    systemctl enable jenkins
    test $? -eq 0 && fb s "Jenkins Done." || fb e "Jenkins Failed."
}

grafana(){
    cat > /etc/yum.repos.d/grafana.repo <<-EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
enabled=1
gpgcheck=0
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
    yum install grafana -y
    # modify smtp via /etc/grafana/grafana.ini 
    sed -i -e "/smtp/aenabled = true\nhost = smtp.163.com:465\nuser = musisan@163.com\npassword = 1101iPerl\nskip_verify = true\nfrom_address = musisan@163.com\nfrom_name = Grafana" /etc/grafana/grafana.ini
    systemctl enable grafana-server
    command -v grafana-cli 1>/dev/null && fb s "Granafa Server Done." || fb e "Grafana Server Failed."
}

prometheus(){
    local prometheusTar='prometheus-2.11.1.linux-amd64.tar.gz'
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
    test $? -eq 0 && fb s "Prometheus Server Done." || fb e "Prometheus Server Failed."
}

alertmanager(){
    local amTar='alertmanager-0.18.0.linux-amd64.tar.gz'
    mkdir -p ${APPDIR}/alertmanager/data
    useradd -r -d ${APPDIR}/alertmanager -c "Alert Server" -s /sbin/nologin alertmanager
    wget https://github.com/prometheus/alertmanager/releases/download/v0.18.0/${amTar}
    tar zxvf ${amTar} && \
        mv ${amTar%.tar.gz}/* ${APPDIR}/alertmanager && \
        rm -rf ${amTar%.tar.gz}
    chown -R alertmanager:alertmanager ${APPDIR}/alertmanager
    ( cd /usr/lib/systemd/system/ && \
        wget ${RAWURL}/systemd/alertmanager.service && \
        sed -i "/apps/s/apps/${APPDIR#/}/g" alertmanager.service && \
        systemctl daemon-reload && systemctl enable alertmanager.service )
    test $? -eq 0 && fb s "AlertManager Done." || fb e "AlertManager Failed."
}

node(){
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
    test $? -eq 0 && fb s "Node Exporter Done." || fb e "Node Exporter Failed."
}

redis(){
    local redisTar='redis-4.0.14.tar.gz'
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
    test $? -eq 0 && fb s "Redis Server Done." || fb e "Redis Server Failed."
}

mongod(){
    local mongoTar='mongodb-linux-x86_64-rhel70-4.0.11.tgz'
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
    test $? -eq 0 && fb s "Mongod Server Done." || fb e "Mongod Server Failed."
}

ssr(){
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
    command -v ssserver && fb s "SSR Done." || fb e "SSR Failed."
}

firewall(){
    systemctl stop firewalld
    systemctl disable firewalld
    yum -y update
    yum -y install iptables-services
    systemctl enable iptables.service
    systemctl start iptables.service
    {
        iptables -R INPUT 4 -m state --state NEW -p tcp --dport ${ssh_port} -j ACCEPT
        iptables -D INPUT 5
        iptables -P INPUT DROP
        service iptables save
    }
}

main(){
    app_dir
    test ! -z $hn_f && host_name
    test ! -z $spp_f && ssh_port_pass
    test ! -z $sk_f && ssh_key
    test ! -z $ha_f && host_app
    test ! -z $ms_f && mirrors
    test ! -z $vbr_f && vim_bash_rc
    test ! -z $g_f && golang
    test ! -z $ml_f && mysql
    test ! -z $nx_f && nginx
    test ! -z $nm_f && nvm
    test ! -z $js_f && jenkins
    test ! -z $ga_f && grafana
    test ! -z $ps_f && prometheus
    test ! -z $ar_f && alertmanager
    test ! -z $ne_f && node
    test ! -z $rs_f && redis
    test ! -z $md_f && mongod
    test ! -z $sr_f && ssr
    test ! -z $ie_f && firewall
}

if [[ "$@" == "-c" ]]; then
    generate
else
    main
fi
