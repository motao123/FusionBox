<div align="center">

# FusionBox

**一条命令，接管整台 Linux 服务器**

9 大模块 · 70+ 软件市场 · 受管应用生命周期 · 每一步都可回滚

[![version](https://img.shields.io/badge/version-1.43.2-blue)](https://github.com/motao123/FusionBox/releases)
[![CI](https://github.com/motao123/FusionBox/actions/workflows/release.yml/badge.svg)](https://github.com/motao123/FusionBox/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![platform](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20CentOS%20%7C%20Alpine-orange)](#附录)
[![GitHub 主包下载量](https://img.shields.io/endpoint?url=https%3A%2F%2Fmotao123.github.io%2FFusionBox%2Fgenerated%2Fgithub-downloads-shield.json)](https://github.com/motao123/FusionBox/releases)
[![GitHub Stars](https://img.shields.io/github/stars/motao123/FusionBox)](https://github.com/motao123/FusionBox/stargazers)

[简体中文](README.md) | [English](README.en.md)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/motao123/FusionBox/main/install.sh)
```

<sub>Debian · Ubuntu · CentOS · RHEL · Fedora · Alpine　｜　amd64 / arm64　｜　需要 root　｜　Bash 为主，受控 Python 辅助</sub>

</div>

---

## 目录

| | |
|---|---|
| [为什么用它](#为什么用它) | [受管应用市场](#受管应用市场) |
| [30 秒上手](#30-秒上手) | [真机验证](#真机验证) |
| [能力地图](#能力地图) | [命令参考](#命令参考) |
| [最近更新](#最近更新) | [诚实边界](#诚实边界) |

---

## 为什么用它

一键脚本到处都是，FusionBox 的差别在于**它不假装自己什么都验证过了**：

- **每一步都可回滚。** 改配置先暂存、再备份、写后校验，失败自动回滚——不留下「改了一半」的机器。
- **拼错命令不会把你关进菜单。** 未知子命令直接给出可执行的下一步并以退出码 2 结束；菜单只在交互终端里出现，脚本和 CI 里不会挂死。
- **受管应用是数据驱动的，不是一堆散装 docker run。** 镜像 digest 固定、只发布到 localhost、内存/CPU/PID 限额、真实健康检查、磁盘预检；安装/更新/备份/卸载/重装全流程可测。
- **只声明会被读取的配置。** `config.yaml` 里每个键都能对应到真实读取点，避免「改了开关却没生效」。
- **验证结论分档记录。** 本地 mock / 隔离夹具 / 真机实测 / 未验证，四档分开标注，不做「应该能行」的承诺。

---

## 30 秒上手

```bash
# 1. 安装（自动补齐缺失依赖）
bash <(curl -fsSL https://raw.githubusercontent.com/motao123/FusionBox/main/install.sh)

# 2. 进入主菜单，或直接调用模块命令
fusionbox
```

三条能立刻感受到差异的命令：

```bash
fusionbox system tools                # 系统工具箱（SSH/防火墙/磁盘/用户管理/加固向导）
fusionbox market managed catalog      # 受管应用市场（模板动态读取，一键部署/备份/卸载）
fusionbox network bench               # VPS 评测矩阵（YABS/Bench/回程路由等）
```

帮助体系是只读的，**非 root 也能查**；`fusionbox help system` 与 `fusionbox system help` 输出正文逐字相同：

```bash
fusionbox lang en                     # 切换界面语言（zh_CN / en / auto）
fusionbox help                        # 总帮助：9 大模块 + 全局命令
fusionbox help system                 # 模块详细帮助（含命令清单 + 本机实时状态行）
fusionbox system help                 # 等价写法，正文相同
fusionbox help sys                    # 别名同样可用（p/net/w/tools/m/ws/cl ...）
fusionbox panels docker help          # 子分发也能取帮助
```

> 末行「本机状态」是对宿主机器的实时只读探测（Docker 是否响应、装了哪些组件），探测上限 3 秒；
> 同一台机器两次调用这一行可能合法地不同，帮助正文不会。

---

## 能力地图

| 模块 | 命令 | 一句话 |
|------|------|------|
| 代理管理 | `fusionbox proxy` | 多后端代理（Xray / v2ray / 233boy sing-box / Clash.Meta） |
| 系统管理 | `fusionbox system` | BBR、基准测试、备份、SSH、防火墙、定时任务、磁盘、时区、回收站、救援指引 |
| 网络工具 | `fusionbox network` | IP 查询、流媒体检测、测速、DNS、路由追踪、端口检测 |
| 网站部署 | `fusionbox web` | LNMP、SSL、17 种应用部署、反向代理、L4 转发、站点备份 |
| 面板工具 | `fusionbox panels` | Docker 完整管理、宝塔 / Aapanel / FRP / Aria2 / 哪吒 |
| 应用市场 | `fusionbox market` | 70+ 软件一键安装（10 个分类）+ 受管模板生命周期 |
| WARP 管理 | `fusionbox warp` | Cloudflare WARP 安装、Proxy 模式、流媒体解锁 |
| 后台工作区 | `fusionbox workspace` | 编号工作区 w1–w10（tmux / screen 自动选择） |
| 集群控制 | `fusionbox cluster` | 多机批量管理、游戏服务端、OCI 只读识别、k 命令、中文速查表 |

<details>
<summary><strong>展开：各模块的详细能力</strong></summary>

| 模块 | 详细能力 |
|---|---|
| `proxy` | Xray-core / v2ray-core / **233boy sing-box（推荐）** / Clash.Meta；协议 VLESS（含 Reality）、VMess、Trojan、Hysteria2、TUIC、Shadowsocks、SOCKS5；传输 TCP / WebSocket / gRPC / HTTPUpgrade；多配置自动合并、分享链接生成、按后端校验协议组合 |
| `system` | 系统信息、BBR（含 BBR2 / BBRplus / 魔改 / Lotserver / xanmod）、CPU 与磁盘基准、网络测速、实时监控、备份恢复、系统清理；工具箱含 SSH 密钥、防火墙（UFW/iptables/Fail2Ban）、cron、磁盘分区与挂载、29 城市时区一键切换 + IANA 自定义 + NTP、回收站、文件管理器、rsync 同步任务 |
| `network` | IPv4/IPv6 与 ISP 信息、Netflix/YouTube/ChatGPT/TikTok/Disney+/Bilibili 解锁检测、上下行测速、多 DNS 解析对比、Traceroute、端口探测、网卡管理 |
| `web` | LNMP / LAMP 一键安装、站点创建与 Nginx 虚拟主机、certbot 自动签发（支持本地 Pebble 与 LE staging 两条验证路线）、数据库与用户权限、17 种应用内置部署、反代与负载均衡、Stream L4 转发、站点克隆、站点数据备份、调优档位与 brotli |
| `panels` | Docker 安装与完整管理（容器/镜像/Compose/网络/卷/清理/备份迁移/daemon.json）、容器端口封禁（DOCKER-USER）、宝塔 / Aapanel / X-UI、Aria2 / Rclone / FRP / 哪吒监控 |
| `market` | 70+ 软件、10 个分类；`managed` 子命令为数据驱动 Compose 生命周期（见下节） |
| `warp` | WARP 安装卸载、Proxy 模式（不断 SSH）、IP 与解锁状态检测、出站配置示例 |
| `workspace` | 编号工作区 w1–w10，tmux / screen 自动选择，支持命令注入 |
| `cluster` | 节点增删、批量执行、文件同步、SSH 出站收藏；游戏服务端（Minecraft Java/Bedrock、Terraria、Palworld）；OCI 只读识别与保活状态；`k` 命令快捷方式 |

</details>

---

## 受管应用市场

`fusionbox market managed` 是一套数据驱动的 Compose 生命周期：digest 固定镜像、localhost 发布、
内存/CPU/PID 限额、真实健康检查、磁盘预检，安装 / 更新 / 备份 / 卸载 / 重装全流程**逐项真机验证**。

| 模板 | 分类 | localhost 端口 | 一句话 |
|------|------|------|------|
| nginx | Web 服务 | 8080 | 静态站点（只读内容卷，支持域名映射） |
| ntfy | 通知服务 | 8081 | 本机通知（SQLite 缓存，无认证） |
| uptime-kuma | 监控面板 | 8082 | 拨测 / 状态页 |
| ddns-go | DDNS | 8083 | 动态域名解析 |
| new-api | AI 网关 | 8084 | LLM API 网关与计费（首启无认证，先设管理员） |
| lobe-chat | AI 对话 | 8085 | 聚合 ChatGPT / Claude / Gemini / Ollama |
| open-webui | AI 对话 | 8086 | Ollama / OpenAI 自托管前端 |
| n8n | 自动化 | 8087 | 工作流自动化 |
| openlist | 网盘 / WebDAV | 8088 | 多存储文件列表（Alist 分支） |
| navidrome | 音乐流媒体 | 8089 | data + music 双卷（music 只读） |
| umami | 网站分析 | 8090 | 应用 + PostgreSQL 双服务（db 健康后才启动；支持复用数据重装、按服务换镜像） |

> 模板清单以 `fusionbox market managed catalog` 实际输出为准；声明式目录与高权限边界见 [docs/market-catalog.md](docs/market-catalog.md)。

---

## 真机验证

在一台**全新安装的 Ubuntu 22.04**（Docker CE 29.8.1 + Compose v5.5.1，无任何历史环境）上从零跑通：

| 层 | 项目 | 结果 |
|---|---|---|
| 静态门禁 | `bash tests/run_checks.sh` | **193 / 193**（root 与非 root 双跑都过） |
| 完整套件 | `bash tests/comprehensive_test.sh` | bash **229** 项 + Python **764** 项（34 模块），零失败 |
| 真实自装 | 官方 `install.sh` | Release 资产下载 + SHA256 校验 → 安装 → `fusionbox help` / 模块帮助 / 非 root 拒绝 / 未知子命令退出码 2 全部符合预期 |
| 真机验收 | `tests/acceptance/` 9 个脚本 | **9 / 9 通过**（见下表） |

| 真机验收脚本 | 覆盖 | 计数 |
|---|---|---|
| `container_lifecycle.sh` | 容器完整生命周期 | 17 / 17 |
| `market_app_expansion.sh` | 受管模板安装 → HTTP → 卸载保留卷 → 数据复用重装 | 11 / 11 |
| `market_multicontainer.sh` | 多容器（umami + PostgreSQL）：依赖顺序、换镜像、回滚、数据复用 | 34 / 34 |
| `two_host.sh` | 两主机编排、rsync、灾备传输（第二台主机由容器扮演） | 29 / 29 |
| `openssh_switch.sh` | OpenSSH 候选切换与回滚（容器扮演生产，断言宿主配置未变） | 32 / 32 |
| `acme_pebble.sh` | 本地 Pebble：签发 → 受管 TLS 装配 → 真实续期 → 失败回滚 | 25 / 25 |
| `acme_staging.sh` | Let's Encrypt staging：真实 DNS + 真实 HTTP-01 签发 | 16 / 16 |
| `netopt_sysctl.sh` | 内核网络参数真实改值 + 快照恢复零漂移 | 11 / 11 |
| `cloudflare_guard.sh` | CF 负载自适应开盾 + API 封 IP（最小权限 Token） | 21 / 21 |

> 上表为本地测试资产的验证结论；`tests/` 不入库，完整回归在本地与验证服务器执行。

CI 只做静态检查（见下），两个仓库（GitHub / CNB）同一口径：`syntax`（脚本语法 + Python 产物 + i18n 双语契约审计 + 六处版本一致性，含面向使用者的 `docs/release-notes.md`）→ `release`（仅 tag 触发，产出校验过的发布包）。**测试资产不入库**：`tests/` 只存本地与验证服务器（`.gitignore` 屏蔽 + `.gitattributes` 的 `export-ignore` 双保险，发布包本就不含测试），完整回归在本地与真机执行。

---

## 最近更新

> 当前版本 **v1.43.2** ｜ 完整历史见 [docs/CHANGELOG.md](docs/CHANGELOG.md)

<!-- 发布槽位：下一版本发布时，将本节替换为新版本 3-5 行摘要；被替换的完整版本段落原文写入 docs/CHANGELOG.md 顶部（保持时间倒序）。 -->

- **安全加固（对扫描结果的逐条复核与修复）**：遥测 Worker 的请求体改为带上限的流式读取（分块与 HTTP/2 请求原先会先整体缓冲再判 4096 字节上限）；写入端点不再向浏览器来源开放跨域，通配 CORS 收窄至两个公开只读端点；`version` 字段数值段限长。监控栈模板 `monitoring.yml` 取消内置的 Grafana 管理员口令（缺失时在启动前即失败），面板与 Prometheus 绑定收敛到 127.0.0.1。`web` 模块生成的站点、反向代理与 ACME TLS 配置补齐 `X-Content-Type-Options` / `X-Frame-Options` / `Referrer-Policy` 三类安全响应头
- **默认暴露面收敛**：一键部署中"首个访问者即可获得管理员或完成初始化"的 6 个应用（Halo、KodExplorer、LinkStack、Uptime Kuma、Vaultwarden、Memos）默认只绑定 127.0.0.1，提示语同步给出反向代理与 SSH 隧道两条对外路径；Vaultwarden 默认关闭公开注册
- **新增交付物断言**：`scripts/deploy_exposure_audit.py` 要求交付的 compose 编排中每个已发布端口要么绑定回环地址、要么就地加一行 `# fb-expose` 注释写明理由，口令类环境变量必须为运行时取值。扫描器只报出 1 处，该断言在仓库内定位到 25 处并已全部显式表态
- **缺陷修复**：`web` 模块的苹果 CMS 部署原先无条件以回落编排覆盖主编排，专用镜像 `maccms` 从未生效；现改为仅在 `docker compose up` 失败时回落
- **验证口径**：遥测 Worker 套件 **8/8** 与 `tsc --noEmit` 通过；静态闸门（i18n 3248 键逐键对等、README 双语同步、主页数字派生、端口与凭据棘轮、语法与 Python 产物）本地全绿。**本轮未重跑真机验收**，端口绑定与 nginx 配置变更需在验证服务器确认

---

## 命令参考

以下按模块折叠，全部命令与说明逐字保留（展开查看）：

<details>
<summary><strong>跨模块常用命令速查</strong></summary>

```bash
fusionbox system users           # 用户管理 (list/add/del/sudo/unsudo/passwd)
fusionbox system hardening       # SSH 加固：新建密钥用户并收紧 root 登录
fusionbox system fail2ban        # Fail2Ban 面板 (状态/解封/日志/参数/卸载)
fusionbox system env             # 环境变量管理 (list/show/check/edit)
fusionbox system rsync           # rsync 同步任务 (add/list/run/cron)
fusionbox system file            # 文件管理器 (ls/cat/cp/mv/del/tar/send)
fusionbox panels docker port-block  # 容器端口封禁 (DOCKER-USER, list/add/del)
fusionbox panels docker uninstall   # Docker 一键卸载 (YES 门禁)
fusionbox workspace work            # 编号工作区 (tmux w1-w10, 命令注入)
fusionbox cluster sshout            # SSH 出站收藏 (add/list/rm/connect)
fusionbox market managed install uptime-kuma / ddns-go   # 受管模板扩容
fusionbox market managed install new-api                 # LLM API 网关受管模板
fusionbox market managed install lobe-chat/open-webui/n8n/openlist/navidrome  # 五款新模板
fusionbox web tune                  # 调优档位 (standard/high/restore)
fusionbox web brotli                # brotli 压缩开关
fusionbox web clone                 # 站点克隆 (目录+配置+可选 WP 库)
fusionbox web uninstall-lnmp        # 卸载 LNMP (YES 门禁+配置备份)
fusionbox update --cron on|off      # 自动更新开关 (每周)
```

</details>

<details>
<summary><strong>1. 代理管理 (<code>fusionbox proxy</code>)</strong></summary>

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
<summary><strong>2. 系统管理 (<code>fusionbox system</code>)</strong></summary>

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
- **时区管理**：29 个常用城市分区一键切换（亚洲/欧洲/美洲/大洋洲/非洲）+ 自定义 IANA 时区 + NTP 同步
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

</details>

<details>
<summary><strong>3. 网络工具 (<code>fusionbox network</code>)</strong></summary>

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
<summary><strong>4. 网站部署 (<code>fusionbox web</code>)</strong></summary>

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
<summary><strong>5. 面板与工具 (<code>fusionbox panels</code>)</strong></summary>

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
<summary><strong>6. 应用市场 (<code>fusionbox market</code>)</strong></summary>

70+ 常用软件一键安装，覆盖十大分类（数量以 `fusionbox market list` 实际输出为准）：

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
<summary><strong>7. WARP 管理 (<code>fusionbox warp</code>)</strong></summary>

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
<summary><strong>8. 后台工作区 (<code>fusionbox workspace</code>)</strong></summary>

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
<summary><strong>9. 集群控制与工具 (<code>fusionbox cluster</code>)</strong></summary>

多服务器管理和实用工具：

**集群管理：** 添加/删除节点、批量执行命令、同步文件

**游戏服务端 (`fusionbox cluster game`)：**
- Minecraft Java 版 (Paper)、Minecraft Bedrock 版
- Terraria、Palworld (幻兽帕鲁)

**Oracle Cloud (`fusionbox cluster oracle`)：** OCI 只读识别、受管/旧保活状态检查；lookbusy 负载安装待固定镜像与隔离验收

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
fusionbox cluster oracle detect  # OCI 只读识别
fusionbox cluster oracle status  # 受管/旧保活状态
fusionbox cluster kcmd           # 配置 k 命令快捷方式
```

</details>

---

## 诚实边界

- 测试结论严格区分四档：**本地 mock / 隔离夹具 / 真机实测 / 未验证**，发布说明随版本附带精确范围
- 当前真机口径（v1.43.0，Ubuntu 22.04 全新环境）：快速闸门 **193/193**（root 与非 root 双跑）、完整套件 bash **229** 项 + Python **764** 项（34 模块）零失败、9 个真机验收脚本全部通过
- **已收口的凭据依赖项**：Cloudflare 联动（v1.41.0，最小权限 Token 真机验证）、ACME 签发两条路线（v1.39.0，本地 Pebble + Let's Encrypt staging 真实 HTTP-01）
- **仍需真实条件才能验证**：Telegram 送达（需要 bot token）、真实 OCI 实例（Oracle 三件套）、真机关机分支；OCI G32 仅完成只读识别，lookbusy 负载、oci-helper（G33）与 root/IPv6（G34）尚未实现
- 受管应用逐项验证范围以各模板说明为准；缺口与待办逐项对账见实施跟踪文档
- 匿名使用统计**默认关闭**，首次交互安装可明确选择；只发送随机安装标识、版本、粗粒度系统/架构和固定事件，详见 [隐私说明](docs/privacy.md)
- 统计 Worker 已部署并使用 Cloudflare D1 聚合；Pages 显示的是去重后的累计匿名装机数
- **双语口径**：核心层与 9 个模块层均已走语言包（zh_CN / en 各 3248 键，逐键对等），英文模式零中文；
  全仓未抽取文案 0 条（由 scripts/i18n_audit.py 逐键强制），约定见 [docs/i18n.md](docs/i18n.md)
- 第三方工具（docker/certbot/apt）的原始输出与品牌专有名词不做翻译
- 商业广告系统、联盟推广及私有 KPanel/.kpb 协议不纳入能力范围

完整对账与待办：[docs/implementation-status.md](docs/implementation-status.md)；**未完成项的具体做法与验收口径**：[docs/roadmap.md](docs/roadmap.md)

---

## 附录

<details>
<summary><strong>系统要求</strong></summary>

- **操作系统**：Debian / Ubuntu / CentOS / RHEL / Fedora / Alpine
- **架构**：amd64 (x86_64) / arm64 (aarch64)
- **权限**：需要 root 权限运行
- **依赖**：bash、curl（安装脚本会自动补齐缺失依赖；受管应用市场与 Compose 备份/迁移需要 Docker + `docker compose` v2）

</details>

<details>
<summary><strong>使用方法与退出码</strong></summary>

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
fusionbox lang zh_CN|en|auto             # 界面语言（可随时切换，非 root 可查看）
fusionbox uninstall   # 卸载 FusionBox 本体（不动各模块安装的服务）
```

未知命令的退出码约定：

```bash
fusionbox network bogus
# [ERROR] 未知子命令: bogus
# [INFO]  用法: fusionbox network help      查看该模块全部命令
# [INFO]        fusionbox help network      查看该模块详细帮助
# [INFO]        fusionbox network           进入交互菜单
# 退出码 2（成功为 0，未知模块为 1）
```

设计意图：拼错命令时给出可执行的下一步，并且**不进入交互菜单**——菜单在脚本/CI 里会阻塞。

</details>

<details>
<summary><strong>配置文件</strong></summary>

`~/.config/fusionbox/config.yaml` 只声明**会被实际读取**的键，避免「改了开关却没生效」：

| 键 | 作用 |
|---|---|
| `general.lang` | 输出语言 `auto` / `zh_CN` / `en` |
| `general.stats` | 匿名统计（默认关闭，等同 `fusionbox privacy`） |
| `general.color` | `false` 关闭全部 ANSI 颜色（适合日志重定向） |
| `system.monitor_interval` | `fusionbox system monitor` 刷新间隔（秒） |
| `system.backup_dir` | `fusionbox system backup\|restore` 默认目录 |
| `network.speedtest_server` | 测速节点：`auto` 或数值节点 ID |

自动更新等不在此文件的设置，请在文件末尾的说明中找到它们的真实归属。

</details>

<details>
<summary><strong>项目结构</strong></summary>

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
├── .cnb.yml                   # CNB 流水线：语法/静态检查 + Tag 发布打包
└── .github/workflows/         # GitHub Actions：发布与统计（install.sh 默认安装源）

> 回归检查与行为测试（`tests/`，含 9 个真机验收脚本）**不随仓库发布**：只存本地与验证服务器，
> 完整回归在本地与真机执行；发布包口径不变（`export-ignore` 不进 tar.gz）。
```

</details>

<details>
<summary><strong>文档索引</strong></summary>

> 除标注 English 者外，下列文档目前只提供中文。

- [实施范围与逐项对账（G 表）](docs/implementation-status.md)
- [未完成项与可执行方案](docs/roadmap.md)
- [匿名统计与隐私说明](docs/privacy.md)
- [声明式应用目录与高权限边界](docs/market-catalog.md)（English）
- [界面语言与本地化约定](docs/i18n.md)
- [完整变更历史](docs/CHANGELOG.md)
- [项目主页（Pages）](https://motao123.github.io/FusionBox/)

</details>

---

## 鸣谢

感谢 **棉花云** 为项目提供支持：优质网络提供商，[www.88sup.com](https://www.88sup.com)。

## 开源协议

MIT License（见仓库根目录 [LICENSE](LICENSE) 文件）
