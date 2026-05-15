#!/usr/bin/env bash
set -euo pipefail

# 配置项
VERSION="1.13.11"
ARCH="linux-amd64"

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"

DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-${ARCH}.tar.gz"
TMP_DIR="/tmp/sing-box-install"
TARGET_FILE="${TMP_DIR}/sing-box-${VERSION}-${ARCH}.tar.gz"
BINARY_FILE="${TMP_DIR}/sing-box-${VERSION}-${ARCH}/sing-box"

SERVICE_USER="sing-box"
SERVICE_GROUP="sing-box"

CLIENT_UUID=""
CLIENT_PUBLIC_KEY=""
CLIENT_SHORT_ID=""
PORT="443"
SERVER_NAME="www.microsoft.com"
FINGERPRINT="firefox"
NODE_NAME="$(hostname)-reality"

log() {
    echo "[INFO] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "请以root权限运行, sudo bash $0"
    fi
}

install_dependencies() {
    log "安装依赖"
    apt-get update -qq
    apt-get install -y -qq curl tar ca-certificates
}

create_service_user() {
    if id "${SERVICE_USER}" >/dev/null 2>&1; then
        log "用户 ${SERVICE_USER} 已存在, 跳过创建"
        return
    fi

    useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
}

install_sing_box_binary() {
    log "下载 sing-box"
    rm -rf "${TMP_DIR}"
    mkdir -p "${TMP_DIR}"
    curl -fsSL "${DOWNLOAD_URL}" -o "${TARGET_FILE}"
    tar -xzf "$TARGET_FILE" -C "$TMP_DIR"
    install -m 0755 "${BINARY_FILE}" "${INSTALL_DIR}/sing-box"
    "${INSTALL_DIR}/sing-box" version >/dev/null
}

generate_config() {
    log "创建配置文件"
    if [[ -d "$CONFIG_DIR" && -f "$CONFIG_FILE" ]]; then
        mv "$CONFIG_FILE" "${CONFIG_DIR}/config.json.$(date +%Y%m%d%H%M%S).bak"
    fi
    mkdir -p "$CONFIG_DIR"
    local keypair
    local private_key
    local public_key
    local uuid
    local short_id
    keypair=$(sing-box generate reality-keypair)
    private_key=$(echo "$keypair" | awk 'NR == 1 {print $2}')
    public_key=$(echo "$keypair" | awk 'NR == 2 {print $2}')
    short_id=$(sing-box generate rand 8 --hex) 
    uuid=$(sing-box generate uuid)
    tee "$CONFIG_FILE" >/dev/null << EOF
{
    "log": {
        "level": "info"
    },
    "inbounds": [
        {
            "type": "vless",
            "tag": "reality-in",
            "listen": "0.0.0.0",
            "listen_port": ${PORT},
            "users": [
                {
                    "uuid": "$uuid",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "$SERVER_NAME",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "$SERVER_NAME",
                        "server_port": 443
                    },
                    "private_key": "$private_key",
                    "short_id": [
                        "$short_id"
                    ]
                }
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

    chown root:"$SERVICE_GROUP" "$CONFIG_DIR"
    chmod 0750 "$CONFIG_DIR"
    chown root:"$SERVICE_GROUP" "$CONFIG_FILE"
    chmod 0640 "$CONFIG_FILE"

    CLIENT_PUBLIC_KEY="$public_key"
    CLIENT_UUID="$uuid"
    CLIENT_SHORT_ID="$short_id"
}

generate_system_service() {
    log "创建 system service file: $SERVICE_FILE"
    tee "$SERVICE_FILE" >/dev/null << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
ExecStartPre=${INSTALL_DIR}/sing-box check -c ${CONFIG_FILE}
ExecStart=${INSTALL_DIR}/sing-box run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectHome=true
PrivateTmp=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

start_service() {
    log "重载systemd"
    systemctl daemon-reload
    log "开机自启并启动sing-box"
    systemctl enable sing-box.service >/dev/null
    systemctl restart sing-box.service 
    log "sing-box状态"
    if systemctl is-active --quiet sing-box.service; then
        log "sing-box已启动"
    else
        error "sing-box 启动失败"
    fi
}

print_client_config() {
    local server_ip
    local node_link
    server_ip=$(curl -fsSL https://ifconfig.me || true)
    node_link="vless://${CLIENT_UUID}@${server_ip}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME}&fp=${FINGERPRINT}&pbk=${CLIENT_PUBLIC_KEY}&sid=${CLIENT_SHORT_ID}&type=tcp#${NODE_NAME}"

    cat << EOF
    sing-box客户端outbounds配置:
{
    "type": "vless",
    "tag": "$NODE_NAME",
    "server": "$server_ip",
    "server_port": ${PORT},
    "uuid": "$CLIENT_UUID",
    "flow": "xtls-rprx-vision",
    "tls": {
        "enabled": true,
        "server_name": "$SERVER_NAME",
        "utls": {
            "enabled": true,
            "fingerprint": "$FINGERPRINT"
        },
        "reality": {
            "enabled": true,
            "public_key": "$CLIENT_PUBLIC_KEY",
            "short_id": "$CLIENT_SHORT_ID"
        }
    }
}
    vless-reality链接:
${node_link}
EOF

}

main() {
    require_root
    create_service_user
    install_dependencies
    install_sing_box_binary
    generate_config
    generate_system_service
    start_service
    print_client_config
}

main "$@"