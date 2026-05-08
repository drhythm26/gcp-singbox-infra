#!/usr/bin/env bash
# Claude generated — 控制端托管版本，密钥由 Terraform 通过 GCP metadata 注入
set -euo pipefail

VERSION="1.13.11"

log() {
    echo "[INFO] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

if [ "$(id -u)" -ne 0 ]; then
    error "请以root运行"
fi

# 从 GCP metadata server 读取控制端注入的配置
METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance"
MH="Metadata-Flavor: Google"

log "从 GCP metadata 读取节点配置"
NODE_NAME=$(curl -sf -H "$MH" "${METADATA_URL}/attributes/singbox-node-name")
PUBLIC_IP=$(curl -sf -H "$MH" "${METADATA_URL}/network-interfaces/0/access-configs/0/external-ip")
UUID=$(curl -sf -H "$MH" "${METADATA_URL}/attributes/singbox-uuid")
REALITY_PRIVATE_KEY=$(curl -sf -H "$MH" "${METADATA_URL}/attributes/singbox-reality-private-key")
REALITY_PUBLIC_KEY=$(curl -sf -H "$MH" "${METADATA_URL}/attributes/singbox-reality-public-key")
SHORT_ID=$(curl -sf -H "$MH" "${METADATA_URL}/attributes/singbox-short-id")
HY2_PASSWORD=$(curl -sf -H "$MH" "${METADATA_URL}/attributes/singbox-hy2-password")

[[ -z "$NODE_NAME" ]] && error "metadata singbox-node-name 为空"
[[ -z "$PUBLIC_IP" ]] && error "无法读取公网 IP"
[[ -z "$UUID" ]] && error "metadata singbox-uuid 为空"
[[ -z "$REALITY_PRIVATE_KEY" ]] && error "metadata singbox-reality-private-key 为空"
[[ -z "$SHORT_ID" ]] && error "metadata singbox-short-id 为空"
[[ -z "$HY2_PASSWORD" ]] && error "metadata singbox-hy2-password 为空"

log "node name: $NODE_NAME"
log "public ip: $PUBLIC_IP"
log "sing-box version: $VERSION"
log "uuid: $UUID"
log "short id: $SHORT_ID"
log "reality public key: $REALITY_PUBLIC_KEY"

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)  SING_BOX_ARCH="amd64" ;;
    aarch64) SING_BOX_ARCH="arm64" ;;
    *)       error "不支持架构: $ARCH" ;;
esac

DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-${SING_BOX_ARCH}.tar.gz"

log "系统架构: $ARCH / sing-box 架构: $SING_BOX_ARCH"
log "url: $DOWNLOAD_URL"

SERVICE_USER="sing-box"
SERVICE_GROUP="sing-box"
INSTALL_ROOT="/usr/local/sing-box"
RELEASE_DIR="${INSTALL_ROOT}/releases/${VERSION}"
CURRENT_LINK="${INSTALL_ROOT}/current"
BIN_LINK="/usr/local/bin/sing-box"
CONFIG_DIR="/etc/sing-box"
CERT_DIR="${CONFIG_DIR}/certs"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
DATA_DIR="/var/lib/sing-box"

log "创建服务账号及目录"
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --user-group \
        --home-dir "$DATA_DIR" \
        --create-home \
        --shell /usr/sbin/nologin "$SERVICE_USER"
fi

install -d -m 0755 -o root -g root "$INSTALL_ROOT"
install -d -m 0755 -o root -g root "$RELEASE_DIR"
install -d -m 0750 -o root -g "$SERVICE_GROUP" "$CONFIG_DIR"
install -d -m 0750 -o root -g "$SERVICE_GROUP" "$CERT_DIR"
install -d -m 0750 -o "$SERVICE_USER" -g "$SERVICE_GROUP" "$DATA_DIR"

log "下载并安装 sing-box"

TMP_DIR="$(mktemp -d)"
ARCHIVE_FILE="${TMP_DIR}/sing-box.tar.gz"

curl -fsSL "$DOWNLOAD_URL" -o "$ARCHIVE_FILE"
tar -xzf "$ARCHIVE_FILE" -C "$TMP_DIR"

install -m 0755 -o root -g root \
    "${TMP_DIR}/sing-box-${VERSION}-linux-${SING_BOX_ARCH}/sing-box" \
    "${RELEASE_DIR}/sing-box"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"
ln -sfn "${CURRENT_LINK}/sing-box" "$BIN_LINK"
rm -rf "$TMP_DIR"
sing-box version

# HY2 证书在节点本地生成，控制端无需感知（客户端链接用 insecure=1）
log "生成或读取 HY2 自签证书"

if [[ ! -f "${CERT_DIR}/hy2.key" || ! -f "${CERT_DIR}/hy2.crt" ]]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "${CERT_DIR}/hy2.key" \
        -out "${CERT_DIR}/hy2.crt" \
        -days 3650 -subj "/CN=bing.com"
    chown root:"$SERVICE_GROUP" "${CERT_DIR}/hy2.key"
    chmod 0640 "${CERT_DIR}/hy2.key"
    chown root:root "${CERT_DIR}/hy2.crt"
    chmod 0644 "${CERT_DIR}/hy2.crt"
else
    log "HY2 证书已存在, 复用: ${CERT_DIR}/hy2.crt"
fi

log "生成 sing-box 配置文件"
cat > "$CONFIG_FILE" << EOF
{
    "log": {
        "level": "info"
    },
    "inbounds": [
        {
            "type": "vless",
            "tag": "reality-in",
            "listen": "0.0.0.0",
            "listen_port": 443,
            "users": [
                {
                    "uuid": "${UUID}",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "www.microsoft.com",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "www.microsoft.com",
                        "server_port": 443
                    },
                    "private_key": "${REALITY_PRIVATE_KEY}",
                    "short_id": [
                        "${SHORT_ID}"
                    ]
                }
            }
        },
        {
            "type": "hysteria2",
            "tag": "hy2-in",
            "listen": "0.0.0.0",
            "listen_port": 8443,
            "users": [
                {
                    "password": "${HY2_PASSWORD}"
                }
            ],
            "tls": {
                "enabled": true,
                "certificate_path": "${CERT_DIR}/hy2.crt",
                "key_path": "${CERT_DIR}/hy2.key"
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF

chown root:"${SERVICE_GROUP}" "$CONFIG_FILE"
chmod 0640 "$CONFIG_FILE"

log "生成 systemd service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${DATA_DIR}
ExecStart=${BIN_LINK} run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=10s
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=${DATA_DIR}

[Install]
WantedBy=multi-user.target
EOF

chown root:root "$SERVICE_FILE"
chmod 0644 "$SERVICE_FILE"

log "检查配置并启动服务"
sing-box check -c "$CONFIG_FILE"
systemctl daemon-reload
systemctl enable --now sing-box
systemctl restart sing-box
sleep 2
systemctl is-active --quiet sing-box
ss -lntp | grep -q ':443'
ss -lnup | grep -q ':8443'
PROCESS_USER="$(ps -o user= -C sing-box | head -n 1 | xargs)"
if [[ "$PROCESS_USER" != "$SERVICE_USER" ]]; then
    error "sing-box 进程用户异常: $PROCESS_USER"
fi
log "sing-box 服务启动成功 [$NODE_NAME / $PUBLIC_IP]"
