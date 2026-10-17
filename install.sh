#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

REPO_RAW="https://raw.githubusercontent.com/hfzjob/ydisks-deploy/main"
APP_DIR="/opt/ydisks-deploy"
BIN_LINK="/usr/local/bin/xy"
STAGE=""

info() { printf '\033[1;36m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }
cleanup() { [[ -z "$STAGE" ]] || rm -rf "$STAGE"; }
trap cleanup EXIT

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 执行：sudo -i 后再运行一键安装命令。"
[[ -r /etc/os-release ]] || die "无法识别系统版本。"
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) die "当前脚本支持 Ubuntu / Debian；识别到系统：${PRETTY_NAME:-unknown}" ;;
esac
case "$(uname -m)" in
  x86_64|aarch64|arm64) ;;
  *) die "暂不支持当前 CPU 架构：$(uname -m)。上游镜像主要支持 amd64/arm64。" ;;
esac

printf '\n========== Ydisks Deploy 一键部署 ==========\n'
printf '1) 中国大陆服务器：优先尝试国内镜像代理（代理可用性不保证）\n'
printf '2) 海外服务器：使用官方 GHCR / Docker Hub 镜像\n'
printf '请选择部署环境 [1/2，默认 1]：'
read -r REGION || REGION=1
REGION="${REGION:-1}"
[[ "$REGION" == 1 || "$REGION" == 2 ]] || die "无效选项，请输入 1 或 2。"

# 提前装好基础工具。国内模式使用阿里云 Docker CE 软件仓库；海外模式使用官方仓库。
if ! command -v curl >/dev/null 2>&1 || [[ ! -s /etc/ssl/certs/ca-certificates.crt ]] || \
   ! command -v python3 >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl gnupg python3 openssl
fi
command -v curl >/dev/null 2>&1 || die "curl 安装失败。"

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    info "已检测到 Docker 与 Compose v2，跳过 Docker 安装。"
    systemctl enable --now docker >/dev/null 2>&1 || true
    docker info >/dev/null 2>&1 || die "已检测到 Docker 与 Compose v2，但 Docker 守护进程不可用。请检查：systemctl status docker"
    return
  fi

  info "正在配置 Docker 软件源并安装 Docker Engine / Compose v2。"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings

  local repo_base
  if [[ "$REGION" == 1 ]]; then
    repo_base="https://mirrors.aliyun.com/docker-ce/linux/${ID}"
  else
    repo_base="https://download.docker.com/linux/${ID}"
  fi

  if ! curl -4fsSL --connect-timeout 10 --max-time 60 "${repo_base}/gpg" -o /etc/apt/keyrings/docker.asc; then
    if [[ "$REGION" == 1 ]]; then
      warn "阿里云 Docker CE 软件源不可用，切换到 Docker 官方软件源。"
      repo_base="https://download.docker.com/linux/${ID}"
      curl -4fsSL --connect-timeout 10 --max-time 60 "${repo_base}/gpg" -o /etc/apt/keyrings/docker.asc || die "Docker GPG 密钥下载失败。请检查网络后重试。"
    else
      die "Docker GPG 密钥下载失败。请检查网络后重试。"
    fi
  fi
  chmod 0644 /etc/apt/keyrings/docker.asc
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] %s %s stable\n' \
    "$(dpkg --print-architecture)" "$repo_base" "${VERSION_CODENAME:?系统未提供 VERSION_CODENAME}" \
    > /etc/apt/sources.list.d/docker.list

  if ! apt-get update; then
    if [[ "$REGION" == 1 && "$repo_base" == https://mirrors.aliyun.com/* ]]; then
      warn "国内 Docker 软件源索引获取失败，自动切换官方 Docker 软件源。"
      repo_base="https://download.docker.com/linux/${ID}"
      curl -4fsSL --connect-timeout 10 --max-time 60 "${repo_base}/gpg" -o /etc/apt/keyrings/docker.asc || die "官方 Docker GPG 密钥下载失败。"
      chmod 0644 /etc/apt/keyrings/docker.asc
      printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] %s %s stable\n' \
        "$(dpkg --print-architecture)" "$repo_base" "${VERSION_CODENAME}" \
        > /etc/apt/sources.list.d/docker.list
      apt-get update || die "国内及官方 Docker 软件源都无法更新。"
    else
      die "Docker 软件源索引获取失败，请检查网络或系统软件源。"
    fi
  fi

  if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    if [[ "$REGION" == 1 && "$repo_base" == https://mirrors.aliyun.com/* ]]; then
      warn "国内 Docker 软件源未能完成安装，自动切换官方 Docker 软件源。"
      repo_base="https://download.docker.com/linux/${ID}"
      curl -4fsSL --connect-timeout 10 --max-time 60 "${repo_base}/gpg" -o /etc/apt/keyrings/docker.asc || die "官方 Docker GPG 密钥下载失败。"
      chmod 0644 /etc/apt/keyrings/docker.asc
      printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] %s %s stable\n' \
        "$(dpkg --print-architecture)" "$repo_base" "${VERSION_CODENAME}" \
        > /etc/apt/sources.list.d/docker.list
      apt-get update || die "官方 Docker 软件源索引更新失败。"
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || die "Docker 安装失败。"
    else
      die "Docker 安装失败，请检查软件源和系统版本。"
    fi
  fi
  systemctl enable --now docker
  docker version >/dev/null || die "Docker Engine 安装后无法运行。"
  docker compose version >/dev/null || die "Docker Compose v2 未正确安装。"
}

# 从本仓库当前 main 分支下载部署资产，支持 bash <(curl ...) 这种入口。
STAGE="$(mktemp -d /tmp/ydisks-deploy.XXXXXX)"
fetch_asset() {
  local f="$1"
  info "下载部署文件：$f"
  curl -4fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
    "${REPO_RAW}/${f}" -o "${STAGE}/${f}" || die "下载 ${f} 失败，请确认 GitHub Raw 可访问后重试。"
}
for f in docker-compose.yml xy update.sh uninstall.sh; do fetch_asset "$f"; done
bash -n "${STAGE}/xy"
bash -n "${STAGE}/update.sh"
bash -n "${STAGE}/uninstall.sh"

install_docker

mkdir -p "$APP_DIR/backups"
chmod 0700 "$APP_DIR" "$APP_DIR/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -f "$APP_DIR/.env" ]]; then
  cp -p "$APP_DIR/.env" "$APP_DIR/backups/env-before-install-${STAMP}"
  chmod 0600 "$APP_DIR/backups/env-before-install-${STAMP}"
  info "检测到已有 .env，备份旧配置并保留数据库密码、管理员密码及数据密钥。"
fi

# 先将部署文件安装到临时路径，再原子替换；不会覆盖 .env 或数据库卷。
for f in docker-compose.yml xy update.sh uninstall.sh; do
  install -m 0644 "${STAGE}/${f}" "${APP_DIR}/${f}.new"
done
install -m 0750 "${STAGE}/xy" "$APP_DIR/xy.new"
install -m 0750 "${STAGE}/update.sh" "$APP_DIR/update.sh.new"
install -m 0750 "${STAGE}/uninstall.sh" "$APP_DIR/uninstall.sh.new"
for f in docker-compose.yml xy update.sh uninstall.sh; do mv -f "${APP_DIR}/${f}.new" "${APP_DIR}/${f}"; done
chmod 0750 "$APP_DIR/xy" "$APP_DIR/update.sh" "$APP_DIR/uninstall.sh"

ask_port() {
  local default_port="$1"
  local answer port

  # 提示文字写入标准错误，不能混入 PORT 的返回值
  printf 'Web 访问端口 [1024-65535，默认 %s]：' "$default_port" >&2

  read -r answer || answer="$default_port"
  answer="${answer:-$default_port}"

  # 只允许 1-5 位十进制数字
  [[ "$answer" =~ ^[0-9]{1,5}$ ]] || die "端口必须是 1024-65535 范围内的数字。"

  # 强制按十进制解析，避免 08080 被 Bash 当作八进制
  port=$((10#$answer))

  (( port >= 1024 && port <= 65535 )) ||
    die "端口范围必须为 1024-65535。"

  # 标准输出只返回纯数字
  printf '%s' "$port"
}

set_env() {
  local key="$1" value="$2" file="$APP_DIR/.env" tmp="$APP_DIR/.env.tmp"
  if [[ -f "$file" ]] && grep -q "^${key}=" "$file"; then
    awk -v k="$key" -v v="$value" 'BEGIN{done=0} index($0,k"=")==1 && !done {print k"="v; done=1; next} {print} END{if(!done) print k"="v}' "$file" > "$tmp"
  else
    { [[ ! -f "$file" ]] || cat "$file"; printf '%s=%s\n' "$key" "$value"; } > "$tmp"
  fi
  mv -f "$tmp" "$file"
  chmod 0600 "$file"
}
val_env() { local key="$1"; [[ -f "$APP_DIR/.env" ]] && sed -n "s/^${key}=//p" "$APP_DIR/.env" | head -n1 || true; }

DEFAULT_PORT="$(val_env XIANYU_HTTP_PORT)"
DEFAULT_PORT="${DEFAULT_PORT:-59188}"

# 兼容上次安装留下的错误端口值
if [[ ! "$DEFAULT_PORT" =~ ^[0-9]{1,5}$ ]] ||
   (( 10#$DEFAULT_PORT < 1024 || 10#$DEFAULT_PORT > 65535 )); then
  warn "现有 .env 中的 XIANYU_HTTP_PORT 无效，将回退到默认端口 59188。"
  DEFAULT_PORT=59188
fi

PORT="$(ask_port "$DEFAULT_PORT")"
# Force IPv4 host binding even if an old .env contained 127.0.0.1 or an IPv6 address.
if [[ ! -f "$APP_DIR/.env" ]]; then
  command -v openssl >/dev/null 2>&1 || { apt-get update && apt-get install -y openssl; }
  DB_PASSWORD="$(openssl rand -hex 24)"
  ADMIN_PASSWORD="$(openssl rand -hex 18)"
  DATA_KEY="$(openssl rand -hex 32)"
  cat > "$APP_DIR/.env" <<ENV
COMPOSE_PROJECT_NAME=ydisks-deploy
POSTGRES_DB=xianyu
POSTGRES_USER=xianyu
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_IMAGE=postgres:17-trixie
DATABASE_URL=postgres://xianyu:${DB_PASSWORD}@postgres:5432/xianyu?sslmode=disable
XIANYU_IMAGE=ghcr.io/christ9038/ydisks-xianyu-helper:latest
XIANYU_DATA_KEY=${DATA_KEY}
XIANYU_ADMIN_PASSWORD=${ADMIN_PASSWORD}
XIANYU_BIND_ADDRESS=0.0.0.0
XIANYU_HTTP_PORT=${PORT}
XIANYU_UPLOAD_DIR=/app/data/uploads
TZ=Asia/Shanghai
LOG_LEVEL=info
LOG_FORMAT=json
BROWSER_HEADLESS=true
XIANYU_CONTINUE_AFTER_UNCERTAIN=1
ENV
  chmod 0600 "$APP_DIR/.env"
fi
set_env COMPOSE_PROJECT_NAME ydisks-deploy
set_env XIANYU_BIND_ADDRESS 0.0.0.0
set_env XIANYU_HTTP_PORT "$PORT"
for required_key in POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD DATABASE_URL XIANYU_ADMIN_PASSWORD XIANYU_DATA_KEY; do
  [[ -n "$(val_env "$required_key")" ]] || die "现有 .env 缺少必需配置 ${required_key}。为避免破坏现有数据库，请先检查 ${APP_DIR}/.env。"
done
value="$(val_env TZ)"; set_env TZ "${value:-Asia/Shanghai}"
value="$(val_env XIANYU_UPLOAD_DIR)"; set_env XIANYU_UPLOAD_DIR "${value:-/app/data/uploads}"
value="$(val_env LOG_LEVEL)"; set_env LOG_LEVEL "${value:-info}"
value="$(val_env LOG_FORMAT)"; set_env LOG_FORMAT "${value:-json}"
value="$(val_env BROWSER_HEADLESS)"; set_env BROWSER_HEADLESS "${value:-true}"
value="$(val_env XIANYU_CONTINUE_AFTER_UNCERTAIN)"; set_env XIANYU_CONTINUE_AFTER_UNCERTAIN "${value:-1}"

# 国内模式分别使用公开 GHCR / Docker Hub 镜像代理；每次先实拉校验，失败时自动尝试下一源。
if [[ "$REGION" == 1 ]]; then
  APP_CANDIDATES=(
    "ghcr.nju.edu.cn/christ9038/ydisks-xianyu-helper:latest"
    "ghcr.linkos.org/christ9038/ydisks-xianyu-helper:latest"
    "ghcr.io/christ9038/ydisks-xianyu-helper:latest"
  )
  DB_CANDIDATES=(
    "docker.m.daocloud.io/library/postgres:17-trixie"
    "docker.1ms.run/library/postgres:17-trixie"
    "postgres:17-trixie"
  )
else
  APP_CANDIDATES=("ghcr.io/christ9038/ydisks-xianyu-helper:latest")
  DB_CANDIDATES=("postgres:17-trixie")
fi

pull_first_available() {
  local kind="$1" candidate
  shift
  for candidate in "$@"; do
    info "尝试拉取 ${kind} 镜像：${candidate}" >&2
    if timeout 600 docker pull "$candidate" >&2; then
      printf '%s' "$candidate"
      return 0
    fi
    warn "镜像拉取失败，继续尝试下一个来源：${candidate}"
  done
  return 1
}
# 捕获输出时将诊断信息留在 stderr，防止污染镜像名称变量。
APP_IMAGE="$(pull_first_available '应用' "${APP_CANDIDATES[@]}")" || die "所有应用镜像来源都拉取失败。服务未启动；可稍后重试或选择海外网络。"
DB_IMAGE="$(pull_first_available 'PostgreSQL' "${DB_CANDIDATES[@]}")" || die "所有 PostgreSQL 镜像来源都拉取失败。服务未启动；可稍后重试。"
set_env XIANYU_IMAGE "$APP_IMAGE"
set_env POSTGRES_IMAGE "$DB_IMAGE"

# 自动识别公网 IPv4；未能识别时不阻断安装，之后可用 xy 查看并手动确认。
PUBLIC_IPV4=""
for endpoint in https://api.ipify.org https://ipv4.icanhazip.com; do
  candidate="$(curl -4fsS --connect-timeout 4 --max-time 8 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ "$candidate" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && \
     python3 -c 'import ipaddress,sys; ip=ipaddress.ip_address(sys.argv[1]); sys.exit(0 if ip.version==4 and ip.is_global else 1)' "$candidate" 2>/dev/null; then
    PUBLIC_IPV4="$candidate"; break
  fi
done
# 即使本次探测失败也清空旧地址，避免 xy 显示已过期的公网 IPv4。
set_env PUBLIC_IPV4 "$PUBLIC_IPV4"

DC=(docker compose --env-file "$APP_DIR/.env" --project-directory "$APP_DIR" -f "$APP_DIR/docker-compose.yml")
"${DC[@]}" config -q || die "Compose 配置验证失败，请检查 ${APP_DIR}/.env。"

# 若常见主机防火墙已启用，只添加 IPv4 放行规则；不会启用防火墙或改写现有默认策略。
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
  ufw allow in proto tcp from 0.0.0.0/0 to any port "$PORT" comment 'Ydisks IPv4 HTTP' >/dev/null || warn "UFW 规则添加失败，请手工放行 IPv4 TCP ${PORT}。"
fi
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" port port=\"${PORT}\" protocol=\"tcp\" accept" >/dev/null || warn "firewalld IPv4 规则添加失败。"
  firewall-cmd --reload >/dev/null || true
fi

info "正在启动服务（不删除既有数据卷）……"
"${DC[@]}" up -d --remove-orphans

# 等待健康检查最多约 2 分钟。
HEALTHY=0
for _ in $(seq 1 60); do
  CID="$("${DC[@]}" ps -q app 2>/dev/null || true)"
  if [[ -n "$CID" ]]; then
    H="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CID" 2>/dev/null || true)"
    if [[ "$H" == healthy ]]; then HEALTHY=1; break; fi
  fi
  sleep 2
done

ln -sfn "$APP_DIR/xy" "$BIN_LINK"
chmod 0750 "$BIN_LINK" 2>/dev/null || true

printf '\n========== 部署结果 ==========\n'
"${DC[@]}" ps
if [[ "$HEALTHY" -eq 1 ]]; then
  info "应用健康检查通过。"
else
  warn "应用尚未通过健康检查；请运行 xy 查看状态/日志，服务仍保留以便排错。"
  "${DC[@]}" logs --tail=80 app || true
fi
printf '\n管理命令：xy\n'
printf '访问端口：%s/tcp（仅显式 IPv4 绑定 0.0.0.0；没有 IPv6 端口映射）\n' "$PORT"
printf '默认管理员用户名：admin\n'
printf '管理员密码：%s\n' "$(val_env XIANYU_ADMIN_PASSWORD)"
printf '地址：'
if [[ -n "$PUBLIC_IPV4" ]]; then printf 'http://%s:%s\n' "$PUBLIC_IPV4" "$PORT"; else printf '未能自动探测公网 IPv4，请执行 xy 查看或检查 VPS 控制台公网 IPv4。\n'; fi
printf '\n安全提示：当前为 HTTP，无 TLS/HTTPS 证书。请勿复用其他网站密码；如需公网长期使用，建议之后通过 VPN 或受信任的 HTTPS 反向代理访问。\n'
printf '闲鱼账号已登录时避免频繁重启，重启可能再次申请登录凭证并触发风控。\n'
