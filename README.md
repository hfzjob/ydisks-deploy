# Ydisks Deploy

Ydisks-Xianyu-Helper 的 Docker Compose 一键部署脚本，面向 Debian / Ubuntu 的 amd64、arm64 VPS。

## 一键安装

以 root 执行：
国外
```bash
curl -4fsSL https://raw.githubusercontent.com/hfzjob/ydisks-deploy/main/install.sh -o /tmp/ydisks-install.sh && bash /tmp/ydisks-install.sh
```
大陆
```
curl -4fL --connect-timeout 10 --max-time 60 \
  'https://gitee.com/hfzjob/ydisks-deploy/raw/master/install.sh' \
  -o /tmp/ydisks-install.sh \
&& bash -n /tmp/ydisks-install.sh \
&& bash /tmp/ydisks-install.sh
```
首次安装会询问服务器类型：

1. **中国大陆**：优先尝试阿里云 Docker CE 软件源以及国内 GHCR / Docker Hub 镜像代理；镜像站不可用时会自动尝试后备来源。
2. **海外**：使用 Docker 官方软件源、GHCR 官方应用镜像和 Docker Hub 官方 PostgreSQL 镜像。

部署完毕后运行：

```bash
xy
```

菜单支持查看 IPv4 访问网址和管理员密码、重启、卸载、更新（更新前自动备份数据库）。

## 网络与协议

- Web 容器只发布 `0.0.0.0:<端口>`，即显式 IPv4 绑定；Compose 文件没有 IPv6 端口映射。
- PostgreSQL 不发布宿主机端口，只在 Compose 内部网络可访问。
- 此版本不申请、不配置 HTTPS 证书，访问地址为 `http://IPv4:端口`。HTTP 不加密传输登录信息，不要复用其他服务的密码；公网长期使用建议放在 VPN 后，或自行配置受信任的 HTTPS 反向代理。
- 安装程序不会启用主机防火墙；若 UFW / firewalld 已开启，会尝试只添加 IPv4 入站端口规则。VPS 服务商的云防火墙 / 安全组也需要放行该 IPv4 TCP 端口。

## 数据保护

- `.env` 权限为 `600`，包含管理员密码和数据密钥，切勿上传到 GitHub。
- 更新前备份 `.env` 和 PostgreSQL，备份保存在 `/opt/ydisks-deploy/backups`。
- 普通卸载只删除容器与网络，默认保留数据库、应用数据、浏览器数据和备份。
- 只有明确输入 `DELETE-DATA` 才会删除项目数据卷和本地全部配置/备份。该操作不可恢复。
- 务必长期保存 `XIANYU_DATA_KEY`；不要在更新/重启时更改它。
- 原项目提醒：已有闲鱼账号登录时不要频繁重启程序，重启可能再次申请登录凭证并触发风控。

## 仓库文件

- `install.sh`：入口脚本，安装 Docker（必要时）、拉取镜像、创建配置、部署服务、建立 `xy` 命令。
- `docker-compose.yml`：应用 + PostgreSQL Compose 配置，持久化三个命名卷，仅发布 IPv4。
- `xy`：交互式快捷管理菜单。
- `update.sh`：先备份数据库和 `.env`，再更新部署文件与镜像。
- `uninstall.sh`：安全卸载，默认保留数据。
- `README.md`：说明文档。

不再使用 `Caddyfile` 和 `renew-cert.sh`；请从仓库删除这两个旧文件，避免误以为本版本会配置 HTTPS。

## 说明

大陆镜像站由第三方运营，域名、可用性、缓存同步和策略可能变化。脚本会尝试多个来源，但不能保证任何公共代理永久可用；对供应链安全有更高要求时，海外模式应优先使用官方源。
