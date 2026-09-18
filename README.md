# FusionBox

> 一站式 Linux 服务器全能管理工具箱

FusionBox 是一个功能全面的 Linux 服务器管理脚本，集成了代理管理、系统管理、网络工具、网站部署、Docker 管理、应用市场、WARP 管理、后台工作区、集群控制等九大核心模块，覆盖常见日常运维场景。

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
- 定时远程备份 (Rclone/SCP/rsync)

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
- 安装/卸载 Docker
- 容器管理 (启动/停止/重启/删除/日志/终端/资源占用)
- 镜像管理、Docker Compose 项目管理
- 容器端口访问控制、IPv6 网络配置
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

## 开源协议

MIT License
