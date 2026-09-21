# hermes / deepseek harness 管理器设计（G69 · A7）

> 状态：**设计稿，未实现**（roadmap A7 的判定：先设计后编码）。本文是实现前的
> 契约基线；实现必须逐条对照，任何偏离都要先改本文。
>
> 本设计依赖真实模型 API 凭据才能验证到「启动并监听」以外的行为（对话、流式
> 输出、用量统计）。凭据就位前，实现范围只到「能装、能起、能探活、能卸载」，
> 其余一律如实标注未验证。

## 0. 定位

harness 管理器管理的是**模型代理/网关类单容器服务**（典型：hermes、deepseek
的本地 harness），它们的特点：

- 无自有数据库，状态 = 配置文件 + 日志（可整目录卷化）
- 上游是模型 API（HTTPS 出站），本地只暴露一个 HTTP 端点
- 凭据（API key）是最高敏感物，权限模型必须显式设计（见 §4）

复用既有受管模型，不新造框架：声明式目录（`market_catalog`）+ 单服务
manifest + `market managed` 生命周期 + G58 访问模式（localhost-direct）+
G59 HTTP 映射（可选）。

## 1. 进程模型：容器，不用 systemd unit

| 维度 | 容器（选定） | systemd unit |
|---|---|---|
| 与既有受管模型一致性 | 完全一致（market v1 生命周期） | 全新事务层 |
| 凭据隔离 | env 注入 + 0700 卷内文件 | unit 文件 0600（root 可读） |
| 升级 | `--service-image` 按服务换镜像 + 恢复 journal | 二进制替换事务 |
| 隔离 | cap_drop ALL / no-new-privileges / 内存上限 | 需另建 systemd 沙箱 |

结论：容器。harness 类应用不出需要宿主特权的运行时行为；若某个具体 harness
要求 systemd（如依赖主机 cgroup 细节），按 high_privilege 路径单列并要求
`I ACCEPT HIGH PRIVILEGE`，不进默认目录。

## 2. 目录条目（契约）

- 镜像 digest 固定，`--service-image` 升级
- 单服务、bridge 网络、`127.0.0.1` 绑定端口（webroot 模式不适用：harness 无
  静态资源，HTTP 映射走 G59 的反代）
- 具名卷两个：`data`（会话/配置状态）、`logs`（可选，默认 local json-file 轮转
  已够用，仅当日志需要宿主侧采集时启用）
- 环境变量白名单：`HERMES_API_BASE` / `HERMES_MODEL` / `HERMES_API_KEY_FILE`
  （key 从文件读，不走 env 明文）
- 健康检查：`CMD-SHELL wget -q -O /dev/null http://127.0.0.1:<port>/<health path>`

## 3. 凭据与权限（本设计的核心）

1. API key 只存在于**受管具名卷内**的 0600 文件，容器内以 `API_KEY_FILE`
   形式引用；安装时由操作者通过 stdin 提供（不进命令行参数、不进 shell 历史）
2. 备份默认**排除凭据卷**（`archive.py` scope 化的既有原则：敏感范围须显式
   选择并确认）；新增 scope 时沿用「可选敏感范围 + 逐项确认」
3. `uninstall` 保留 `data` 卷（与市场一致），**凭据卷显式询问**：默认保留、
   `--purge-secrets` 才删
4. `domain`/TLS 暴露（G59）对 harness 类应用默认拒绝——模型端点面向局域网
   工具链而非公网；确需公网时走 high_privilege 确认流程

## 4. 生命周期与升级

- 安装：preflight（端口/磁盘/镜像）→ 拉镜像 → 写 compose → up → 健康门禁
- 升级：结构性变更拒绝（既有原则）；`--service-image` 事务 + 失败恢复上一镜像
- 卸载：保留 `data`；凭据卷显式询问
- 卸载后残留检查：容器、卷、登记三处一致（既有 `resources()` 反向校验复用）

## 5. 验收口径（L1–L4 分层验收，实现时逐条对照）

| 层级 | 内容 | 凭据要求 |
|---|---|---|
| L1 | 安装/健康/HTTP 200/卸载/数据保留/重装 | 不需要 |
| L2 | 配置热加载、日志轮转、用量端点 | 不需要 |
| L3 | 真实对话请求、流式输出、上游错误透传、用量统计 | **需要真实 key** |
| L4 | 多 harness 共存、端口冲突、故障注入 | 不需要 |

发布说明只允许声称已达到的层级；L3 未验证前，任何「已支持 hermes」的表述
都视为过度声明。

## 6. 明确不做

- 不做模型 key 的托管轮换/代理聚合（安全责任不可由本工具承担）
- 不做多租户/计费
- 不做 WebUI 的反向注入（WebUI 归 harness 自身；FusionBox 只做反代与 TLS）
