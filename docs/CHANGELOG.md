# FusionBox 变更历史

> 本文件由 README 迁移而来，内容为各版本发布说明原文（时间倒序）。最新摘要见 [README](../README.md#最近更新)；逐项实施对账见 [implementation-status.md](implementation-status.md)。

## v1.43.5 更新检查镜像后备：fusionbox update 在 GitHub 不可达时自动改走 CNB 镜像

- **背景**：v1.43.4 给安装器加了 CNB 镜像后备，但更新路径（`fusionbox update` /
  `self_update_cron`）仍只走 GitHub——屏蔽 GitHub 的容器实测确认更新会失败。本轮补齐：
  更新与安装共用同一套镜像常量（`FUSION_MIRROR`，默认 CNB，环境变量可覆盖）
- **实现**：`fusion.sh` 新增 `_update_from_mirror`——307 Location 匿名发现最新 tag
  （与 install.sh 同一机制），Release 资产 + SHA256SUMS 下载并同源校验，产物写入
  与 GitHub 路径相同的临时文件名，通过校验后并入既有"已校验 Release 包"安装分支
  （archive_root=FusionBox、tag 记录、版本比较、`_update_show_notes` 全部复用）。
  **静默尝试**：不打印提示、不新增语言包键——更新由运行中的旧版 fusion.sh 执行，
  新增键会在"新 fusion.sh + 旧语言包"窗口打印裸键名，复用既有键无此问题
- **避免整包空下载**：镜像最新版与当前版本一致时（cron 定时更新的常态），提前返回
  "已是最新"（复用 `MSG_MAIN_0008`），不下载 tarball；镜像落后于运行版本的极端情形
  由既有的 `_version_is_newer` 降级保护兜底（warn 后拒绝）
- **回落顺序**：GitHub Release →（不可达）CNB 镜像 Release →（也失败）main 分支快照
  （无校验，沿用既有 MSG_MAIN_0012/0013 提示）→ 失败报错
- **门禁 198→199**：新增断言——更新检查镜像后备存在（`_update_from_mirror` +
  `FUSION_MIRROR` 静态 grep）
- **验证口径**：屏蔽 GitHub 的裸容器实测：v1.43.4 经镜像装出（安装镜像后备）→
  以新 fusion.sh 覆盖运行侧（version.txt 保持 1.43.4 模拟"已装旧版"）→
  `fusionbox update` 静默走镜像发现 v1.43.5 → 下载 + SHA256 校验 → 升级成功且
  升级说明打印；同版本场景提前返回不下载；镜像与 GitHub 资产 sha256 双端一致；
  静态门禁服务器 **199/199**

## v1.43.4 审计跟进：安装镜像后备、FUSION_LANG 优先级、日志静默降级、文档勘误

- **安装镜像后备（P1）**：实测发现 CNB 匿名 `-/raw/` 与 `-/archive/` 返回的是 HTTP 200 的
  **软 404 HTML 页**（Content-Type: text/html，不能凭状态码判断可用性），只有 Release 资产
  真实可用且与 GitHub 逐字节一致（`FusionBox-v1.43.3.tar.gz` sha256 双端均为 `f1c9168e…`），
  `-/releases/latest` 以 307 Location 匿名暴露最新 tag。install.sh 据此新增 `_download_mirror`
  （默认 `https://cnb.cool/code_free/FusionBox`，环境变量 `FUSION_MIRROR` 可覆盖）：
  GitHub 探测失败时先探测镜像主机（bash 内建 `/dev/tcp`，裸系统无 curl/wget 也能判），
  可达则照常补依赖（系统源不经 GitHub）后走镜像 Release 下载并过 SHA256SUMS 校验；
  GitHub 可达但 Release 下载/校验失败时同样回落镜像。校验逻辑抽取为 `_verify_downloaded`
  两条路径共用。新增 `MSG_INST_0035`，语言包 3249→3250，install.sh 内置表同步。
  README 双语「30 秒上手」各补一个纯镜像手动安装 `<details>` 块（4 行：latest 发现 →
  资产+SUMS 下载 → `sha256sum -c` → 解包跑 install.sh，GitHub 被屏时走本地安装路径）
- **FUSION_LANG 优先级（P1）**：`common.sh::_load_config` 原先 env 先设、config 后覆盖，
  而安装器总会写入 `general.lang`（哪怕值是 `auto`），导致 docs/i18n.md 承诺的
  `FUSION_LANG=en` 单次覆盖在**所有已安装系统上永远无效**（真机夹具复现：config=auto +
  env=en 输出仍中文）。改为显式配置 > 环境变量 > `auto`（跟随 `$LANG`）——`auto` 语义
  即"尚未选择"，环境变量可打破平局，显式选择不被翻转
- **日志静默降级（P2）**：HOME 不可写（如容器内 nobody）时 `_init_log` 的 `mkdir` 报错 +
  每条 `_log_write` 的 append 报错会污染帮助输出（真机实测 4 行 stderr）。现 `mkdir`
  失败置 `F_LOG_OK=0` 静默停用，`_log_write` 加守卫与 `2>/dev/null`；正常路径日志行为不变
- **文档勘误（P1）**：README 双语"完整 Docker 卸载尚未实现"为过期假话——
  `panels_docker_uninstall`（c5280aa，G30 起）是停删容器、清镜像/卷/网络、禁服务、
  四类包管理器卸包、数据可选擦除、验证 docker 消失的完整实现，同文件命令参考也早已
  列出 `fusionbox panels docker uninstall`；按实际能力订正双语各一处
- **README.en 净化（P2）**：品牌名改官方英文（宝塔→BT Panel、哪吒监控→Nezha monitoring、
  棉花云→Mianhua Cloud，与 `src/i18n/en.sh` 既有译法一致），命令占位符改英文
  （`<名称>`→`<name>`、`<端口>`→`<port>`、`<关键词>`→`<keyword>`、`<应用>`→`<app>`），
  正文中文残留清零；双语闸门 `CJK_ALLOW` 白名单清空，命令与行内代码比对引入
  **占位符归一化**（`<...>` → `<#>` 后比对，两边可各用目标语言书写占位符，其余仍逐字）；
  负向测试复跑：删 EN 命令、命令本体错字仍被抓住，占位符翻译正确放行
- **依赖安装自动重试**：真机 Ubuntu 24.04 裸容器实测撞上 security 池与索引瞬时不同步
  （`libcurl4t64 ... 404 Not Found`，apt 自身提示 "maybe run apt-get update"），而 `set -e`
  让整个安装以 RC=100 裸死、无任何提示。现各包管理器分支在首次安装失败后
  `_ensure_dep_index --force` 强制重刷索引并重试一次，仍失败才经既有 `MSG_INST_0016`
  报错退出；`_ensure_dep_index` 增加 `--force` 绕过一次性守卫
- **门禁 193→198**：新增 5 断言——FUSION_LANG 打破 auto（夹具 config + env 断言
  `F_LANG`）、显式 config 仍优先于 env、日志静默降级（HOME 指向普通文件触发 mkdir 失败）、
  安装器镜像后备存在（静态 grep）、依赖安装失败自动重试（静态 grep）；run_checks.sh 顶部
  加 Windows 环境提示（自动 `PYTHONUTF8=1`；fcntl 类检查假红以 Linux 为准）；
  tests/README.md（不入库）记录 Linux-only 口径、WindowsApps python3 stub 陷阱与假红清单
- **版本计数同步**：README 双语静态门禁当前口径改 **197 / 197**（历史记录保留 193），
  双语「双语口径」键数 3249→3250，index.html `data-fact="i18n_keys"` 同步（site_facts
  棘轮强制）
- **验证口径**：新验证服务器（Ubuntu 24.04，Docker 隔离）：Ubuntu 22.04 裸容器三条安装
  路径（GitHub 正常 / `/etc/hosts` 屏蔽 GitHub 后自动镜像 / 分支树本地离线安装）+
  24.04 裸容器真机安装（当场抓到并修复上述依赖 404）+ 注入一次性失败的 apt-get 包装器
  确证重试路径；`FUSION_LANG` 夹具矩阵（auto+en→en、en+zh_CN→en）与 nobody 帮助
  stderr=0 实测；1.43.3→1.43.4 端到端升级并确认升级说明通道首次以新版格式可见；
  静态门禁服务器 **198/198**

## v1.43.3 安装体验与面板清单：默认中文、装完进主菜单、fb/FB 快捷命令、1Panel 进 Aapanel 出

- **安装器语言默认值（PR #39）**：`install.sh` 原为 `case "${FUSION_LANG:-${LANG:-en}}"` 且只认
  `zh*`，而云镜像常见 `C.UTF-8` 或非登录 shell 无 `LANG`，导致安装全程英文、装完的菜单却是
  中文。现与运行时 `src/lib/i18n.sh::_i18n_resolve_auto` 同规则：只有显式 `en*` 用英文，其余一律
  中文；`FUSION_LANG` 可显式覆盖
- **装完进主菜单（PR #39）**：交互式（stdin 与 stdout 均为 tty）时 `exec /usr/local/bin/fusionbox`
  （无参数即主菜单）；`curl | bash` 时 `-t 0` 为假，仍走原用法提示分支，不会把脚本剩余内容当
  菜单输入吃掉。新增 `MSG_INST_0034`，并**同时写入 install.sh 内置表**——新安装脚本会配到旧
  发布包（v1.43.2 的语言包无此键），只靠语言包会打印裸键名
- **面板清单（PR #40）**：新增 `panels_1panel`（官方 `resource.fit2cloud.com/1panel/package/v2/quick_start.sh`，
  实测 200/2782B），移除 Aapanel 的函数、`aa|aapanel` 分发、菜单项与 help 行；语言包 0627-0630
  四个键原位改写成 1Panel 语义，故键数不变、菜单编号不变。宝塔安装把安装码作为参数传给官方
  脚本（用户给出的命令前半段 curl/wget 回退 `_download` 已实现，且它落临时文件而非当前目录，
  故保留 `_download`）。**该安装码随公开仓库发布，等于对所有访客公布**，是否需要改法待维护者定
- **快捷命令 fb / FB（PR #41）**：与 `fusionbox` 同是指向 `/etc/fusionbox/fusion.sh` 的软链接，创建点
  在 `fusion_deploy` 提交之后——安装（传 bin）与更新（不传 bin，回退到 `/usr/local/bin/fusionbox`
  同目录）两条路径都补齐。**但 `self_update` 原先 `source "$FUSION_BASE/src/lib/deploy.sh"` 加载的是
  机器上旧版那份 deploy.sh**（尽管它已校验过新下载的那份存在、非软链、包体哈希正确），
  于是 deploy.sh 里的新动作要再下一次更新才落地——真机升级 v1.43.2→v1.43.3 实测确认 `fb`/`FB`
  未被创建。现改为 `bash -n` 后加载刚下载的那份；已存在且非本脚本所建的链接只提示不覆盖；`self_uninstall` 对称删除。
  提示沿用 `deploy.sh` 既有英文诊断语气，未新增语言包键
- **升级说明通道（PR #38）**：新增 `docs/release-notes.md`，`fusion.sh` 的升级提示与
  CNB 的 `descriptionFromFile` 都改指它；GitHub 每次 push/PR 的版本一致性步与 CNB 的 validate-version
  都要求"顶部小节版本 == version.txt"，即升版本号却不写使用者说明会让闸门变红。
  **生效时点纠正**：发布 v1.43.3 后端到端实测发现，升级提示是由"正在运行的旧版 fusion.sh"打印的，
  所以 1.43.2 → 1.43.3 这次更新输出的仍是 CHANGELOG 原文；新通道从 1.43.3 → 下一版起才生效。
  原先写"本版首次生效"是错的
- **描述修正**：`MSG_NET_0152` 原名"TCP 重传｜统计 TCP 重传率"，与 `ibsgss/TcpQuality` 实际行为
  （全国三网节点 TCP 质量探测、输出带宽与链路质量）不符，已改准。另核实 `LloydAsp/NodeQuality`
  与 `ibsgss/TcpQuality` 早已在评测矩阵内（`MSG_NET_0148` / `MSG_NET_0152`，URL 与两仓库 README 的
  官方命令逐字一致），无需新增
- **验证口径**：真机（Ubuntu 22.04 / Docker 29.8.1 / nginx 1.18.0）在隔离 base 目录跑真实
  `fusion_deploy` 验证软链接三种情形（外部同名命令不覆盖、正常建链、更新路径建链）并实跑
  `fb version` / `FB version`；四个外部 URL 实测可达；CI 静态闸门（语法、Python 产物、i18n 3249 键
  逐键对等、README 双语同步含注释闭合断言、主页数字派生、端口与凭据棘轮、版本一致性含
  发版说明检查）全绿。
  **发布后补跑（2026-09-24）**：在验证服务器跑了 `tests/run_checks.sh` 与 `tests/comprehensive_test.sh`，
  结果 **193/193 通过、完整回归 RC=0**。这一跑当场抓到 3 个由前几轮改动造成的陈旧检查——函数改名后
  按名字抽取落空、POSIX 字符类 `[[:space:]]` 被 bashism 判据误伤、引用策略白名单未含新增的
  `README.en.md`——均已修正并复跑至全绿。因 `tests/` 不入库，这些修复只存在于本机与验证服务器。
  本节原先的"未重跑"仅指发布前那一刻，现予订正

## v1.43.2 安全加固：遥测 Worker 收口、交付编排端口与凭据棘轮、6 个面板默认只绑本机

外部扫描结果逐条独立复核后的修复；判级与机理以本条为准，其中两处扫描结论属夸大或影响面写错，已注明。

- **遥测 Worker**（`telemetry-worker/src/index.ts`）：`readBody()` 原为 `await request.arrayBuffer()` 全量缓冲后再判 4096 字节上限，且 `Content-Length` 头检在分块传输与 HTTP/2（无该头）下被整体跳过——现改为按块累计、越限立即取消流。测试用一条 1 MiB 无 `Content-Length` 的流断言"只读过上限一块就停"，旧实现下实测吸完 1056768 字节才拒绝
- **写入端点不再对浏览器开放跨域**：原先所有响应带 `Access-Control-Allow-Origin: *` 且 `Allow-Methods` 含 POST，配合 `/v1/event` 无鉴权，任意网页可借访客出口 IP 消耗其 source 限流额度并伪造遥测。通配 CORS 现只保留 `/v1/public/summary`、`/v1/public/badge` 两个只读端点，`/v1/event` 见 `Origin` 请求头即 403（采集端是 curl，不发该头）；`version` 数值段由无界 `\d+` 改为 `\d{1,10}`，避免它成为可被撑到请求体上限的 D1 主键片段。D1 表的保留/清理策略是数据口径决定，本轮有意未做
- **`templates/docker/monitoring.yml`**：Grafana 管理员口令原为内置字面量 `fusionbox`，现改 `${GRAFANA_ADMIN_PASSWORD:?}`（缺失即启动前失败，不回落默认口令）并关闭 Grafana 自助注册；Prometheus 与 Grafana 端口改绑 `127.0.0.1`，与托管应用层 `src/lib/market_apps.py:207` 的渲染口径一致。扫描报告称 node-exporter 同样暴露属夸大——该服务无 `ports` 段
- **`web` 模块生成的 nginx 配置**：站点、反向代理 HTTPS 块、ACME 托管 TLS 块补 `X-Content-Type-Options` / `X-Frame-Options` / `Referrer-Policy`；`web_firewall` 注入集与 `templates/nginx/fusionbox.conf` 去掉已废弃的 `X-XSS-Protection`。HSTS 与 CSP 有意不自动下发并在产物内留注：前者一旦下发，证书失效时浏览器仍强制 HTTPS，用户没有临时回退余地；后者对未知应用会直接打断第三方脚本。扫描报告称 `fusionbox.conf` 缺头会"传播到所有 vhost"不准确——全仓无任何代码安装或 include 该文件，它是给人手工 include 的模板
- **6 个一键部署默认只绑本机**：判据是"首个访问者能否拿到管理员或完成初始化"。改：Halo（初始化向导）、KodExplorer（默认账号）、LinkStack（管理面板）、Uptime Kuma（首个访问者即管理员）、Vaultwarden（明文 HTTP 上的密码管理器，同时 `SIGNUPS_ALLOWED` 默认 false）、Memos（首个注册者即所有者）。保持对外并注明理由的 10 处：WordPress / Typecho / Discuz / Nextcloud / Flarum / 苹果 CMS 属对外站点且各有真实认证，Emby / Jellyfin 的正常用法是局域网内设备连媒体库，Alist 的随机管理员口令只出现在服务端日志，IT-Tools 是无状态纯前端工具箱
- **新断言**：`scripts/deploy_exposure_audit.py` 要求交付的 compose 中每个已发布端口要么绑回环、要么就地注明 `# fb-expose: <理由>`，口令类环境变量必须运行时取值否则注明 `# fb-cred-ok: <理由>`；已接入 `.cnb.yml` 的 `&ci-stages`（push 与 pull_request 同源）与 GitHub syntax job。扫描器只报出 1 处裸端口，该断言在仓库内定位到 **25 处**（`web.sh` 17、`cluster.sh` 5、`panels.sh` 1、`nginx-proxy.yml` 2），至此全部显式表态
- **缺陷修复（苹果 CMS）**：`_deploy_apple_cms` 写完主编排并 `chmod` 后，又无条件用"fallback：若专用镜像不可用"的编排覆盖同一个文件，而代码里没有任何条件判断——`maccms` 镜像从未生效，部署出来的始终是空 docroot 的 `php:8.1-apache`。现改为仅当 `docker compose up -d` 失败才 `down` 后写入回落编排重启。以 docker 桩实测四条路径确认差异
- **文档闸门缺陷修复**：README 与 README.en 的发布槽位在 v1.43.1 发布时丢了闭合符，导致从"最近更新"起整篇正文被当作 HTML 注释（GitHub 渲染时"命令参考"及其后内容全部消失）。已闭合，并给 `scripts/docs_readme_gate.py` 加"注释必须成对、且发布槽位之后不得残留未闭合注释"的断言——双语闸门当时未报，是因为两个文件同病，结构对比自然相等
- **验证口径**：遥测 Worker 套件 8/8 + `tsc --noEmit` 干净；静态闸门本地全绿（i18n 3248 键逐键对等、README 双语同步、主页数字派生、端口与凭据棘轮、语法与 Python 产物）。**本轮未重跑真机验收**：端口绑定与 nginx 配置变更需在验证服务器确认，环境限制未变（真实 OCI 实例、TG bot token、真机关机分支）

## v1.43.1 修补：应用市场最后一条硬编码文案 + 审计器补数据数组棘轮

- `src/modules/market.sh` 的 `MARKET_APPS` 里，`"utility:Warp:cloudflare-warp:Cloudflare WARP VPN"`
  是 75 条中唯一一条硬编码（其余 74 条均为 `$(L MSG_MARKET_xxxx)`），中文模式下这一行的说明会显示英文
- 已改为键式取值：新增 `MSG_MARKET_0429`，中文包补中文说明、英文包保留原英文文案不改写；
  语言包由 **3247 键 → 3248 键**，中英仍逐键对等
- **为什么之前没被发现**：v1.43.0 的「全仓未抽取归零」结论本身没错，但 `scripts/i18n_audit.py --coverage`
  只扫描 `msg/echo/printf` 等文案出口，**不检查数据数组里的字面量**，所以这类漏网条目不会让审计变红。
  本条不改写 v1.43.0 的历史记录，只在此补记实际缺口。
- **已给审计器补上这条盲区**：`scripts/i18n_audit.py` 新增数据数组检查——`MARKET_APPS` /
  `SYSTEM_TZ_PRESETS` / `PANELS_DOCKER_MIRRORS` / `CLUSTER_TASKS` / `NETWORK_BENCH_ITEMS`
  这 5 个约定全量键式的数组，出现任何字面量条目即失败（**与语种无关**，漏网的正是纯英文条目）；
  另加兜底规则：任何数组条目含中文且未走语言包一律失败。标识符型数组
  （`P_PROTOCOLS` 的 `"VLESS-TCP" "vless" "tcp"`、`CLUSTER_GAMES` 的纯 ASCII 条目）不受影响
- **同批交付**：`README.en.md` 全文英译与 `scripts/docs_readme_gate.py`（中英结构/命令/链接/锚点同步闸门）、`scripts/site_facts.py`（主页数字派生校验）一并接入 GitHub 与 CNB 两条流水线；主页数字改由源码派生，不再手打
- **验证口径**：本版只动文案与工具链，未重跑真机验收；真机口径沿用 v1.43.0 的 Ubuntu 22.04 结果（闸门 193/193、完整套件 bash 229 + Python 764 项）


## v1.43.0 双语支持第二批：模块层 100% 双语（全仓文案收口）

- **9 个模块全部双语化**：system / web / panels / cluster / network / market / workspace /
  proxy / warp；语言包从 290 键扩到 **3247 键**，中英两套**逐键对等**（键集合、占位符数量与顺序
  由 `tests/test_i18n.py` 与 `run_checks.sh` 第 22 节强制）
- **抽取器覆盖全部文案出口**（不再只认 `msg/echo/printf`）：
  - 交互与守卫：`read -p`、`confirm`、`read_input`、`select_option`、
    `_fb_user_read_password`、`_require_python3/_docker/_docker_compose`、`shutdown -h +5`
  - 日志：`_log_write`
  - 变量赋值：`local status="${F_RED}离线${F_RESET}"`、`note="[FusionBox] 流量告警：…"`
  - 数据表：应用市场目录（74 条 `分类:名称:包:描述`）、VPS 评测矩阵（13 条
    `名称|分类|说明|URL|模式`）、时区预设（29 条）、Docker 镜像源、集群任务表
  - 值表达式：`${x:-默认}` / `${#arr[@]}` / `${arr[$i]}` / `$((算术))` / `$(命令)` / `$1`
    一律**整体作为参数透传**（同一行内求值时机与结果等价，语言包里因此不留变量）
- **全仓未抽取文案归零**：`scripts/i18n_audit.py --coverage` 逐文件均为 0；
  `run_checks.sh` 第 22 节由「核心层」升级为「全仓」强制——新增的中文字面量出口会让闸门直接变红
- **顺带修掉一个真实产品缺陷**：`_env_backup` 两次调用 `date`（秒级精度），跨秒时返回给调用方的
  备份路径与实际落盘文件名不一致，`system env edit` 的「编辑失败自动恢复」会**静默失效**；
  现改为一次取时间戳，并补回归测试（mock date 复现跨秒场景）
- 语言包取值统一做 shell 转义（`\`、`"`、`$`、反引号），避免 `.` 加载时被二次展开
- 修掉 here-string（`<<<`）被误判为 heredoc、以及 `printf` 跨行格式串被跳过的两个抽取器缺陷
- **仓库策略**：测试资产不再入库——`tests/` 进 `.gitignore`（本地与验证服务器保留完整测试），
  CI 收敛为静态检查（语法 / Python 产物 / i18n 契约审计 / 版本一致性）；发布包口径不变
  （`.gitattributes` 的 `export-ignore` 一直保证 tar.gz 不含测试）

- 实测（真机，逐字节对比 v1.42.0）：中文输出**完全一致**；英文模式下 9 个模块的帮助、
  菜单与入口输出 **0 中文**

## v1.42.0 双语支持第一批：核心层 100% 双语 + 语言切换命令

- i18n 核心独立为 `src/lib/i18n.sh`：两套**地位对等**的完整语言包
  （`src/i18n/zh_CN.sh` / `en.sh`，各 290 键），按当前语言取值、缺键回落另一语言
  并登记缺失；颜色与变量一律作为参数传入，语言包内不含转义码
- 新增 `fusionbox lang [zh_CN|en|auto]`：查看/切换界面语言（写入
  `config.yaml` 的 `general.lang`，非 root 可查看）；`FUSION_LANG` 仍可单次覆盖
- **核心层完成**：主菜单、全局帮助、通用提示（暂停/确认/选择）、依赖守卫、
  卸载流程、安装器全部走语言包；`fusionbox help` 新增 `lang` 一行
- **顺带修掉脚本化缺陷**：只读命令在非交互场景不再卡在「按 Enter 键继续...」
  （`pause` 在 stdin 非 TTY 时立即返回），管道与 CI 可直接消费输出
- 工具与门禁：`scripts/i18n_extract.py`（抽取/改写，带两条防丢变量自检）、
  `scripts/i18n_audit.py`（键与占位符一致性、英文包无中文、覆盖进度、安装器内置表漂移）、
  `tests/test_i18n.py`（21 项契约测试）、`run_checks.sh` 第 22 节
- 实测（全新 Ubuntu 22.04，逐字节对比 v1.41.0）：中文模式输出**完全一致**（仅新增 lang 帮助行）；
  英文模式 `help` / `version` / `status` / `privacy` / 主菜单 **0 中文**
- 模块层待续：system(911) / web(578) / panels(298) / cluster(230) / network(120) /
  market(110) / workspace(98) / proxy(93) / warp(76) 共约 2514 条文案，已有工具链，
  按模块分批推进，覆盖计数用棘轮约束只增不减

## v1.41.0 Cloudflare 联动真实凭据验证与 Global Key 铸造（B4 收口）

- **B4 收口（Cloudflare 半边）**：最小权限 API Token 真实凭据验证完成——`fusionbox-cf-guard` 负载自适应开盾真机 8/8（security_level 真实切到 under_attack + 负载回落恢复基线 + 幂等），`fusionbox-cf-ban` 封禁/解封/幂等真机全过；新增真机验收 `tests/acceptance/cloudflare_guard.sh`（21/21，任何退出路径恢复 security_level 基线并清理测试规则）
- **实测修复**：CF API 会返回 pretty JSON（`"success": true` 冒号带空格），cf-ban/cf-guard 的紧凑格式断言全部改为空白容忍——静态测试抓不到、真机首跑即现形
- **新功能**：Cloudflare 联动配置支持直接粘贴 Global API Key——自动列出账户 Zone、现场铸造仅限所选 Zone 的最小权限 Token（Zone Settings + Firewall Services，14 天有效期），Global Key 本身绝不落盘；真实 Key 端到端验证通过（铸造 → verify active → 读取 security_level）
- **TG 半边维持**：`system notify` 真实发送验证仍需 bot token，凭据缺失时显式拒绝的姿势保持不变

- B4 收口（Cloudflare 半边）：用户提供 Global API Key 后，按 roadmap 建议
  现场铸造仅限测试 Zone（endgo.top）的最小权限 API Token
  （Zone Read + Zone Settings Read/Write + Firewall Services Write，14 天
  有效期），Global Key 本身不落盘
- 真机验收 `tests/acceptance/cloudflare_guard.sh`（21/21，不进 CI）：
  Token verify、security_level 基线、缺凭据显式拒绝（conf 缺失/Token 缺失/
  非法 IP 三路全部退出 1）、封禁 → API 侧确认 → 幂等 → 解封 → 确认消失、
  cf-guard 高负载档真实切到 under_attack + 幂等 + 负载回落恢复基线 medium +
  state 文件断言；任何退出路径恢复 security_level 基线并清理测试规则
  （默认测试 IP 192.0.2.1 TEST-NET-1，绝不误伤真实用户）
- **实测修复（静态测试抓不到）**：CF API 返回 pretty JSON（`"success": true`
  冒号带空格），cf-ban 的 `"success":true`/`"id":"..."` 紧凑断言与 cf 配置
  purge 的同类断言全部改为空白容忍正则；find_rule_id 改 sed 提取
- **新功能**：`web guard → Cloudflare 联动配置` 支持直接粘贴 Global API Key
  （37 位十六进制识别）——验证邮箱 → 列出账户 Zone → 选择 → 现场铸造
  仅限所选 Zone 的最小权限 Token 并写入配置；真实 Key 端到端验证通过
  （菜单驱动 → 铸造 → verify active → 读取 security_level）
- 单测：`test_notifications.py` 新增 cf-ban pretty/compact 双格式矩阵
  （封禁/失败/幂等/解封七场景）与 Global Key 铸造流程（成功 + 失败显式
  拒绝，绝不把 Global Key 写进配置）
- TG 半边维持：`system notify` 真实发送仍待 bot token，凭据缺失显式拒绝

## v1.40.0 应用扩容、harness 设计与真实参数收尾（roadmap 批次 4）

- A6 首批扩容：`vocechat` 入内置目录（digest 固定、单容器 256m、具名卷 data、
  自检端点健康检查），真机验收 `tests/acceptance/market_app_expansion.sh`
  （安装 → HTTP 200 → 卸载保留卷 → reuse-data 重装 → 数据与 HTTP 复核）
- 实测边界（如实记录）：Webtop（linuxserver s6 系列）在 `cap_drop ALL` 下无法
  运行（s6 需要 setuid/setgid），与受管加固模型不兼容；WireGuard 需 NET_ADMIN
  （high_privilege 路径）与雷池（多容器）可行未实施；2FAuth/Nexterm 上游镜像
  源未确认
- A7 设计稿：docs/harness-design.md——容器化、凭据文件化（0600 卷内 + stdin
  输入）、备份默认排除凭据卷、L1–L4 分层验收（L3 真实对话需模型 API 凭据）
- B5 收口：`tests/acceptance/netopt_sysctl.sh`——`system netopt` 真实改值
  （somaxconn 等运行值实测变化）+ 首次应用前快照逐键一致 + 恢复后 11 键与
  基线零漂移；G18/G67 的「真实改参数」缺口就此收口
- A3/A5 判定收口：一键 DD 维持「明确拒绝 + 带外恢复」（roadmap A3 判定）；
  Oracle 三件套在真实 OCI 实例就位前只做「拒绝的姿势」——均为设计决策

## v1.39.0 ACME 两条真机验证路线（Pebble + Let's Encrypt staging）

roadmap 批次 3（P2）：G35/G36/G59 从「部分实现」推进到「真机验证」。

- `web ssl issue/renew` 新增 `--server`（`WEB_ACME_SERVER` env）：覆盖 ACME 目录
  URL，指向 Pebble / Let's Encrypt staging 等非生产服务；必须为 https://
- 自定义 `WEB_ACME_LE_DIR` 时 certbot 的 `--config-dir/--work-dir/--logs-dir`
  整体切换——测试签发绝不污染生产 /etc/letsencrypt
- 保留 TLD 守卫（拒绝 `.invalid/.test/.local/.localhost`）保护生产签发路径；
  显式 server 覆盖时放行，用于测试域名——生产默认行为零变化
- 路线 A `tests/acceptance/acme_pebble.sh`（24/24）：本地 Pebble 容器 +
  `PEBBLE_VA_ALWAYS_VALID=1`（challenge 判定交由路线 B 的真实传输覆盖）——
  真实 certbot 协议链路、SAN/私钥/受管 TLS 装配、Pebble 证书短有效期断言、
  `renew --days 30` 真实触发（指纹变化 + nginx 重载）、不可达目录 URL 失败后
  无证书且 challenge 配置回滚
- 路线 B `tests/acceptance/acme_staging.sh`（16/16）：`<公网IP>.sslip.io` +
  Let's Encrypt staging——真实 DNS 解析报告、真实 HTTP-01 传输、真实 CA 签发
  （staging 中间证书）、受管 TLS 启用、DNS 不可解析域失败回滚
- run_checks 新增第 19 节（server 覆盖/放行参数/目录隔离/验收资产静态检查）

验证（Linux 验证服务器 Ubuntu 24.04.5）：闸门 174/174（root 与非 root）；
完整套件零失败；两条 ACME 路线真机全过。生产 LE 目录（非 staging）签发
未验证——同代码路径，但速率限制与真实账号注册不同，如实标注。

## v1.38.0 两主机夹具、真实容器生命周期与跨主机迁移编排

roadmap 批次 2（P1）：B1 真实容器生命周期 + B3 两主机夹具 + A4 跨主机迁移编排（G29，
同时覆盖 G15/G16/G61/G63 的真实条件验证）。

- 新增 `panels docker-migration remote`（`src/lib/docker_migration_remote.py`）：
  目标机环境门禁（python3/docker/守护进程/FusionBox 安装/0700 落地目录）→
  `archive_transfer --kind docker-v1` 校验传输（源包保留）→ 目标机只读 preflight →
  目标机 `restore`（事务化）→ 逐容器健康校验；restore 失败或健康不达标时目标机
  自动 rollback，rollback 也失败则报告事务 ID 与恢复指引；`--dry-run` 不向目标机
  写入任何文件；`--json` 输出单行机器可读摘要（单点上报，无中间行污染）
- 编排只做顺序化，不新写 SSH/传输/恢复机制：复用 `cluster_session.key_options`
  （严格 known_hosts、禁密码、禁 agent）、`archive_transfer.run`、目标机自身的
  `docker_migration.py preflight|restore|rollback`
- 两主机夹具：privileged 容器（ubuntu + sshd + 内嵌 dockerd vfs）扮演第二台主机；
  `cluster_session.run_ssh` 对远端只要求 bash/python3，无物理机依赖；专用临时密钥
  （一次性 ssh-agent 或 `--identity`），不复用生产密钥；容器销毁即回收
- `cluster node-exec|connect` 新增 `--identity`：`run_ssh` 一直支持显式身份，
  CLI 此前未暴露；真机同时确认 OpenSSH 默认身份取自 passwd 而非 $HOME，
  HOME 覆盖对 ssh 无效
- 真机修复 4 个既有缺陷（全部只在真实 Docker 上暴露）：
  1) 迁移契约拒绝 `MaskedPaths/ReadonlyPaths`——引擎对每个容器注入默认值
     （且含宿主特定条目），导致任何真实 `docker run` 容器都无法导出；改为纳入
     声明做审计（engine-managed，无 CLI 入口，不可能携带用户意图），契约升为 2
  2) `docker ps -aq` 返回截断的 12 位 ID，与 64 位选中 ID 比对恒假——
     「拓扑一致性」校验在真实 Docker 上从未生效；补 `--no-trunc`
  3) 跨镜像存储后端镜像 ID 不可移植：containerd snapshotter 以 manifest digest
     为镜像 ID，经典存储以 config digest 为 ID，`docker load` 不保留
     RepoDigests——加载校验改为以声明 RepoTags + 离线包完整性为准，
     create 用原始 `image_reference`（tag）而非引擎特定 ID
  4) 架构命名不一致：`docker info` 报 x86_64/aarch64，镜像 inspect 报
     amd64/arm64，preflight 的 OS/架构比较恒假；加归一映射
- restore 失败原因写入 journal（`error` 字段）——此前 `from None` 吞掉底层异常，
  目标机失败不可诊断；编排失败时读取并展示 journal 错误与最近 stderr
- compose-backup 的市场集成确认：market install 即以 `fusionbox-compose-v1`
  登记，卸载删除登记；restore 语义为「向已重建项目灌回数据」而非从零引导，
  已在验收脚本中如实覆盖
- 新增真机验收（不进 CI，需 root/Docker/网络，可一键重放）：
  `tests/acceptance/two_host.sh` **29/29**（登记/信任/出站/批量/归档往返/
  dry-run 零写入/门禁拒绝/完整迁移/preflight 冲突不波及健康状态/中断回滚清零），
  `tests/acceptance/container_lifecycle.sh` **17/17**（真实 HTTP 部署/停止启动/
  compose 备份确定性/数据全损后重建并灌回/数据行逐字节复核）
- 新增 `tests/test_docker_migration_remote.py`（15 项进 CI）：门禁拒绝矩阵、
  dry-run 零写入、preflight 拒绝保 target_clean、restore 失败回滚、回滚失败
  要求人工介入、无事务即失败、健康不达标回滚、成功路径与 JSON 单行输出

验证（Linux 验证服务器 Ubuntu 24.04.5 / Docker 29.8.1，目标机 Docker 29.1.3 vfs）：
闸门 `run_checks.sh` 168/168（root 与非 root，新增第 18 节）；完整套件
bash 229 项 + Python 741 项（33 模块）全过、零失败。

## v1.37.1 OpenSSH 候选切换与回滚（带自动恢复）

roadmap 批次 1 的第二半（A2）。此前 `ssh-candidate` 只有 `fetch/verify/build/test/status/clean` —— 能验证候选，不能切换。补上 `switch` 与 `rollback`，并把安全网做成机制而不是叮嘱。

**切换是一个带自动恢复的事务，而不是一次替换**

- **门禁**（全部通过才允许动生产二进制）：候选必须来自已验证源码（GPG 验签记录）、必须有**独立登录**成功记录、候选二进制对**现有生产配置**通过 `sshd -t`、生产 sshd 当前确实在应答（读协议横幅）
- **策略漂移必须显式接受**：比对生产与候选对同一配置的 `sshd -T` 有效值（`Port`/`PermitRootLogin`/`PasswordAuthentication`/`PubkeyAuthentication`/`AuthorizedKeysFile`/`UsePAM`/`Subsystem` 等 12 项），有差异时**默认拒绝**并打印差异，`--accept-config-drift` 才放行——静默改变认证策略比切换失败更糟
- **原子替换**：同目录临时文件 + `fsync` + `rename` + 目录 `fsync`，权限 0755/root，拒绝符号链接路径；备份原二进制到状态目录（0700，记录 SHA-256）
- **生效方式**：`reload` 让 sshd 重新 exec 磁盘上的二进制（现有连接不受影响），而不是重启
- **独立看门狗进程**（`setsid` 脱离）：切换后若生产端口在宽限期内没有应答，**自己把旧二进制放回去并重新加载**，状态记为 `auto-rolled-back`。这是「切换 sshd 会把自己锁在外面」这个风险的机制性答案，而不是让操作者自己承担
- **`rollback`**：手动回到上一份（校验备份摘要，不匹配则拒绝）；已回滚状态下再次回滚直接拒绝——不猜
- `--dry-run`：跑完所有门禁并打印计划，**不碰任何文件**
- `status` 增加切换审计：当前状态、生产二进制是否等于候选/备份、上次切换详情

**真机验证时发现并修掉两个只有真机能暴露的问题**

1. **`sshd -T` 输出格式在 OpenSSH 10.x 变成保留大小写**（`Port 50222`、`PasswordAuthentication no`），而既有 `_candidate_test` 用小写字串比对，于是「独立端口回连」这一步在真实 10.5 构建上必然失败——这段代码此前从未跑过真实产物。改为大小写不敏感比对（比的是有效值，不是某个版本的拼写）。
2. **reload 后立刻探测存在竞态**：`SIGHUP` 触发的 re-exec 有几十到几百毫秒窗口，旧进程已释放监听、新进程尚未绑定。单次探测因此**误判失败并触发一次不必要的回滚**。改为轮询等待（默认 20 秒，可配）。

**验收方式本身也值得说明**：切换事务不在宿主机上做。验证服务器唯一访问路径就是宿主 sshd，按 roadmap 自己的判定，没有带外通道就不该在生产 sshd 上做实验。因此：宿主机跑**真实**的 fetch → GPG 验签 → 构建 → 独立端口回连；把真实产物拷进容器，由容器里的另一个 sshd 扮演「生产 sshd」执行 `switch`/`rollback`，用**真实 SSH 登录 + 远端软件版本**判定是否换了二进制，并断言宿主 `/usr/sbin/sshd` 与配置哈希全程未变。

- `tests/acceptance/openssh_switch.sh`（真机，不进 CI）**32/32 通过**：真实签名获取与验签、真实构建（OpenSSH 10.5p1）、独立端口回连、dry-run 不改文件、策略漂移拒绝、切换后**客户端看到的远端版本就是候选版本**、看门狗复核、手动回滚、三类拒绝路径（非 sshd 文件、符号链接、重复回滚）、宿主未被触碰
- 新增 `tests/test_openssh_switch.py`（13 项，CI 可跑）：事务层测试——门禁、dry-run 不变更、切换、失败自动回滚、看门狗兜底与保留、探测轮询、漂移接受、重复回滚拒绝
- `run_checks.sh` 158/158（root 与非 root）；完整套件 bash 229 项 + Python 725 项（32 模块）全过、零失败

**边界（如实说明）**：`switch` 的实际生效对象在本轮是容器里的 sshd；在宿主机（也就是唯一访问路径）上执行生产切换，需要带外通道（VPS 控制台/救援模式）作为前提——这是 roadmap 对 G20 一贯的判定，本轮没有改变它。源码候选的获取/验签/构建/回连与切换/回滚事务本身均已真机验证。

## v1.37.0 多容器应用：从「只有框架」到「完整生命周期」

roadmap 批次 1 的第一半（A1）。之前多容器「不缺框架、但没人用、也不能维护」：声明式目录与 Compose 生成本就存在，可真正缺的是服务字段白名单、目录里没有任何多服务应用、以及 `update`/`reinstall` 对声明式应用直接拒绝。现在补齐，并配一个真实双服务应用做端到端真机验收。

- **服务字段白名单扩展**：`depends_on` / `shm_size` / `sysctls` / `tmpfs` / `read_only` / `entrypoint`。每一项都是能力，因此每一项都有独立的取值约束，而不是透传给 Docker：
  - `depends_on` 只能引用同一应用内已声明的服务，拒绝自依赖、重复项与**成环**（环会让启动顺序失去定义）
  - `sysctls` 只允许**在这台 Docker 上不加 `--privileged` 真的能生效**的键。白名单来自实测（Docker 29.8.1）：`net.core.somaxconn`、`net.ipv4.ip_local_port_range`、`net.ipv4.tcp_syncookies` 可用；`vm.max_map_count`、`fs.file-max` 被拒。这条实测结论直接决定了一个能力边界：**基于 Elasticsearch 的应用（如 RAGFlow）在本安全模型下无法承载**，已如实写入文档与 roadmap，而不是留一个「理论上支持」的说法
  - `tmpfs` 拒绝相对路径与路径穿越；`shm_size` 复用内存的 `<n>m` 形式；`read_only` 必须是布尔
- **真机踩到并拦下的一个坑**：`entrypoint: ["/bin/sh","-c"]` + `command: ["sleep","600"]` 会被 Docker 拼成一个 argv —— 实际执行的是 `sleep`，`600` 变成 `$0`，容器起来就退出。这不是配置写错那么好发现的问题（pull 成功、容器创建成功、只在运行时静默失败），因此改成**目录校验阶段直接拒绝**，并留下回归断言。
- **`network_mode: bridge` 的语义修正（最关键的修复）**：声明式目录里的 `bridge` 现在表示**应用自己的私有网络**（服务之间用服务 ID 互相解析），不再被写成字面量 `bridge`。此前的写法会把每个服务挂到 Docker 全局默认网桥，服务名互相不可解析 —— 多容器应用连不上自己的数据库，容器反复重启。这个问题只有真机部署才会暴露，静态测试与单服务场景都看不出来。仅 `host` 原样透传，且 host 网络服务不得发布端口。
- **多服务 `update`（事务化、带自动回滚）**：`market managed update <应用> --confirm [--service-image <服务>=<镜像@sha256:…>]`
  - 先按目录计算目标快照，**结构性变更一律拒绝**（服务集合、卷、发布端口、网络模式、binds、devices、socket —— 那属于迁移，不是升级），只允许换镜像
  - 无改动时是明确的 no-op，不会白白重建容器
  - 有改动时是一次事务：先拉齐镜像 → 写私有恢复 journal → 换快照与 Compose → `--wait` 起栈 → 健康门禁；失败则恢复上一份快照与镜像；**两级都失败**才进入 `recovery-required` 并保留 journal，后续变更被拒绝，要求人工介入（不会留下「说不清状态」的中间态）
- **多服务 `reinstall --reuse-data`**：仅从 `uninstalled` 且无容器、且声明的具名卷全都还在时才允许；绝不新建替代卷掩盖数据丢失。
- **`resources()` 反向校验扩展**：新增的每一项能力都会与运行中容器的真实参数比对（网络模式、ShmSize、Sysctls、ReadonlyRootfs、Tmpfs、Entrypoint），任何一项漂移即在 stop/remove/recreate 之前被拒绝。
- **内置目录新增真实应用 `umami`**（网站分析 = 应用 + PostgreSQL 双服务，端口 8090）：用来证明框架不是纸面能力。它的完整生命周期由 `tests/acceptance/market_multicontainer.sh` 在真机上验证。
- **测试**：`tests/test_market_catalog.py` 新增多容器字段校验矩阵（含环、白名单、shell-form entrypoint 守卫、内置 umami 一致性）；`tests/test_market_apps.py` 新增 `ManifestLifecycle`（Compose 生成、host 网络透传、结构性变更拒绝、镜像覆写规则、no-op、成功/失败回滚、双失败保留 journal、reinstall 条件、**逐字段漂移检测**）；`tests/run_checks.sh` 新增第 17 节（不依赖 Docker/root/网络）。
- 真机验收（Linux 验证服务器 Ubuntu 24.04.5，Docker 29.8.1）：`tests/acceptance/market_multicontainer.sh` **34/34 通过** —— 安装后 `db` 先于 `app` 启动、两个容器均 healthy、localhost:8090 真实返回 200、`shm_size` 落地 64 MiB、只暴露声明端口；`update` 无改动为 no-op、真换镜像成功、换成必然起不来的镜像时**失败并自动回滚**（容器回到上一镜像且仍健康、journal 已清除）；新字段在真机上既被正确落地、也能在漂移时被抓到；`uninstall` 保留具名卷，`reinstall --reuse-data` 后**此前写入的数据行仍在**。

## v1.36.6 修掉自造的 CI flake（帮助状态探测）

v1.36.5 的 tag 触发的 CI 通过，**同一提交**由 main 触发的 CI 失败——排查后确认是自己造的 flake，本批修掉。一个 flaky 闸门比没有闸门更糟：它会训练人忽略红灯。

- 根因：`help <模块>` 与 `<模块> help` 的一致性断言直接比对**原始输出**，而帮助末尾的「本机状态」是对宿主机的实时探测。探测用 `timeout 3 docker info --format '{{.ServerVersion}}'`，在负载波动的 runner 上可能一次超时、一次成功，于是两次输出「合法地」不同，断言与真实行为无关地失败。
- 修复分两层，缺一不可：
  - **探测本身更轻、更诚实**：改用 `docker version --format '{{.Server.Version}}'`（不枚举容器/镜像，显著更快，超时窗口内更稳）；超时文案由「已安装，守护进程未运行」改为「已安装（守护进程未响应）」——超时只说明守护进程没在时限内回话，不等于没装，不应替宿主机下结论。
  - **断言只测真正的不变量**：`run_checks.sh` 第 16 节与 `tests/test_help_dispatch.sh` 改为**先归一化状态行再比对**（帮助正文仍逐字节比对），并新增「状态行必须非空」的独立断言，避免归一化把问题一并抹掉。
- 新增 flake 回归夹具（`tests/test_help_dispatch.sh` 1b 节）：给 `PATH` 注入一个第一次调用故意 `sleep 10`（超过 3 秒探测上限）、第二次立刻返回版本号的 docker 垫片，断言**原始输出确实不同**（证明夹具有效）而**归一化后两种写法仍然一致**。这正是 CI 上真实发生过的场景，现在被固定为断言。
- 环境不具备 `timeout` 时该节显式 SKIP 并说明原因，不伪装通过。
- 文档口径同步收紧：README 由「逐字节相同的输出」改为「帮助正文完全相同（末尾状态行是实时探测）」，并加一句说明为什么这一行可能不同。历史版本段落（v1.36.3/v1.36.4 提到的「逐字节一致」）是当时的观测记录，按惯例不改写，以本段为准。
- 验证（Linux 验证服务器 Ubuntu 24.04.5）：`run_checks.sh` **153/153**（root 与非 root）；`test_help_dispatch.sh` **157/157**（含新增夹具）；完整套件 bash **229** 项（42 基础 + 157 帮助/配置 + 30 隐私统计）+ Python 697 项全过、零失败。

## v1.36.5 未完成项清单与过期陈述修正

本批只动文档，不改任何运行时代码。目的是把「还差什么」从一句「后续」变成可执行、可验收的清单。

- 新增 [roadmap.md](roadmap.md)：全部未完成项按四类拆分——**未实现（7 组）/ 环境受限（6 项）/ 明确不做（5 项）/ 有边界（22 项）**。每项给出代码现状（附文件与函数位置）、精确缺口、可执行步骤、可判定的验收口径、依赖与风险；并给出按「一批做完即可独立发布」划分的四个批次。
- 纠正一处长期误判：过去把「真实容器生命周期 / 真实 ACME / 两主机集群」笼统记为受环境限制，复核后确认**其中 5 项的条件现在就能造出来**，不需要新增机器或凭据。
  - 验证服务器 Docker 一直可用（29.8.1 active、13 个镜像、23 GB 空闲），真实容器生命周期可以直接跑；
  - 两主机场景可用容器扮演第二台主机——`cluster_session.run_ssh()` 只用标准 `ssh`、严格 `known_hosts`，远端只要求 bash/python3，**没有对「远端必须是物理机」的依赖**，一个跑 openssh-server 的容器就是合格目标，一次夹具可覆盖 G15/G16/G29/G61/G63 五项；
  - 真实 ACME 有两条路线：本地 Pebble（协议级、无外部依赖）与 Let's Encrypt staging + 含 IP 的公共域名（如 `sslip.io` 形式，真实 CA 与真实 HTTP-01）。
- 澄清一处与文档描述不同的技术现状：多容器应用**不缺框架**——`market_catalog.parse()` 的声明式目录与 `market_apps.manifest_document()` 已能生成并校验多服务 Compose；真正缺的是内置目录 10 个应用全部为单服务形态、以及服务字段白名单缺 `depends_on` / `shm_size` / `sysctls` / `tmpfs` / `read_only` / `entrypoint`、多服务不支持 per-image 覆写。这把该方向的成本从「造框架」改写为「放宽白名单并补校验」。
- 修正 4 行过期陈述（复核时发现文档低估了自身能力，与高估同样有害）：
  - **G12**「SSH 登录通知未实现」→ 实际已实现：`system login-alert install|status|test|uninstall`（PAM `open_session` 钩子 + TG 发送 + 受管状态校验），未验证的只是真实凭据；
  - **G17**「旧归档迁移仍后续」→ 旧归档读取已实现（`archive.py` 的 `legacy_map`），scope 已含 8 项；
  - **G61**「全量 /home 仍后续」→ `home` 早已是可选敏感 scope（逐项确认），剩余的是应用重建与两主机灾备；
  - **G62**「SSH 常驻 attach 模式后续」→ `screen`/`tmux`/`work` 均已有 `attach`，改为待明确语义后收敛为可判定陈述。
- 建议的下一步（见 roadmap 第 6 节）：批次 1 = 多容器应用框架 + OpenSSH `switch`/`rollback`（两者都不依赖真实 OCI、真实 ACME 或第二台机器）；批次 2 = Docker 真机与两主机夹具；批次 3 = ACME 两路；批次 4 = Oracle 三件套与 harness 管理器（需真实环境或先出设计）。
- 版本号五处一致更新为 1.36.5；`tests/run_checks.sh` 与完整回归套件在验证服务器上照旧全绿。

## v1.36.4 结束双发布线（仓库统一）

本批不新增功能能力，只解决一个结构性债务：**两个仓库、两条版本线、同一功能两套实现**。

- 背景：GitHub 与 CNB 在 v1.33.0（`28fe054`）之后各自演进。GitHub 线到 1.34.0（一致性修复），CNB 线到 1.36.2（OpenSSH 候选生命周期、i18n 首启体验、备份报错中文化、CNB 流水线等 11 个提交）。两条线**版本号互相冲突且指向不同内容**：`v1.34.0` 在 GitHub 上是帮助/配置一致性修复，在本仓库上却是首启体验修复。结果就是同一处逻辑被改两遍、同一批测试资产存在两个版本、发布说明无法对齐。
- 处理方式：以真实 merge 合并两条历史（无 force push、无提交丢失），两个仓库现在指向**同一个提交、同一个版本号 `v1.36.4`**，后续只维护一条线。
- 版本号对照（历史事实，不改写）：GitHub 的 `v1.34.0` 标签对应的一致性修复，其内容已并入本文件下文的 `v1.36.3` 段落；本仓库的 `v1.34.0` 是首启体验修复，两者不是同一件事。`v1.33.0` 及更早为两条线共有。
- 测试策略统一：`tests/` 全部随仓库发布并接入 CI（此前本仓库只跟踪 `tests/run_checks.sh`），发布包仍经 `.gitattributes` 的 `export-ignore` 不含测试。CNB 独有的 `.cnb.yml`、`src/lib/openssh_candidate.py`、`tests/run_checks.sh` 保留。
- CI 统一为三层：`syntax`（全部 shell/测试脚本语法、Python 产物、市场目录、下载量脚本、**`run_checks.sh` 快速闸门**、五处版本一致性）→ `tests`（`comprehensive_test.sh` 完整套件，root 下运行）→ `release`（仅打标签时，`needs: [syntax, tests]`）。CNB 侧 `.cnb.yml` 继续执行同一份 `run_checks.sh`，两个平台的闸门口径一致。
- 验证（Linux 验证服务器 Ubuntu 24.04）：`bash tests/run_checks.sh` **153/153**，且在 **root 与非 root 下都通过**（不依赖 root/Docker/网络）；完整套件 **bash 217 项 + Python 697 项全部通过、零失败**；真机 CLI 验收通过（三种等价帮助写法逐字节一致、13 组别名、未知模块 `rc=1`、未知子命令 `rc=2` 且不渲染菜单、29 城市时区设置后原时区已恢复、`color=false` 关闭全部 ANSI）。
- 未变：受环境限制仍未验证的项（真实容器生命周期、真实 ACME 签发、两主机集群、TG/CF 真实凭据）与明确不做的四项（KPanel、广告联盟、一键 DD、受管模板追数量）保持原状。

## v1.36.3 帮助分发、未知子命令与配置诚实性

本批不新增功能能力，只处理「文档/提示承诺了、代码没兑现」的一致性问题——边界内的不一致最伤信任。

- `fusionbox help <模块>` 从空头支票变成真实分发：`show_help` 过去打印「提示: fusionbox help <模块>」却完全忽略该参数，用户被自己的提示误导一次。现在 `_help_module_spec` 把别名映射到模块文件与 `<模块>_help()`，覆盖 9 个模块与全部别名（`p/sys/s/net/w/tools/m/ws/cl` 等），退出码为 0（成功）/1（未知模块）/2（模块加载失败）。
- `fusionbox help <模块>` 与 `fusionbox <模块> help` 在 `route()` 层归一化到同一条路径，**输出逐字节相同**；两者都是纯只读帮助，因此 `FUSION_HELPONLY` 让它们无需 root（`panels docker help` 同样放行），真实操作仍被 root 门禁拦住。模块帮助后追加**本机安装状态**（只读、3 秒超时探测，避免 `docker info` 在守护进程未运行时卡住），补齐 `status` 有依赖自检而 `help` 没有的短板。
- 9 个模块（含 `panels docker` 子分发）的未知子命令不再静默滑进交互菜单：统一走 `_module_unknown_cmd`，明确报错并给出 `help` / 菜单两条出路，退出码 2。此前 `fusionbox network bogus` 会直接渲染菜单并等输入，无 tty 时 `read` 报错后仍继续，脚本与 CI 场景直接卡死。
- `configs/config.yaml` 重写为「只声明真实会被读取的键」：移除 `general.auto_update`、`proxy.*`、`web.php_version`、`docker.auto_clean`、`panels.*_port`、`network.streaming_test` 等全部无读取点的键，并在文件末尾列出它们的真实归属（自动更新走 `update --cron`，代理路径由安装布局固定）。同时新兑现四个键：`general.color`（false 清空全部 ANSI 变量；i18n 文案不含内嵌转义码，因此关色完整）、`system.monitor_interval`（正整校验 + 非法回退）、`system.backup_dir`（backup/restore 默认目录）、`network.speedtest_server`（`auto` 或数值 ID，非法值告警回退而非静默忽略）。
- G07 时区预设从硬编码 4 个城市扩到 **29 个**，按亚洲/欧洲/美洲/大洋洲/非洲分区展示，改为数据表驱动（`SYSTEM_TZ_PRESETS`，新增城市只需追加一行）；新增 `_system_tz_apply` 做 IANA 标识白名单校验与 zoneinfo 存在性检查，拒绝路径穿越式输入（如 `../../etc/passwd`），`timedatectl` 失败回退软链接 + 写 `/etc/timezone`。仅在真正改动时写日志（旧实现取消也记「已更改」）。
- G18 修正文档与代码不一致：`implementation-status.md` 标记为「后续」，而 `system tuning apply` 早已支持 `high/balanced/web/stream/game/db` 六个场景，本批改为如实标注。
- `tests/run_checks.sh` 回归检查由 94 项扩到 153 项，新增第 16 节：帮助分发（9 模块 + 13 组别名 + 两种写法逐字节一致 + 条目数不少于 100）、未知子命令（rc=2 且不渲染菜单、help 参数不被误伤）、配置键闭环（每个键都有读取点、声明了不受控设置、不再含装饰性的 `auto_update`）、`general.color=false` 清空 ANSI、时区预设数量与校验函数、发布版本号在五处一致。全部在非 root / 无 Docker / 无网络下可跑。
- CI 增加发布版本一致性检查步骤（`version.txt` / `src/init.sh` / README / Pages / 实施状态）；GitHub 侧另有完整套件 job（bash 217 项 + Python 697 项），而本仓库按既有约定只随仓库发布 `tests/run_checks.sh`。
- 验证：Linux 验证服务器（Ubuntu 24.04）完整回归通过——bash 217 项（42 基础 + 145 帮助/配置 + 30 隐私统计）与 Python 697 项（31 个测试模块）全部 OK、零失败；另有真机 CLI 验收 95 项全过（三种等价帮助写法逐字节一致、13 组别名、未知模块 rc=1、未知子命令 rc=2 且不进菜单、`help panels` 0 秒返回、29 城市时区菜单设置与非法值拒绝后原时区已恢复、`color=false` 关闭全部 ANSI）。
- 未变：受环境限制仍未验证的项（真实容器生命周期、真实 ACME 签发、两主机集群、TG/CF 真实凭据）与明确不做的四项（KPanel、广告联盟、一键 DD、受管模板追数量）保持原状，本批不声称任何新增的外部集成完成度。

## v1.36.2 修复发布附件上传

- 修复 CNB `tag_push` 的 `upload-release-attachments` 阶段必失败的问题：`cnbcool/attachments` 插件按 Tag 查找 Release（日志 `目标 RELEASE / 获取 release id`），而仓库此前从未创建 Release，插件直接 404 退出，`FusionBox-*.tar.gz` 与 `SHA256SUMS` 无法成为发布附件。
- `tag_push` 流水线新增 `create-release` 阶段（内置任务 `git:release`，描述取自 `docs/CHANGELOG.md`，标记 `latest`），置于 `package` 之后、上传附件之前，使附件有目标 Release 可挂。
- `tests/run_checks.sh` 回归检查由 93 项扩展至 94 项：新增「先建 Release 再上传附件」顺序断言。
- 版本号、README、`docs/implementation-status.md`、`docs/index.html` 同步到 1.36.2。

## v1.36.1 修复 tag_push 发布流水线

- 修复 CNB `tag_push` 发布流水线 `validate-version` 阶段必失败的问题：默认 Runner 的 shell 是 `sh`（dash），而脚本使用了 bash 专属的 `[[ ... ]]`，实测报 `sh: 4: [[: not found` 后直接退出，导致 Tag 推送无法产出发布资产。
- 将 `validate-version` 与 `package` 脚本改写为 POSIX `sh` 兼容（`case` 做格式校验、`[ ... ]` 做比较、`set -eu` 不依赖 `pipefail`），版本一致性校验逻辑不变。
- `tests/run_checks.sh` 回归检查由 90 项扩展至 93 项：新增「CI 显式指定镜像」「tag_push 段落不含 bash 专属语法」「版本校验用 POSIX case」三项，防止回退。
- 版本号、README、`docs/implementation-status.md`、`docs/index.html` 同步到 1.36.1。

## v1.36.0 备份/恢复报错中文化、建议清单收尾

- 备份与恢复的全部用户可触达报错改为中文并给出下一步，不再暴露英文技术串：未知备份范围、备份文件重名、恢复冲突（abort 策略下目标已存在）、备份中不含所请求范围、备份源在快照期间变化、归档校验失败等。
- 顶层报错前缀统一为「备份操作失败:」；`--require-all-scopes` 严格模式的失败信息同步中文化（此前为英文 `No backup sources for scope`）。
- 严格模式语义不变：`--require-all-scopes` 仍对任一空范围硬失败；默认路径仍跳过空范围、仅全部为空时失败。
- `tests/run_checks.sh` 回归检查由 83 项扩展至 90 项：新增 7 项覆盖中文报错与顶层前缀（未知范围、严格模式、重名、范围缺失、abort 冲突、无英文前缀残留）。
- 完成 1.34.0 优先改进清单第 9 项（发布版本与 main 对齐）：`v1.36.0` Tag 与 `version.txt`、`src/init.sh` 的 `FUSION_VER` 三处一致，CNB 侧 `tag_push` 流水线据此校验并打包 `FusionBox-v1.36.0.tar.gz` + `SHA256SUMS` 作为发布附件。
- 修复 CNB 流水线 `syntax` 阶段必失败的问题：该阶段原先依赖默认 Runner 镜像提供 `python3`，而默认镜像没有，`python3 -m py_compile` 直接返回 127，导致 main 与 PR 的 CNB CI 从未真正通过。现为 `main`/`pull_request` CI 与 `tag_push` 发布流水线显式指定 `python:3.11` 镜像，并设 `PYTHONDONTWRITEBYTECODE=1`。
- 版本号、README、`docs/implementation-status.md`、`docs/index.html` 同步到 1.36.0。

## v1.35.0 更新变更摘要、阶段进度与 SSH 常驻工作区

- `fusionbox update` 成功更新后展示本次版本的变更摘要：从已校验的归档内 `docs/CHANGELOG.md` 精确截取目标版本段落；版本段落缺失或文件不存在时给出「未提供变更说明」提示，不静默失败。
- 新增可复用的阶段进度反馈：`progress_begin` / `progress_step` / `progress_end`，输出 `[n/总数] 阶段名`。LNMP 安装接入 4 个阶段；受管应用安装在调用前说明「校验端口 → 拉取镜像 → 创建容器 → 等待健康检查」，如实反映慢在哪，不伪造无法观测的百分比。
- 工作区升级为 SSH 常驻重连：`fusionbox ws w3` 在槽位不存在时自动创建并进入（断线重登永远回到同一编号）；新增 `ws w<n> ensure|resume` 显式确保存在、`ws w<n> ssh` 打印重连方法；菜单与帮助同步。
- `tests/run_checks.sh` 回归检查由 59 项扩展至 71 项：新增更新变更摘要截取、阶段进度输出格式、工作区常驻入口与自愈创建三组覆盖。
- 长任务阶段反馈扩展到 Docker 安装（`[1/4] 安装 Docker 引擎`…`[4/4] 校验 docker 与 compose`）与代理核心安装（下载 → 安装 → 建服务 → 校验），此前仅 LNMP 安装有阶段计数。
- 新增 CNB 侧流水线 `.cnb.yml`：`main` 与 PR 跑语法检查 + `tests/run_checks.sh` 回归；`tag_push` 校验 Tag 与 `version.txt`/`src/init.sh` 一致后打包 `FusionBox-vX.Y.Z.tar.gz` 与 `SHA256SUMS` 并作为 release 附件上传，使本仓库托管在 CNB 时有真实 CI 与可同步的发布产物。
- 回归检查由 71 项扩展至 83 项：新增 Docker/代理安装阶段接入、阶段结束复位与 8 个新 i18n 键的中英同步校验。
- 版本号、README、`docs/implementation-status.md`、`docs/index.html` 同步到 1.35.0。

## v1.34.0 首次使用体验修复与依赖前置检查

- 修复 `market.sh` 中 `2>/dev/null` 吞掉 python3 缺失错误导致的误导提示「不支持的受管应用 ID」；缺 python3 时现在给出中文原因与安装命令。
- 新增全局依赖自检：主菜单与 `fusionbox status` 显示 python3 / docker / docker compose v2 / curl 状态与受影响功能；`_require_python3`、`_require_docker_compose` 等守卫覆盖备份/恢复、用户与 SSH 管理、受管市场等 50+ 调用点。
- 修复全新机器 `system backup` 必然失败：不存在的 scope 跳过并中文提示，全部为空才失败；新增 `--require-all-scopes` 恢复严格模式。
- 受管市场新增 Docker/Compose v2 前置检查，缺依赖时给出中文原因与安装命令，不再以「输出已隐藏」掩盖根因。
- `market managed`、`panels compose-backup`、`panels docker-migration` 无参时输出中文帮助，不再暴露英文 argparse 堆栈。
- 受管应用菜单文案改为从 catalog 动态读取数量，并修正为「受管应用生命周期」；README 同步。
- `en.sh` 鸣谢串补英文翻译；`status` 与应用信息同时显示可用核数与宿主核数（容器内不再误报宿主核数）。
- 缺 `ping` 等可选命令时给出安装建议，不再只报「未找到」。
- 重新纳入 `tests/run_checks.sh` CI 回归检查（59 项）：覆盖依赖前置检查、空 scope 跳过、无参中文帮助、i18n 英文环境、CPU 口径、编号工作区槽位归一化与新入口；此前 v1.24.2 移出仓库的 `tests/` 仅供 CI 使用，不含本地/验证服务器专用用例。
- 修复 `show_dependency_status` 与 `show_logs` 未走 i18n 的问题：英文环境不再输出中文依赖自检与日志标题。
- 新增 `fusionbox log`/`system log fusionbox` 日志入口、`fusionbox rescue` 只读救援指引、`fusionbox cluster alias` 中文速查表。
- 编号工作区升级为固定槽位 `w1`-`w10`，支持 tmux/screen 自动选择，可直接 `fusionbox ws w3` 进入、`ws w3 send/capture` 注入与查看回显。
- `fusionbox help` 增加依赖说明；版本号同步为 1.34.0。

## v1.33.0 OpenSSH 只读预检与破坏性边界

- 新增 `fusionbox system ssh-preflight`：只读运行 `sshd -t/-T`，汇总有效端口、认证策略、授权密钥路径、systemd 服务/socket activation 和当前 TCP listeners；不会写配置、切换版本或 reload 服务。
- 提供候选升级前的配置有效性与监听状态证据；测试服务器 5522 端口真实预检通过，并如实报告 `PermitRootLogin yes`、`PasswordAuthentication yes`，未修改 SSH。
- DD 重装、OpenSSH 候选版本并行启动/切换和自动回滚仍未实现；必须先有专用机器、固定下载摘要、双重确认、救援通道和独立故障演练。
- 预检从主入口绕过日志/统计初始化；服务状态查询失败保留 unknown，`switch_allowed` 恒为 false，不能据此批准版本切换。
- 修复 SSH 进程组在 leader 已退出、子进程忽略 TERM 时的清理；密码 writer 非阻塞且可取消，ASKPASS 仅支持初次密码提示且原子单次消费；known_hosts 通过锁定 FD 读取、检查路径漂移和子命令错误，追加前补 LF。
- Oracle 识别进一步收紧：普通 Oracle DMI 不证明 OCI，metadata 严格验证后仅输出证据类别，状态检查不读取未知登记内容；help/别名均使用只读入口。
- 首页版本说明替换为“累计装机 N 次”；受限 Cloudflare Token 存 GitHub Secrets，持续部署验证公网汇总，缺少凭据时明确失败。累计量为 opt-in 安装标识去重数，详见隐私说明。
- Linux 验证服务器完整回归：42 项基础检查 + 632 项行为测试全部通过、零跳过；另有独立高端口 sshd 11/11 验收，包含无尾换行公钥保留、重复迁移、认证失败与资源清理。ASKPASS 重复提示和孤儿进程使用真实本地子进程测试；未声称真实密码过期/PAM 改密服务器验收。
- 修复全量回归发现的 THP 空快照恢复：原 unit 与当前文件都不存在时不调用 systemctl。本地真实 Worker/D1 写入验证重复 install/heartbeat 只增加一个安装标识；没有向线上库写入测试安装数据。

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
