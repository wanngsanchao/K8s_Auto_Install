#!/bin/sh
#description install kubelet&docker
#date 2020-03-12
#Author wsc
#将现在好的文件放到master的tmp目录下即可
#tar -zxvf /tmp/kubernetes-server-linux-amd64.tar.gz /tmp
#将可执行文件放到/usr/bin目录下

#关闭防火墙、se、内存交换
nodename=$(hostname)
masterIP=$(cat /etc/hosts | grep master | awk '{print $1}')
softdir="/tmp"

systemctl stop firewalld && systemctl disable firewalld
setenforce 0 && sed -i 's/SELINUX=enabled/SELINUX=disabled/' /etc/selinux/config 
swapoff -a

echo -e "#####################################解压KubernetesSoft文件#####################################\n"
tar -zxvf $softdir/kubernetesSoft.tar.gz -C $softdir

echo -e "#####################################step1.安装docker#####################################\n"
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
ExecStart=/usr/bin/dockerd
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
echo -e "#####################################安装step2.kubelet#####################################\n"
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

echo -e "#####################################安装step3.kube-proxy#####################################\n"
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
rm -rf $softdir/kubernetesSoft* $softdir/node.sh
