# Claude generated
# 所有节点密钥由 Terraform 控制端统一生成，存入 state，幂等可复用

resource "random_uuid" "hk_uuid" {}
resource "random_uuid" "sg_uuid" {}
resource "random_uuid" "jp_uuid" {}

resource "random_password" "hk_hy2_password" {
  length  = 32
  special = false
}

resource "random_password" "sg_hy2_password" {
  length  = 32
  special = false
}

resource "random_password" "jp_hy2_password" {
  length  = 32
  special = false
}

# byte_length = 8 → 16位 hex，与 openssl rand -hex 8 等效
resource "random_id" "hk_short_id" {
  byte_length = 8
}

resource "random_id" "sg_short_id" {
  byte_length = 8
}

resource "random_id" "jp_short_id" {
  byte_length = 8
}
