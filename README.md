# FusionBox

> 一站式 Linux 服务器全能管理工具箱

FusionBox 是一个功能全面的 Linux 服务器管理脚本，集成了代理管理、系统管理、网络工具、网站部署、Docker 管理、应用市场、WARP 管理、后台工作区、集群控制等九大核心模块，覆盖日常运维的全部场景。

## 功能概览

| 模块 | 命令 | 功能 |
|------|------|------|
| 代理管理 | `fusionbox proxy` | 多后端代理 (Xray/v2ray/sing-box/Clash.Meta) |
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

- **支持后端**：Xray-core、v2ray-core、sing-box、Clash.Meta (mihomo)
- **支持协议**：VLESS、VMess、Trojan、Hysteria2、TUIC、Shadowsocks、SOCKS5
- **传输方式**：TCP、WebSocket、gRPC、HTTPUpgrade
- **配置管理**：自动合并多配置、分享链接生成

```bash
fusionbox proxy install          # 安装代理核心（4选1）
fusionbox proxy add              # 添加代理配置（15种协议）
fusionbox proxy list             # 列出所有配置
fusionbox proxy start            # 启动代理服务
fusionbox proxy stop             # 停止代理服务
fusionbox proxy restart          # 重启代理服务
fusionbox proxy status           # 查看代理状态
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

## 开源协议

MIT License
