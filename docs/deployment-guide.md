# 部署指导

> 本文档提供在华为云上落地本实践的端到端步骤。全程使用华为云原生服务与工具，不涉及任何第三方云产品。

## 1. 前置准备

- 已注册华为云账号，并在目标区域（默认 `cn-north-4`）拥有足够配额。
- 本地安装：[Terraform](https://www.terraform.io/)（≥ 1.5）、[kubectl](https://kubernetes.io/docs/tasks/tools/)、[Helm](https://helm.sh/)（可选）。
- 准备访问凭据，并通过环境变量注入（**切勿写入文件**）：

```bash
export HW_ACCESS_KEY="<你的访问密钥 AK>"
export HW_SECRET_KEY="<你的私密访问密钥 SK>"
```

- 配置 `kubectl` 可访问目标 CCE 集群（集群创建后，从控制台或 `huaweicloud` 工具获取 kubeconfig）。

## 2. 部署基础设施

进入 `infra/` 目录，初始化并创建资源：

```bash
cd infra
terraform init
terraform apply -var-file=terraform.tfvars   # 或复制 terraform.tfvars.example 为 terraform.tfvars 后填写
```

`apply` 完成后，记录以下输出（供后续回填）：

```bash
terraform output rds_address      # RDS for PostgreSQL 内网地址
terraform output redis_address    # DCS Redis 内网地址
terraform output obs_bucket       # OBS 桶名
terraform output obs_endpoint     # OBS 内网端点
terraform output elb_public_ip    # 入口 ELB 公网地址
terraform output cce_cluster_id   # CCE 集群 ID
```

## 3. 准备容器镜像（预推 SWR，免 NAT 网关）

集群节点部署在私网子网，为**避免创建 NAT 网关**即可拉取镜像，本交付物已将 `src/manifests/` 全部 5 个清单的镜像地址指向 SWR 同区域内部端点（VPC 内可达，不消耗公网流量）。

| 组件 | 镜像（SWR 路径，需将 `dify-org` 替换为你的 SWR 组织名） |
|---|---|
| api / worker | `swr.cn-north-4.myhuaweicloud.com/dify-org/dify-api:1.13.3` |
| web | `swr.cn-north-4.myhuaweicloud.com/dify-org/dify-web:1.13.3` |
| sandbox | `swr.cn-north-4.myhuaweicloud.com/dify-org/dify-sandbox:latest` |
| plugin-daemon | `swr.cn-north-4.myhuaweicloud.com/dify-org/dify-plugin-daemon:0.5.5-local` |

### 步骤 3.1 预推镜像到 SWR（一次性，在有 docker + 有效 SWR 凭据的机器上执行）

在**本仓库根目录**执行预推脚本（拉取 Docker Hub `langgenius/*` 官方镜像并推送到你的 SWR 组织，同时把清单占位符 `dify-org` 替换为你的组织名）：

```bash
SWR_ORG=<你的 SWR 组织名> REGION=cn-north-4 ./push-images-to-swr.sh
```

脚本完成后，请在 SWR 控制台将该组织下 4 个仓库的**访问类型设为「公开」**——同区域 CCE 节点即可免密拉取，全程无需 NAT 网关。若需保持私有仓库，按脚本末尾提示在 `dify` 命名空间创建 `swr-secret` 并给各 Deployment 增加 `imagePullSecrets`。

> 说明：源镜像来自 Docker Hub；本步骤只需联网拉取一次，之后集群节点全程走 SWR 内网。

## 4. 回填清单占位符

在 `src/manifests/01-configmap.yaml` 中，将以下占位符替换为实际值：

| 占位符 | 替换为 |
|---|---|
| `<替换为 RDS PostgreSQL 内网地址>`（DB_HOST / PGVECTOR_HOST） | `terraform output rds_address` 的值 |
| `<替换为 DCS Redis 内网地址>`（REDIS_HOST） | `terraform output redis_address` 的值 |
| `<替换为 OBS 桶名>`（S3_BUCKET_NAME / PLUGIN_STORAGE_OSS_BUCKET） | `terraform output obs_bucket` 的值 |
| `<替换为访问入口地址，如 https://dify.example.com>`（CONSOLE_API_URL / APP_API_URL 等） | 入口 ELB 公网地址或已绑定域名 |

## 5. 创建敏感凭据

通过 `kubectl` 创建 Secret（**仅本地执行，凭据不入库**）：

```bash
kubectl -n dify create secret generic dify-secrets \
  --from-literal=DB_USERNAME='root' \
  --from-literal=DB_PASSWORD='<你的 RDS 密码>' \
  --from-literal=PGVECTOR_USER='root' \
  --from-literal=PGVECTOR_PASSWORD='<你的 RDS 密码>' \
  --from-literal=REDIS_PASSWORD='<你的 DCS 密码>' \
  --from-literal=S3_ACCESS_KEY='<你的 OBS AK>' \
  --from-literal=S3_SECRET_KEY='<你的 OBS SK>' \
  --from-literal=SECRET_KEY="$(openssl rand -base64 42)" \
  --from-literal=DIFY_INNER_API_KEY="$(openssl rand -base64 32)" \
  --from-literal=PLUGIN_DAEMON_KEY="$(openssl rand -base64 32)" \
  --dry-run=client -o yaml | kubectl apply -f -
```

> 说明：RDS for PostgreSQL 默认管理员账号为 `root`；如实例已自定义账号，请相应调整 `DB_USERNAME` / `PGVECTOR_USER`。

## 6. 部署应用

按依赖顺序应用清单：

```bash
kubectl apply -f src/manifests/00-namespace.yaml
kubectl apply -f src/manifests/01-configmap.yaml
kubectl apply -f src/manifests/02-secrets.yaml
kubectl apply -f src/manifests/03-api.yaml
kubectl apply -f src/manifests/04-worker.yaml
kubectl apply -f src/manifests/05-web.yaml
kubectl apply -f src/manifests/06-sandbox.yaml
kubectl apply -f src/manifests/07-plugin-daemon.yaml
kubectl apply -f src/manifests/08-ingress.yaml
```

## 7. 验证

1. 确认 Pod 全部就绪：

```bash
kubectl -n dify get pods
```

2. 确认入口 ELB 已创建并分配公网地址（控制台「弹性负载均衡」页查看）。

3. 健康检查：

```bash
curl -I http://<ELB 公网地址>/health      # 期望 200
curl -I http://<ELB 公网地址>/e/health/check  # 期望 200
```

4. 浏览器访问 `http://<ELB 公网地址>/`，使用初始化管理员账号（默认邮箱 `admin@dify.ai`，密码为 `INIT_PASSWORD` 设定的 `dify123456`）登录，验证控制台与对话功能。

5. 在控制台「模型供应商」中接入任意模型供应商（平台自有 ModelArts / MaaS / 盘古，或任意 OpenAI 兼容端点），创建应用并测试对话与知识库检索。

> 注意：RDS for PostgreSQL 需提供 `pgvector` 扩展；若实例默认未预装，请在首次部署前由管理员执行 `CREATE EXTENSION IF NOT EXISTS vector;`。

## 8. 清理资源

如不再需要，请按以下顺序回收，避免产生闲置资源：

```bash
kubectl -n dify delete -f src/manifests/08-ingress.yaml
kubectl -n dify delete -f src/manifests/07-plugin-daemon.yaml
kubectl -n dify delete -f src/manifests/06-sandbox.yaml
kubectl -n dify delete -f src/manifests/05-web.yaml
kubectl -n dify delete -f src/manifests/04-worker.yaml
kubectl -n dify delete -f src/manifests/03-api.yaml
```

随后在 `infra/` 目录执行：

```bash
terraform destroy
```

> 控制台中由 Ingress 自动创建的 ELB 会随 Ingress 删除而回收；`terraform destroy` 回收其余托管资源。OBS 桶设置了 `force_destroy`，销毁时会一并清空。
