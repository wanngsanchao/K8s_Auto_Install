**K8s_Auto_Install Documention**
<font color=red>**1.clone K8s_Auto_Install 项目到本地**</font
```
git clone git@github.com:wanngsanchao/K8s_Auto_Install.git
```
<font color=red>**2.执行步骤**</font>
```
1.自定义/etc/ansible/hosts的主机分组文件，定义master和node的节点
2.使用ansible-playbook进行k8s集群部署:
ansible-playbook deploy.yml
```
