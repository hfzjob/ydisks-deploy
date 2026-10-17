#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
D="/opt/ydisks-deploy"

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo '请使用 root 执行。' >&2; exit 1; }
[[ -f "$D/docker-compose.yml" && -f "$D/.env" ]] || { echo '未找到部署配置；服务可能已经卸载。'; exit 0; }
dc() { docker compose --env-file "$D/.env" --project-directory "$D" -f "$D/docker-compose.yml" "$@"; }

cat <<'INFO'
即将卸载 Ydisks Deploy 服务。
默认操作会停止并删除 Compose 容器和网络，但会保留：
  - PostgreSQL 数据卷
  - 应用数据卷、浏览器数据卷
  - /opt/ydisks-deploy/.env、数据库备份和部署文件
不会卸载 Docker，也不会影响其他容器。
INFO
read -r -p '输入 UNINSTALL 确认卸载服务：' confirm || true
[[ "${confirm:-}" == UNINSTALL ]] || { echo '已取消卸载。'; exit 0; }

dc down --remove-orphans
rm -f /usr/local/bin/xy
echo '服务容器已卸载，数据与配置保留在 /opt/ydisks-deploy。'

read -r -p '如要永久删除此项目的数据库/应用数据卷及全部备份，请输入 DELETE-DATA（默认保留）：' purge || true
if [[ "${purge:-}" == 'DELETE-DATA' ]]; then
  echo '正在删除本项目数据卷和本地配置……'
  dc down --volumes --remove-orphans || true
  rm -rf -- "$D"
  echo '项目容器、命名数据卷、环境配置及备份已永久删除。'
else
  echo '未删除数据卷、密钥或备份。需要恢复时重新运行一键安装脚本即可。'
fi
