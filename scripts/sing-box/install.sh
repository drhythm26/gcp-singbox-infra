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