# 版本说明（面向使用者）

> 本文件是 `fusionbox update` 升级完成后打印的"本次更新内容"，也是 CNB Release 的说明正文。
> 写作约定：只写使用者能感知到的变化与需要做的动作，用书面语；不写审计过程、判级、
> 扫描器结论、验证口径这类维护者内部信息——那些记在 [CHANGELOG.md](CHANGELOG.md)。
> 每个版本一节，节标题必须是 `## vX.Y.Z`（升级提示按版本号截取当前版本那一节）；
> 版本号与 `version.txt` 的一致性由 CI 的"Release version consistency"检查强制。

## v1.43.2

- **面板类一键部署默认只对本机开放**：Halo、KodExplorer、LinkStack、Uptime Kuma、
  Vaultwarden、Memos 部署完成后只监听 `127.0.0.1`，公网地址访问不到。要从外部使用，
  两种做法任选：用 `fusionbox web` 配反向代理并签发 HTTPS 证书后按域名访问；
  或临时用 SSH 隧道 `ssh -L 端口:127.0.0.1:端口 root@服务器` 在本地打开。
  其余一键部署（WordPress、Nextcloud、Discuz、Flarum 等站点类，以及 Emby、Jellyfin
  等局域网媒体服务）保持原来的对外方式，行为未变。
- **密码管理器不再接受陌生人注册**：Vaultwarden 部署后注册功能是关闭的。添加第一个账户时，
  按部署完成时屏幕给出的步骤临时打开注册、建号后再关闭。
- **监控栈模板不再有内置管理员口令**：使用 `templates/docker/monitoring.yml` 前，请在同目录
  的 `.env` 里设置 `GRAFANA_ADMIN_PASSWORD`；没设置时启动会直接报错提示，而不是用默认口令。
  Prometheus 与 Grafana 面板同样只对本机开放。
- **Web 模块生成的站点更规范**：新建站点、反向代理与 HTTPS 配置会带上三类常用安全响应头；
  已废弃的 `X-XSS-Protection` 不再下发。HSTS 需要你自行决定，配置里留有说明。
- **修复**：`fusionbox web` 里的"苹果 CMS 一键部署"此前一直用不上专用镜像，部署出来的是
  一个空的通用 PHP 容器；现在优先使用专用镜像，只有它不可用时才回落到通用方案。
- **遥测更收紧**（遥测默认关闭，需你主动开启才会上报）：上报请求的体积上限与跨域写入
  限制都已加强，统计接口的行为不变。
