**K8s_Auto_Install Documention**

[![GoDoc Widget]][GoDoc] [![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/569/badge)](https://bestpractices.coreinfrastructure.org/projects/569)

<img src="https://github.com/kubernetes/kubernetes/raw/master/logo/logo.png" width="100">

<font color=red>**1.clone K8s_Auto_Install 项目到本地**</font>
```shell
git clone git@github.com:wanngsanchao/K8s_Auto_Install.git
```

<font color=red>**2.执行步骤**</font>
```shell
#1.自定义/etc/ansible/hosts的主机分组文件，定义master和node的节点
#2.使用ansible-playbook进行k8s集群部署:
ansible-playbook deploy.yml
```
