#!/usr/bin/env bash
set -e

VERSION="1.13.11"
ARCH="linux-amd64"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/sing-box"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-${ARCH}.tar.gz"
TMP_DIR="/tmp/sing-box-install"
BINARY_FILE="${TMP_DIR}/sing-box-${VERSION}-${ARCH}/sing-box"
TAR_FILE="${TMP_DIR}/sing-box-${VERSION}-${ARCH}.tar.gz"

log() {
    echo "[INFO] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error "请使用: sudo bash $0"
    fi
}

install_dependencies() {
    log "安装基础依赖"
    apt update
    apt install -y curl tar
}

download_singbox() {
    log "下载 sing-box ${VERSION}"
    rm -rf "${TMP_DIR}"
    mkdir -p "${TMP_DIR}"
    curl -L "${DOWNLOAD_URL}" -o "${TAR_FILE}"
}

install_binary() {
    log "解压并安装 sing-box"
    tar -xzf "${TAR_FILE}" -C "${TMP_DIR}"
    cp "${BINARY_FILE}" "${INSTALL_DIR}/sing-box"
    chmod +x "${INSTALL_DIR}/sing-box"
    log "当前 sing-box 版本"
    sing-box version
}

create_config() {
    log "创建sing-box配置"
    mkdir -p "${CONFIG_DIR}"
    if [[ ! -f "${CONFIG_DIR}/config.json" ]]; then
        log "未发现 config.json, 创建config.json"
    else
        log "config.json文件已存在, 删除config.json"
        rm -rf "${CONFIG_DIR}/config.json"
    fi
    KEYPAIR=$(sing-box generate reality-keypair)
    PRIVATE_KEY=$(echo "${KEYPAIR}" | awk 'NR == 1 {print $2}')
    PUBLIC_KEY=$(echo "${KEYPAIR}" | awk 'NR == 2 {print $2}')
    UUID=$(sing-box generate uuid)
    SHORT_ID=$(sing-box generate rand 8 --hex)
    cat > "${CONFIG_DIR}/config.json" << EOF
{
    "log": {
        "level": "info"
    },
    "inbounds": [
        {
            "type": "vless",
            "tag": "reality-in",
            "listen": "::",
            "listen_port": 443,
            "users": [
                {
                    "uuid": "$UUID",
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
                    "private_key": "${PRIVATE_KEY}",
                    "short_id": [
                        "${SHORT_ID}"
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

    if ! sing-box check -c /etc/sing-box/config.json; then
        error "sing-box config.json 有问题"
}

create_service() {
    log "创建 systemd service 文件"
    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now sing-box.service
    systemctl status --no-pager sing-box.service
}

main() {
    require_root
    install_dependencies
    download_singbox
    install_binary
    create_config
    create_service
    log "安装完成"
}

main "$@"
