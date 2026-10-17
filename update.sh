#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
D="/opt/ydisks-deploy"
RAW="https://raw.githubusercontent.com/hfzjob/ydisks-deploy/main"

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo '请使用 root 执行。' >&2; exit 1; }
[[ -f "$D/.env" && -f "$D/docker-compose.yml" ]] || { echo '未找到已安装的部署配置。' >&2; exit 1; }
dc() { docker compose --env-file "$D/.env" --project-directory "$D" -f "$D/docker-compose.yml" "$@"; }

cat <<'WARN'
即将更新 Ydisks 应用镜像与部署脚本。
1. 更新前会备份 .env 和 PostgreSQL 数据库。
2. 不会删除数据库、应用数据或浏览器数据卷。
3. 更新会重建/重启应用；闲鱼账号在线时可能触发重新申请登录凭证。
WARN
read -r -p '输入 UPDATE 确认继续：' confirm || true
[[ "${confirm:-}" == UPDATE ]] || { echo '已取消更新。'; exit 0; }

STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$D/backups"
chmod 0700 "$D/backups"
cp -p "$D/.env" "$D/backups/env-${STAMP}"
chmod 0600 "$D/backups/env-${STAMP}"

# 确保数据库运行并通过健康检查后再备份。
dc up -d postgres
CID=''
for _ in $(seq 1 60); do
  CID="$(dc ps -q postgres 2>/dev/null || true)"
  if [[ -n "$CID" ]]; then
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CID" 2>/dev/null || true)"
    [[ "$status" == healthy ]] && break
  fi
  sleep 2
done
[[ -n "$CID" ]] || { echo '无法启动 PostgreSQL，停止更新。' >&2; exit 1; }
status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CID" 2>/dev/null || true)"
[[ "$status" == healthy ]] || { echo "PostgreSQL 健康状态为 ${status:-unknown}，停止更新。" >&2; exit 1; }

BACKUP="$D/backups/postgres-${STAMP}.sql.gz"
if dc exec -T postgres sh -ec 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' | gzip -1 > "$BACKUP"; then
  [[ -s "$BACKUP" ]] || { echo '数据库备份文件为空，停止更新。' >&2; exit 1; }
  chmod 0600 "$BACKUP"
  echo "数据库备份完成：$BACKUP"
else
  rm -f "$BACKUP"
  echo '数据库备份失败，停止更新；旧服务不会被更新。' >&2
  exit 1
fi

# 先下载到临时目录，全部成功并通过语法检查后才替换现有脚本。
STAGE="$(mktemp -d /tmp/ydisks-update.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
for f in docker-compose.yml xy update.sh uninstall.sh; do
  echo "下载更新文件：$f"
  curl -4fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 "${RAW}/${f}" -o "$STAGE/$f" || {
    echo "下载 $f 失败；保留当前已安装文件。" >&2; exit 1;
  }
done
bash -n "$STAGE/xy"
bash -n "$STAGE/update.sh"
bash -n "$STAGE/uninstall.sh"
for f in docker-compose.yml xy update.sh uninstall.sh; do
  cp -p "$D/$f" "$D/backups/${f}-${STAMP}" 2>/dev/null || true
  install -m 0644 "$STAGE/$f" "$D/${f}.new"
done
for f in xy update.sh uninstall.sh; do chmod 0750 "$D/${f}.new"; done
for f in docker-compose.yml xy update.sh uninstall.sh; do mv -f "$D/${f}.new" "$D/$f"; done
chmod 0750 "$D/xy" "$D/update.sh" "$D/uninstall.sh"

# compose pull 显式拉取，pull_policy: missing 不影响此处的更新动作。
dc config -q
dc pull app postgres
dc up -d --remove-orphans

echo '更新完成，当前容器状态：'
dc ps
printf '\n提示：可通过 xy 的 ① 查看访问信息，或运行 docker compose logs --tail=100。\n'
