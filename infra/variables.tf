# ============================================================================
# 变量定义 — Dify 实践（华为云）
# 凭据一律通过环境变量 / terraform.tfvars 注入，文件中只保留占位符
# ============================================================================

variable "region" {
  description = "华为云区域 ID"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "项目名称，用于资源命名前缀"
  type        = string
  default     = "dify-on-huaweicloud"
}

variable "vpc_cidr" {
  description = "VPC 网段"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_az_a_cidr" {
  description = "可用区 a 子网网段"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_az_b_cidr" {
  description = "可用区 b 子网网段"
  type        = string
  default     = "10.0.2.0/24"
}

variable "rds_flavor" {
  description = "RDS PostgreSQL 规格（主备实例规格码必须以 .ha 结尾）"
  type        = string
  default     = "rds.pg.n1.large.2.ha"
}

variable "rds_password" {
  description = "RDS PostgreSQL 管理员密码（请通过 terraform.tfvars 注入，勿硬编码）"
  type        = string
  sensitive   = true
  default     = "Dify@ChangeMe2024"
}

variable "dcs_password" {
  description = "DCS Redis 访问密码（请通过 terraform.tfvars 注入，勿硬编码）"
  type        = string
  sensitive   = true
  default     = "Dify@ChangeMe2024"
}

variable "obs_bucket_name" {
  description = "OBS 桶名（全局唯一，仅含小写字母、数字、连字符）"
  type        = string
  default     = "dify-hwc-practice-assets"
}

variable "node_flavor" {
  description = "CCE 节点池规格（Dify 各组件单 Pod 内存请求约 1Gi，4GiB 节点无法容纳多副本，须使用 ≥8GiB 规格）"
  type        = string
  default     = "s6.xlarge.2"
}

variable "container_cidr" {
  description = "CCE 容器网段（vpc-router 模式，Pod 源 IP 所属 CIDR，需放行至数据层安全组）"
  type        = string
  default     = "172.16.0.0/16"
}

variable "node_password" {
  description = "CCE 节点登录密码（请通过 terraform.tfvars 注入，勿硬编码）"
  type        = string
  sensitive   = true
  default     = "Dify@ChangeMe2024"
}

variable "node_count" {
  description = "CCE 节点池初始节点数"
  type        = number
  default     = 2
}

variable "swr_organization" {
  description = "容器镜像服务（SWR）组织名，用于存放 Dify 镜像"
  type        = string
  default     = "dify-practice"
}
