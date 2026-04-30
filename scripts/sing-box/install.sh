#!/usr/bin/env bash
set -euo pipefail

VERSION="1.13.11"
NODE_NAME="${1:-}"
PUBLIC_IP="${2:-}"

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

if [[ -z "$NODE_NAME" ]] || [[ -z "$PUBLIC_IP" ]]; then
    error "用法: sudo bash install.sh <node-name> <public-ip>"
fi

log "node name: $NODE_NAME"
log "public ip: $PUBLIC_IP"
log "sing-box version: $VERSION"

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)
        SING_BOX_ARCH="amd64"
        ;;
    aarch64)
        SING_BOX_ARCH="arm64"
        ;;
    *)
        error "不支持架构: $ARCH"
        ;;
esac

DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-${SING_BOX_ARCH}.tar.gz"

log "系统架构: $ARCH"
log "sing-box包架构: $SING_BOX_ARCH"
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
SECRET_FILE="${CONFIG_DIR}/secrets.env"
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


log "下载并安装sing-box"

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

log "生成或读取密钥文件"

if [[ ! -f "$SECRET_FILE" ]]; then
    KEYPAIR="$("$BIN_LINK" generate reality-keypair)"
    UUID="$("$BIN_LINK" generate uuid)"
    REALITY_PRIVATE_KEY="$(echo "$KEYPAIR" | awk '/PrivateKey/ {print $2}')"
    REALITY_PUBLIC_KEY="$(echo "$KEYPAIR" | awk '/PublicKey/ {print $2}')"
    SHORT_ID="$(openssl rand -hex 8)"
    HY2_PASSWORD="$(openssl rand -base64 24)"
    cat > "$SECRET_FILE" << EOF
UUID=${UUID}
REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}
REALITY_PUBLIC_KEY=${REALITY_PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
HY2_PASSWORD=${HY2_PASSWORD}
EOF

    chown root:root "$SECRET_FILE"
    chmod 0600 "$SECRET_FILE"
else
    log "密钥文件已存在, 复用: $SECRET_FILE"
fi

source "$SECRET_FILE"
log "UUID: $UUID"
log "Reality public key: $REALITY_PUBLIC_KEY"
log "Short ID: $SHORT_ID"

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
                        "server": "www.mirosoft.com",
                        "server_port": 443
                    },
                    "private_key": "${REALITY_PRIVATE_KEY}",
                    "short_id": [
                        "$SHORT_ID"
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
                    "password": "$HY2_PASSWORD"
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

