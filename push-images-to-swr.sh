#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 预推 Dify 镜像到华为云 SWR（免 NAT 网关方案）
#
# 适用场景：集群节点部署在私网子网、不希望为拉取镜像而创建 NAT 网关。
# 做法：本脚本在「有 docker + 有效 SWR 登录凭据」的机器上，把 Docker Hub
#       `langgenius/*` 官方镜像拉取一次并推送到你的 SWR 组织；之后 CCE 节点
#       全程走 SWR 同区域内部端点（swr.<region>.myhuaweicloud.com），VPC 内可达。
#
# 用法：
#   cd <本仓库根目录>
#   SWR_ORG=<你的 SWR 组织名> [REGION=cn-north-4] ./push-images-to-swr.sh
#
# 前置：
#   1. 已安装 docker 且 daemon 可运行
#   2. 已按 SWR 控制台「组织管理 → 我的权限」生成 docker 登录指令并完成登录
#      （登录口令 = 控制台给出的临时密钥，或 AK/SK 派生的登录密钥）
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")"

REGION="${REGION:-cn-north-4}"
SWR_ORG="${SWR_ORG:?请先设置环境变量 SWR_ORG，例如：SWR_ORG=my-org ./push-images-to-swr.sh}"

SWR_SERVER="swr.${REGION}.myhuaweicloud.com"
MANIFESTS_DIR="src/manifests"

# 源镜像（Docker Hub langgenius/*）-> 推送到 SWR 同名仓库
IMAGES=(
  "langgenius/dify-api:1.13.3"
  "langgenius/dify-web:1.13.3"
  "langgenius/dify-sandbox:latest"
  "langgenius/dify-plugin-daemon:0.5.5-local"
)

echo "==> 目标 SWR: ${SWR_SERVER} / 组织: ${SWR_ORG}"

# 登录（若已登录会直接成功）
if ! docker login "${SWR_SERVER}"; then
  echo "docker login 失败：请先按 SWR 控制台提示获取登录密钥并登录"
  echo "  示例：docker login -u ${SWR_ORG}@<AK> -p <登录密钥> ${SWR_SERVER}"
  exit 1
fi

for img in "${IMAGES[@]}"; do
  repo="${img#langgenius/}"     # dify-api:1.13.3
  name="${repo%%:*}"            # dify-api
  tag="${repo##*:}"             # 1.13.3 / latest
  target="${SWR_SERVER}/${SWR_ORG}/${name}:${tag}"
  echo ""
  echo "==> [${name}] 拉取 ${img}"
  docker pull "${img}"
  echo "==> [${name}] 打标签 ${target}"
  docker tag "${img}" "${target}"
  echo "==> [${name}] 推送 ${target}"
  docker push "${target}"
done

echo ""
echo "==> 将清单中的占位符 dify-org 替换为 ${SWR_ORG}"
sed -i '' "s#dify-org#${SWR_ORG}#g" "${MANIFESTS_DIR}"/*.yaml 2>/dev/null \
  || sed -i  "s#dify-org#${SWR_ORG}#g" "${MANIFESTS_DIR}"/*.yaml

echo ""
echo "==> 推送完成。请在 SWR 控制台将该组织下 4 个仓库的「访问类型」设为公开，"
echo "    同区域 CCE 节点即可免密拉取（无需 NAT 网关）。"
echo ""
echo "    若需保持私有仓库，请于 dify 命名空间创建 imagePullSecret 后给各 Deployment"
echo "    加上 imagePullSecrets（脚本不会自动修改清单的拉取凭据）："
echo "      kubectl -n dify create secret docker-registry swr-secret \\"
echo "        --docker-server=${SWR_SERVER} \\"
echo "        --docker-username=${SWR_ORG}/<IAM用户名或AK> \\"
echo "        --docker-password=<SWR登录密钥>"
echo "      # 然后给每个 Deployment 的 spec.template.spec 增加："
echo "      #   imagePullSecrets:"
echo "      #     - name: swr-secret"
