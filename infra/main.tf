# ============================================================================
# Dify 实践（华为云）— Terraform 主入口
# 架构：CCE 集群部署 Dify 容器 + RDS for PostgreSQL + DCS Redis + OBS
#        + 对象存储（OBS）+ 弹性负载均衡入口
# 凭据通过环境变量注入，本文件不含任何真实凭据
# ============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "= 1.97.1"
    }
  }

  backend "local" {}
}

provider "huaweicloud" {
  region = var.region
  # AK / SK 从环境变量读取（HW_ACCESS_KEY / HW_SECRET_KEY），不硬编码
}

# ----------------------------------------------------------------------------
# 网络层
# ----------------------------------------------------------------------------

resource "huaweicloud_vpc" "main" {
  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr
}

resource "huaweicloud_vpc_subnet" "az_a" {
  name       = "${var.project_name}-subnet-a"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = var.subnet_az_a_cidr
  gateway_ip = cidrhost(var.subnet_az_a_cidr, 1)
  availability_zone = "${var.region}a"
}

resource "huaweicloud_vpc_subnet" "az_b" {
  name       = "${var.project_name}-subnet-b"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = var.subnet_az_b_cidr
  gateway_ip = cidrhost(var.subnet_az_b_cidr, 1)
  availability_zone = "${var.region}b"
}

# 应用安全组（CCE 节点 + 入口）
resource "huaweicloud_networking_secgroup" "app" {
  name        = "${var.project_name}-sg"
  description = "Dify 实践应用安全组（节点与入口）"
}

resource "huaweicloud_networking_secgroup_rule" "app_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.app.id
}

resource "huaweicloud_networking_secgroup_rule" "app_https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.app.id
}

resource "huaweicloud_networking_secgroup_rule" "app_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.app.id
}

# 数据层安全组（RDS / DCS），仅允许应用安全组访问
resource "huaweicloud_networking_secgroup" "data" {
  name        = "${var.project_name}-data-sg"
  description = "RDS / DCS 安全组"
}

resource "huaweicloud_networking_secgroup_rule" "pg_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_group_id   = huaweicloud_networking_secgroup.app.id
  security_group_id = huaweicloud_networking_secgroup.data.id
}

resource "huaweicloud_networking_secgroup_rule" "redis_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6379
  port_range_max    = 6379
  remote_group_id   = huaweicloud_networking_secgroup.app.id
  security_group_id = huaweicloud_networking_secgroup.data.id
}

# 允许 VPC 内 CCE 节点访问数据层（节点安全组由 CCE 托管，故直接放行 VPC 网段）
resource "huaweicloud_networking_secgroup_rule" "pg_ingress_vpc" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_ip_prefix  = var.vpc_cidr
  security_group_id = huaweicloud_networking_secgroup.data.id
}

resource "huaweicloud_networking_secgroup_rule" "redis_ingress_vpc" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6379
  port_range_max    = 6379
  remote_ip_prefix  = var.vpc_cidr
  security_group_id = huaweicloud_networking_secgroup.data.id
}

# 允许 CCE 容器网段（Pod 源 IP）访问数据层（vpc-router 模式 Pod 不走 VPC 子网 CIDR）
resource "huaweicloud_networking_secgroup_rule" "pg_ingress_pod" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_ip_prefix  = var.container_cidr
  security_group_id = huaweicloud_networking_secgroup.data.id
}

resource "huaweicloud_networking_secgroup_rule" "redis_ingress_pod" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6379
  port_range_max    = 6379
  remote_ip_prefix  = var.container_cidr
  security_group_id = huaweicloud_networking_secgroup.data.id
}

# ----------------------------------------------------------------------------
# 集群 API 公网入口（EIP）
# ----------------------------------------------------------------------------

resource "huaweicloud_vpc_eip" "cluster_api" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "${var.project_name}-cluster-api-bw"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

# ----------------------------------------------------------------------------
# 数据层：RDS for PostgreSQL（Dify 主库 + pgvector 向量库）
# ----------------------------------------------------------------------------

resource "huaweicloud_rds_instance" "postgres" {
  name              = "${var.project_name}-pg"
  flavor            = var.rds_flavor
  vpc_id            = huaweicloud_vpc.main.id
  subnet_id         = huaweicloud_vpc_subnet.az_a.id
  security_group_id = huaweicloud_networking_secgroup.data.id
  availability_zone = ["${var.region}a", "${var.region}b"]

  db {
    type     = "PostgreSQL"
    version  = "15"
    password = var.rds_password
    port     = 5432
  }

  volume {
    type = "CLOUDSSD"
    size = 40
  }

  ha_replication_mode = "async"
}

# ----------------------------------------------------------------------------
# 数据层：DCS Redis（Dify 缓存 + Celery 消息代理）
# ----------------------------------------------------------------------------

resource "huaweicloud_dcs_instance" "redis" {
  name              = "${var.project_name}-redis"
  engine            = "Redis"
  engine_version    = "7.0"
  capacity          = 2
  flavor            = "redis.single.xu1.large.2"
  vpc_id            = huaweicloud_vpc.main.id
  subnet_id         = huaweicloud_vpc_subnet.az_a.id
  security_group_id = huaweicloud_networking_secgroup.data.id
  availability_zones   = ["${var.region}a"]
  password          = var.dcs_password

  # DCS 更新实例时不支持变更安全组白名单（API 报错 DCS.4872），由创建期已正确绑定，忽略后续漂移
  lifecycle {
    ignore_changes = [security_group_id]
  }
}

# ----------------------------------------------------------------------------
# 存储层：OBS 桶（Dify 文件 / 向量数据集 / 模型产物）
# ----------------------------------------------------------------------------

resource "huaweicloud_obs_bucket" "assets" {
  bucket        = var.obs_bucket_name
  acl           = "private"
  force_destroy = true
  versioning    = true

  tags = {
    project = var.project_name
  }
}

# ----------------------------------------------------------------------------
# 镜像仓库：SWR 组织（容器镜像服务）
# ----------------------------------------------------------------------------

resource "huaweicloud_swr_organization" "main" {
  name = var.swr_organization
}

# ----------------------------------------------------------------------------
# 计算层：CCE 集群（Kubernetes）
# ----------------------------------------------------------------------------

resource "huaweicloud_cce_cluster" "main" {
  name                   = "${var.project_name}-cce"
  cluster_type           = "VirtualMachine"
  flavor_id              = "cce.s1.small"
  vpc_id                 = huaweicloud_vpc.main.id
  subnet_id              = huaweicloud_vpc_subnet.az_a.id
  container_network_type = "vpc-router"
  eip                    = huaweicloud_vpc_eip.cluster_api.address
  description            = "Dify 实践 CCE 集群"
}

# CCE 节点访问 OBS / SWR 的委托
resource "huaweicloud_iam_agency" "cce" {
  name                  = "${var.project_name}-cce-agency"
  description           = "CCE 节点访问 OBS / SWR 的委托"
  duration              = "FOREVER"
  delegated_domain_name = "op_svc_cce"

  project_role {
    project = var.region
    roles = [
      "OBS OperateAccess",
      "SWR Admin",
    ]
  }
}

resource "huaweicloud_cce_node_pool" "main" {
  cluster_id         = huaweicloud_cce_cluster.main.id
  name               = "${var.project_name}-nodepool"
  flavor_id          = var.node_flavor
  initial_node_count = var.node_count
  availability_zone  = "${var.region}a"
  subnet_id          = huaweicloud_vpc_subnet.az_a.id
  password           = var.node_password
  os                 = "Huawei Cloud EulerOS"

  root_volume {
    size       = 40
    volumetype = "SSD"
  }

  data_volumes {
    size       = 100
    volumetype = "SSD"
  }

  # 运行期节点数会被弹性伸缩 / 手动调整，让出所有权
  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
