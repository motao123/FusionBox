# FusionBox 变更历史

> 本文件由 README 迁移而来，内容为各版本发布说明原文（时间倒序）。最新摘要见 [README](../README.md#最近更新)；逐项实施对账见 [implementation-status.md](implementation-status.md)。

## v1.33.0 OpenSSH 只读预检与破坏性边界

- 新增 `fusionbox system ssh-preflight`：只读运行 `sshd -t/-T`，汇总有效端口、认证策略、授权密钥路径、systemd 服务/socket activation 和当前 TCP listeners；不会写配置、切换版本或 reload 服务。
- 提供候选升级前的配置有效性与监听状态证据；测试服务器 5522 端口真实预检通过，并如实报告 `PermitRootLogin yes`、`PasswordAuthentication yes`，未修改 SSH。
- DD 重装、OpenSSH 候选版本并行启动/切换和自动回滚仍未实现；必须先有专用机器、固定下载摘要、双重确认、救援通道和独立故障演练。
- 本地 Python/Bash 回归与测试服务器只读预检通过；未执行破坏性操作。

## v1.32.0 Oracle 只读识别与旧保活边界

- 新增 `fusionbox cluster oracle detect|status`：本机 OCI 证据识别，可选一次有界、禁止代理和重定向的 OCI metadata 只读探测；不读取实例凭据、不输出实例标识。
- `status` 报告受管登记、Docker 可用性和旧 `oracle-keepalive` 脚本/cron/log 残留；只读入口跳过启动日志、匿名心跳和状态目录创建。
- lookbusy 负载安装、启停和卸载入口在固定镜像 digest、资源策略和 Linux 隔离验收完成前明确拒绝；不会自动接管或删除旧 cron/脚本。G33/G34 仍未实现。
- 本地 Windows 只读 helper 编译与行为检查通过；无 WSL/OCI 环境，未宣称真实 Oracle 或 Docker 生命周期验证。

## v1.31.0 集群临时密码会话与密钥迁移

- 新增单节点 `trust/connect/node-exec/migrate-key`。默认纯密钥，密码需隐藏交互或显式 FD；批量命令不自动降级。
- ASKPASS 通过私有目录中的 FIFO 收取密码，避免 OpenSSH 关闭继承 FD 导致认证失败；凭据不写普通文件，不进入 argv/env/日志，认证和会话结束清理通道。每次会话只允许一次 ASKPASS，强制改密挑战快速失败并清理整个 SSH 子进程组。
- 使用独立私有 known_hosts，首次需人工核对指纹，变更拒绝；锁内追加并补齐尾换行，迁移前验证 `.pub` 和私钥匹配，远端拒绝链接文件并在追加后验证纯密钥登录。
- Linux 临时高端口 OpenSSH 实际验收 11/11：成功与错误密码、禁止自动降级、CLI 参数、公钥迁移、密钥验证、主机密钥不符拒绝和清理。生产 5522 端口配置不变；不是多节点生产验收。
- 使用方式与限制见 [cluster-sessions.md](cluster-sessions.md)。

## v1.30.0 ACME 预检、签发与续期事务闭环

- 新增 `fusionbox web acme preflight|status|issue|renew`：严格校验域名、邮箱、规范 webroot 和续期阈值；DNS 仅报告，同时检查 80/443、高端口测试覆盖、Nginx site 冲突、Certbot 版本和 webroot 插件。
- 签发复用现有静态站点 webroot，或暂存 FusionBox challenge 配置；每次启用前运行 `nginx -t`，之后任何 mkdir/Certbot/证书/TLS/reload 失败均由统一 trap 恢复原配置并再次校验/reload。
- 成功后验证 SAN、有效期和证书/私钥匹配，再原子安装受管 TLS 配置。Challenge/TLS 固定文件要求精确 owner marker 与 SHA256，外部或漂移配置一律拒绝接管。
- renew 使用 `flock`、剩余天数阈值和证书指纹前后对比，仅在证书变化时执行 `nginx -t` 与 reload；失败向上传播。
- 本地 ACME/P1 专项 20 项及 Web 回归通过；Linux 验证服务器完整 ACME/安全组合 32 项通过并清理测试目录。由于没有可控公网域名、DNS 和 80/443 验证条件，真实证书签发未执行、未宣称完成。

## v1.29.0 SSH 登录通知与六场景内核调优

- 新增 `fusionbox system login-alert install|status|test|uninstall`：复用私有 Telegram 配置，通过 PAM session hook 发送用户、来源地址和时间等最小字段。PAM 使用 `[success=ok default=ignore]`，通知脚本所有失败路径放行，安装前后以 `sshd -t` 校验。
- 登录脚本、PAM 目标及状态文件记录完整期望内容和 SHA256；遇管理员外部编辑时拒绝覆盖、测试或删除。Telegram 凭据通过 curl stdin config 传递，不进入 argv 或操作日志。
- 新增 `fusionbox system tuning high|balanced|web|stream|game|db|status|restore`：按 RAM 自动降档并逐键探测内核支持，仅写受管 sysctl/limits/THP unit。
- 首次快照保存有效 sysctl、原文件内容/hash、THP 当前模式及 unit exists/enabled/active；二次应用保留旧快照字节，应用、切换、restore 或 rollback 任一步失败都会恢复并报告，不静默吞错。
- 本地通知与安全回归通过；Linux 验证服务器上的 POSIX 事务用例覆盖登录通知 install/status/test/uninstall、漂移拒绝、THP 解析、调优 profile 切换与 restore。未使用真实 Telegram 凭据，因此消息实际送达仍标记未验证。

## v1.28.0 Docker 目标机预检与事务恢复（P1b）

- 新增 `docker migration preflight`：验证 bundle 后以只读方式检查目标 OS/架构、Docker/Compose、磁盘与 inode、HostIP/协议端口、名称、网络/IPAM、bind 映射、local volume 和镜像 ID/RepoTag 冲突；失败时零变更。
- `restore --confirm-clean-target` 只支持经过严格声明校验的干净目标：私有 staging 解包、镜像加载与 ID/tag 核验、local bridge 网络和卷创建、目录 bind 恢复、容器重建、多网络连接、启动与 health 检查。
- `/var/lib/fusionbox/docker-migration` 中的 root-owned 0700/0600 journal 在每项副作用前后 fsync；资源使用 pending/created 状态，`resume` 可补齐中断步骤，`rollback` 只删除带本事务标签或 marker 的资源。
- bind 创建、清空、复制、metadata 与回滚使用固定父目录/root FD 和 openat 风格操作，逐级校验 inode/dev，防止符号链接或目录置换导致越界删除。镜像回滚只移除本事务新增且此前不存在的 tags/ID。
- 本地恢复安全测试 13/13，Linux 验证服务器（Docker 29.8.1、x86_64）同样 13/13，验证后零容器且临时文件已清理。尚无独立第二台目标机，因此未把单机测试表述为真实跨主机验收。

## v1.27.0 Docker 完整迁移导出与可信传输（P1a）

- 新增 `fusionbox panels docker migration export|verify`：可选择普通容器集合或完整已创建 Compose project，保存关键 inspect 声明、不可变镜像、网络/IPAM、端口/HostIP、环境变量、启动参数、资源/restart/health 配置及数据挂载。
- 镜像按 ID 去重执行 `docker image save`；local named/anonymous/external volumes 文件级导出，经规范路径和精确文本双确认的 bind 以逻辑名称入包。操作者必须另外冻结宿主进程、其他运行时和网络存储写入者；数据库应先做原生 dump/停写，P1a 不声称提供跨文件事务快照。
- 导出前拒绝特权、设备、tmpfs、host PID/IPC、container network、远程/rootless daemon、非 local volume、危险 bind 和范围外共享写入者；停止完整选择集合后再次复核拓扑与写入者，finally 只恢复本操作实际停止的容器。
- bundle 使用严格 manifest，逐成员记录 size/SHA256/mode/UID/GID，拒绝路径穿越、链接、特殊文件、重复或未声明成员；失败时不发布目标包。
- `archive_transfer.py --kind docker-v1` 支持密钥 SSH push/pull/status 和本地 bundle 校验，不在远端执行恢复。P1a 仅提供可验证离线导出；目标机预检、重建和 journal rollback 属于 P1b。

## v1.26.0 显式范围系统备份与事务恢复

- 系统备份使用显式 `fusion/web/docker/ssh/cron/usr-local/home` scope；默认仍为保守的 `fusion,web,docker`，敏感范围逐项输入确认，定时任务固定使用非交互默认范围。
- format-2 manifest 记录 owner、scope/root 映射以及逐文件 UID/GID、mode、size、SHA256；创建时拒绝链接、特殊文件、跨文件系统和源路径变化。
- 恢复支持 scope 子集、当前状态预览及 abort/replace/skip 冲突策略；先暂存再激活，失败逆序回滚并保留 recovery directory。提取文件时重新校验 SHA256。
- 只读兼容 format-1 历史备份和旧的第四位置 root 参数；站点入口继续同时覆盖 Web 与 `/opt/docker` 数据。
- 当前仍是文件级离线备份，不自动停写入服务，不保证数据库一致性；数据库原生 dump/restore 和跨机 Docker 重建继续后续实现。

## v1.25.0 隐私统计、可信下载与声明式市场基础

- 固定鸣谢“棉花云：优质网络提供商 www.88sup.com”仅出现在交互主菜单、README 与 Pages，不提供商业广告专栏、联盟参数或点击跟踪。
- 修复一层 YAML 配置读取；新增 `fusionbox privacy status|on|off|reset-id`。匿名统计默认关闭，首次交互安装默认拒绝，非交互安装始终关闭；随机安装 ID 与同意记录均原子写入私有配置目录。
- 新增开源 Cloudflare Worker + D1 聚合后端，包含严格事件协议、HMAC 假名化、双主体原子限流、公开 summary/badge 与隐私说明。真实 Worker 尚待 Cloudflare 凭据、D1 ID 和迁移后上线，客户端生产端点在此之前保持为空。
- 安装与自更新优先下载 `FusionBox-vX.Y.Z.tar.gz` 和 `SHA256SUMS`，严格校验摘要、归档路径、条目类型、版本与发行结构；只有 GitHub latest API 不可用时才明确回退 main 快照，Release 下载或校验失败不会降级。
- GitHub Actions 每日只累计 `FusionBox-v*.tar.gz` 主资产下载量，并向 README/Pages 提供确定性 JSON；下载量不冒充用户数。
- 新增版本化声明式应用目录：严格 JSON、digest 固定镜像、HTTPS + SHA256/revision pin、原子缓存、内置回退、撤回条目、多服务/TCP/UDP/NAS/device/host network/Docker socket 能力，以及高权限精确确认。v1 声明式生命周期当前限定为 install/status/uninstall。

## v1.24.2 仓库瘦身与 LICENSE

- tests/ 退出仓库（本地与验证服务器保留；行为测试规模不变：42 基础 + 584 行为，零跳过），CI 改为仅对发布脚本做语法检查后打包
- 补充 MIT LICENSE 文件
- README 已于 v1.24.1 重构为产品式分层结构；本文件承载 v1.24.0 → v1.2.0 全部版本原文

## v1.24.0 受管市场大扩容：五款新模板（G51/G53/G54）

以对标项目的应用定义为配置规格（镜像/端口/挂载/环境变量），全部转换为 FusionBox 受管目录自有格式，digest 均经测试服务器实拉验证：

```bash
fusionbox market managed install lobe-chat --confirm    # AI 聚合对话，8085 -> 3210，内存 1.5G（实测 OOM 调高）
fusionbox market managed install open-webui --confirm   # AI 对话（Ollama/OpenAI），8086 -> 8080，首启约 5-10 分钟
fusionbox market managed install n8n --confirm          # 工作流自动化，8087 -> 5678，localhost HTTP 已关安全 Cookie
fusionbox market managed install openlist --confirm     # 文件列表/WebDAV，8088 -> 5244，root+全 cap 丢弃运行
fusionbox market managed install navidrome --confirm    # 音乐流媒体，8089 -> 4533，music 卷只读挂载
```

- **框架扩展**：受管模板支持多具名卷（`mounts` 列表，navidrome 的 data+music 只读组合）与环境变量（`environment`，经校验）；`compose up --wait-timeout` 随每应用 `health_retries` 缩放（原 45 秒硬编码导致慢启动应用必然失败）。
- 真机验证中发现并修复：lobe-chat 512M 内存 OOM（调至 1.5G）、openlist 非 root 无法写新卷（改为 root+全 cap 丢弃）、openlist/open-webui 首启超过固定健康窗口（60/300 次重试）。
- 真机验证 **27/27 全过**：五款应用各一轮完整生命周期（安装/健康/HTTP 服务实测——lobe-chat 307、n8n 200、openlist 200、navidrome 302 / open-webui 200——重复安装与端口占用拒绝、卸载保留数据、清理核对）。
- 各应用安全语义：localhost 发布、mem/cpus/pids 限额、日志轮转、digest 固定拒绝升级；new-api/lobe-chat 首次设置凭证的提醒在 catalog 描述中。

Linux 验证目标：42 基础 + 584 行为（新增 8），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34；受管应用真机 27/27。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.23.0 自动更新开关与 new-api 受管模板（G66/G51）

```bash
fusionbox update --cron on|off|status    # 每周日 03:07 自动运行 fusionbox update（受管 cron 条目，0600）
fusionbox market managed install new-api --confirm   # LLM API 网关（127.0.0.1:8084 -> 3000，1GiB 预检）
```

- **自动更新（G66）**：受管 `/etc/cron.d/fusionbox-update` 仅调用既有带暂存校验/回滚的 `self_update`；日志写入私有文件；需已安装部署（/usr/local/bin/fusionbox）；off 即删条目。业务状态/配置在既有部署流程中保留。
- **new-api（G51 首个 AI 类模板）**：LLM API 网关与计费面板，SQLite 位于具名卷，digest 固定镜像（实拉验证 `sha256:0a4d62b1…`），`/api/status` 真实健康检查。**首次启动无认证，部署后请立即设置管理员密码**（catalog 描述已注明）。
- 真机验证 15/15：cron on/status/off 全往返（0600 条目写入/删除）、真实部署 new-api（健康 + /api/status 200 + 载荷）、重复安装拒绝、卸载清理核对。

Linux 验证目标：42 基础 + 576 行为（含 update-cron 单元与市场目录校验扩展），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34；真机 15/15。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.22.0 rsync 任务、文件管理器与小工具（G16/G14/G22）

```bash
fusionbox system rsync add|list|run|enable|disable|rm   # 同步任务（0600 清单，可选每日 03:30 cron，镜像模式需确认）
fusionbox system file ls|cat|mkdir|cp|mv|del|chmod|tar|untar|send
fusionbox system genpass [8-128]        # 随机密码生成
fusionbox system gai status|v4-first|default   # IPv4/IPv6 优先级切换（自动备份 gai.conf）
fusionbox system locale [语言]           # 查看或切换系统语言
```

- **rsync 任务**：端点严格校验（本地绝对路径 / user@host:/path）；默认安全同步（-a），`--delete` 镜像模式需显式确认；enable/disable 原子改写受管 `/etc/cron.d/fusionbox-rsync`；rm 仅删任务不删数据。
- **文件管理器**：`del` 一律移入 `/root/.fusionbox_trash/files`（可经 system trash 管理），拒绝删除 `/`；send 走 scp 并校验目标格式；tar/untar 基于 basename 语义。
- **小工具**：genpass 从 /dev/urandom 生成（8-128 位）；gai.conf 修改前后均自动备份；locale 走 locale-gen + update-locale（重新登录生效）。
- 真机验证 32/32：真实 rsync 目录同步落盘、0600 清单与 cron 条目写入/移除、重复与非法名称拒绝、文件管理器全操作（含回收站与拒绝删 /）、真实 genpass 32 位、gai 往返。

Linux 验证目标：42 基础 + 576 行为（新增 59），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34；真机 32/32。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.21.0 Web 调优档位与 brotli/WP-Redis（G45/G46/G47/G48）

```bash
fusionbox web tune show                  # 查看当前 nginx/PHP-FPM/MySQL 关键参数
fusionbox web tune standard|high         # 档位切换（修改前自动备份，可 restore）
fusionbox web tune restore               # 恢复最近一次调优备份
fusionbox web brotli status|on|off       # brotli 压缩开关（Ubuntu brotli 模块包）
fusionbox web wp-redis <domain>          # WordPress Redis 预配置
```

- **tune 档位**：nginx worker_connections（1024/4096）+ gzip（high 档）；PHP-FPM 池按总内存计算（standard 内存÷80、high 内存÷40，下限 5）；MySQL innodb_buffer_pool_size（128M/1G）**只写配置不自动重启数据库**。修改前备份到 `/etc/fusionbox/tune-backups/latest`（manifest 映射），`nginx -t`/`php-fpm -t` 校验失败自动回滚；restore 按 manifest 逐文件恢复并重载。
- **brotli**：安装 Ubuntu 打包的 `libnginx-mod-http-brotli-filter`，写自有 `conf.d/fusionbox-brotli.conf`，`nginx -t` 失败自动移除；off 仅删自有文件。zstd 无稳定发行版模块，明确不提供。
- **wp-redis**：检测 wp-config.php 标准锚点注入 `WP_REDIS_HOST`/`WP_CACHE`（幂等），redis 可用性检查 + 可选安装 redis-server/php-redis，`php -l` 校验失败回滚；激活缓存还需 WP 内 Redis Object Cache 插件（不代装）。
- 真机验证 24/24：真实 nginx 档位修改/备份/恢复、真实 brotli 模块安装并实测 `Content-Encoding: br` 响应、真实 redis 安装 + wp-config 注入与幂等、门禁拒绝。

Linux 验证目标：42 基础 + 517 行为（新增 61），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34；真机 24/24。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.20.0 受管市场模板扩容：Uptime-Kuma 与 ddns-go（G51/G52 部分）

在受管市场（`market managed`）新增两个单卷、localhost 发布的模板，沿用既有登记/锁/端口预检/健康检查/回滚框架：

```bash
fusionbox market managed install uptime-kuma --confirm   # 监控面板，127.0.0.1:8082 -> 3001，1.5GiB 磁盘预检
fusionbox market managed install ddns-go --confirm       # DDNS 更新器，127.0.0.1:8083 -> 9876，512MiB 预检
fusionbox market managed status <app>
fusionbox market managed uninstall <app> --confirm       # 保留数据卷；显式重装沿用原镜像
```

- 镜像以官方 manifest digest 固定（uptime-kuma:1 `sha256:70233f4a…`、ddns-go `sha256:0336e6ed…`，测试服务器实拉验证），候选 digest 变更即拒绝升级。
- 真实健康检查：kuma 使用镜像自带 `extra/healthcheck.js`（镜像无 wget，实测纠正）；ddns-go 用 wget 探测 9876。两者均以容器默认 root 用户运行（镜像默认），localhost only，`domain` 明确不支持。
- 首次访问为重定向语义：kuma `/`→302 `/dashboard`、ddns-go `/`→307 `/login`，属预期而非故障。
- 真机验证：真实部署/健康/状态/对外 HTTP 服务（重定向确认）/重复安装与占用端口拒绝/卸载保留卷/清理核对，共 13 项；两类应用各一轮完整生命周期。

Linux 验证目标：42 基础 + 456 行为（新增 1），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34；受管应用真实部署 13/13。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.19.0 运维小工具合集（G68/G21/G15/G62/G19）

```bash
fusionbox system info                 # 新增 x86-64 psABI 级别（v1-v4，二进制兼容性参考）
fusionbox system sshkey               # 新增 7) 从 GitHub 用户 / https URL 导入公钥（逐条校验+确认）
fusionbox cluster sshout add|list|rm|connect   # SSH 出站收藏（0600 清单、严格校验、直连）
fusionbox workspace work new|attach|send|kill|list   # work1-10 编号 tmux 会话（可注入首条/任意命令）
fusionbox market clamav <路径>         # ClamAV 病毒扫描（按需安装，威胁返回非零，摘要+日志）
```

- sshkey 导入仅接受 https；每行经 ssh-keygen 校验并逐条确认后写入，全部拒绝时不改动 authorized_keys。
- sshout 收藏存 `/etc/fusionbox/ssh_out.conf`（0600），名称/目标/端口严格校验，防注入形态拒绝。
- 编号会话基于 tmux（缺失时明确报错），注入命令经 send-keys 在会话内执行。
- clamav 扫描排除 /sys /proc /dev，日志落 /root（0600）；发现威胁返回 1，出错返回非零。
- 真机验证（25 项全过）：psABI 真实 CPU（v4）、GitHub 真实拉取公钥（全拒绝时 authorized_keys 零改动）、sshout 真实文件往返与拒绝路径、work5 真实 tmux 会话注入命令执行并清理、clamav 拒绝路径；完整扫描为 mock 覆盖（夹具不安装重型杀毒包）。

Linux 验证目标：42 基础 + 455 行为（新增 85），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34；真机 25/25。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.18.0 站点运维闭环（G39/G41/G42/G49/G50）

```bash
fusionbox web clone <源域名> <新域名>      # 克隆站点：目录+配置（nginx -t 回滚；WP 可选克隆库并替换域名）
fusionbox web cache                        # 清缓存：重启 php-fpm、清 fastcgi_cache 目录、重载 nginx、可选 CF purge
fusionbox web goaccess [domain]            # GoAccess 报表（/root/fusionbox-reports，0700/0600，含 IP 不入 Web 目录）
fusionbox web upgrade [nginx|php|mysql|redis|all]   # 组件热升级（按包管理器，失败保持原版本，不提供降级）
fusionbox web uninstall-lnmp               # 卸载 LNMP（YES 门禁；配置先备份到 /root；keep/wipe 数据）
```

- 克隆按源 server 块解析（复用 `web sites` 解析器），新目录建在源根目录同级，配置做域名+路径替换；`nginx -t` 失败自动删除新配置并保留目录回滚；WordPress 站点检测 wp-config.php 后可克隆数据库（CREATE DATABASE + mysqldump + sed 域名替换导入）。
- 缓存清理只清 nginx.conf/conf.d 中声明的 `fastcgi_cache_path` 目录；CF purge 需已配置 `/etc/fusionbox/cloudflare.conf`，未配置时如实跳过。
- 热升级按 dpkg/rpm 实际安装包升级（含 nginx-core）；升级失败不伪装成功，也不宣称可回滚。
- LNMP 卸载配置备份失败即中止；wipe 分支删除 /var/www、/var/lib/mysql、/var/lib/redis。
- 真机验证（25 项全过）：临时启用服务器上已有但损坏的 nginx-core 夹具——sites 清单解析、真实克隆（含克隆站对外服务）、缓存清理、GoAccess 真实安装与报表、nginx 热升级、卸载门禁与完整卸载（配置备份 tar + 包 purge + 数据 wipe 逐项核验）；验证后恢复服务器原状（nginx-core 保持已安装未激活，验证产物清理）。

Linux 验证目标：42 基础 + 370 行为（新增 37），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34；真机 25/25。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.17.0 Docker 一键卸载与容器端口封禁（G30/G27）

```bash
fusionbox panels docker port-block add <容器名> <tcp|udp> <端口>   # DOCKER-USER DROP（原始目标=容器 IP）
fusionbox panels docker port-block list                            # 列出受管规则
fusionbox panels docker port-block del <容器名> <tcp|udp> <端口>    # 按 comment 标记删除
fusionbox panels docker uninstall                                  # 一键卸载（YES 门禁）
```

- **端口封禁（G27）**：规则插入 `DOCKER-USER` 链顶部，按 `容器 IP + 容器端口`（DNAT 后的原始目标）匹配，带 `fb-port-block:容器:协议:端口` comment 标记；只增删自有规则，不触碰他人配置。严格校验容器名/协议/端口；插入失败自动回滚已插规则；容器多网络时逐 IP 出规则。限制：IPv4 only、规则不持久（重启失效）、容器重建后 IP 变化需先 del 旧规则。
- **一键卸载（G30）**：先展示只读资源统计（容器/镜像/卷/网络计数与数据目录体积，失败不伪装为零）→ 双重确认（confirm + 输入 `YES`）→ 可选保留数据目录（`keep`）→ 停止并删除全部容器/网络/卷/镜像 → 停用 docker/docker.socket/containerd → 按 apt/yum/apk/zypper 逐包检测并 purge → 校验 docker 命令消失。无论资源由谁创建（市场/Compose/手工）全部删除，数据不可恢复；containerd 停用影响本机其他容器运行时。
- 真机验证（20/20）：临时 netns + veth 产生真实转发流量——基线可达已发布端口 → 加规则后 DOCKER-USER DROP 生效（curl 超时）→ del 后恢复 → iptables-save 零残留；卸载仅验证拒绝路径（YES 门禁取消后容器数量不变），完整卸载由 36 项 mock 测试覆盖（测试服务器需保留 Docker 环境供后续夹具使用）。

Linux 验证目标：42 基础 + 333 行为（新增 36），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34；真机 20/20。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.16.0 环境变量与网卡管理（G09/G10）

```bash
fusionbox system env list             # 列出清单内 rc 文件与语法状态
fusionbox system env show <file>      # 查看文件（仅允许清单内路径，拒绝 /etc/shadow 等）
fusionbox system env check            # 全部 shell rc 文件 bash -n 语法检查
fusionbox system env edit <file>      # 编辑：预备份到私有目录，保存后 bash -n 校验，失败可一键恢复
fusionbox network nic list            # 网卡/地址一览 + 默认路由网卡识别
fusionbox network nic info <dev>      # 地址/计数器/ethtool 链路与驱动详情
fusionbox network nic down <dev>      # 停用网卡（默认路由网卡需显式风险确认）
fusionbox network nic up <dev>        # 启用网卡
```

- env 只管理允许清单内文件：/etc/profile、/etc/bash.bashrc、/etc/profile.d/*.sh、/etc/environment、~/.bashrc、~/.bash_profile、~/.profile；拒绝软链接与清单外路径。
- 编辑前自动备份到 `$HOME/.config/fusionbox/backups/env/`（0700），保存后 `bash -n` 校验；语法错误时可从备份一键恢复，防止坏的 rc 文件破坏登录 shell。
- nic up/down 直接改变网络状态：停用承载默认路由的网卡前必须确认风险提示；设备名校验严格（字母/数字/._-，≤15 字符），未知设备在执行前被拒绝。
- 真机验证：env list/check/show/允许清单拒绝/备份与 no-op 编辑循环 11 项 + nic 只读与拒绝路径 6 项；up/down 不在真实服务器执行（隔离边界：不改网络状态），由 mock 测试覆盖。

Linux 验证目标：42 基础 + 297 行为（新增 50 项 env/nic 与夹具中的既有项复核），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34；真机 17/17。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.15.0 Fail2Ban 管理面板（G11）

`fusionbox system fail2ban`（别名 `f2b`）补齐 Fail2Ban 完整运维面板：状态总览、封禁清单、解封、日志、SSH 防护参数与卸载。系统工具菜单选项 11 提供相同入口。

```bash
fusionbox system fail2ban status        # jails 总览 + sshd jail 详情（只读）
fusionbox system fail2ban banned        # 当前封禁 IP 清单
fusionbox system fail2ban unban 192.0.2.1   # 解封（IPv4/IPv6 严格校验后调用 fail2ban-client）
fusionbox system fail2ban log 50        # 日志尾部 N 行（上限 500；无文件时回退 journalctl）
fusionbox system fail2ban params 5 600  # maxretry/bantime（沿用 v1.12.1 受管事务：staged 校验+回滚）
fusionbox system fail2ban uninstall     # 停用服务 + 移除自有参数文件 + 按包管理器 purge
```

- 解封/状态/日志为只读或幂等操作：unban 对未封禁 IP 同样返回成功语义（地址不再在封禁清单）。
- 卸载仅移除 FusionBox 受管的 `jail.d/99-fusionbox-sshd.local`（marker 归属校验，未知文件拒绝删除）；jail.local 等自有配置保留；服务 `systemctl disable --now` 后按 apt/yum/apk/zypper 卸载软件包，卸载后校验二进制消失。
- 卸载会使 SSH 暴力破解防护消失，需显式确认；真机验证仅覆盖 status/banned/ban-unban 循环/日志（测试服务器 fail2ban 正在防护 SSH，不实际停用），卸载与 params 事务由 mock 覆盖。

Linux 验证目标：42 基础 + 247 行为（新增 16），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34；真机 14/14。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.14.0 用户管理与 SSH 加固工作流（G03/G04/G05）

新增用户全生命周期与登录策略管理。危险操作沿用 `system_safety.py` 事务模式：暂存 + 备份 + 校验（visudo/sshd -t/-T）+ 失败回滚，拒绝软链接与未知归属文件。

```bash
fusionbox system users                 # 交互菜单（列表/创建/删除/sudo/密码）
fusionbox system users add deploy      # 创建用户（useradd -m，bash shell）
fusionbox system users passwd deploy   # 修改用户密码（chpasswd，stdin 传入，不落 argv/日志）
fusionbox system users sudo deploy     # 授予 sudo（受管文件 /etc/sudoers.d/90-fusionbox-deploy）
fusionbox system users sudo deploy nopasswd
fusionbox system users unsudo deploy   # 回收 sudo（仅删除自有 marker 文件）
fusionbox system users del deploy      # 删除用户及主目录（拒绝 root 与 uid<1000）
fusionbox system hardening             # 加固向导：建用户→装公钥→sudo→验证登录→收紧 root
fusionbox system sshkey                # 新增 5) 开启 root 密码登录  6) 禁止 root 密码登录
```

- 用户名仅允许小写字母开头、数字/_/-，最长 32 字符；密码拒绝冒号/换行、上限 512 字符，通过 stdin 传递，不进命令行参数与日志。
- sudo 授权只写自有命名文件（marker 归属校验，拒绝覆盖同名未知文件），staged `visudo -c` 验证后安装 0440 root:root，目标验证失败回滚；不修改 sudoers 主文件、组成员或他人配置。
- `PermitRootLogin` 仅接受 yes/prohibit-password/no；沿用 `sshd -t`/`sshd -T` 生效值校验、重载与失败回滚，socket activation 仍拒绝自动处理。
- 加固向导在密钥登录验证通过（本机回环实测或人工独立确认）前绝不修改 root 策略；粘贴公钥场景本机无私钥，必须人工另行验证后再继续。
- 真机验证为隔离范围：密钥登录经生产 sshd 以专用测试用户实测（零配置改动，登录前后校验和一致）；PermitRootLogin 生效值仅在暂存配置副本上以 sshd -t/-T 验证，生产 sshd 未重载；root 密码未改动。

Linux 验证目标：42 基础 + 231 行为（新增 22），SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34。ACME/Cloudflare/Telegram 仍待凭据验证，全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.13.0 受管 ntfy 通知服务（限定目录扩容）

复用原有注册表、flock、归属检查、端口探测及 Compose 备份，不新增第二套生命周期。新增 [ntfy 官方镜像](https://docs.ntfy.sh/install/) `binwiederhier/ntfy:v2.28.0`，固定官方 manifest digest `sha256:6ef4b819f722fccdc036af611c4774cfdc2de821ab74fdd48bbf4c9d6f8973da`，部署登记实际本地 image ID。不是任意镜像安装器。

```bash
fusionbox market managed catalog
fusionbox market managed install ntfy --confirm
curl -d 'hello' http://127.0.0.1:8081/demo
curl 'http://127.0.0.1:8081/demo/json?poll=1&since=all'
fusionbox market managed status ntfy
fusionbox panels compose-backup backup fb-market-ntfy /root/ntfy.tar.gz --confirm-stop-writers
fusionbox market managed uninstall ntfy --confirm
fusionbox market managed reinstall ntfy --confirm --reuse-data
```

- 默认仅 `127.0.0.1:8081`，UID/GID `65534:65534`、全部 capabilities 删除、no-new-privileges，无 Docker socket、无特权模式。内存上限 128 MiB、0.5 CPU、64 PID，日志 2×5 MiB；注册表与 Docker 数据盘各需 512 MiB 空闲（最低预检，不是磁盘配额；镜像现场约 115 MiB，缓存随流量增长）。
- 本机通知 publish/poll 与 SQLite 24 小时消息缓存，卷 `fb-market-ntfy_data` 挂载 `/tmp`，缓存文件 `/tmp/ntfy-cache.db`。**无认证，所有本机可访问者能发布/读取话题，不用于敏感数据或不可信多用户环境。**无需初始化密码，不生成或输出凭据；未启用附件、外部推送或公开入口。
- 实际 `/v1/health` JSON 必须 `healthy: true`，不以“容器运行”代替健康。卸载保留数据/配置/登记，重装只使用原 image ID。`update` 仅检查固定版本；候选 image ID 不同即拒绝，不会把迁移后的数据库盲目回滚到旧镜像。跨版本迁移需另行设计；重装失败只清理新建自有容器，不承诺回滚应用本身可能写入的数据。
- 备份/恢复复用 `panels compose-backup`，必须确认停写，实际停止本项目容器后复制 SQLite；不是在线数据库一致性承诺。仅同一登记/配置/镜像项目恢复，外部写入者须暂停；不支持跨机重建。`domain/tls/tls-refresh ntfy` 明确拒绝，原 Nginx 域名/TLS 能力保持不变。

Linux 验证目标：42 基础 + 209 行为，SSH 21、Compose 13、Docker 诊断 15、Nginx 市场 20、ntfy 17、TLS 34。ntfy 真实夹具覆盖发布/读取、离线备份与恢复、保留卷重装/重启、版本升级拒绝、健康失败清理与重试；只操作专用夹具，结束证明容器/卷/网络清理。ACME/Cloudflare/Telegram 仍缺真实凭据；全部剩余待办未宣称完成，优先级见[实施跟踪](docs/implementation-status.md)。

## v1.12.1 审计安全修复（历史）

- SSH 授权密钥使用 ssh-keygen 验证，显示/删除使用相同物理行号；注释、无效和带选项的密钥不作为禁用密码的依据。密码开关仅修改 PasswordAuthentication，不宣称禁用 PAM/交互式认证。必须先在独立连接验证密钥登录。
- SSH 配置保留权限/归属与私有备份，校验 sshd -t/-T 后重载，失败恢复；Include 生效值不符、Match 或 socket activation 要求人工处理。不会修改 root 登录策略。
- Swap 删除仅针对明确确认归属、非链接、私有的 /swapfile；验证活动路径和 swapoff 成功后原子修改 fstab，保留其他条目。失败不自动 swapon，备份保留。
- Fail2Ban 仅写自有 jail.d/99-fusionbox-sshd.local，拒绝未知同名文件和无效数值；暂存/整体校验及重载失败回滚。不覆盖 jail.local，不改变启用状态/端口/后端；更晚配置可能覆盖参数。
- 旧 Docker export/save 使用私有暂存、校验与不覆盖发布；失败不传输、不报成功。export 仅容器文件系统，不含卷或运行配置。**旧 Docker 端口开关已禁用**：DNAT 后不能按宿主端口正确匹配；请明确设置 Compose 宿主 IP 绑定并验证，容器+原始目标地址规则仍待实现。
- Nginx/PHP-FPM 旧优化入口检查校验和重载结果，失败恢复配置，双重失败明确报告运行状态未知；备份保留。

依赖 Python 3、OpenSSH 工具及对应已安装服务。操作期间须暂停外部配置写入；断电/进程强杀与回滚失败需根据备份人工恢复。这不是全部待办完成声明。Linux 验证目标：42 基础 + 202 行为（新增 25），SSH 21、Compose 13、Docker 诊断 15、市场 20、TLS 34；真实 sshd 和 Fail2Ban 仅临时配置校验，服务重载/Swap/防火墙失败路径使用模拟。ACME/Cloudflare/Telegram 仍待真实凭据验证。

## v1.12.0 Docker 只读诊断（G26/G31 限定范围）

```bash
fusionbox panels docker summary          # 引擎镜像数、容器状态计数、网络/卷数、磁盘用量
fusionbox panels docker summary --all    # 另列全部容器、镜像标签、网络、卷
fusionbox panels docker detail NAME_OR_ID
```

Docker 菜单 14/15、容器管理 9 提供相同入口；已有日志/终端/stats 入口保留。使用 Bash 与 Docker 原生格式模板，无新增 Python 运行依赖。沿用 CLI 的 Docker context/环境与主入口 root 要求，不安装、不启动 Docker、不更改任何资源。CLI 不暂停；参数错误返回 2，查询失败返回非零。缺少 Docker、守护进程不可达、权限不足或对象消失不会伪装为零；错误正文不输出，避免泄露端点凭据。

总览默认仅聚合数据；`--all` 显示所选引擎清单，请勿公开生产输出。Stopped 明确定义为 created + exited + dead，paused/restarting/removing 独立计数；镜像数来自引擎，标签行可能重复同一镜像 ID。磁盘用量使用 Docker shared/reclaimable 口径，不是宿主剩余空间。多个查询不是原子快照。

详情只接受单个简单名称或 ID，显示镜像引用/ID、状态/健康状态、重启策略、配置及运行端口、挂载/网络、持久化 HostConfig 限额和运行容器的即时 stats。全部环境变量值、命令参数、标签、健康检查日志都不展示；无 raw inspect 开关。挂载路径/网络仍可能敏感。Memory=0 表示无容器内存上限；NanoCPUs=0 仅表示无 NanoCPU 上限，quota/cpuset/父 cgroup 仍可能限流；CPU 使用率不是 CPU 限额。停止/暂停容器不采样 stats，配置限额仍显示；采样失败明确标未知并失败退出，不填零。

验证目标：Linux 42 基础 + 177 行为（新增 12），SSH 21、Compose 13、同一 Compose 专用夹具新增 Docker 诊断 15、市场 20、TLS 34。新夹具验证运行/停止/暂停/健康、端口/具名卷/网络、镜像/限额、名称/ID 与敏感环境隐藏；诊断原始输出不进日志。只完成 G26 详情与 G31 总览范围，不代表所有 Docker 管理功能或全部待办完成。ACME、Cloudflare、Telegram 仍待真实凭据验证。

## v1.11.1 校验归档 SSH 异地传输（历史）

新增 `fusionbox cluster archive push|pull|status`，集群菜单选项 9 提供参数帮助。复用严格校验的节点清单；仅支持现有 `archive.py` / `backup_jobs.py` 生成的 `config/system/web` 清单归档。Compose 专用归档、旧无清单 tar、应用重建和跨主机恢复不在本批范围。

```bash
# 先由目标 SSH 用户创建专用、私有、已确认归属的目录（0700）。
# key 与已通过独立渠道核对的 known_hosts 必须操作者拥有、0600/0400。
# 将 ARCHIVE_SHA256 设置为可信来源的完整归档 SHA-256；push 前可用 sha256sum 计算。
fusionbox cluster archive push backup-node config.tar.gz \
  --file /root/config.tar.gz --scope config --sha256 "$ARCHIVE_SHA256" \
  --remote-root /srv/fusionbox-archives --key /root/.ssh/backup_ed25519 \
  --known-hosts /root/.ssh/backup_known_hosts --confirm-owned-store
# pull 使用同样参数，将 --file 改为本地目标；其父目录须已存在、归本人所有且 0700。
# status 使用同样参数但不需要 --file；检查远端文件权限和预期 SHA-256。
```

仅使用显式密钥、BatchMode 与严格 known-host 校验，禁用密码/交互认证、SSH agent、用户 SSH config、转发与自动信任新主机。两端需 Linux/Python 3，客户端需 OpenSSH；不自动安装、不保存密码、不迁移密钥、不修改 SSH 服务。连接超时 10 秒，传输 `--timeout` 默认 300 秒、允许 1–3600 秒；失败返回非零，手动重试。远端路径只接受规范绝对路径的字母/数字/下划线/点/横线，文件名必须为简单 `.tar.gz` basename。

私有临时文件接收完成、SHA-256 一致后才原子发布；使用 no-clobber hard-link publication 避免 rename 覆盖并发目标，随后移除临时名。已有同哈希私有普通文件允许幂等重试，不同内容、软链接、额外硬链接、特殊文件或不安全目录拒绝。push 先冻结并完整校验本地归档；pull 在本地再次检查 SHA-256、清单范围与压缩完整性，从不自动解压。源文件始终保留，临时失败清理；断电/强杀可能留下私有 `.transfer-*`，须人工审查。操作期间须暂停同账户外部写入者；存储目录应专用于归档。无自动调度、保留删除或旧 cron 迁移。

SHA-256 证明与可信预期字节一致，**不是归档作者签名或真实性证明**；SSH host key 认证连接端点。请独立保管可信摘要与 host key。验证目标：Linux 42 基础 + 165 行为测试，真实隔离 SSH 21 检查，Compose 13、市场 20、TLS 34。SSH 使用单台服务器临时 sshd、loopback 高端口、独立配置/密钥/authorized_keys，结束清理；不是两主机灾难恢复演练。公共 ACME、Cloudflare、Telegram 仍待真实凭据验证。

## v1.10.0 集群节点安全导入/导出（历史）

```bash
fusionbox cluster export /root/nodes.json
fusionbox cluster import /root/nodes.json --dry-run
fusionbox cluster import /root/nodes.json --confirm
```

G64 本批仅完成节点清单迁移：版本 1 JSON 包含 `format: fusionbox-cluster-nodes`、`version: 1`、`nodes`，每项仅 `id/user/host/port`。不接受密码、私钥、SSH 选项或命令，不导出 SSH 配置/known_hosts，不连接节点。默认只预览，确认后合并；所有同名节点（即使字段相同）拒绝，无覆盖模式。支持严格 DNS/IPv4/裸 IPv6；不支持 IPv6 zone ID、方括号地址或隐式 SSH 用户。上限 4096 节点/输入 1 MiB。

本地继续使用 `nodes.conf` 的 `name|user@host|port` 格式；合法旧记录可直接读取/导出，不自动迁移或改写。确认合并/增删才原子写入规范化记录（0600），原节点字段保留，导入源文件不变。旧文件中的无用户地址、重复 ID、额外字段或不安全字段必须先人工修复，拒绝静默丢弃。节点目录要求操作者拥有且不可被其他用户写入；文件必须操作者拥有、私有 0600/0400、单硬链接，拒绝所有路径软链接。导出目标必须不存在，父目录须已存在；绝不覆盖既有文件。导入源也需私有权限。新增/删除/导入/导出共享非阻塞 flock，冲突报错后重试；执行从锁内校验的快照读取，快照后节点变更不改变本次目标。外部手工写入者须暂停。

菜单节点管理增加导入/导出。Linux 验证目标：42 基础 + 150 行为（新增 14），Compose 13、市场 20、TLS 34 保留。真实集群连接、批量任务、SSH 密钥/配置迁移均未验证，也未纳入本批。

## v1.9.0 自备证书刷新与实际入口状态（历史）

新增 `fusionbox market managed tls-refresh nginx --confirm`：在注册表锁内重新检查当前登记的 PEM/私钥、SAN、有效期与匹配关系，通过 Nginx 校验后重载，并有界等待本机 SNI 入口实际提供新证书 SHA-256。`status` 显示到期时间、剩余完整天数和本机实际证书是否匹配；本机身份探测不校验 CA 信任，不能替代公共链/主机名验证。

刷新仍不复制、修改或删除用户证书/私钥，无私钥快照。必须先暂停外部证书与 Nginx 配置写入者；外部覆盖了原文件后无法恢复旧文件。校验失败不重载；重载或实际证书确认失败返回失败并保留私有 `.tls-refresh.json` journal，报告运行状态未知，不声称回滚成功。旧工作进程可能仍在服务，但不能保证。修复原路径文件后显式重试同一命令，确认成功才清除 journal；期间其他受管变更被阻止，状态仍可查看。未知 journal 拒绝覆盖，不自动签发/续期，不安装 Certbot hook。

本批验证目标：Linux 42 基础 + 136 行为、Compose 13、市场 20、域名/TLS 34 项；包含真实外部文件轮换、失败后旧证书仍提供服务、显式恢复、过期/错配拒绝，以及读取失败、跨日边界和连续失败回归。完整发布以最终提交归档测试结果为准。

## v1.8.1 自备证书 HTTPS（历史）

受管域名可显式启用已有 PEM 证书与私钥。先创建域名映射，再启用 TLS；默认 HTTPS 443 并将 HTTP 重定向到 HTTPS，`--tls-port` 可选独立端口，`--no-redirect` 显式保留 HTTP 服务。

```bash
fusionbox market managed tls nginx --cert /root/certs/fullchain.pem --key /root/certs/key.pem --confirm
fusionbox market managed status nginx
fusionbox market managed tls nginx --disable-tls --confirm
```

依赖已安装 OpenSSL。只引用操作者提供的文件，不复制、删除、输出私钥，也不自动 chmod。要求绝对规范 ASCII 路径、无软链接/硬链接、当前操作者拥有的普通文件；私钥权限 0600/0400，证书不得组/全局可写，父目录不可被其他用户写入（系统 sticky 临时目录除外）。不支持加密私钥、CN 回退或通配 SAN；验证 PEM 可解析、精确 DNS SAN、有效起止时间、证书和私钥公钥一致。状态重新校验当前文件并显示到期时间；这些检查不证明公共 CA 信任、完整证书链、DNS 或公网可达性。

沿用自有配置、冲突检测、暂存/整体 Nginx 校验、重载失败回滚与双重失败 journal。更新保留 TLS；卸载 HTTP/HTTPS 均返回 503，重装验证证书后恢复 TLS；停用恢复 HTTP 并保留原证书/私钥文件。外部证书或配置写入者必须暂停；证书更换后需重新执行 tls 命令校验并重载，无自动续期。证书文件失效导致 Nginx 无法校验时需人工修复原文件；重装入口失败仍返回失败，不保证应用与入口共同原子恢复。

隔离夹具生成 `test.local` 自签名证书并以 `curl --cacert` 严格验证真实 TLS 握手（不使用 `-k`）；错误主机名、过期证书、私钥不匹配被拒绝且状态不变。这是自签名测试信任，**不是公开 CA/ACME 验证**。未调用任何外部签发服务，未改生产 443。Linux 42 基础 + 128 行为、Compose 13、市场 20、域名/TLS 24 项检查；详见实施跟踪。ACME/Cloudflare/Telegram 与其余待办未宣称完成。

## v1.7.0 受管应用 HTTP 域名入口（历史）

受管 Nginx 支持独立自有宿主 Nginx 配置，不复用旧站点写入器。依赖 Linux、Python 3 标准库、Docker Compose v2 与已运行的宿主 Nginx；宿主配置必须已有 `include /etc/nginx/conf.d/*.conf;`。不安装/改写主配置、不修改防火墙。操作前暂停其他 Nginx 配置写入者，FusionBox 的锁只能协调自身操作。

```bash
fusionbox market managed domain nginx --domain app.example.com --confirm
fusionbox market managed status nginx
fusionbox market managed domain nginx --remove-domain --confirm
# 可选独立 HTTP 端口（默认 80）
fusionbox market managed domain nginx --domain app.example.com --listen 18080 --confirm
```

严格限制小写 ASCII DNS 域名、固定 `/` 路径、来自受管登记的 `127.0.0.1` 上游；拒绝 URL/IP/通配符/配置注入与未知配置覆盖。读取 `nginx -T` 检测其他站点域名冲突；正则 server_name 保守拒绝。配置路径固定为 `/etc/nginx/conf.d/fusionbox-market-fb-market-nginx.conf`，校验 token 与完整内容；先暂存 `nginx -t -c`，再校验整体配置并重载。失败恢复旧配置并再次校验/重载；双重失败保留 `.domain-recovery.json` 并阻止后续变更，需人工核对 before/after、实际文件与运行配置后恢复。强杀/断电不保证跨文件原子性。

更新保留映射；卸载先将自有入口改为 503，保留域名设置，避免端口被其他进程复用时错误转发；重装沿用原上游端口并恢复映射。存在映射时禁止更换端口或 `--auto-port`，需先显式移除映射。应用重装成功但域名重载失败仍返回失败，应用可能运行而入口保持暂停，按恢复信息处理。

这是 **HTTP-only 域名映射**，不是 HTTPS/ACME 集成；TLS 明确不可用，没有签发或验证真实证书。DNS/公网可达性需自行配置和验证。默认直接访问仍仅限 localhost，域名映射不会封锁本机上游访问，不声称 `domain_only` 防火墙隔离。市场菜单 6、help、status 均提供入口。更多应用、迁移、真实 ACME/Cloudflare/Telegram 仍待后续。

## v1.6.1 保留数据重装与端口探测（历史）

受管 Nginx 新增 `reinstall --confirm --reuse-data`，只接受已卸载且无容器、归属正确的保留卷、未改动配置与可用的原镜像 ID；不拉取新镜像、不新建替代数据卷。成功后恢复服务并保留静态内容；失败尝试清理本次创建且归属验证通过的容器，恢复原配置，保留原登记/数据。清理失败明确要求人工检查，不删除未知资源。强杀/断电仍需人工检查，不提供跨文件原子事务。

```bash
fusionbox market managed reinstall nginx --confirm --reuse-data
fusionbox market managed install nginx --port 8080 --auto-port --confirm
fusionbox market managed reinstall nginx --auto-port --confirm --reuse-data
```

`--auto-port` 从首选值起最多检查 20 个 localhost 端口（上限 65535）；重装默认使用原端口，首次安装默认 8080。占用时探测下一端口，磁盘/权限等错误不忽略。探测不是端口预留；Docker 实际绑定或健康失败仍返回失败。市场菜单选项 6、help 和卸载状态提示提供入口。此批仅完善原有生命周期，不扩展应用目录、公网/域名访问或数据库迁移。

## v1.6.0 受管应用生命周期基础

新增独立的 `market managed` 入口，首批只支持低占用 Nginx 静态站点。既有软件包/第三方安装入口保持独立，不自动接管。复用 Compose 注册表 `/var/lib/fusionbox/compose-projects`、全局 flock 与原子 0600 写入，目录 0700；生成固定结构 Compose JSON，不 source/eval 注册数据。安装检查端口与注册表/Docker 数据盘至少 256 MiB 可用空间；仅绑定 localhost，64 MiB 内存、0.5 CPU、64 PID、日志大小有限制。

```bash
fusionbox market managed catalog
fusionbox market managed install nginx --port 8080 --confirm
fusionbox market managed status nginx
fusionbox market managed update nginx --confirm
fusionbox market managed uninstall nginx --confirm
# 已生成的项目也可使用现有备份入口（需确认停写）
fusionbox panels compose-backup backup fb-market-nginx /root/nginx.tar.gz --confirm-stop-writers
```

安装必须通过容器健康检查才成功；状态显示归属类型、事务状态、健康与本地地址。更新拉取固定目录中的 `nginx:stable-alpine`，比较实际 image ID；保留前一镜像记录，用不可变本地 image ID 部署，失败尝试回滚并返回失败。内容卷以只读方式挂入 Nginx，更新不会执行内容迁移。卸载只停止/删除经过归属检查的容器，**保留具名数据卷、配置与登记**，无自动数据删除。数据目录为 `fb-market-nginx_data`，可通过 Docker volume inspect 定位并人工部署静态内容；默认首页为 Nginx 欢迎页。

失败安装保留创建的资源与私有恢复记录，使用 status 检查后确认 uninstall；不会报告成功或删除未知资源。卸载后不自动重新安装/认领保留卷，需人工恢复；配置漂移、未知归属、共享卷拒绝更新。更新/回滚双重失败返回人工恢复要求，保留旧镜像记录和数据，不保证服务可用。进程被强杀或断电后检查登记状态、Compose 与 `.previous.json`，不得与外部 Docker/Compose 操作并发。锁只协调 FusionBox；端口预检后仍可能发生竞争，最终以 Docker 和健康结果为准。仅支持本机 Docker socket、Linux/Python 3/Compose v2+；尚无自动端口分配、远程部署、域名/证书接入或任意应用迁移。

验证结果见本版本实施跟踪。真实 ACME、Cloudflare、Telegram 仍未验证。

## v1.5.1 恢复双重失败停机保护

修复 v1.5.0 的不安全默认：恢复和回滚同时失败时，登记项目保持停止，不执行任何 start，返回失败并报告安全归档路径和人工干预要求。备份失败/恢复前安全备份失败（未改数据）仍恢复原运行状态；恢复失败且回滚成功才允许恢复原运行状态。部分容器重启失败会继续尝试其他原运行容器，但整体返回失败，明确报告失败数量与可能部分运行，不宣称恢复成功。安全归档路径在变更前输出，重启失败时仍可定位。

Linux 42 基础 + 96 行为测试全通过，零跳过；真实隔离双容器 Compose 夹具 13 断言，包括双重失败无重启、停止状态和保留安全副本。测试专用容器/卷/网络已确认清理。

## v1.5.0 受管 Compose 项目备份与恢复

Docker 菜单的 Compose 入口现在支持显式登记本机单文件 Compose 项目，然后执行受管备份/同项目恢复。登记需要确认项目归属，使用规范化 Compose 路径和项目名；注册表与全局 `flock` 使用 0700/0600 私有权限。操作只允许本机 Docker socket、已有 Compose 容器、local named volumes；拒绝 bind、external、anonymous、共享到其他项目、非 local driver、特权/设备/secret/config/tmpfs 等不受支持资源，不把任意宿主路径打进归档。

备份/恢复前必须确认所有外部写入者已停止。程序仅停止该登记项目原本运行的容器，记住原本停止的容器并保持停止；成功或无数据损坏的失败路径尝试恢复原运行状态；恢复和回滚双重失败保持停止。备份包含 Compose 文件、解析后的配置、容器运行元数据和具名卷内容，带 SHA-256 manifest。恢复在停写前完整校验归档、项目身份、Compose 内容、卷范围和压缩尾部；停写后先保留安全备份，失败尝试回滚并保留安全归档及错误状态。恢复不自动执行任意 Compose 文件，不删除项目外资源，不输出元数据内容或 Docker 错误正文。

```bash
fusionbox panels compose-backup register <project> <compose.yaml> --confirm-owned-import
fusionbox panels compose-backup backup <project> <archive.tar.gz> --confirm-stop-writers
fusionbox panels compose-backup restore <project> <archive.tar.gz> --confirm-stop-writers
```

Linux 验证：42 项基础检查 + 95 项行为测试全通过、零跳过；真实隔离 Compose 夹具包含两个容器（一个初始运行、一个初始停止）和具名卷，成功备份/恢复、注入备份失败、注入恢复失败并成功回滚、原状态/内容/安全副本共 10 项断言通过；回滚失败另有隔离单元测试，容器、卷、网络已确认清理。此范围不宣称数据库一致性、bind/external 卷、远端 Docker、两主机迁移或任意 Compose 应用支持。真实 ACME/Cloudflare/Telegram 仍待凭据验证。

恢复仅限原登记项目与未变更的 Compose/resolved 配置，不重建容器或镜像；不包含容器可写层、镜像包、ACL/xattr，不能当作整机迁移。卷文件仅支持目录和常规文件（链接/特殊文件拒绝）。归档可能含密码，必须私密保存；SHA-256 不是签名。需预留归档与安全副本空间；SIGKILL/断电不能保证自动重启或原子恢复，应人工检查项目状态与注册表目录下安全归档。恢复与回滚同时失败时项目保持停止，返回失败并要求人工使用安全归档恢复，不启动可能损坏的数据。不要与外部 Compose 操作并行；锁只协调 FusionBox。

## v1.4.4 备份保留与校验恢复

网站数据菜单 → 每日配置任务新增立即快照、登记归档列表、保留数量预览/确认执行和校验恢复。默认不删除，cron 也不自动清理。只有本版本任务成功写入 `inventory.json` 的归档才受保留策略管理；删除前检查所有登记归档 SHA-256、范围和压缩完整性，至少保留最新 1 份。未知文件、旧版本归档和手动备份不自动认领、不按通配符删除。中断可能留下未登记归档或失效记录，需人工检查；校验失败会阻止后续清理。

```bash
python3 /etc/fusionbox/src/lib/backup_jobs.py retention demo --keep 7                 # 仅预览
python3 /etc/fusionbox/src/lib/backup_jobs.py retention demo --keep 7 --enable-delete # 本次执行
python3 /etc/fusionbox/src/lib/backup_jobs.py restore demo --archive <登记文件名> --ack-stopped-writers
python3 /etc/fusionbox/src/lib/archive.py verify web <归档路径>                      # 只读校验
```

恢复前必须停止配置/数据写入，校验 gzip 尾部和全部文件后才开始暂存；替换清单目录、保留旧目录，不自动重载服务。任务运行、保留和恢复共用 Linux flock。SHA-256 用于本地完整性检查，不是数字签名；恢复不保证断电原子性。

Linux 验证：42 项基础检查 + 84 项行为测试全通过、零跳过；新增 6 项覆盖保留预览/删除、未知文件保留、损坏阻断、链接拒绝、确认恢复和登记失败。真实隔离 Docker 卷离线往返另通过内容、权限、恢复副本 3 项断言并清理夹具。该测试只验证文件归档原语，不是完整 Compose/数据库备份认证。Docker 菜单明确 export 不含卷/运行配置，禁用旧 Compose 全目录打包与向 `/` 解压入口。受管 Compose 项目登记、卷/运行元数据、一致停写与失败重启、远端迁移仍待实现；ACME/CF/TG 无真实凭据，未验证。

## v1.4.3 每日配置备份任务

网站数据菜单选项 3 提供创建、列表/状态、删除自有任务与旧 cron 检测。仅备份 `/etc/nginx`、`/etc/caddy` 到本地 `/var/lib/fusionbox/backup-jobs/<id>/`，使用带 `config` 清单范围的归档；不含站点/数据库/容器数据、不传输远端、不停止服务。必须明确确认计划时段没有配置写入者；含链接或特殊文件时拒绝发布。任务使用 Linux flock、私有权限、原子状态和完整归档发布，失败没有可用的半成品。删除任务保留归档，不自动清理磁盘。

依赖 Python 3 标准库和已运行的 cron 服务，菜单先检查 Python；无需 pip。旧任务只报告文件/行号，不输出可能含凭据的命令、不自动改写：历史远程全量任务与新配置范围不等价。恢复需先停止配置写入，并使用 `python3 /etc/fusionbox/src/lib/archive.py restore config <归档路径>`，替换整个清单目录且保留旧目录，不自动重载服务。

## v1.4.2 通知与区域状态修复

Telegram 三条发送路径共用 stdin curl 配置，不把 token 放进 curl 参数或持久临时文件，并检查 HTTP 退出码与 JSON `ok: true`。生成脚本须重新运行安装/更新菜单部署。资源通知发送失败不进入冷却；流量动作失败不写完成标记，下一检查周期重试（成功发送后其他动作失败可能重复通知）。Cloudflare 自适应状态/初始级别按 Zone ID 隔离，切换配置不复用其他区域状态；卸载保留每区域恢复记录且不改变远端安全级别。API 全部为模拟验证，真实账户未验证。

旧远程定时备份生成的 tar 不兼容清单恢复，新建任务入口暂时拒绝执行；已有 cron 不自动删除，需人工审查。迁移安全归档与远端传输仍待后续。

## v1.4.1 可靠性修复与验证范围

本批保留并验证安装器事务回滚和代理命令归属修复；补齐证书负天数、重载失败、调度文件写入检查、集群任务失败传播、DNS 地址校验及暂存替换。系统/站点手动备份改用 Python 3 标准库：私有临时归档、清单与范围校验、成功后发布；恢复拒绝旧无清单归档、路径穿越、链接和特殊文件，分目录切换并保留恢复前目录，切换失败尝试回滚。恢复会替换清单中的整个目录，不自动重载服务；需先停止写入服务。此机制不是数据库快照或跨目录原子事务，断电/强杀后需人工恢复。包含软链接的配置需人工处理，不能直接使用此保守备份入口。

本批 Linux 隔离验证：42 项基础检查、67 项行为测试全部通过，零跳过；不触碰线上 SSH、DNS、sysctl、防火墙或现有容器卷。外部上游安装器、真实 ACME/Cloudflare/Telegram 未验证。TG token 参数暴露、流量重试和 CF 分区域状态已在 v1.4.2 修复；远程定时备份迁移仍待后续。

### v1.4.0 已有运维能力

新增系统 DNS/主机名/hosts/软件源/日志菜单、自定义 Swap、流量告警与 Telegram 资源告警、分级网络参数优化；新增 VPS 评测列表、Docker 镜像配置合并与回滚、证书状态/续期调度检查、站点清单/删除/别名、基础 fail2ban 防护、Cloudflare 辅助工具、集群任务与游戏服务管理。

- 游戏存档使用 Compose 解析出的真实卷名；恢复先验证归档、停止服务、备份现状，失败时尝试回滚，再恢复原运行状态。需要 Python 3、Docker Compose 和 Alpine 镜像。
- 网络优化保存首次修改前的实际 sysctl 值；DNS 管理由 systemd-resolved 或符号链接接管时拒绝覆盖。安装与卸载保留 `/etc/fusionbox` 中的业务状态和密钥权限。
- 续期管理先检查系统 certbot timer/cron，避免重复调度。没有自建续期脚本不代表证书一定过期；实际 ACME 签发/续期需要可解析域名及挑战条件，本批未验证。
- 安全测试不执行真实安装、不改 SSH/防火墙、不关机。Linux 上验证 42 项基础检查、12 项隔离行为测试；另以独立 Compose 项目验证卷解析、备份、恢复、服务恢复与清理共 6 项断言。Windows 的符号链接测试需权限，Linux 无此跳过。
- Telegram 仅模拟响应成功/失败；Cloudflare 未接入真实账户，自动防护与资源告警属于需要自行验证的可选能力。防 CC 仅匹配宿主 Nginx 标准日志的 4xx 请求，不等于完整 DDoS 防护，也未覆盖 Docker 防火墙链。
- 镜像源按运行环境验证，移除已失效的 USTC/网易/百度 Docker 预设；其他第三方镜像和远程评测脚本不保证可用。评测会执行外部代码，需阅读来源并确认。

候选需求逐项状态见 [实施跟踪](docs/implementation-status.md)。应用市场扩容、通用迁移、站点克隆、SSH 加固等后续项没有写成已完成。

## 功能概览

| 模块 | 命令 | 功能 |
|------|------|------|
| 代理管理 | `fusionbox proxy` | 多后端代理 (Xray/v2ray/233boy sing-box/Clash.Meta) |
| 系统管理 | `fusionbox system` | BBR/基准测试/备份/SSH/防火墙/定时任务/磁盘/时区/回收站 |
| 网络工具 | `fusionbox network` | IP查询/流媒体检测/测速/DNS/路由追踪/端口检测 |
| 网站部署 | `fusionbox web` | LNMP/SSL/17种应用部署/反向代理/L4转发/站点备份 |
| 面板工具 | `fusionbox panels` | Docker完整管理/宝塔/Aapanel/FRP/Aria2 |
| 应用市场 | `fusionbox market` | 80+应用一键安装 (10个分类) |
| WARP管理 | `fusionbox warp` | Cloudflare WARP 安装/Proxy模式/流媒体解锁 |
| 后台工作区 | `fusionbox workspace` | Screen/Tmux 会话管理 |
| 集群控制 | `fusionbox cluster` | 多服务器批量管理/游戏服务端/Oracle防回收/k命令 |

---

## 模块详细功能

### 1. 代理管理 (`fusionbox proxy`)

多后端通用代理管理，支持一键安装和配置：

- **支持后端**：Xray-core、v2ray-core、**233boy/sing-box（推荐）**、Clash.Meta
- **支持协议**：VLESS(含 Reality)、VMess、Trojan、Hysteria2、TUIC、Shadowsocks、SOCKS5
- **传输方式**：TCP、WebSocket、gRPC、HTTPUpgrade
- **配置管理**：自动合并多配置、分享链接生成
- **协议适配**：FusionBox 自带配置生成针对 Xray/v2ray 内核；sing-box 后端由社区最佳实践的 [233boy/sing-box](https://github.com/233boy/sing-box) 脚本接管（安装时自动创建 REALITY 配置，支持 TUIC/Hysteria2 等全协议）；添加配置时自动校验拒绝后端不支持的协议组合

```bash
fusionbox proxy install          # 安装代理核心（4选1，sing-box 走 233boy 脚本）
fusionbox proxy add              # 添加代理配置（按后端自动校验协议）
fusionbox proxy sb               # 进入 233boy sing-box 交互主菜单
fusionbox proxy sb add           # 透传：添加 sing-box 配置（同 sing-box add）
fusionbox proxy sb url           # 透传：生成分享链接
fusionbox proxy list             # 列出所有配置
fusionbox proxy start            # 启动代理服务
fusionbox proxy stop             # 停止代理服务
fusionbox proxy restart          # 重启代理服务
fusionbox proxy status           # 查看代理状态（含 233boy sing-box 实例）
fusionbox proxy url <名称>       # 生成分享链接
fusionbox proxy del <名称>       # 删除配置
fusionbox proxy bbr              # 启用 BBR 加速
```

### 2. 系统管理 (`fusionbox system`)

全面的系统运维工具：

**基础功能：**
- **系统信息**：CPU、内存、磁盘、网络、内核、虚拟化等详细信息
- **BBR 管理**：完整 BBR/BBR2/BBRplus/魔改版/Lotserver/xanmod 管理
- **性能测试**：CPU 基准测试、磁盘 I/O 测试、网络测速
- **实时监控**：CPU/内存/磁盘/网络实时监控面板
- **备份恢复**：系统配置一键备份与恢复
- **系统清理**：包缓存、日志、临时文件、Docker 垃圾清理

**系统工具 (`fusionbox system tools`)：**
- **SSH 密钥管理**：添加/生成/删除密钥、禁用密码登录
- **防火墙管理**：UFW/iptables、端口开关、IP 封禁、Fail2Ban
- **定时任务管理**：添加/删除/编辑 cron、自动备份/清理
- **磁盘管理**：分区/格式化/挂载/扩展/大文件扫描/目录大小
- **时区管理**：常用时区一键切换、NTP 时间同步
- **回收站管理**：安全删除/恢复/清空

```bash
fusionbox system info            # 查看系统信息
fusionbox system bbr             # BBR 管理
fusionbox system benchmark       # 运行性能测试
fusionbox system monitor         # 实时系统监控
fusionbox system backup          # 备份系统配置
fusionbox system update          # 更新系统软件包
fusionbox system clean           # 系统清理
fusionbox system tools           # 系统工具子菜单
fusionbox system users           # 用户管理 (list/add/del/sudo/unsudo/passwd)
fusionbox system hardening       # SSH 加固：新建密钥用户并收紧 root 登录
fusionbox system fail2ban        # Fail2Ban 面板 (状态/解封/日志/参数/卸载)
fusionbox system env             # 环境变量管理 (list/show/check/edit)
fusionbox panels docker port-block  # 容器端口封禁 (DOCKER-USER, list/add/del)
fusionbox panels docker uninstall   # Docker 一键卸载 (YES 门禁)
fusionbox workspace work            # 编号工作区 (tmux work1-10, 命令注入)
fusionbox cluster sshout            # SSH 出站收藏 (add/list/rm/connect)
fusionbox market managed install uptime-kuma / ddns-go   # 受管模板扩容
fusionbox web tune                      # 调优档位 (standard/high/restore)
fusionbox web brotli                    # brotli 压缩开关
fusionbox system rsync                  # rsync 同步任务 (add/list/run/cron)
fusionbox update --cron on|off          # 自动更新开关 (每周)
fusionbox market managed install new-api  # LLM API 网关受管模板
fusionbox market managed install lobe-chat/open-webui/n8n/openlist/navidrome  # 五款新模板
fusionbox system file                   # 文件管理器 (ls/cat/cp/mv/del/tar/send)
fusionbox web clone                 # 站点克隆 (目录+配置+可选 WP 库)
fusionbox web uninstall-lnmp        # 卸载 LNMP (YES 门禁+配置备份)
fusionbox system sshkey          # SSH 密钥管理
fusionbox system firewall        # 防火墙管理
fusionbox system cron            # 定时任务管理
fusionbox system disk            # 磁盘管理
fusionbox system timezone        # 时区管理
fusionbox system trash           # 回收站管理
```

### 3. 网络工具 (`fusionbox network`)

实用的网络诊断和测试工具：

- **IP 查询**：IPv4/IPv6 地址、地理位置、ISP 信息
- **流媒体检测**：Netflix、YouTube、ChatGPT、TikTok、Disney+、Bilibili 等
- **网速测试**：下载/上传速度测试
- **DNS 测试**：多 DNS 服务器解析速度对比
- **路由追踪**：Traceroute 路径分析
- **端口检测**：远程端口开放状态检查
- **Ping 测试**：网络连通性测试

```bash
fusionbox network ip             # 查询 IP 地址
fusionbox network streaming      # 流媒体解锁检测
fusionbox network speedtest      # 网速测试
fusionbox network nic            # 网卡管理 (list/info/up/down)
fusionbox network dns            # DNS 解析测试
fusionbox network trace <host>   # 路由追踪
fusionbox network ping <host>    # Ping 测试
fusionbox network port <ip> <端口> # 端口检测
```

### 4. 网站部署 (`fusionbox web`)

一键搭建 Web 运行环境和应用部署：

**基础环境：**
- **LNMP/LAMP**：Nginx/Apache + MySQL/MariaDB + PHP 一键安装
- **网站管理**：快速创建网站、配置 Nginx 虚拟主机
- **SSL 证书**：Certbot 自动申请 Let's Encrypt 证书
- **数据库管理**：MySQL/MariaDB 建库、建用户、权限管理

**LDNMP 应用一键部署 (`fusionbox web deploy`)：**

| 分类 | 应用 |
|------|------|
| 内容管理 | WordPress、Typecho、Halo、Discuz! Q |
| 网盘文件 | 可道云、Nextcloud、Alist |
| 影视媒体 | 苹果CMS、Emby、Jellyfin |
| 论坛社区 | Flarum、LinkStack |
| 工具服务 | Bitwarden、Uptime Kuma、IT-Tools、Memos、Vaultwarden |

**反向代理 (`fusionbox web proxy`)：**
- HTTP 反向代理
- HTTPS 反向代理 (自动 SSL)
- 负载均衡 (多后端)

**Stream L4 代理 (`fusionbox web stream`)：**
- TCP/UDP 端口转发

**站点数据管理 (`fusionbox web sitedata`)：**
- 一键备份/恢复站点数据
- 本地配置定时归档；旧远程全量任务新建入口禁用，现有任务需人工审查

```bash
fusionbox web lnmp               # 安装 LNMP 环境
fusionbox web site               # 创建网站
fusionbox web ssl                # 申请 SSL 证书
fusionbox web deploy             # LDNMP 应用部署
fusionbox web wordpress          # 快速部署 WordPress
fusionbox web proxy              # 反向代理管理
fusionbox web stream             # Stream L4 端口转发
fusionbox web sitedata           # 站点数据管理
```

### 5. 面板与工具 (`fusionbox panels`)

服务器面板和常用工具管理：

**Docker 完整管理 (`fusionbox panels docker`)：**
- Docker 安装入口；完整 Docker 卸载尚未实现
- 容器管理 (启动/停止/重启/删除/日志/终端/资源占用)
- 镜像管理、Docker Compose 项目管理
- 旧容器端口开关已禁用（DNAT 映射缺失）；IPv6 网络配置入口保留
- daemon.json 编辑 (镜像加速/日志限制/DNS)
- 备份/迁移/恢复 (容器/镜像/Compose项目)
- 网络管理/卷管理/垃圾清理

**服务器面板：** 宝塔、Aapanel、X-UI 一键安装

**实用工具：** Aria2、Rclone、FRP 内网穿透、哪吒监控

```bash
fusionbox panels docker          # Docker 完整管理
fusionbox panels bt              # 安装宝塔面板
fusionbox panels frp             # 安装 FRP 内网穿透
fusionbox panels aria2           # 安装 Aria2
fusionbox panels rclone          # 配置 Rclone
fusionbox panels nezha           # 安装哪吒监控
```

### 6. 应用市场 (`fusionbox market`)

80+ 常用软件一键安装，覆盖十大分类：

| 分类 | 应用 |
|------|------|
| 开发工具 | Git、Python3、Node.js、Go、Rust、Redis、Memcached、SQLite |
| 网络工具 | Wget、Curl、Netcat、Socat、MTR、Iperf3、Nmap、Speedtest、FRP、Rclone |
| 系统工具 | Htop、Btop、Glances、Nano、Vim、Unzip、Zip、Fail2Ban、UFW、Certbot、rsync、cron、supervisor、Prometheus |
| Web 服务 | Nginx、Apache、Caddy、PHP、MySQL、PostgreSQL、phpMyAdmin、WordPress |
| 代理工具 | Shadowsocks、V2ray、Xray、HAProxy |
| 媒体工具 | FFmpeg、ImageMagick、ExifTool |
| 容器相关 | Docker CE、Docker Compose、Portainer、cAdvisor |
| 监控工具 | Netdata、Glances、Bashtop、Neofetch、Fastfetch |
| 安全工具 | ClamAV、Rkhunter、Lynis、Unattended-upgrades |
| 实用工具 | Aria2、FileBrowser、Gost、Warp、7zip、Tmux、JQ、yq、Tree、Lsof、Strace、Tcpdump |

```bash
fusionbox market list            # 列出所有应用
fusionbox market search <关键词> # 搜索应用
fusionbox market install <应用>  # 安装应用
fusionbox market remove <应用>   # 移除应用
fusionbox market category        # 按分类浏览
```

### 7. WARP 管理 (`fusionbox warp`)

Cloudflare WARP 管理，用于代理出站流量解锁流媒体：

- **安全模式**：默认使用 Proxy 模式 (SOCKS5 代理)，不会断开 SSH
- **安装/卸载**：一键安装 Cloudflare WARP 客户端
- **IP 检测**：查看原始 IP 和 WARP IP
- **流媒体解锁**：检测 WARP 解锁状态
- **代理配置**：Xray/sing-box 出站配置示例

```bash
fusionbox warp install           # 安装 WARP
fusionbox warp on                # 开启 WARP (Proxy模式)
fusionbox warp off               # 关闭 WARP
fusionbox warp status            # 查看 WARP 状态
fusionbox warp ip                # 查看 IP / 流媒体解锁
fusionbox warp proxy             # 代理配置说明
```

### 8. 后台工作区 (`fusionbox workspace`)

终端会话管理：

- **Screen 管理**：创建/列出/进入/终止 screen 会话
- **Tmux 管理**：创建/列出/进入/终止 tmux 会话

```bash
fusionbox workspace screen       # Screen 管理
fusionbox workspace tmux         # Tmux 管理
fusionbox workspace list         # 列出所有后台会话
```

### 9. 集群控制与工具 (`fusionbox cluster`)

多服务器管理和实用工具：

**集群管理：** 添加/删除节点、批量执行命令、同步文件

**游戏服务端 (`fusionbox cluster game`)：**
- Minecraft Java 版 (Paper)、Minecraft Bedrock 版
- Terraria、Palworld (幻兽帕鲁)

**Oracle Cloud (`fusionbox cluster oracle`)：** 防回收保活脚本、OCI CLI 安装

**k 命令快捷方式 (`fusionbox cluster kcmd`)：**
```bash
k=fusionbox  ks=system  kb=bbr  kn=network
kw=web  kp=proxy  kd=docker  km=market
```

```bash
fusionbox cluster add            # 添加集群节点
fusionbox cluster exec <cmd>     # 批量执行命令
fusionbox cluster sync           # 同步文件到集群
fusionbox cluster game           # 游戏服务端部署
fusionbox cluster oracle         # Oracle Cloud 防回收
fusionbox cluster kcmd           # 配置 k 命令快捷方式
```

---

## 快速安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/motao123/FusionBox/main/install.sh)
```

## 使用方法

```bash
# 主菜单（无参数运行）
fusionbox

# 模块命令
fusionbox proxy       # 代理管理
fusionbox system      # 系统管理
fusionbox network     # 网络工具
fusionbox web         # 网站部署
fusionbox panels      # 面板与工具
fusionbox market      # 应用市场
fusionbox warp        # WARP 管理
fusionbox workspace   # 后台工作区
fusionbox cluster     # 集群控制

# 系统命令
fusionbox status      # 系统状态概览
fusionbox version     # 查看版本
fusionbox update      # 更新 FusionBox
fusionbox uninstall   # 卸载 FusionBox 本体（不动各模块安装的服务）
fusionbox help        # 查看帮助

# 模块帮助
fusionbox <模块> help # 查看模块详细帮助
```

## 系统要求

- **操作系统**：Debian/Ubuntu/CentOS/RHEL/Fedora/Alpine
- **架构**：amd64(x86_64) / arm64(aarch64)
- **权限**：需要 root 权限运行
- **依赖**：bash、curl（安装脚本会自动安装缺失依赖）

## 项目结构

```
FusionBox/
├── fusion.sh                  # 主入口脚本
├── install.sh                 # 一键安装脚本
├── version.txt                # 版本号
├── README.md                  # 项目文档
├── configs/
│   └── config.yaml            # 默认配置文件
├── src/
│   ├── init.sh                # 初始化脚本
│   ├── lib/
│   │   └── common.sh          # 公共函数库
│   ├── i18n/
│   │   ├── en.sh              # 英文语言包
│   │   └── zh_CN.sh           # 中文语言包
│   └── modules/
│       ├── proxy.sh           # 代理管理模块
│       ├── system.sh          # 系统管理模块
│       ├── network.sh         # 网络工具模块
│       ├── web.sh             # 网站部署模块
│       ├── panels.sh          # 面板与工具模块
│       ├── market.sh          # 应用市场模块
│       ├── warp.sh            # WARP 管理模块
│       ├── workspace.sh       # 后台工作区模块
│       └── cluster.sh         # 集群控制模块
├── templates/
│   ├── nginx/
│   └── docker/
└── tests/
    ├── test_basic.sh          # 基础测试
    └── comprehensive_test.sh  # 综合测试
```

## 安全与健壮性（v1.2.0）

v1.2.0 对全项目做了一轮安全审计与真机功能实测（Ubuntu 24.04 全模块 80+ 项），主要改进：

**安全**
- 第三方面板/工具安装源全部改为 HTTPS，远程脚本先落地临时文件再执行（不再 `curl | bash`）
- 代理密码/UUID 改用 CSPRNG 生成（旧版为 `sha256(时间戳)`，熵≈0）；配置文件 `600`、配置目录 `700`
- Aria2 RPC 密钥随机化（旧版硬编码且公网监听）；Minecraft RCON 密码随机化
- 危险操作默认拒绝：`confirm` 空输入不再视为同意；系统恢复/防火墙重置/mkfs 需输入大写 `YES`
- 修复 MySQL 建用户 SQL 注入与密码经进程列表泄露；修复 crontab/iptables/nginx 配置多处注入面
- SSH 加固顺序修正（先放行防火墙再重启 sshd）；禁用密码登录前强制校验密钥存在
- 修复自更新链路（函数遮蔽 + 仓库地址不一致）

**健壮性**
- 安装脚本事务化：下载解压成功后才替换现有安装；补上缺失的离线本地安装分支
- 修复软链接安装后命令不可用的问题（`$0` 路径解析）
- 修复 Web L4 转发在原生 Ubuntu 上必然失败的问题（自动安装 nginx stream 模块，失败回滚主配置）
- 应用部署/代理服务失败不再谎报成功；Docker Compose 部署失败返回错误
- 全部交互菜单在 stdin 关闭（CI/管道）时安全退出，不再死循环
- 新增 `fusionbox uninstall` 完整卸载；版本号统一从 version.txt 读取

## 更新日志

### v1.3.0

- **代理管理集成 [233boy/sing-box](https://github.com/233boy/sing-box)**：`fusionbox proxy install` 选择 sing-box 后端时由该社区脚本接管（安装全自动、自动创建 REALITY 配置，支持 TUIC/Hysteria2 等全协议）
- 新增 `fusionbox proxy sb [参数]`：无参数进入 233boy 交互主菜单，带参数原样透传（`sb add` / `sb url` / `sb del` / `sb status`…）
- 代理状态与总状态页并列显示 233boy sing-box 实例；`proxy uninstall` 支持联动卸载
- 修复：只装 233boy sing-box（无自有后端）时 `proxy status` 误显示"未安装"、`proxy add` 不给正确引导

### v1.2.0

- 全项目安全加固与真机功能实测（详见下方"安全与健壮性"）；新增 `fusionbox uninstall`；CI 增加测试卡发布
