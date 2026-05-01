# FusionBox

> 一站式 Linux 服务器管理工具箱 — 让服务器管理变得简单高效

FusionBox 是一个功能全面的 Linux 服务器管理脚本，集成了系统管理、网络工具、网站部署、Docker 管理、代理配置、应用市场等六大核心模块，覆盖日常运维的绝大部分场景。

## 功能模块

### 1. 代理管理 (`fusionbox proxy`)
多后端通用代理管理，支持一键安装和配置：
- **支持后端**：Xray-core、v2ray-core、sing-box、Clash.Meta
- **支持协议**：VLESS、VMess、Trojan、Hysteria2、TUIC、Shadowsocks、SOCKS
- **传输方式**：TCP、WebSocket、HTTP/2、HTTPUpgrade、QUIC、gRPC
- **TLS 方案**：Reality、自签证书、ACME(Let's Encrypt)
- **附加功能**：BBR 加速、配置导入导出、分享链接/二维码生成

### 2. 系统管理 (`fusionbox system`)
全面的系统运维工具：
- **系统信息**：CPU、内存、磁盘、网络、内核、虚拟化等详细信息
- **BBR 管理**：一键启用/禁用 BBR 拥塞控制算法
- **性能测试**：CPU 基准测试、磁盘 I/O 测试、网络测速
- **实时监控**：CPU/内存/磁盘/网络实时监控面板
- **备份恢复**：系统配置一键备份与恢复
- **系统清理**：包缓存、日志、临时文件、Docker 垃圾清理
- **安全管理**：SSH 加固、UFW 防火墙、Fail2Ban、端口管理
- **Swap 管理**：创建/删除 Swap 交换文件

### 3. 网络工具 (`fusionbox network`)
实用的网络诊断和测试工具：
- **IP 查询**：IPv4/IPv6 地址、地理位置、ISP 信息
- **流媒体检测**：Netflix、YouTube、ChatGPT、TikTok、Disney+、Bilibili 等
- **网速测试**：基于 Cloudflare 的下载/上传速度测试
- **DNS 测试**：多 DNS 服务器解析速度对比
- **路由追踪**：Traceroute / MTR 路径分析
- **端口检测**：远程端口开放状态检查

### 4. 网站部署 (`fusionbox web`)
一键搭建 Web 运行环境：
- **LNMP/LAMP**：Nginx/Apache + MySQL/MariaDB + PHP 一键安装
- **网站管理**：快速创建网站、配置 Nginx 虚拟主机
- **SSL 证书**：Certbot 自动申请 Let's Encrypt 证书
- **性能优化**：Nginx Gzip、Worker 调优、PHP-FPM 参数优化
- **安全防护**：安全响应头、速率限制、WAF 规则
- **数据库管理**：MySQL/MariaDB 建库、建用户、权限管理

### 5. 面板与工具 (`fusionbox panels`)
服务器面板和常用工具管理：
- **Docker**：安装、容器管理、镜像管理、Compose 项目、垃圾清理
- **服务器面板**：宝塔面板、Aapanel 一键安装
- **代理面板**：X-UI 一键安装
- **下载工具**：Aria2 配置管理
- **云存储**：Rclone 配置管理
- **内网穿透**：FRP 服务端/客户端安装
- **监控探针**：哪吒监控 Agent 安装

### 6. 应用市场 (`fusionbox market`)
60+ 常用软件一键安装，覆盖六大分类：
- **开发工具**：Git、Python3、Node.js、Go、Rust、Redis、Docker CE
- **网络工具**：Wget、Curl、Netcat、MTR、Iperf3、Nmap、Speedtest
- **系统工具**：Htop、Btop、Vim、Tmux、Fail2Ban、UFW、Certbot、Prometheus
- **Web 服务**：Nginx、Apache、Caddy、PHP、MySQL、PostgreSQL、WordPress
- **代理工具**：Shadowsocks、V2ray、Xray、HAProxy
- **媒体工具**：FFmpeg、ImageMagick、ExifTool

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

# 系统命令
fusionbox status      # 系统状态概览
fusionbox version     # 查看版本
fusionbox update      # 更新 FusionBox
fusionbox help        # 查看帮助
```

### 常用示例

```bash
# 代理管理
fusionbox proxy install          # 安装代理核心
fusionbox proxy add              # 添加代理配置
fusionbox proxy list             # 列出所有配置
fusionbox proxy status           # 查看代理状态

# 系统管理
fusionbox system info            # 查看系统信息
fusionbox system bbr             # 启用 BBR 加速
fusionbox system benchmark       # 运行性能测试
fusionbox system backup          # 备份系统配置
fusionbox system security        # 安全审计

# 网络工具
fusionbox network ip             # 查询 IP 地址
fusionbox network streaming      # 流媒体解锁检测
fusionbox network speedtest      # 网速测试
fusionbox network dns            # DNS 解析测试

# 网站部署
fusionbox web lnmp               # 安装 LNMP 环境
fusionbox web site               # 创建网站
fusionbox web ssl                # 申请 SSL 证书
fusionbox web optimize           # 优化 Web 性能

# 面板工具
fusionbox panels docker          # Docker 管理
fusionbox panels bt              # 安装宝塔面板
fusionbox panels frp             # 安装 FRP 内网穿透

# 应用市场
fusionbox market list            # 列出所有应用
fusionbox market install nodejs  # 安装 Node.js
fusionbox market search docker   # 搜索应用
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
│   │   └── common.sh          # 公共函数库（颜色、日志、交互、检测）
│   ├── i18n/
│   │   ├── en.sh              # 英文语言包
│   │   └── zh_CN.sh           # 中文语言包
│   └── modules/
│       ├── proxy.sh           # 代理管理模块
│       ├── system.sh          # 系统管理模块
│       ├── network.sh         # 网络工具模块
│       ├── web.sh             # 网站部署模块
│       ├── panels.sh          # 面板与工具模块
│       └── market.sh          # 应用市场模块
├── templates/
│   ├── nginx/
│   │   ├── fusionbox.conf     # Nginx 优化配置模板
│   │   └── proxy-site.conf    # 反向代理站点模板
│   └── docker/
│       ├── nginx-proxy.yml    # Nginx Proxy + Let's Encrypt
│       └── monitoring.yml     # Prometheus + Grafana 监控
└── tests/
    ├── test_basic.sh          # 基础测试
    └── comprehensive_test.sh  # 综合测试
```

## 开源协议

MIT License
