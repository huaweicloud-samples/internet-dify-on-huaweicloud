# ============================================================================
# 输出
# ============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = huaweicloud_vpc.main.id
}

output "subnet_az_a_id" {
  description = "可用区 a 子网 ID"
  value       = huaweicloud_vpc_subnet.az_a.id
}

output "subnet_az_b_id" {
  description = "可用区 b 子网 ID"
  value       = huaweicloud_vpc_subnet.az_b.id
}

output "rds_address" {
  description = "RDS PostgreSQL 内网地址"
  value       = huaweicloud_rds_instance.postgres.private_ips[0]
}

output "rds_port" {
  description = "RDS PostgreSQL 端口"
  value       = huaweicloud_rds_instance.postgres.db[0].port
}

output "redis_address" {
  description = "DCS Redis 内网地址"
  value       = huaweicloud_dcs_instance.redis.private_ip
}

output "obs_bucket" {
  description = "OBS 桶名"
  value       = huaweicloud_obs_bucket.assets.bucket
}

output "obs_endpoint" {
  description = "OBS 内网端点"
  value       = "obs.${var.region}.myhuaweicloud.com"
}

output "cce_cluster_id" {
  description = "CCE 集群 ID"
  value       = huaweicloud_cce_cluster.main.id
}

output "cluster_api_eip" {
  description = "集群 API 公网地址"
  value       = huaweicloud_vpc_eip.cluster_api.address
}

output "elb_public_ip" {
  description = "入口 ELB 公网地址（由 Ingress 注解自动创建的独享型 ELB 分配）"
  value       = "由 src/manifests/08-ingress.yaml 中 kubernetes.io/elb.autocreate 自动创建，创建后于 ELB 控制台查看"
}

output "kube_config_raw" {
  description = "CCE kubeconfig（敏感，请妥善保管）"
  value       = huaweicloud_cce_cluster.main.kube_config_raw
  sensitive   = true
}
