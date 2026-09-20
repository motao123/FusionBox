# FusionBox

![version](https://img.shields.io/badge/version-1.31.0-blue)
![CI](https://github.com/motao123/FusionBox/actions/workflows/release.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-green)
![platform](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20CentOS%20%7C%20Alpine-orange)
![GitHub 主包下载量](https://img.shields.io/endpoint?url=https%3A%2F%2Fmotao123.github.io%2FFusionBox%2Fgenerated%2Fgithub-downloads-shield.json)
![GitHub Stars](https://img.shields.io/github/stars/motao123/FusionBox)

> 一站式 Linux 服务器全能管理工具箱：9 大模块 + 受管应用市场，Bash 为主、受控 Python 辅助，
> 采用暂存、备份、校验和回滚；各功能的本地测试、Linux 隔离验证与外部服务验收范围分别记录。

## 两分钟上手

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/motao123/FusionBox/main/install.sh)
```

安装后运行 `fusionbox` 进入主菜单，或直接使用模块命令。三条代表性命令：

```bash
fusionbox system tools                # 系统工具箱（SSH/防火墙/磁盘/用户管理/加固向导）
fusionbox market managed catalog      # 受管应用市场（10 个模板，一键部署/备份/卸载）
fusionbox network bench               # VPS 评测矩阵（YABS/Bench/回程路由等）
```

## 功能总览

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

### 受管应用市场（`fusionbox market managed`）

数据驱动 Compose 生命周期：digest 固定镜像、localhost 发布、内存/CPU/PID 限额、真实健康检查、
磁盘预检、安装/更新/备份/卸载/重装全流程，逐项真机验证。

| 模板 | 分类 | localhost 端口 | 一句话 |
|------|------|------|------|
| nginx | Web 服务 | 8080 | 静态站点（只读内容卷，支持域名映射） |
| ntfy | 通知服务 | 8081 | 本机通知（SQLite 缓存，无认证） |
| uptime-kuma | 监控面板 | 8082 | 拨测/状态页 |
| ddns-go | DDNS | 8083 | 动态域名解析 |
| new-api | AI 网关 | 8084 | LLM API 网关与计费（首启无认证，先设管理员） |
| lobe-chat | AI 对话 | 8085 | 聚合 ChatGPT/Claude/Gemini/Ollama |
| open-webui | AI 对话 | 8086 | Ollama/OpenAI 自托管前端 |
| n8n | 自动化 | 8087 | 工作流自动化 |
| openlist | 网盘/WebDAV | 8088 | 多存储文件列表（Alist 分支） |
| navidrome | 音乐流媒体 | 8089 | data + music 双卷（music 只读） |

## 最近更新（v1.31.0）

<!-- 发布槽位：下一版本发布时，将本节替换为新版本 3-5 行摘要；被替换的完整版本段落原文写入 docs/CHANGELOG.md 顶部（保持时间倒序）。 -->

- 集群新增单节点 `trust/connect/node-exec/migrate-key`；默认只用密钥，密码登录必须显式选择
- 临时密码通过私有 FIFO 传递给 OpenSSH ASKPASS，不写入普通文件、命令参数或环境变量；会话结束清理
- 公钥迁移先校验匹配私钥，远端追加后再验证纯密钥登录；主机密钥变更一律拒绝
- Linux 临时高端口 OpenSSH 实际验收 11/11 通过，含错误密码、禁止自动降级、CLI 参数、公钥迁移和清理；生产 SSH 未改动

完整版本历史（含全部细节）：[docs/CHANGELOG.md](docs/CHANGELOG.md)

## 命令参考

以下按模块折叠，全部命令与说明逐字保留（展开查看）：

<details>
<summary><strong>1. 代理管理 (`fusionbox proxy`)</strong></summary>

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

</details>

<details>
<summary><strong>2. 系统管理 (`fusionbox system`)</strong></summary>

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

</details>

<details>
<summary><strong>3. 网络工具 (`fusionbox network`)</strong></summary>

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

</details>

<details>
<summary><strong>4. 网站部署 (`fusionbox web`)</strong></summary>

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

</details>

<details>
<summary><strong>5. 面板与工具 (`fusionbox panels`)</strong></summary>

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

</details>

<details>
<summary><strong>6. 应用市场 (`fusionbox market`)</strong></summary>

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

</details>

<details>
<summary><strong>7. WARP 管理 (`fusionbox warp`)</strong></summary>

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

</details>

<details>
<summary><strong>8. 后台工作区 (`fusionbox workspace`)</strong></summary>

终端会话管理：

- **Screen 管理**：创建/列出/进入/终止 screen 会话
- **Tmux 管理**：创建/列出/进入/终止 tmux 会话

```bash
fusionbox workspace screen       # Screen 管理
fusionbox workspace tmux         # Tmux 管理
fusionbox workspace list         # 列出所有后台会话
```

</details>

<details>
<summary><strong>9. 集群控制与工具 (`fusionbox cluster`)</strong></summary>

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

</details>

## 诚实边界

- 测试结论严格区分：**本地 mock / 隔离夹具 / 真机实测 / 未验证**，发布说明随版本附带精确范围
- 待真实凭据/环境才能验证（代码已有、持续标注未验证）：ACME 公网域名签发、Cloudflare API 联动、Telegram 送达、真实多节点集群、OCI Oracle 项（G32-34）
- 受管应用逐项验证范围以各模板说明为准；缺口与待办逐项对账见下方实施跟踪文档
- 匿名使用统计**默认关闭**，首次交互安装可明确选择；只发送随机安装标识、版本、粗粒度系统/架构和固定事件，详见 [隐私说明](docs/privacy.md)
- 统计 Worker 已部署并使用 Cloudflare D1 聚合；匿名统计仍默认关闭，只有用户明确同意后才发送事件，Pages 显示的是去重后的累计匿名装机数
- 商业广告系统、联盟推广及私有 KPanel/.kpb 协议不纳入能力范围

完整对账与待办：[docs/implementation-status.md](docs/implementation-status.md)

## 附录

<details>
<summary><strong>系统要求</strong></summary>

## 系统要求

- **操作系统**：Debian/Ubuntu/CentOS/RHEL/Fedora/Alpine
- **架构**：amd64(x86_64) / arm64(aarch64)
- **权限**：需要 root 权限运行
- **依赖**：bash、curl（安装脚本会自动安装缺失依赖）

</details>

<details>
<summary><strong>项目结构</strong></summary>

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
└── tests/                     # 行为测试（本地与验证服务器使用，不随仓库发布）
```

</details>

## 快速安装与使用方法

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
fusionbox privacy status|on|off|reset-id  # 匿名统计（默认关闭）
fusionbox uninstall   # 卸载 FusionBox 本体（不动各模块安装的服务）
fusionbox help        # 查看帮助

# 模块帮助
fusionbox <模块> help # 查看模块详细帮助
```

## 文档索引

- [实施范围与逐项对账（G 表）](docs/implementation-status.md)
- [匿名统计与隐私说明](docs/privacy.md)
- [声明式应用目录与高权限边界](docs/market-catalog.md)
- [完整变更历史](docs/CHANGELOG.md)
- [项目主页（Pages）](https://motao123.github.io/FusionBox/)

## 鸣谢

感谢 **棉花云** 为项目提供支持：优质网络提供商，[www.88sup.com](https://www.88sup.com)。

## 开源协议

MIT License（见仓库根目录 [LICENSE](LICENSE) 文件）
