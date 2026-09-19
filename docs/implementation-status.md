# v1.24.0 受管市场大扩容：五款新模板

G51/G53/G54 扩容：受管目录新增 lobe-chat（G51）、open-webui（G51）、n8n（G51）、openlist（G53）、navidrome（G54）。框架扩展：`mounts` 多具名卷列表、`environment` 映射、每应用 `health_retries` 并使 `compose up --wait-timeout` 随之缩放（修复 45 秒硬编码导致慢启动应用必然失败）、document() 的 command 变为可选（root+全 cap 丢弃运行 openlist）。真机验证 27/27：五款应用完整生命周期（安装/健康/HTTP 服务实测/守卫/卸载清理），测试产物已清理。真实部署驱动修复：lobe-chat 512M OOM 调至 1.5G、openlist 新卷权限改 root 运行、openlist/open-webui 慢启动健康窗口。最终 Linux 验证目标：42 基础 + 584 行为。剩余：G51/G53-55 其余应用按需扩容、G32-34（OCI 环境）、G52 socket 依赖面板、G13 shutdown（不可真机验证）。

## v1.23.0 自动更新开关与 new-api 受管模板（历史）

G66/G51 限定范围完成：`update --cron on|off|status`（受管 cron.d 条目复用既有带校验回滚的 self_update，需已安装部署，0600）；受管目录新增 `new-api`（LLM API 网关，digest 实拉验证，SQLite 具名卷，/api/status 真实健康检查，首启无认证警告写入描述）。真机验证 15 项全过：cron 全往返、真实部署/健康/HTTP 200/守卫/清理。最终 Linux 验证目标：42 基础 + 576 行为。**至此 69 项差距中：受管范围完成 55 项、部分覆盖 6 项、明确不做 8 项；未实现仅剩 G32-34（需真实 OCI 环境）、G51 其余 AI 应用（逐项评估）、G52 中需 Docker socket 的面板（与受管安全模型冲突）、G13 shutdown 分支（不能真机关机，mock 已覆盖）——均为环境/安全边界所限，列入后续观察。**

## v1.22.0 rsync 任务、文件管理器与小工具（历史）

G16/G14/G22 限定范围完成：`system rsync`（0600 持久化清单、端点严格校验、镜像模式确认、受管 cron.d 原子改写、rm 不删数据）；`system file`（ls/cat/mkdir/cp/mv/chmod/tar/untar/send，del 一律进回收站、拒绝删 /）；`system genpass`、`system gai`（前后自动备份）、`system locale`。真机验证 32 项全过：真实 rsync 同步、cron 写入/移除、文件管理器全操作（含回收站与拒绝删 /）、genpass、gai 往返。最终 Linux 验证目标：42 基础 + 576 行为（新增 59）。剩余：G66 自动更新、G51 NewAPI、G32-34（需 OCI 环境）、G52 其余（socket 依赖）。

## v1.21.0 Web 调优档位与 brotli/WP-Redis（历史）

G45/G46/G47/G48 限定范围完成：`web tune`（standard/high 档位事务化修改 nginx/PHP-FPM/MySQL，manifest 备份 + nginx -t/php-fpm -t 校验回滚 + restore；MySQL 仅写配置不自动重启数据库）、`web brotli`（Ubuntu brotli 模块包 + 自有 conf，nginx -t 回滚；zstd 无稳定包不提供）、`web wp-redis`（wp-config 锚点注入，幂等，php -l 校验回滚，Redis Object Cache 插件需用户自装）。真机验证 24 项全过：真实档位修改/备份/恢复、真实 brotli 模块 + Content-Encoding: br 响应实测、真实 redis + wp-config 注入。最终 Linux 验证目标：42 基础 + 517 行为（新增 61）。剩余：G16 rsync 任务、G14 文件管理器、G22 小工具、G66 自动更新、G51 NewAPI。

## v1.20.0 受管市场模板扩容（历史）

G51/G52 限定范围部分完成：受管目录新增 `uptime-kuma`（监控面板，1.5GiB 预检，镜像自带 node healthcheck——实测镜像无 wget 后纠正）与 `ddns-go`（DDNS 更新器，512MiB 预检）。两者均为单具名卷、localhost 发布、digest 固定镜像（实拉验证）、domain 映射明确拒绝。真机验证：两类应用各一轮完整生命周期（安装/健康/状态/HTTP 服务重定向语义/重复与端口占用拒绝/卸载保留卷）共 13 项，测试产物（卷/登记）已清理。最终 Linux 验证目标：42 基础 + 456 行为。剩余：G51-G56 其余应用逐项扩容、Oracle 生态（G32-34）、rsync 任务/文件管理器（G16/G14）、工作区 SSH 常驻模式。

## v1.19.0 运维小工具合集（历史）

G68/G21/G15/G62/G19 限定范围完成：`_psabi_from_flags`（v1-v4 依据 CPU flags）并入 system info；`system sshkey` 选项 7 从 GitHub/https URL 拉取公钥（逐条 ssh-keygen 校验+确认，拒绝时不改动）；`cluster sshout`（add/list/rm/connect，0600 清单、严格校验）；`workspace work`（tmux work1-10 编号会话、首条命令与 send-keys 注入、重复/越界拒绝）；`market clamav <路径>`（按需安装、摘要+0600 日志、威胁 rc=1）。真机验证 25 项全过：真实 CPU v4 识别、GitHub 真实拉取（拒绝时零改动）、sshout 文件往返、tmux 会话注入执行并清理、clamav 拒绝路径；完整扫描 mock 覆盖。最终 Linux 验证目标：42 基础 + 455 行为（新增 85）。剩余：市场受管模板扩容（G51-G56 逐项）、Oracle 生态（G32-34，需真实 OCI 环境）、rsync 任务/文件管理器（G16/G14）、工作区 SSH 常驻模式剩余细节。

## v1.18.0 站点运维闭环（历史）

G39/G41/G42/G49/G50 限定范围完成：`web clone`（server 块解析复用、同级目录复制、域名+路径替换、nginx -t 回滚、可选 WP 数据库克隆）、`web cache`（FPM 重启、fastcgi_cache 目录清理、CF purge 凭据可选）、`web goaccess`（私有目录报表）、`web upgrade`（按包管理器组件升级，无降级声明）、`web uninstall-lnmp`（YES 门禁、配置备份失败即中止、keep/wipe 数据）。真机验证 25 项全过：真实 nginx 夹具上完成清单/克隆/对外服务/缓存/报表/升级/门禁与完整卸载（备份 tar + purge + wipe 逐项核验），验证后恢复原状。最终 Linux 验证目标：42 基础 + 370 行为（新增 37）。剩余：市场模板扩容（G51/G52）与杂项（G62/G68/G32-34/G15/G16/G21/G19/G14）。

## v1.17.0 Docker 一键卸载与容器端口封禁（历史）

G27/G30 限定范围完成：`panels docker port-block add/del/list`（DOCKER-USER 顶部插入、原始目标=容器 IP+端口、comment 标记只管自有规则、插入失败回滚、iptables-save 解析删除时剥离引号保证 -D 匹配）；`panels docker uninstall`（只读统计→YES 门禁→可选数据目录保留→全量清理→按包管理器 purge→命令消失校验）。真机验证 20/20：临时 netns+veth 真实转发流量验证 DROP 生效与恢复；卸载仅拒绝路径，完整流由 mock 覆盖（服务器保留 Docker 供后续夹具）。最终 Linux 验证目标：42 基础 + 333 行为（新增 36）。剩余优先范围：P1 已全部完成；P2 站点闭环（G39/G41/G42/G49/G50）、市场模板扩容（G51/G52）、杂项（G62/G68/G32-34/G15 等）。

## v1.16.0 环境变量与网卡管理（历史）

G09/G10 限定范围完成：`system env`（list/show/check/edit）仅允许清单内 rc 文件，编辑前私有备份、保存后 bash -n 校验并支持一键恢复；`network nic`（list/info/up/down）严格设备名校验、ethtool 详情、默认路由网卡停用需显式风险确认。真机验证 env 全链路（备份/no-op 编辑循环/允许清单拒绝）与 nic 只读、拒绝路径共 17 项通过；nic up/down 未在真实服务器执行（不改网络状态边界），由 mock 覆盖。最终 Linux 验证目标：42 基础 + 297 行为（新增 50）。剩余优先范围：Docker 完整卸载与容器原始目标防火墙规则（G27/G30）。

## v1.15.0 Fail2Ban 管理面板（历史）

G11 限定范围完成：`system fail2ban`（status/banned/unban/log/params/uninstall + 菜单）。unban 以 ipaddress 严格校验 IPv4/IPv6 后调用 fail2ban-client；幂等语义（未封禁 IP 返回同样成功）。log 尾部 N 行上限 500，/var/log/fail2ban.log 优先、journalctl 回退。卸载仅移除受管 marker jail 文件（未知文件拒绝），systemctl disable --now 后按包管理器 purge 并校验二进制消失；jail.local 等自有配置不触碰。params 复用 v1.12.1 受管事务。真机验证：status/banned/TEST-NET ban→unban→banned 清单循环/日志边界共 14 项通过；卸载与 params 仅 mock（服务器真实 fail2ban 正在防护 SSH，不实际停用）。最终 Linux 验证目标：42 基础 + 247 行为（新增 16）。剩余优先范围：环境变量/网卡管理（G09/G10）；Docker 卸载与容器级防火墙（G27/G30）。

## v1.14.0 用户管理与 SSH 加固工作流（历史）

新增 G03/G04/G05 限定范围：用户创建/删除（拒绝 root 与 uid<1000，userdel -r 前置归属审查）、chpasswd 改密（stdin 传入，拒绝冒号/换行，不落 argv/日志）、受管 sudoers.d 授权/回收（marker 归属校验、staged visudo -c 验证、0440 root:root、目标校验失败回滚、不触碰 sudoers 主文件与他人文件）、`ssh PermitRootLogin yes|prohibit-password|no` 事务化切换（沿用 sshd -t/-T 生效值校验、重载回滚、socket activation 拒绝）。`system hardening` 向导：建用户→装公钥（粘贴或本机生成，authorized_keys 0600/.ssh 0700 归属校验）→sudo→验证密钥登录→收紧 root；验证未通过（回环实测失败或无法验证且未人工确认）绝不修改 root 策略。sshkey 菜单新增 root 密码登录开/关。

真机隔离验证：专用测试用户全流程（创建/密码/sudo 授权回收/公钥安装/删除清理）；密钥登录经生产 sshd 以测试用户实测（零配置改动，sshd_config 校验和登录前后一致）；PermitRootLogin 生效值仅在暂存配置副本以 sshd -t/-T 验证，生产 sshd 未重载；root 密码未改动，sudoers 主文件未改动。userdel 对残留登录会话（systemd user slice）可能暂时失败，已给出可操作错误信息。sudoers 主文件全局语义、PAM 限策、SELinux 环境未验证。

最终归档 Linux 验证目标：42 基础 + 231 行为（新增 22），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34。剩余优先范围调整：环境变量/网卡管理、Fail2Ban 完整面板（G09/G10/G11）；Docker 卸载与容器级防火墙（G27/G30）。

## v1.13.0 受管 ntfy 小范围扩容（历史）

新增 ntfy v2.28.0 官方 digest 固定镜像，复用数据驱动 Compose 生命周期；非 root、无特权/socket、localhost 默认、资源限额与每应用磁盘预检。SQLite 消息缓存 24h，非认证本机通知用途；不支持公开入口/域名/TLS，候选镜像改变拒绝升级，避免未经验证的数据库迁移回滚。实际 HTTP JSON 健康检查，卸载保留卷、同镜像重装；离线停容器备份/恢复与持久化通过专用夹具。详情与命令见 README。

最终归档 Linux 验证目标：42 基础 + 209 行为（新增 7），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34。新增真实 API 发布/读取、SQLite 停写快照/恢复、重装/重启持久化、拒绝迁移、失败清理/重试；不改生产服务。外部 ACME/CF/TG 凭据验证仍缺。

当前优先剩余范围（不重开 v1.12.1 六项已修复问题）：
1. P1 环境变量/网卡管理（G09/G10）、用户 CRUD/改密/加固向导（v1.14.0）、Fail2Ban 面板（v1.15.0）均已完成；剩余 P1 为 Docker 完整卸载与容器级防火墙（G27/G30）。
2. P1 全量 Docker 卸载与容器原始目标防火墙规则；归档传输已有，目标机应用重建/迁移与数据库版本升级仍缺。
3. P2 站点克隆/数据库域名替换、CF 缓存清理、GoAccess、运行时热升级/卸载；已有入口/局部校验不等于端到端完成。
4. P2 现代应用各分类仍大部分缺失；ntfy 仅一个轻量运维通知模板，不声称完成 G51–G56。游戏定时备份/兼容矩阵、后台编号工作区/注入、自动更新仍待。
5. 仅模拟/条件依赖：TG/CF 真账户、ACME 公共域名签发、上游代理安装器完整生命周期、真实集群批量操作及发行版矩阵。安全测试通过不等于这些外部集成完成。

## v1.12.1 审计安全修复（历史）

本批完成六项限定修复：SSH plain key 验证与物理行删除、sshd -t/-T/重载回滚；明确确认归属的 /swapfile 定向删除与 fstab 备份/原子写入；Fail2Ban 自有 jail.d 参数配置与验证/回滚；旧 Docker 导出暂存/发布/失败传播；禁用错误 DNAT 端口开关；Nginx/PHP-FPM 优化失败恢复。

SSH Match/socket activation 拒绝自动修改，Include 生效值冲突拒绝，PasswordAuthentication 不等于禁用其他认证。Fail2Ban 保留启用状态/端口/后端，后续配置可能覆盖参数。Swap 不自动恢复激活。备份保留，外部写入须暂停，中断/双重失败仍需人工恢复。端口按容器+宿主原始目标规则、完整 Docker 卸载、全量迁移与其他 G 项均不在完成范围。

最终 Linux 归档验证目标：42 基础 + 202 行为（新增 25），SSH 21、Compose 13、Docker 诊断 15、市场 20、TLS 34。新增真实 sshd/Fail2Ban 临时配置验证，无生产 daemon reload；其他危险操作仅 mock。ACME/CF/TG 凭据依赖保持待验证。

## v1.12.0 历史记录


v1.12.0 完成 G26 容器只读详情与 G31 全局总览限定范围：Bash/Docker 模板，summary/summary --all/detail 与菜单集成；全状态计数、引擎镜像数、网络/卷、Docker 磁盘用量。详情显示镜像 ID、健康、端口/挂载/网络、重启策略、持久化资源限制与运行 stats；环境值/命令/标签/健康输出全部省略。失败非零且不伪装零，菜单原计数失败修复。快照非原子，配置上限与运行占用区分，CPU=0 语义明确；不管理资源，不证明所有 Docker 功能完成。

最终归档验证目标：42 基础 + 177 行为（新增 12），SSH 21、Compose 13、复用 Compose 专用资源的诊断 15、市场 20、TLS 34。仅测试自有夹具；不公开生产清单。外部 ACME/CF/TG 及其余待办保持未完成。

## v1.11.1 历史记录

v1.11.1 完成限定归档文件传输：cluster archive push/pull/status，复用节点校验；显式密钥与严格 known_hosts，不保存密码，不加载用户 SSH config。专用私有归属目录、路径逐段 no-follow、SHA-256 校验临时文件后 no-clobber 原子发布，同哈希可重试，冲突拒绝、源始终保留。pull 校验现有 config/system/web manifest/scope/压缩完整性，不解压；摘要完整性不是作者真实性。Compose 专用归档传输、应用重建、全量 /home、调度和旧 cron 迁移仍待后续。

最终归档验证目标：42 基础 + 165 行为、SSH 21、Compose 13、市场 20、TLS 34。SSH 为单服务器 loopback 独立临时 sshd、临时密钥/authorized_keys，生产 SSH 配置/服务不变；不是两主机灾难恢复。Docker SSH 镜像未预装，采用已安装 sshd 的独立配置方案；CI 同样使用 runner 已安装 OpenSSH，不新增下载依赖。外部 ACME/CF/TG 仍待验证。

## v1.10.0 历史记录

v1.10.0 G64 完成限定范围的节点清单导入/导出：版本化非执行 JSON，仅 id/user/host/port，无凭据；默认 dry-run，确认合并，同名全部拒绝。严格主机/IP/用户/端口校验，支持裸 IPv6；共享 flock、私有原子写入、导出不覆盖、拒绝链接。旧 nodes.conf 保持存储格式，合法旧行直接读，不自动改写；非法/重复/隐式用户旧行需人工修复。执行消费校验快照，不执行导入内容；添加不再自动 SSH 探测。配置/密钥/known_hosts 迁移及真实集群任务不在范围。

Linux 最终归档验证目标：42 基础 + 150 行为（新增 14），Compose 13/市场 20/TLS 34。新增覆盖字段往返、畸形/重复/冲突、注入不执行、权限/链接、失败保持旧配置、共享锁与 IPv6 SCP 参数；无生产集群或 SSH 配置变更。

## v1.9.0 历史记录

v1.9.0 新增受管 `tls-refresh --confirm`，锁内重验当前自备文件、Nginx 校验/重载并等待本机 SNI 证书指纹匹配；status 显示剩余完整天数与文件/实际入口差异。保持不复制私钥的承诺，没有密钥快照；外部已覆盖文件无法回滚。重载/入口验证失败报告 runtime unknown，保留私有 refresh journal，阻止其他变更；修复文件后显式重试成功才清除。未知 journal 拒绝接管。外部写入者须暂停，无 ACME/Certbot hook/自动续期。

本批最终归档验证目标：Linux 42 基础 + 136 行为、Compose 13、市场 20、域名/TLS 34；新增轮换、重载失败旧入口/显式恢复、无效刷新拒绝、读取失败、天数边界、连续失败与状态差异检查。自签名夹具仍以 curl --cacert 验证，不使用 -k。公共 CA、真实 ACME、完整链认证与其余待办仍未完成。

## v1.8.1 历史记录

v1.8.1 自备 PEM HTTPS：显式 cert/key 路径、OpenSSL 解析/精确 SAN/有效期/公钥匹配，私钥归属与 0600/0400、拒绝链接和不安全路径。不复制/删除私钥、不签发、不自动续期。默认 HTTP 重定向，可显式关闭；TLS enable/status/disable 沿用自有配置与事务回滚，双重失败保留 journal。更新/卸载 503/重装保留 TLS。状态校验本地文件不代表公共 CA 信任、链验证或公网可达性。

Linux 42 基础 + 128 行为（新增 4），零跳过；真实专用 Docker Nginx 域名/TLS 24 项检查，以 test.local 自签名证书与 curl --cacert 验证（无 -k），含错误主机名、过期、密钥不匹配、重载失败、持久化与停用。Compose 13/市场 20 继续验证。没有生产 Nginx/443 或外部 ACME 变更。证书外部写入须暂停，失效文件可能需人工恢复。最终发布以 exact archive 重跑为准。

## v1.7.0 历史记录

v1.7.0 补齐受管 Nginx HTTP-only 域名映射：独立自有 conf.d 文件、严格域名/固定上游与路径、已解析 Nginx 配置冲突检查、暂存语法验证、整体验证/重载与失败回滚。双重失败保留恢复 journal 并阻止后续变更，未知文件拒绝覆盖。更新保留映射；卸载暂停入口返回 503，重装沿用原端口恢复入口；有映射时禁止自动换端口。菜单/help/status 可发现。无证书申请、无 TLS 验证、无防火墙修改；本机上游仍可访问，不声称 domain_only 隔离。外部配置写入者需暂停，进程中断需人工恢复。Python 3 是明确依赖。

验证范围：Linux 42 基础 + 124 行为（新增 8）零跳过；专用 Docker Nginx 高端口夹具 12 项检查覆盖真实 Host 路由/拒绝、重载失败恢复、冲突、更新/卸载/重装持久化与删除。既有 Compose 13 与市场 20 夹具继续执行。生产宿主 Nginx、80/443、SSH/DNS/防火墙/sysctl 均不修改。发布以最终提交归档重跑结果为准。

## v1.6.1 历史记录

v1.6.1 仅补齐保留数据重装与自动端口探测：显式 `--confirm --reuse-data`，验证卸载状态/空容器命名空间、私有登记/配置、原镜像与自有卷；失败清理本次创建的自有容器，保留原登记/配置/数据，未知归属拒绝删除。自动端口从首选值最多探测 20 个 localhost 端口，不承诺预留；实际 Docker 竞争失败仍返回失败。新增菜单/help/status 引导。Linux 42 基础 + 116 行为（新 5），真实市场夹具包含内容保留重装、占用首选端口回退、真实绑定竞争失败清理及重试；Compose 13 断言继续验证。中断/清理失败仍需人工恢复，目录不扩容，公网/域名及数据库迁移不在本批。


v1.6.0 Q11/G57 市场生命周期基础：新增独立 `market managed`，只支持已做隔离真实验证的 Nginx 静态站点；复用 Compose JSON 注册表、全局 flock、原子私有写入。端口占用/磁盘预检、明确归属与类型检测、健康状态、固定目录镜像更新与失败回滚、卸载保留具名数据/配置/登记。默认 localhost、内存/CPU/PID/日志限额；失败安装保留恢复线索，不接管旧安装器。更新内容卷只读，无数据库迁移语义。卸载后重装/恢复保留卷仍需人工，不支持自动端口分配、公网/域名入口或任意目录扩容。强杀/断电可能需按登记与 previous 记录人工恢复。

本批验证：Linux 42 基础 + 111 行为测试（原 96 + 新 15），零跳过；真实市场夹具验证安装/HTTP 内容/Compose 备份、更新、失败健康回滚与卸载保留数据。真实 Compose 13 断言继续覆盖备份恢复和双重失败停机。发布以最终提交归档重跑结果为准。


v1.5.1 安全修复：恢复与回滚同时失败不再重启容器，项目保持停止，返回失败并报告安全归档与人工干预要求。备份失败和成功回滚仍恢复原运行状态；部分重启失败继续尝试剩余容器，报告失败数量/可能部分运行，绝不报告成功。安全路径在变更前打印。Linux 42 基础 + 96 行为测试全通过、零跳过；真实隔离 Compose 13 断言包括双重失败保持停止与安全副本保留，确认清理夹具容器/卷/网络。下面 v1.5.0 为历史记录，异常重启行为以此修复为准。

v1.5.0 新增受管 Compose 注册表与本机备份/恢复：项目归属显式确认，规范化 Compose 路径/项目身份，0700/0600 权限与全局 flock；只允许固定本机 Docker socket、已创建的本项目容器和 local named volumes。拒绝 bind/external/anonymous/共享卷、非 local driver、privileged/devices/secrets/configs/tmpfs、paused/restarting/auto-remove 容器及远端/alternate Docker endpoint。归档包含 compose、resolved config、容器元数据、卷数据和 SHA-256 manifest，不输出密钥或 Docker 错误正文。

备份和恢复要求显式停写确认，只停止本项目原本运行容器，完成/失败后尝试恢复原状态；恢复先完整校验再变更，先保留安全归档，失败尝试回滚并保留安全归档。真实 Compose 夹具两个容器混合原始状态、具名卷、成功和注入失败分支共 10 断言通过并清理。Linux 42 基础 + 95 行为测试全通过、零跳过。此项不覆盖数据库语义、bind/external 场景、远端迁移或任意 Compose 规范；真实 API 凭据能力继续待验证。


v1.4.4 完成本地配置任务归档登记/SHA-256、显式 keep-count 保留预览与单次启用删除（默认及 cron 无删除）、锁内校验恢复与菜单入口；旧/未知归档不认领，不按 glob 删除。所有登记归档须校验成功才允许清理，保留数至少 1；磁盘故障/中断留下的失效登记需人工审查。恢复新增 gzip 全流校验，损坏尾部在目标改动前阻断；保留目录回滚机制仍非断电原子性。移除站点旧通配符删除与不可达 cron 生成器，Docker export 明确仅文件系统，旧 Compose 不安全打包/恢复入口禁用。

本批 Linux 测试 42 基础 + 84 行为全部通过、零跳过（新增 6）。真实新建 Docker 专用卷：离线文件内容、权限、恢复副本 3 断言通过，夹具卷与临时数据清理。没有停止或修改任何已有容器/卷；不是完整 Compose 备份或两主机迁移证明。G28 仍缺受管项目登记、卷/运行元数据及确认停写/失败重启；生产数据库一致性、远端迁移、真实 ACME/CF/TG 保持待验证。

v1.4.3 新增本地 nginx/caddy 配置每日任务，明确稳定配置前提，无服务停止/远端传输/数据库快照。支持自有任务创建/列表/删除、flock、防半成品、私有归档/状态，以及不泄露命令内容的旧 cron 检测。7 项隔离回归覆盖权限、失败、并发、归属和旧任务保留。Python 3/cron 是明确依赖。旧远程全量任务不等价，不能自动迁移；远端传输、保留策略与生产一致性认证仍待后续。

v1.4.2 修复 TG 三条发送路径 token argv、失败后重试与冷却、CF 每区域状态/原始级别和配置原子替换。新增 4 项生成脚本测试，API/关机全部模拟；未验证真实账户。CF 卸载保留每区域恢复记录，不改变远端级别。旧远程定时备份不兼容安全清单，新建入口暂时拒绝，已有 cron 需人工检查，安全迁移尚待实现。

v1.4.1 本批 Linux 隔离验证：42 项基础检查、12 项安全、19 项安装器、24 项代理生命周期、12 项可靠性测试全部通过，无跳过。保留原生 Linux 软链接和权限验证。新增证书负天数与重载失败传播、调度暂存写入、DNS 标准库地址校验/暂存替换、集群 swap 前置失败阻断与批量失败状态、系统/站点手动备份清单范围检查和目录回滚。备份需要 Python 3，拒绝旧归档、链接和特殊文件；恢复替换清单中的整个目录并保留旧目录，不自动停服务，不提供数据库一致性或断电原子性。

v1.4.1 当时待处理（前三项现已在 v1.4.2 修复）：TG token argv、流量通知重试、CF 每区域状态、远程定时备份加固。上游安装器、真实 ACME/CF/TG 仍未验证；不是全部 69 项完成声明。下方 v1.4.0 与 Windows 记录为历史验证，不替代本批 Linux 结果。

这是一份候选清单，不是全功能通过声明。原报告声称 69 项，但按实际需求表提取为 69 行；分类数量与正文不完全一致。配套脚本的字节数不能当作行数；未搜索到 renew 不能推断系统没有 Certbot 定时器。

测试证据：42 项基础检查、12 项隔离行为测试（Linux 全通过），6 项真实 Docker/Compose 卷往返断言。服务器未修改 SSH、系统 DNS/sysctl 或既有防火墙，未执行关机；测试项目/卷/网络/备份已清理，Alpine 镜像缓存与 /tmp/fusionbox-v140-validation 测试代码、上传包保留供复核。详细日志保存在操作者仓库外，不含凭据。

状态中的“部分实现/已提供入口”仅说明代码范围；除上述断言外，没有对所有菜单和发行版进行功能认证。CF 未实测；TG 仅 mock；ACME 无域名条件。
本批 P0 安装器修复：独立脚本/进程替换无相邻 version.txt 时不再因 set -e 提前退出；安装与更新共用暂存复制、必需文件/版本/脚本语法校验、代码路径逐项切换和失败回滚。仅替换代码白名单，保留业务数据、既有配置和权限；成功更新保留旧代码恢复目录，回滚失败保留恢复目录与锁。拒绝托管代码路径软链接和命令目录；安装根目录软链接解析后在目标内操作。逐项切换不是全目录原子切换，SIGKILL/断电后需人工检查恢复目录与锁；自动更新/参数回灌仍未实现。

安装命令归属加固：已有命令仅接受可验证指向安装根目录 fusion.sh 的软链接，并原样保留；拒绝普通文件、目录和无关链接。新建用户配置显式设置 0600，事务使用 umask 077 与私有暂存目录；既有用户配置权限不改动。

本批代理生命周期修复：区分 FusionBox 原生核心与上游管理入口，通过链接归属判断而非执行未知命令；拒绝覆盖占用的命令/上游目录与服务路径，卸载分别确认原生和上游组件，仅清理确认归属的命令链接与服务文件，保留未知命令/服务；下载、安装、管理入口、卸载与服务操作失败向上传递退出码。这些为隔离 mock 验证，不代表真实上游安装器或服务端生命周期认证。

本批本地验证（Git Bash / Windows）：安全入口 `bash tests/comprehensive_test.sh` 通过，42 项基础检查通过；原 12 项行为测试为 11 通过、1 跳过；19 项安装测试为 15 通过、4 跳过；24 项代理生命周期测试为 22 通过、2 跳过。安装覆盖 checkout/独立文件/进程替换/stdin、离线与就地安装、更新、部分复制失败、代码及命令激活失败回滚、状态/配置保留、无关命令拒绝和并发锁。跳过项为原生软链接及 POSIX 权限验证；Windows 安装入口以 stub 替代符号链接创建，代理部分测试 mock 链接归属。未安装可用 WSL，本批未做原生 Linux/远端服务器验证，也未访问服务器凭据。


| ID | 候选能力 | 状态 | 范围与下一步 |
|---|---|---|---|
| G01 | 优化 DNS（按国家写 resolv.conf + `chattr +i` 防篡改） | 部分实现 | system dns；普通文件 DNS 配置；受管理链接拒绝覆盖 |
| G02 | 系统更新源切换（内置镜像源/linuxmirrors） | 部分实现 | system mirror；APT/YUM 分支，未覆盖所有发行版 |
| G03 | 用户管理（建普通/高级用户、sudoers 授权回收、删除） | 受管范围完成 | v1.14.0 users add/del/sudo/unsudo：受管 sudoers.d marker 文件 + visudo 暂存校验 + 0440；拒绝 root/uid<1000 与未知归属文件；sudoers 主文件与组成员不修改 |
| G04 | 修改登录密码 / 一键开启 root 密码登录 | 受管范围完成 | v1.14.0 users passwd（stdin chpasswd）+ sshkey 菜单 root 密码登录开/关（PermitRootLogin yes/prohibit-password 事务化）；PAM 限策未验证 |
| G05 | 禁用 root 登录并新建密钥用户 | 受管范围完成 | v1.14.0 system hardening 向导：建用户→公钥→sudo→登录验证门禁→收紧 root（prohibit-password/no）；验证未通过不修改策略 |
| G06 | Swap 任意大小 + 旧 swap 清理 | 部分实现 | 自定义 Swap；未自动清理未知旧 swap |
| G07 | 时区预设 20+ 城市 | 后续 | 未在本批补齐；需独立设计、实现与隔离验证 |
| G08 | 系统日志管理菜单（journalctl 查询/服务日志/secure 登录日志/实时跟踪/清理） | 已提供入口 | system log；未实测所有日志后端 |
| G09 | 系统环境变量管理（查看/编辑 bashrc/profile/source 重载） | 受管范围完成 | v1.16.0 system env：允许清单内文件查看/编辑/语法检查，备份+恢复；source 重载属用户 shell 行为，只提示不代执 |
| G10 | 网卡管理（ip link up/down、ethtool 详情） | 受管范围完成 | v1.16.0 network nic list/info/up/down；默认路由停用双确认；真机仅只读路径 |
| G11 | fail2ban 完整面板（拦截记录/实时日志/参数配置/卸载） | 面板范围完成 | v1.15.0 status/banned/unban/log/params/uninstall；真实 fail2ban 上验证状态/解封/日志；卸载仅 mock（不停用生产防护） |
| G12 | TG Bot 监控预警（CPU/内存/磁盘/流量阈值 + 登录通知） | 凭据依赖 | system notify；资源阈值与冷却，TG 仅 mock，SSH 登录通知未实现 |
| G13 | 流量阈值自动关机（/proc/net/dev 统计超限关机） | 部分实现 | traffic-guard；默认 warn；shutdown 分支未执行，月统计从安装基线开始 |
| G14 | 文件管理器 | 受管范围完成 | v1.22.0 system file：全操作真机验证；del 进回收站；跨机 send 走 scp（真实远端未验证） |
| G15 | SSH 出站连接工具（收藏与管理） | 受管范围完成 | v1.19.0 cluster sshout：0600 受管清单+严格校验+connect 直连；connect 真实目标需第二台主机，未验证 |
| G16 | rsync 远程同步任务管理 | 受管范围完成 | v1.22.0 system rsync：任务清单+可选 cron 真机验证；远端执行依赖第二台主机未验证；密钥管理沿用 cluster 模型 |
| G17 | 系统备份范围扩展 + 备份管理 | 部分实现 | 配置任务归属登记、完整性校验、显式保留/恢复；系统范围扩展与旧归档迁移仍后续 |
| G18 | 内核参数优化面板（6 场景自适应 + 恢复） | 后续 | 未在本批补齐；需独立设计、实现与隔离验证 |
| G19 | 病毒扫描（ClamAV 全盘/指定目录+日志） | 受管范围完成 | v1.19.0 market clamav 扫描动作（按需安装、0600 日志、威胁 rc 传播）；真实扫描 mock 覆盖 |
| G20 | 修复 OpenSSH 高危版本（源码编译升级） | 不建议源码替换 | 优先发行版安全更新，避免断开 SSH 管理通道 |
| G21 | SSH 密钥远端导入（GitHub / URL 一键抓取） | 受管范围完成 | v1.19.0 sshkey 菜单 7：https 拉取+逐条校验确认；真机 GitHub 拉取验证，拒绝时零改动 |
| G22 | 小工具集 | 基本完成 | hostname/hosts/语言切换/密码生成器/gai.conf 已加入（v1.22.0）；命令收藏/快捷键由 cluster kcmd 覆盖；PS1 美化未做（低价值） |
| G23 | 测试脚本合集（17 项评测矩阵，数据表驱动） | 部分实现 | network bench 列表及确认执行；未声称全部上游可用 |
| G24 | 评测前自动补 Swap（小内存机器） | 不自动实施 | 低内存仅提示用户配置 Swap，避免评测自动改变内存策略 |
| G25 | Docker 一键换源 + 内置国内加速源 | 部分实现 | Docker JSON 合并与回滚；失效预设移除，源须现场验证 |
| G26 | 容器管理增强（进容器/日志/占用/详细信息） | 只读详情范围完成 | v1.12.0 detail/菜单：环境值隐藏、状态/健康/镜像/端口/挂载/网络/重启/配置限额与运行占用；已有日志/exec/stats 保留，非所有管理功能认证 |
| G27 | 容器名级端口开关（按容器+宿主 IP 生成规则） | 受管范围完成 | v1.17.0 port-block：DOCKER-USER 原始目标规则+comment 标记；真机转发流量验证 DROP/恢复；IPv4/非持久明示 |
| G28 | Docker 备份增强（compose 项目整备 + 自动生成还原脚本） | 部分实现 | v1.5.0 受管本机单文件 Compose + local named volumes 备份/同项目恢复；数据库/外部卷/迁移仍后续 |
| G29 | Docker 远程迁移（scp 到目标机） | 后续 | 未在本批补齐；需独立设计、实现与隔离验证 |
| G30 | Docker 一键卸载（清容器/镜像/包/daemon.json） | 受管范围完成 | v1.17.0 uninstall：YES 门禁+可选数据保留+按包管理器 purge；真机仅门禁路径，完整流 mock |
| G31 | Docker 全局状态总览（容器/镜像/网络/卷计数+全列） | 只读总览范围完成 | v1.12.0 summary/--all 与菜单，全状态/引擎镜像/网络/卷计数、完整列表和 Docker 磁盘口径；失败不报零，顺序查询非原子快照 |
| G32 | Oracle 防回收（lookbusy 容器按 CPU/内存比例占用） | 后续 | 未在本批补齐；需独立设计、实现与隔离验证 |
| G33 | Oracle：R 探长开机（oci-helper） | 后续 | 未在本批补齐；需独立设计、实现与隔离验证 |
| G34 | Oracle：root 密码登录切换 + IPv6 恢复 | 后续 | 未在本批补齐；需独立设计、实现与隔离验证 |
| G35 | 证书自动续期（flock + sha256 指纹 + 到期前 15 天 + webroot/standalone 回退 + cron） | 部分实现 | web ssl auto/renew；检查已有 timer/cron；真实 ACME 未验证 |
| G36 | 证书到期状态表（全站证书 + 剩余天数） | 已提供入口 | web ssl status；实际域名证书未验证 |
| G37 | 站点清单表（解析 server_name 生成访问地址+证书状态） | 已提供入口 | web sites；解析常规 Nginx 配置，不是完整 Nginx 语法解析器 |
| G38 | 删除站点（目录/conf/证书/库全清） | 部分实现 | web site del；备份配置，数据与证书另行确认；不自动删数据库 |
| G39 | 克隆站点（建库+dump 导入+全表替换域名） | 受管范围完成 | v1.18.0 web clone：目录+配置克隆真机验证；WP 库克隆实现（wp-config 检测+dump 域名替换），真实库场景未验证 |
| G40 | 关联多域名（复制 conf 替换 server_name/证书） | 部分实现 | web site alias；配置校验回滚，证书仍需域名条件 |
| G41 | 清缓存（重启容器 + Cloudflare purge API） | 受管范围完成 | v1.18.0 web cache：FPM 重启+缓存目录清理真机验证；CF purge 凭据依赖未实测 |
| G42 | 站点访问日志分析（goaccess 报表） | 受管范围完成 | v1.18.0 web goaccess：真实安装+报表生成，/root 私有存放 |
| G43 | 防 CC（fail2ban nginx filter + DOCKER-USER chain + Cloudflare action） | 部分实现 | 宿主 Nginx 4xx fail2ban；未覆盖 DOCKER-USER/真实流量测试 |
| G44 | Cloudflare 联动（负载>5 自动 under_attack + CF API 封 IP） | 凭据依赖 | CF 封禁辅助脚本/开盾；保存初始安全级别；未实测 API |
| G45 | 优化模式（标准/高性能切换） | 受管范围完成 | v1.21.0 web tune standard/high：真机 nginx 档位验证；MySQL 只写配置不自动重启 |
| G46 | brotli/zstd 压缩开关 | brotli 完成 | v1.21.0 web brotli：真机实测 Content-Encoding: br；zstd 无稳定发行版模块，不提供 |
| G47 | WordPress + Redis 预配置 | 受管范围完成 | v1.21.0 web wp-redis：注入+幂等+php -l 回滚（真机 redis 安装+注入）；Object Cache 插件需 WP 内自装 |
| G48 | 运行时调优模板注入 | 并入 tune 档位 | v1.21.0 tune 档位覆盖 PHP-FPM 池/MySQL buffer/nginx；opcache 细项与 valkey 未单独覆盖 |
| G49 | 组件热更新（单独升级 nginx/mysql/php/redis） | 受管范围完成 | v1.18.0 web upgrade：真机 nginx 升级路径验证；失败保持原版本，不提供降级 |
| G50 | LDNMP 环境卸载 | 受管范围完成 | v1.18.0 uninstall-lnmp：真机完整卸载（备份/purge/wipe），验证后恢复原状 |
| G51 | AI/LLM 类应用 | 部分扩容 | v1.23.0 new-api + v1.24.0 lobe-chat/open-webui/n8n 受管模板（真机验证）；Dify/RAGFlow 等多容器应用需框架支持 compose 多服务，后续 |
| G52 | 面板类应用 | 部分扩容 | v1.20.0 uptime-kuma 监控面板受管模板（真机全生命周期）；1Panel/Dockge 等未实现（Dockge 需 Docker socket，与受管安全模型冲突） |
| G53 | 网盘/同步类 | 部分扩容 | v1.24.0 openlist 受管模板（真机全生命周期）；其余应用按需扩容；Syncthing 的 P2P UDP 端口与受管 localhost 模型冲突未收录 |
| G54 | 媒体/影音类 | 部分扩容 | v1.24.0 navidrome 受管模板（data+music 多卷，真机验证）；其余应用按需扩容 |
| G55 | 远程/安全/协作类（RustDesk/WireGuard/Webtop/Nexterm/JumpServer/雷池/ONLYOFFICE/RocketChat/VoceChat/2FAuth） | 后续 | 未在本批补齐；需独立设计、实现与隔离验证 |
| G56 | 运维工具类（Lucky/ddns-go/AllinSSL/searxng/Umami/Beszel/komari/思源/Wallos） | 部分扩容 | v1.13.0 ntfy + v1.20.0 ddns-go 受管模板；其余列举应用未实现 |
| G57 | 市场机制：统一登记（appno.txt 原子写 0600）+ flock 并发锁 + 端口占用探测分配 + 已装检测 + 镜像更新检测 + 卸载清理 | 部分实现 | v1.6.1 复用 Compose JSON 登记/锁、20 端口有界探测、归属/健康、镜像 ID 更新与回滚；卸载保留数据并支持显式重装；旧安装迁移后续 |
| G58 | 应用访问模式持久化（direct/domain_only 记录并在更新后恢复） | 部分实现 | v1.7.0 localhost-direct / HTTP 映射登记与更新/重装持久化；无 domain_only 防火墙隔离 |
| G59 | 一键域名访问（应用=反代+证书一条龙） | 部分实现 | v1.8.1 自有宿主 HTTP/自备 PEM HTTPS、SAN/有效期/密钥校验与重载回滚；真实 ACME 后续 |
| G60 | 磁盘空间预检（按应用体积校验 + NAS 路径软链） | 部分实现 | v1.13.0 每应用数据驱动最低预检：Nginx 256 MiB、ntfy 512 MiB，注册表/Docker 数据盘均检查；非配额，NAS/任意应用体积估算后续 |
| G61 | 全量备份/还原（/home 打包 + 可 scp 异地） | 部分实现 | v1.11.1 完成现有 config/system/web 安全归档 SSH push/pull/status；单服务器隔离 SSH 验证；全量 /home、应用重建与两主机灾备仍后续 |
| G62 | 后台工作区增强（编号会话、注入命令、SSH 常驻） | 受管范围完成 | v1.19.0 workspace work：tmux 编号会话+注入真机验证；SSH 常驻 attach 模式后续 |
| G63 | 集群内置批量任务（18 项：update/clean/docker/swap/time/iptables…） | 部分实现 | cluster task；沿用密钥连接，未在生产节点批量执行 |
| G64 | 集群配置备份/导入导出 | 节点清单范围完成 | v1.10.0 无凭据 JSON、预览/确认合并、冲突拒绝、共享锁与私有原子写入；合法旧 nodes.conf 原格式兼容，异常行人工修复；完整 SSH 配置/密钥/known_hosts 迁移不在范围 |
| G65 | 游戏服管理面板（启停/重启/状态/内存/存档导入导出/定时备份/改配置/更新/卸载 12 项） | 部分实现 | game-manage；真实隔离卷往返测试通过；无定时备份/游戏内容兼容矩阵 |
| G66 | 脚本更新机制增强 | 受管范围完成 | 暂存校验回滚 + 业务状态保留（既有）+ v1.23.0 cron 自动更新开关（真机全往返）；Range 读版本未做（整包校验更严） |
| G67 | 网络优化脚本（探测带宽→分级写 sysctl→restore/status 可回滚） | 部分实现 | system netopt；运行值快照恢复有 mock 断言，未改服务器真实网络参数 |
| G68 | x86-64 psABI 级别检测（v1/v2/v3） | 受管范围完成 | v1.19.0 _psabi_from_flags 并入 system info；真机 CPU 识别为 v4 |
| G69 | hermes / deepseek harness 管理器（AI Agent 服务管理，含 systemd/WebUI/域名+BasicAuth） | 大范围后续 | 独立生态与生命周期设计，未纳入本次实现 |

后续优先顺序：完整 Docker 跨机迁移与系统备份扩围 → DD 重装/OpenSSH/密码集群等高风险事务能力 → Web/ACME 闭环 → 应用与 AI Agent 生态扩容。v1.25.0 已建立默认关闭的匿名统计、可信 Release 下载和声明式远程目录基础；远程目录只解析严格 JSON，禁止任意配置 `source`。商业广告/联盟推广及私有 KPanel/.kpb 协议不纳入能力范围。
