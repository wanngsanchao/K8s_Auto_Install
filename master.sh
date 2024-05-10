#!/bin/sh
#关闭防火墙
systemctl stop firewalld && systemctl disable firewalld
#关闭se
setenforce 0 && sed -i 's/SELINUX=enabled/SELINUX=disabled/' /etc/selinux/config 
swapoff -a

masterIP=$1
softdir="/tmp"

echo -e "#####################################解压KubernetesSoft文件#####################################\n"
tar zxvf $softdir/kubernetesSoft.tar.gz -C $softdir

echo -e "#####################################Step1.安装etcd#####################################\n"

#将可执行文件放到/usr/bin目录下
mv $softdir/kubernetesSoft/master/bin/{etcd,etcdctl} /usr/bin/
#创建配置文件目录和日志目录,将配置文件放到/etc/etcd/下
mkdir -p /etc/etcd && mv $softdir/kubernetesSoft/master/config/etcd.conf /etc/etcd/ 
#创建数据存储目录
mkdir -p /var/lib/etcd
#创建etcd配置文件
#创建systemd服务配置文件usr/lib/systemd/system/etcd.service
cat >/usr/lib/systemd/system/etcd.service <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
EnvironmentFile=/etc/etcd/etcd.conf
#User=etcd
# set GOMAXPROCS to number of processors
ExecStart=/usr/bin/etcd --name=\${ETCD_NAME} --data-dir=\${ETCD_DATA_DIR} --listen-client-urls=\${ETCD_LISTEN_CLIENT_URLS} --advertise-client-urls=\${ETCD_ADVERTISE_CLIENT_URLS}
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

#启动etcd服务
systemctl start etcd.service
#设置开机启动
systemctl enable ectd.service
#查看etcd服务状态
systemctl status etcd.service
#配置flannel的网络模式
etcdctl --endpoints=http://$masterIP:2379 set /coreos.com/network/config '{"Network": "172.16.0.0/16", "SubnetLen": 24, "SubnetMin": "172.16.1.0","SubnetMax": "172.16.5.0", "Backend": {"Type": "vxlan"}}'

echo -e "#####################################Step2.安装kube-apiserver#####################################\n"

#将可执行文件放到/usr/bin目录下
mv $softdir/kubernetesSoft/master/bin/kube-apiserver /usr/bin/
#创建配置文件目录和日志目录
mkdir -p /etc/kubernetes && mkdir -p /var/log/kubernetes/kube-apiserver
#创建/etc/kubernetes/apiserver配置文件
cat >/etc/kubernetes/apiserver <<EOF
KUBE_API_ARGS="--etcd_servers=http://$masterIP:2379 --insecure-bind-address=0.0.0.0 --insecure-port=8080 --service-cluster-ip-range=10.10.0.0/16 --service-node-port-range=1-65535 --admission_control=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota --logtostderr=false --log-dir=/var/log/kubernetes/kube-apiserver --v=2"
EOF
#创建systemd服务配置文件usr/lib/systemd/system/etcd.service
cat >/usr/lib/systemd/system/kube-apiserver.service <<EOF
#将kube-apiserver的可执行文件复制到/user/bin目录下一遍可以全局调用
#编写systemd服务文件/usr/lib/systemd/system/kube-apiserver.service
#Unit单元只表示启动顺序和依赖没有关系
[Unit]
Description=Kubenetes API SERVER
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
#服务要在etcd启动之后才可以启动
After=etcd.service
Wants=etcd.service

#表示服务的启动行为
[Service]
Type=notify
EnvironmentFile=/etc/kubernetes/apiserver
ExecStart=/usr/bin/kube-apiserver \$KUBE_API_ARGS
Restart=on-failure
LimitNOFILE=65536

#指定服务启动的用户组
[Install]
WantedBy=mulit-user.target
EOF
#启动kube-apiserver.service服务
systemctl start kube-apiserver.service
#设置开机启动
systemctl enable kube-apiserver.service
#查看kube-apiserver.service服务状态
systemctl status kube-apiserver.service

echo -e "#####################################Step3.安装kube-controller-mannager#####################################\n"

#将可执行文件放到/usr/bin目录下
mv $softdir/kubernetesSoft/master/bin/{kube-controller-manager,kubectl} /usr/bin/
#创建配置文件目录和日志目录和日志目录
mkdir -p /etc/kubernetes && mkdir -p /var/log/kubernets/kube-controller-manager
#创建/etc/kubernetes/apiserver配置文件
cat >/etc/kubernetes/controller-manager <<EOF
KUBE_CONTROLLER_MANAGER_ARGS="--master=http://127.0.0.1:8080 --logtostderr=false --log-dir=/var/log/kubernets/kube-controller-mannager --v=2"
EOF
#创建systemd服务配置文件usr/lib/systemd/system/etcd.service
cat >/usr/lib/systemd/system/kube-controller-manager.service <<EOF
#将kube-controller-manager的可执行文件复制到/user/bin目录下一遍可以全局调用
#编写systemd服务文件/usr/lib/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
#仅仅表示启动顺序,并不表示依赖
After=kube-apiserver.service
#表示依赖,一定要依赖的服务先启动
Requires=kube-apiserver.service

#设置启动行为
#加载文件以便其他模块来调用文件中的内容类似于"."或是"source"
[Service]
EnvironmentFile=/etc/kubernetes/controller-manager
#定义启动进程时执行的命令,后面的$KUBE_CONTROLLER_MANAGER_ARGS就是从EnvironmentFile的文件中加载过来的变量
ExecStart=/usr/bin/kube-controller-manager \$KUBE_CONTROLLER_MANAGER_ARGS
#定义进程退出时systemd的重启方式,这里Restart有多个值可以设置,其中on-failure表示非正常退出时(退出码为非0,此种情况很
#有可能属于程序自身异常退出;也包含被信号终止或超时信号终止#有可能是被人为的破坏进程,超时还不太清楚具体啥意思)才会重启
Restart=on-failure
#设置进程最大可以打开的文件数(可以参考ulimit资源控制)
LimitNOFILE=65536

#指定啥时候启动进程
[Install]
#指定kube-controller-manager服务所属的服务组是multi-user.target, 因为这个服务组中的服务都是开机启动的,这也是systemctl enable 能够设置开机启动的原因
WantedBy=multi-user.target
EOF
#启动kube-controller-manager.service服务
systemctl start kube-controller-manager.service
#设置开机启动
systemctl enable kube-controller-manager.service
#查看kube-controller-manager.service服务状态
systemctl status kube-controller-manager.service

echo -e "#####################################Step4.安装kube-scheduler#####################################\n"

#将可执行文件放到/usr/bin目录下
mv $softdir/kubernetesSoft/master/bin/kube-scheduler /usr/bin/
#创建配置文件目录和日志目录
mkdir -p /etc/kubernetes && mkdir -p /var/log/kubernets/kube-scheduler
#创建/etc/kubernetes/apiserver配置文件
cat >/etc/kubernetes/scheduler <<EOF
KUBE_SCHEDULER_ARGS="--master=http://127.0.0.1:8080 --logtostderr=false --log-dir=/var/log/kubernets/kube-scheduler --v=2"
EOF
#创建systemd服务配置文件usr/lib/systemd/system/etcd.service
cat >/usr/lib/systemd/system/kube-scheduler.service <<EOF
#将kube-scheduler的可执行文件复制到/user/bin目录下一遍可以全局调用
#编写systemd服务文件/usr/lib/systemd/system/kube-scheduler.service
#设置启动顺序以及依赖
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github/GoogleCloudPlatform/kubernetes/
After=kube-apiserver.service
Requires=kube-apiserver.service

[Service]
EnvironmentFile=/etc/kubernetes/scheduler
ExecStart=/usr/bin/kube-scheduler \$KUBE_SCHEDULER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
#启动kube-scheduler.service服务
systemctl start kube-scheduler.service
#设置开机启动
systemctl enable kube-scheduler.service
#查看kube-scheduler.service服务状态
systemctl status kube-scheduler.service

echo -e "#####################################Step5.清理软件安装包#####################################\n"
rm -rf $softdir/kubernetesSoft* $softdir/master.sh
