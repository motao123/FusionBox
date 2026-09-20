# 单节点 SSH 会话

密钥是默认认证方式。密码模式需要显式指定，适合初次接入后迁移到密钥；批量执行、同步和任务不支持自动回退密码。

```bash
fusionbox cluster add
fusionbox cluster trust my-node
fusionbox cluster connect my-node
fusionbox cluster connect my-node --password
fusionbox cluster node-exec my-node --password -- 'uname -a'
fusionbox cluster migrate-key my-node --password --public-key /root/.ssh/id_ed25519.pub
```

`trust` 显示扫描得到的主机指纹。通过服务商控制台等独立渠道核对后输入 `YES`，密钥固定到私有 `/etc/fusionbox/cluster/known_hosts`。扫描本身不能证明服务器身份，已固定密钥发生变化时拒绝覆盖。

密码交互使用隐藏输入；自动化可使用 `--password-fd N` 从调用者提供的文件描述符读一行。不要将密码写在命令行、环境变量、磁盘临时文件或 shell 历史中。实现使用 0700 临时目录、0600 FIFO 和 ASKPASS helper；FIFO 是进程通信通道，不是持久化密码文件。每个 SSH 会话只允许一次 ASKPASS 读取，服务器若要求强制改密会快速失败，不支持在同一会话交互提交新密码。终止或认证失败会清理本次通信资源及其子进程组。root 或同一 Unix 身份的进程不属于保密隔离边界。

公钥迁移要求 `.pub` 文件及同路径去掉 `.pub` 后的非交互私钥，写远端前通过 `ssh-keygen -y` 核对匹配关系。远端要求 Linux、`stat` 和 `flock`，拒绝符号链接或多重硬链接的 authorized_keys，保留已有条目，只追加缺少的公钥。追加成功后执行纯密钥认证；如果验证失败，明确报告“公钥已安装但验证失败”，不会删除原有密钥或关闭密码登录。加密私钥或非标准 AuthorizedKeysFile 需人工处理。

`node-exec` 的所有本地选项放在 `--` 前；`--` 后单个字符串按远端 shell 命令执行，多个参数分别引用后组成远端命令。

## 验证范围

在 Linux 服务器回环地址使用独立随机高端口 sshd、随机测试用户和独立主机密钥进行 11 项实际验收：正确/错误密码、默认禁止密码回退、CLI 参数顺序、密钥迁移、纯密钥验证、主机密钥不符拒绝和资源清理。未修改生产 sshd，没有把此结果当作多服务器批量验收。
