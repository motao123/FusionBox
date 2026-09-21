# 未完成项与可执行方案

> 基线：`3ac2ada` / v1.36.4（2026-09-21 编写，随 v1.36.5 首次交付、v1.36.6 继续维护）。来源：`docs/implementation-status.md` 逐项状态 + 对本仓库代码的复核。
> 复核范围：`src/lib/*`、`src/modules/*`、`fusion.sh`、`tests/*`。凡「已实现/未实现」的判断都附了代码位置；凡复核后发现文档与代码不符的，单列在第 7 节。

本文回答两个问题：**还差什么**，以及**每一项具体怎么做完、怎么算做完**。区分「没写代码」和「写了但无法证明」——这两类的处理成本差一个数量级。

---

## 0. 状态口径

| 分类 | 含义 | 处理方式 |
|---|---|---|
| **A 未实现** | 代码路径不存在，或只有「拒绝执行」的空壳 | 需要设计 + 实现 + 隔离验证 |
| **B 环境受限** | 代码已写且单测通过，但从未在真实条件下跑过 | 成本主要是**造出条件**，不是写代码 |
| **C 明确不做** | 设计决策，与安全模型或职责边界冲突 | 保留判定依据，不再计入欠账 |
| **D 有边界** | 核心已实现，明确划定了不做的那部分 | 按需扩容，不是缺陷 |

判断「做完」的默认口径（沿用本仓库既有习惯）：真实命令跑通 + 前后状态可比对 + 失败路径有回滚 + 失败时不产生半成品。**只读入口和「拒绝执行」不算能力完成**。

---

## 1. 速览

| 分类 | 项数 | 说明 |
|---|---|---|
| A 未实现 | 7 组 | 其中 3 组（Oracle 三件套）依赖当前没有的真实 OCI 实例 |
| B 环境受限 | 6 项 | **5 项的条件现在就能在本机+验证服务器造出来**（见第 3 节），1 项需要你提供凭据 |
| C 明确不做 | 5 项 | 不再变更 |
| D 有边界 | 22 项 | 见第 5 节清单 |

**结论先说**：72 项候选能力里，真正缺实现的只有 7 组；剩下的大头是「条件没造出来」。而其中 5 项的条件能在**不花钱、不新增机器**的前提下造出来——这是当前投入产出最高的方向。

---

## 2. A 类：未实现

### A1 多容器应用（Dify / RAGFlow / JumpServer 等）— G51 G52 G53 G54 G55 G56

**现状（已核实，且与文档描述不同）**

多服务**不是缺框架**，框架已经在：

- `src/lib/market_catalog.py:113` `parse()` 支持声明式目录，`_service()`（第 73 行）定义服务字段白名单
- `src/lib/market_apps.py:186` `manifest_document()` 已能生成多服务 Compose（每服务独立 image/ports/volumes/健康检查）
- `src/lib/market_apps.py:289` `manifest_resources()` 已按「项目+服务」逐个校验容器
- `src/lib/market_catalog.py:158` `high_privilege` 会按声明能力自动推导并强制一致

**真正的缺口**：内置 `CATALOG`（`market_apps.py:23`）10 个应用**全部是单服务 legacy 形态**，多服务路径没有任何应用在用；且服务字段白名单缺真实多容器应用必需的能力。

| 缺口 | 位置 | 影响的应用 |
|---|---|---|
| 无 `depends_on`（启动顺序） | `market_catalog.py:74` keys 元组 | Dify、RAGFlow、RocketChat 等全部 |
| 无 `shm_size` | 同上 | Elasticsearch / 浏览器类 |
| 无 `sysctls` | 同上 | ES（`vm.max_map_count`） |
| 无 `tmpfs` / `read_only` 文件系统 | 同上 | 安全加固类 |
| 无 `entrypoint` | 同上 | 覆盖镜像默认入口的应用 |
| 多服务不允许 per-image 覆写 | `market_apps.py:231` 直接 `raise` | 升级 / 镜像替换路径 |

注意：放开字段时必须同步收紧校验（`_service` 的既有风格是白名单 + 类型/取值正则），否则声明式目录会变成任意 Compose 注入通道。

**可执行步骤**

1. 在 `market_catalog._service` 的 keys/required 中新增 `depends_on`、`shm_size`、`sysctls`、`tmpfs`、`read_only`、`entrypoint`，并为每项写正则/类型约束（`depends_on` 只能引用同一 app 内已声明的服务 id；`shm_size` 复用 `memory` 的 `[1-9][0-9]*m` 形式）。
2. 在 `manifest_document()` 中把新字段落到 Compose：`depends_on` 生成 `{service: {condition: service_healthy}}`，仅当被依赖服务声明了 `health`（否则 `service_started`）。
3. `manifest_resources()` 增加对新字段的反向校验（容器实际参数与声明一致才算健康）。
4. 多服务 per-image 覆写：改为「按服务 id 定位镜像并只替换该服务的 image 字段」，替换前校验新镜像摘要格式，保留原 Compose 以便回滚。
5. `tests/test_market_catalog.py` / `tests/test_market_apps.py` 增加：新字段的合法/非法取值矩阵、跨 app 引用拒绝、依赖未声明服务拒绝、多服务 per-image 覆写往返。
6. `tests/run_checks.sh` 增加一节断言：白名单字段与 `manifest_document` 生成字段一一对应（防止「声明了但不落地」这类债复发）。
7. 首批应用：**Dify**（web + api + worker + postgres + redis + weaviate）、**RAGFlow**（需 ES → 直接验证 `shm_size`/`sysctls` 路径）。

**验收**：验证服务器上真实部署 Dify → 所有容器 healthy → `market managed status` 显示一致 → 升级一次 → 卸载保留数据 → 复用数据重装 → 备份/恢复往返。全程比对 `docker ps` 与声明的一致性。

**风险 / 资源**：Dify 约 6 容器、峰值内存 2–3 GB；验证服务器 7.9 GB 内存、23 GB 空闲磁盘可容，但镜像总量较大（需要预拉并记录摘要）。国内拉取失败要有明确报错，不做静默降级。

---

### A2 OpenSSH 候选版本切换与回滚 — G20

**现状（比文档描述的更接近完成）**

`system ssh-candidate` 已实现 6 个动作（`src/modules/system.sh:1494` → `src/lib/openssh_candidate.py`）：

| 动作 | 实现 | 说明 |
|---|---|---|
| `fetch` | `_download_sources()` | 下载签名源码 |
| `verify` | `verify_sources()` / `_gpg_verify()` | **GPG 签名校验** |
| `build` | `_build()` / `_safe_extract()` | 解包（拒绝链接）+ 编译到独立 prefix |
| `test` | `_candidate_test()` / `_wait_for_port()` | 在**独立高端口**拉起候选 sshd 并真实回连 |
| `status` / `clean` | `_status()` / `_clean()` | 状态与清理 |

**缺口就两个动作**：`switch` 和 `rollback`。`main()` 的 `choices` 里没有它们。

**可执行步骤**

1. 新增 `switch`，门禁必须全部满足才允许替换生产 `sshd`：
   - 存在已验证的 `verify` 记录，且源码摘要与当前候选一致
   - `test` 已通过（有回连成功记录，且未过期）
   - `sshd -t` 校验当前生产配置通过
   - **登录预检**：用现有会话之外的第二条连接，按当前有效策略做一次真实登录（密钥或密码，取决于 `sshd -T`），失败即中止
   - 记录原二进制路径、大小、SHA-256、并保留可执行副本到状态目录
2. 替换采用「先写临时文件 → `sshd -t` → 原子 rename → 保留旧文件」，**不重启正在服务的 sshd**，只对下一个连接生效。
3. 替换后开第二条连接复验；失败自动 `rollback`（还原旧二进制）并输出明确原因。
4. 新增 `rollback`：还原到最近一次记录的原版；无记录时明确拒绝而非猜测。
5. `status` 增加「当前 sshd 版本 / 是否为受管候选 / 上次切换时间与结果」。
6. 测试：`tests/test_openssh_candidate.py` 增加开关门禁矩阵（缺 verify、缺 test、配置非法、第二连接失败）、回滚往返、以及**不允许在非 POSIX/非 root 环境执行**。

**验收**：验证服务器上真实执行一次 `switch` → 新连接使用新版本、现有会话不断开 → `rollback` → 版本回退且配置校验和不变。

**风险（最高的一项）**：改 sshd 有自锁风险。前置条件：**必须有带外通道**（VPS 控制台的 VNC / 救援模式），否则不执行切换。这一点应写进 `switch` 的首次使用提示里。

---

### A3 一键 DD 重装

**现状**：仓库内无任何实现（`grep` 无 DD / reinstall 相关代码路径）。

**判断**：这是**唯一近乎不可逆**的能力——写盘失败即失联，且失败时无法用本工具自救。建议排在最后，且只做「受约束的版本」：

1. 镜像白名单 + 摘要固定 + 只接受 https
2. 分区布局与启动模式（BIOS/UEFI）显式确认，不允许猜测
3. 网络参数（IP/网关/DNS/SSH 端口）在重启前写入并**回读校验**
4. 重启前输出「带外恢复步骤」并要求显式确认
5. 重启后由外部（另一台机器）探测回连，工具本身无法自证

**当前建议**：不实现。在此之前保持「明确拒绝 + 指向带外恢复」，比给一个可能砖机的按钮更负责。

---

### A4 Docker 跨主机迁移 — G29

**现状（已核实的实际边界）**

| 环节 | 状态 |
|---|---|
| 本机打包/校验/还原/回滚 | 完整：`src/lib/docker_migration.py`（bundle `create`/`check`/`before`/`apply`/`undo`/`again`） |
| 传输到远端存储 | 已有：`src/lib/archive_transfer.py --kind docker-v1`（`cluster archive push/pull/status`） |
| **远端编排** | **缺**：没有「远端 preflight → 传输 → 远端 apply → 远端健康 → 失败回滚」的串接 |
| 两主机实测 | 无 |

**可执行步骤**

1. 新增编排入口（建议 `panels docker-migration remote` 子命令），复用既有 `run_ssh`（`cluster_session.py:229`）而不是新写 SSH：
   - 目标机 preflight：Docker 版本/存储驱动、目标盘剩余空间与 inode、端口占用、同名项目与卷冲突
   - 传输：复用 `--kind docker-v1` 的 push 与目标侧 pull（含摘要校验）
   - 目标机 `apply`：调用目标机上的同一份 `docker_migration.py apply`（要求目标机已安装 FusionBox）
   - 健康检查：复用既有声明式健康判定，超时即回滚
2. 前置依赖：**B3 两主机夹具**（见第 3 节，Docker 里造第二台主机即可，不用买机器）。
3. `tests/test_docker_migration.py` 增加编排层的失败矩阵（preflight 失败、传输中断、目标机 apply 失败 → 源侧与目标侧状态断言）。

**验收**：夹具上跑通一次「源机打包 → 目标机恢复 → 服务健康」，并验证中断场景不留半成品。

---

### A5 Oracle 三件套 — G32 G33 G34

**现状**：`src/lib/oracle_tools.py` 只做**识别与状态**（`detect_environment()`、`_metadata_evidence()`、`_legacy_status()`、`_managed_status()`），G32 的安装入口明确拒绝执行。

**缺口**

| 项 | 缺口 |
|---|---|
| G32 lookbusy | 固定镜像 digest、CPU/内存比例策略、负载生命周期（开机自启/停止/清理）、与既有受管模型的归属登记 |
| G33 oci-helper | 无实现 |
| G34 root 密码登录切换 + IPv6 恢复 | 无实现 |

**可执行步骤（拆成能做的和不能做的）**

- **现在能做**：把 Oracle 相关代码收进 `src/lib/` 的既有受管模型（归属登记 + 摘要固定 + 单元测试），安装动作继续拒绝。这能在没有真实实例时把「拒绝的姿势」做扎实。
- **需要真实实例才能做**：负载真实占用比例、开机自启与生命周期、oci-helper 的实际行为、IPv6 恢复。**这三项在没有真实 OCI 实例前不声称完成。**

**依赖**：一个 Oracle Cloud 实例（或明确的「不做」决定）。

---

### A6 协作 / 远程安全类应用 — G55

十个应用：RustDesk、WireGuard、Webtop、Nexterm、JumpServer、雷池、ONLYOFFICE、RocketChat、VoceChat、2FAuth。

**按依赖分档**（避免一次性铺开）：

| 档 | 应用 | 前置 |
|---|---|---|
| 单容器、无外部 DB | Nexterm、2FAuth、WireGuard（需 `NET_ADMIN` → 走 `high_privilege` 路径）、雷池 | 只需加目录条目 |
| 单容器 + 轻量内嵌存储 | VoceChat、Webtop | 同上 + 数据卷 |
| 多容器（自带 DB/Redis） | JumpServer、RocketChat、ONLYOFFICE、RustDesk（服务端含 DB） | **依赖 A1** |

**步骤**：先做第一、二档（纯目录条目 + 真机起停验证），第三档等 A1 落地后按同样的验收口径补。

---

### A7 hermes / deepseek harness 管理器 — G69

**现状**：无实现，且**没有设计文档**。

**建议**：这一项先出设计，不先写代码。需要明确的：进程模型（systemd unit vs 容器）、WebUI 与域名 + BasicAuth 的复用方式（可复用 G59 的 HTTP 映射能力）、模型 API 凭据的存放与权限、升级与日志、卸载时的数据保留策略。

**依赖**：真实模型 API 凭据（否则只能验证到「启动并监听」）。

---

## 3. B 类：环境受限 —— 关键是「怎么把条件造出来」

以下是**已实测**的验证环境能力，后面每一项方案都建立在这上面：

| 能力 | 实测值 |
|---|---|
| 系统 / 权限 | Ubuntu 24.04.5，root |
| Docker | **29.8.1，服务 active，已有 13 个镜像** |
| 内存 / 磁盘 | 7.9 GB / 23 GB 空闲（`/`） |
| Nginx | 1.24.0（Ubuntu） |
| certbot | **未安装**（ACME 验证需先装） |
| Python | 3.12.3 |
| 公网 IP | 156.239.52.100（**无绑定域名**） |

### B1 真实容器生命周期 → 现在就能做

之前这条被记为「受环境限制」，但服务器上 Docker 一直可用。缺的不是条件，是**没做过的真机流程**。

**步骤**：镜像预拉 + 摘要记录 → 真实部署（不止 healthy，还要真实 HTTP 请求）→ 停止/启动 → 升级（含摘要变化）→ 卸载保留数据 → 复用数据重装 → 备份/恢复往返。产出放进 `tests/acceptance/`（真机脚本，不进 CI）。

**注意**：这类脚本不应进 CI（CI 无 Docker/网络契约见 `tests/run_checks.sh`），但应可一键重放。

### B2 真实 ACME → 两条路都可立即执行

| 路线 | 做法 | 覆盖范围 | 限制 |
|---|---|---|---|
| **A：协议级（无外部依赖）** | Docker 跑 Pebble + challtestsrv，certbot 指向本地目录 URL（`--server https://127.0.0.1:14000/dir`），challtestsrv 把测试域名解析到本机 | 签发 / 续期 / webroot 与 standalone 回退 / 失败回滚 / SAN / 有效期 | 不是真实 CA，证书链非公共信任 |
| **B：真实 CA + 真实公网 DNS** | 用含 IP 的公共域名（`sslip.io` / `nip.io` 形式，如 `156.239.52.100.sslip.io`）指向验证服务器，向 **Let's Encrypt staging** 签发 | 真实 ACME 客户端行为、真实 HTTP-01 校验、速率限制宽松 | 需要验证服务器入站 80/443 对公网开放；证书由 staging 签发，不受浏览器信任 |

**建议先 A 后 B**：A 用来把逻辑跑扎实（快、可重复、无需入站），B 用来证明与真实 CA 互通。

**验收**：证书 SAN/有效期/密钥校验、nginx 配置校验后重载、续期触发、失败时旧证书与配置不变。

### B3 两主机场景 — 用 Docker 造第二台主机（不用买机器）

**依据**：`cluster_session.py:229` 的 `run_ssh()` 只用标准 `ssh -F /dev/null`、严格 `known_hosts`、密钥或密码认证，远端只要求能执行 bash / python3。**没有对「远端必须是物理机」的任何依赖**。因此一个跑 `openssh-server` 的容器就是合格的第二台主机。

**步骤**

1. `docker run -d --name fb-node2 -p 2222:22`（Ubuntu + openssh-server，含 python3）
2. 生成**专用**临时密钥对，只授权给该容器；不复用生产密钥
3. `cluster add` 指向 `127.0.0.1:2222`，验证 `trust/connect` 与严格 known_hosts 行为
4. 依次跑通：`cluster archive push/pull --kind docker-v1`、`cluster task` 批量、`cluster exec`
5. 容器销毁即回收，无持久副作用

**一次夹具覆盖 5 项**：G15（SSH 出站真实目标）、G16（rsync 远端）、G29（A4 的编排验证）、G61（灾备传输）、G63（批量任务真实执行）。

### B4 TG / Cloudflare 真实凭据 — 唯一需要你提供的东西

| 需要 | 用途 | 建议 |
|---|---|---|
| Telegram bot token + chat id | 验证 `system notify` 与 `system login-alert` 的真实发送 | 专用测试 bot，不要用生产群 |
| Cloudflare API Token | 验证 G44 的 `under_attack` 与封 IP | **权限最小化**：只给测试 Zone 的对应权限 |

在拿到凭据之前，正确做法是**把「凭据缺失」做成显式拒绝 + 明确提示**，而不是让 mock 通过后声称已验证。

### B5 其余受限项

| 项 | 缺的条件 | 方案 |
|---|---|---|
| G13 流量阈值 `shutdown` 分支 | 不能真机关机 | 用一次性 VPS 或 `systemd-nspawn` 验证；在此之前维持「mock 覆盖」的诚实标注 |
| G18 / G67 内核与网络参数 | 担心影响验证服务器 | 验证服务器是专用环境，可真实执行一次改值 + 快照恢复，并记录 `sysctl` 前后 diff |
| G04 PAM 限策 / SELinux | 需要隔离环境 | 容器或一次性 VPS；当前标注为未验证是准确的 |

---

## 4. C 类：明确不做（保留判定依据）

| 项 | 判定 | 依据 |
|---|---|---|
| KPanel / `.kpb` 私有协议 | 不纳入能力范围 | 闭源私有协议，无法做一致性保证 |
| 商业广告 / 联盟推广 | 不纳入 | 与工具定位冲突 |
| G24 自动补 Swap | 不自动实施 | 不替用户决定内存策略；低内存只提示 |
| Dockge 等需 Docker socket 的面板 | 不实现 | 把宿主 Docker 控制面交给容器，与「受管 localhost + 能力收敛」模型直接冲突 |
| Syncthing（P2P UDP） | 不收录 | 与受管 `localhost` 绑定模型冲突 |
| 受管模板「追数量」 | 不做 | 只收「少而可验证」的模板 |

---

## 5. D 类：有边界（核心已实现，按需扩容）

| 项 | 已实现的部分 | 明确不做的部分 / 下一步 |
|---|---|---|
| G01 DNS | 普通文件 DNS 配置；受管链接拒绝覆盖 | 按国家写 `resolv.conf` + `chattr +i` 防篡改（当前拒绝接管受管文件，是安全取舍） |
| G02 换源 | APT / YUM 分支 | 覆盖其余发行版 |
| G06 Swap | 自定义大小 | 自动清理未知旧 swap |
| G08 日志 | `system log` 入口 | 未实测所有日志后端（journalctl / syslog / 文件） |
| G17 备份 | 8 个 scope + 归属登记 + 完整性校验 + 显式保留/恢复 + **旧归档读取**（`archive.py:159` `legacy_map`） | 剩余边界需复核（见第 7 节） |
| G23 评测矩阵 | 数据表驱动 + 确认执行 | 不声称上游脚本全部可用 |
| G25 Docker 换源 | JSON 合并与回滚 | 源可用性需现场验证（失效预设已移除） |
| G28 Compose 备份 | 本机单文件 Compose + local named volumes | 数据库/外部卷/跨项目迁移 |
| G35 证书续期 | `web ssl auto/renew` + 已有 timer/cron 检查 | 真实 ACME（见 B2） |
| G36 证书状态表 | `web ssl status` | 真实域名证书 |
| G38 删站点 | 目录/conf/证书清理 + 配置备份 | 不自动删数据库（正确取舍） |
| G40 多域名 | 复制 conf + 替换 server_name + 校验回滚 | 证书仍需域名条件 |
| G43 防 CC | 宿主 Nginx 4xx fail2ban | DOCKER-USER chain + 真实流量测试 |
| G51/G52/G53/G54/G56 应用扩容 | 10 个受管模板（真机验证） | 见 A1 / A6 |
| G57 市场机制 | 登记/锁/端口探测/归属/健康/更新回滚 | 旧安装迁移 |
| G58 访问模式持久化 | localhost-direct / HTTP 映射登记与持久化 | 无 `domain_only` 防火墙隔离 |
| G59 一键域名 | 自有宿主 HTTP / 自备 PEM HTTPS + 校验回滚 | 真实 ACME（见 B2） |
| G60 磁盘预检 | 按应用数据驱动最低空间 + Docker 数据盘 | 非配额；NAS 路径与任意应用体积估算 |
| G61 全量备份 | 现有 scope 安全归档 + SSH push/pull/status；`home` 已是可选敏感 scope | 应用重建与两主机灾备（见 B3） |
| G63 集群批量 | `cluster task` 沿用密钥连接 | 生产节点批量执行（见 B3） |
| G65 游戏服管理 | 12 项 + 真实隔离卷往返 | 定时备份 / 游戏内容兼容矩阵 |
| G67 网络优化 | `system netopt` + 快照恢复断言 | 未改真实网络参数（见 B5） |
| G12 / G44 通知与 CF | 见第 7 节（文档陈述需修正） | 真实凭据（见 B4） |

---

## 6. 建议批次

按「一批做完即可独立验证并发布」划分。

### 批次 1（P0，不依赖任何新条件）→ 预计产出 v1.37.0

多容器应用框架（A1）+ OpenSSH `switch`/`rollback`（A2）+ 文档过期陈述修正（第 7 节）。

- 为什么最先：A1 一个改动解锁 G51/G52/G53/G54/G55/G56 六组应用；A2 只差两个动作；两者都**不依赖真实 OCI、真实 ACME、第二台机器**
- DoD：新增字段的合法/非法矩阵测试 + `run_checks.sh` 字段闭环断言 + 验证服务器上真实部署 Dify 全流程 + OpenSSH 真机切换并回滚

### 批次 2（P1，Docker 夹具）→ 覆盖 5 项

B1 真实容器生命周期 + B3 两主机夹具 + A4 跨主机迁移编排。

- DoD：`tests/acceptance/` 真机脚本可一键重放；跨主机迁移成功 + 中断不留半成品

### 批次 3（P2，ACME 两路）

B2 路线 A（Pebble）+ 路线 B（staging + `sslip.io`）→ 把 G35/G36/G59 从「部分实现」推到完成。

- DoD：签发/续期/回滚全过，且证书与配置在失败时保持不变

### 批次 4（P3）

A6 第一、二档应用（单容器）→ 再 A6 第三档 → A5（需 OCI 实例）→ A7（需设计）→ A3（建议不做）

---

## 7. 复核发现的文档与代码不符（建议随批次 1 修正）

复核时发现 `docs/implementation-status.md` 有四处陈述已经过期。这类「文档说了、代码没有 / 代码有了、文档说没有」正是本项目一直在清理的债，列在这里以免继续被当成未完成项管理。

| 位置 | 当前陈述 | 代码事实 | 建议 |
|---|---|---|---|
| G12 第 179 行 | 「…TG 仅 mock，**SSH 登录通知未实现**」 | **已实现**：`system login-alert install\|status\|test\|uninstall`（`src/modules/system.sh:3772` → `src/lib/system_safety.py:641` `_login_script()`），PAM `open_session` 钩子 + TG 发送 + 受管状态校验 | 改为「TG 发送未用真实凭据验证」，删掉「未实现」 |
| G17 第 184 行 | 「…**旧归档迁移仍后续**」 | 旧归档读取已实现（`src/lib/archive.py:159-183` 的 `legacy_map`） | 复核后改写为实际剩余边界 |
| G61 第 228 行 | 「…**全量 /home**、应用重建与两主机灾备仍后续」 | `home` 已是可选敏感 scope（`archive.py:17` `SCOPES['home']`，`system.sh:942` 提示「可选敏感范围: ssh cron usr-local home」），需逐项确认 | 删掉「全量 /home 仍后续」，保留「应用重建与两主机灾备」 |
| G62 第 229 行 | 「…**SSH 常驻 attach 模式后续**」 | `workspace screen\|tmux\|work` 均有 `attach`（`src/modules/workspace.sh:35/107/233`） | 明确「SSH 常驻」的具体语义后再定，当前表述含混 |

第 4 行（G62）属于表述含混而非事实错误，但同样应当收敛成可判定的陈述。

---

## 8. 附录：可复用资产

| 资产 | 位置 | 用途 |
|---|---|---|
| 真机验收脚本 | `tests/acceptance/`（批次 2 建立） | 需要 Docker/网络/root 的流程，不进 CI |
| CI 快闸门 | `tests/run_checks.sh` | 153 项，**不依赖 root/Docker/网络**（CNB CI 契约） |
| 完整回归 | `tests/comprehensive_test.sh` | bash 229 + Python 697 |
| 验证服务器 | 156.239.52.100:5522（root） | 本文件所有真机方案的目标 |
| 双远端发版流程 | 技能 `fusionbox-dual-remote-release` | 一批做完后同步 GitHub + CNB |
