#!/bin/sh
#description install kubelet&docker
#date 2020-03-12
#Author wsc

#关闭防火墙、se、内存交换
nodename=$(hostname)
masterIP=$1
softdir="/tmp"

systemctl stop firewalld && systemctl disable firewalld
setenforce 0 && sed -i 's/SELINUX=enabled/SELINUX=disabled/' /etc/selinux/config 
swapoff -a

echo -e "#####################################解压KubernetesSoft文件#####################################\n"
tar -zxvf $softdir/kubernetesSoft.tar.gz -C $softdir

echo -e "#####################################step1.安装flanneled#####################################\n"
#解压docker二进制文件
#将docker的二进制文件放到/usr/bin中
mv $softdir/kubernetesSoft/node/bin/{flanneld,mk-docker-opts.sh} /usr/bin
#创建flanneled配置文件目录
mkdir -p /etc/kubernetes
#通过mk-docker-opts.sh创建docker启动时所需要的网络参数，这个网络参数将会凡在下面的文件中
mkdir -p /run/flannel
#创建flanneled服务的配置文件,有个坑的地方下面的-etcd-prefix=/coreos.com/network因为flannel会自动加载，
#如果key的结尾有个config,那么就不需要添加一个config
cat >/etc/kubernetes/flanneld.conf<<EOF
FLANNEL_OPTIONS="--etcd-endpoints=http://$masterIP:2379 --ip-masq=true --etcd-prefix=/coreos.com/network/"
EOF
#创建flanneld的system的服务文件
cat >/usr/lib/systemd/system/flanneld.service <<EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network-online.target network.target
Before=docker.service

[Service]
Type=notify
EnvironmentFile=/etc/kubernetes/flanneld.conf
ExecStart=/usr/bin/flanneld \$FLANNEL_OPTIONS
#flannled启动之后根据flannnel从etcd获取到vxlan网段信息生效docker启动的网络参数信息,文件会默认生成到/run/docker_opts.env
ExecStartPost=/usr/bin/mk-docker-opts.sh -c
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

#刷新system管理文件
systemctl daemon-reload
#启动flanned服务
systemctl start flanneld
#检查flanneld服务状态
systemctl enable flanneld

echo -e "#####################################Step2.安装docker#####################################\n"
#解压docker二进制文件
#将docker的二进制文件放到/usr/bin中
mv $softdir/kubernetesSoft/node/bin/docker/* /usr/bin

#创建docker配置文件目录
mkdir -p /etc/docker
mkdir -p /data/docker-root

#创建/etc/docker/daemon.json的配置文件
cat > /etc/docker/daemon.json << EOF
{
"graph":"/data/docker-root",
"registry-mirrors": ["https://7bezldxe.mirror.aliyuncs.com"]
}
EOF

#创建docker的systemd服务文件
cat > /usr/lib/systemd/system/docker.service << EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target firewalld.service

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
EnvironmentFile=/run/docker_opts.env
ExecStart=/usr/bin/dockerd \$DOCKER_OPTS
ExecReload=/bin/kill -s HUP \$MAINPID
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

#启动docker服务
systemctl start docker
#查看docker服务状态
systemctl status docker
#设置docker的开机自启
systemctl enable docker
echo -e "#####################################安装step3.kubelet#####################################\n"
mv $softdir/kubernetesSoft/node/bin/kubelet /usr/bin/
mv $softdir/kubernetesSoft/node/bin/kube-proxy /usr/bin/
#创建配置文件目录
mkdir -p /etc/kubernetes
#创建kubelet保存数据的目录
mkdir -p /var/lib/kubelet
#创建日志存储目录
mkdir -p /var/log/kubernetes/kubelet
#创建/etc/kubernetes/apiserver配置文件
cat >/etc/kubernetes/kubelet <<EOF
KUBELET_ARGS="--api-servers=http://$masterIP:8080 --hostname-override=$nodename --logtostderr=false --log-dir=/var/log/kubernetes/kubelet --v=2"
EOF
#创建systemd服务配置文件/usr/lib/systemd/system/kubelet.service
cat >/usr/lib/systemd/system/kubelet.service <<EOF
#将kubelet的可执行文件复制到/user/bin目录下一遍可以全局调用
#编写systemd服务文件/usr/lib/systemd/system/kubelet.service
#设置启动顺序和依赖
[Unit]
Description=Kubenetes Kubelet Server
Documentation=https://github.com/GoogleCloudPlatform/kubenetes
After=docker.service
Requires=docker.service

#设置启动行为
[Service]
#是kubelet保存数据的目录,需要提前手动创建,疑问这个目录究竟保存的是啥数据
WorkingDirectory=/var/lib/kubelet
EnvironmentFile=/etc/kubernetes/kubelet
ExecStart=/usr/bin/kubelet \$KUBELET_ARGS
Restart=on-failure

#设置启动服务组
[Install]
WantedBy=multi-user.target
EOF
#启动kubelet.service服务
systemctl start kubelet.service
#设置开机启动
systemctl enable kubelet.service
#查看kubelet.service服务状态
systemctl status kubelet.service

echo -e "#####################################安装step4.kube-proxy#####################################\n"
# 复制文件到Path目录
mv $softdir/kubernetesSoft/node/bin/kube-proxy /usr/bin/
# 创建配置文件目录，单独使用步骤脚本时不能省略
# mkdir -p /etc/kubernetes
# 创建日志存储目录
mkdir -p /var/log/kubernetes/kube-proxy
#创建/etc/kubernetes/apiserver配置文件
cat >/etc/kubernetes/kube-proxy <<EOF
KUBE_PROXY_ARGS="--master=http://$masterIP:8080 --logtostderr=false --log-dir=/var/log/kubernetes/kube-proxy --v=2"
EOF
#创建kube-proxy日志保存的目录，单独使用步骤脚本时不能省略
# mkdir -p /var/lib/kubernetes
#创建systemd服务配置文件/usr/lib/systemd/system/kube-proxy.service
cat >/usr/lib/systemd/system/kube-proxy.service <<EOF
#将kube-proxy的可执行文件复制到/user/bin目录下一遍可以全局调用
#编写systemd服务文件/usr/lib/systemd/system/kube-proxy.service
#设置启动顺序和依赖文件
[Unit]
Description=Kubenetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
#在网络服务之后在开启
After=network.target
Requires=network.service

#设置启动行为
[Service]
EnvironmentFile=/etc/kubernetes/kube-proxy
ExecStart=/usr/bin/kube-proxy \$KUBE_PROXY_ARGS
Restart=on-failure
LimitNOFILE=65536

#设置启动用户组
[Install]
WantedBy=multi-user.target
EOF
#启动kube-proxy.service服务
systemctl start kube-proxy.service
#设置开机启动
systemctl enable kube-proxy.service
#查看kube-proxy.service服务状态
systemctl status kube-proxy.service

echo -e "#####################################清理安装包文件#####################################\n"
#rm -rf $softdir/kubernetesSoft* $softdir/node.sh
