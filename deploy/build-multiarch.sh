#!/usr/bin/env bash
# 多架构构建：linux/amd64 + linux/arm64
#
# 用法（在仓库根目录执行）：
#   ./deploy/build-multiarch.sh                     # 只构建并加载到本地（各自架构分别 load 不了，故默认推本地 registry）
#   ./deploy/build-multiarch.sh --push              # 构建并推送到 Docker Hub（需先 docker login）
#   ./deploy/build-multiarch.sh --push --only arm64 # 只做 arm64
#
# 说明：
#   * arm64 在 x86 机器上要靠 QEMU：脚本会检查 binfmt，缺了自动装（需要 root/privileged）。
#   * chromium 由 patchright 自己按架构下载（debian12-arm64 → chrome-headless-shell-linux-arm64），
#     Dockerfile 不需要传架构参数；Dockerfile.slim 里的删除/校验路径已改成通配。
#   * 真正跑起来的多架构发布请用 GitHub Actions（.github/workflows/cn-image.yml），
#     它按架构并行构建、单独拍扁、最后 imagetools 合并 manifest —— 比本地 QEMU 快得多。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DH_USER="${DOCKERHUB_USERNAME:-wangxiangya}"
IMAGE="docker.io/${DH_USER}/ms-rewards-v5"
BUILDER="multiarch"
PLATFORMS="linux/amd64,linux/arm64"
PUSH=0
ONLY=""
LOCAL_REGISTRY=0
REG_PORT=5000

while [ $# -gt 0 ]; do
    case "$1" in
        --push) PUSH=1 ;;
        --only) ONLY="$2"; shift ;;
        --image) IMAGE="$2"; shift ;;
        --local-registry) LOCAL_REGISTRY=1 ;;
        --port) REG_PORT="$2"; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
    shift
done

if [ "$ONLY" = "arm64" ]; then PLATFORMS="linux/arm64"; fi
if [ "$ONLY" = "amd64" ]; then PLATFORMS="linux/amd64"; fi

VERSION="$(node -p "require('./package.json').version")"

echo "== 1/5 检查 QEMU binfmt"
if ! ls /proc/sys/fs/binfmt_misc/ 2>/dev/null | grep -q '^qemu-aarch64$'; then
    echo "   未注册 qemu-aarch64，尝试安装（需要 privileged）"
    docker run --privileged --rm tonistiigi/binfmt --install arm64
else
    echo "   qemu-aarch64 已就绪"
fi

echo "== 2/5 准备 buildx builder: ${BUILDER}"
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
    docker buildx create --name "$BUILDER" --driver docker-container >/dev/null
fi
docker buildx use "$BUILDER"
docker buildx inspect "$BUILDER" --bootstrap >/dev/null

echo "== 3/5 打 cn.bing.com 补丁"
node .github/scripts/patch-bing-origin.js >/dev/null
grep -q 'export function isBingHost' src/constants/urls.ts && echo "   isBingHost 就位"

echo "== 4/5 构建运行时镜像（${PLATFORMS}）"
DOCKERFILE="-f Dockerfile"
if [ "$LOCAL_REGISTRY" = "1" ]; then
    # 国内直连 registry-1.docker.io 常被 IPv6 卡死：先把基础镜像拉下来塞进本机 registry，
    # 再让 buildkit 从 localhost 取，Dockerfile 只替换 FROM 行。
    BASE_IMAGE="node:24-bookworm-slim"
    echo "   --local-registry: 准备 localhost:${REG_PORT} 与基础镜像 ${BASE_IMAGE}"
    if ! docker ps --format '{{.Names}}' | grep -qx 'reg'; then
        docker run -d --name reg -p "127.0.0.1:${REG_PORT}:5000" --restart unless-stopped registry:2 >/dev/null
        sleep 3
    fi
    for P in ${PLATFORMS//,/ }; do
        docker pull --platform "$P" "$BASE_IMAGE" >/dev/null
        docker tag "$BASE_IMAGE" "localhost:${REG_PORT}/${BASE_IMAGE}"
        docker push "localhost:${REG_PORT}/${BASE_IMAGE}" >/dev/null
    done
    if [ ! -f /root/.config/buildkit/buildkitd.toml ]; then
        mkdir -p /root/.config/buildkit
        printf '[registry."localhost:%s"]\n  http = true\n  insecure = true\n' "$REG_PORT" > /root/.config/buildkit/buildkitd.toml
    fi
    sed "s|^FROM ${BASE_IMAGE}|FROM localhost:${REG_PORT}/${BASE_IMAGE}|" Dockerfile > /tmp/Dockerfile.arm64
    DOCKERFILE="-f /tmp/Dockerfile.arm64"
    docker buildx rm "$BUILDER" >/dev/null 2>&1 || true
    docker buildx create --name "$BUILDER" --driver docker-container --driver-opt network=host \
        --config /root/.config/buildkit/buildkitd.toml >/dev/null
    docker buildx use "$BUILDER"
    docker buildx inspect "$BUILDER" --bootstrap >/dev/null
fi

if [ "$PUSH" = "1" ]; then
    docker buildx build --builder "$BUILDER" --platform "$PLATFORMS" \
        $DOCKERFILE -t "${IMAGE}:5-cn" -t "${IMAGE}:${VERSION}-cn" --push .
else
    # 本地不 push 时按架构分别输出 OCI 目录，避免 classic docker 无法 load 异构镜像
    for P in ${PLATFORMS//,/ }; do
        ARCH="${P#linux/}"
        OUT="/tmp/msr-${ARCH}.oci.tar"
        echo "   -> ${ARCH} 输出到 ${OUT}"
        docker buildx build --builder "$BUILDER" --platform "$P" \
            $DOCKERFILE -t "msr:${ARCH}" --output "type=oci,dest=${OUT}" .
    done
fi

echo "== 5/5 完成"
if [ "$PUSH" = "1" ]; then
    echo "已推送多架构: ${IMAGE}:5-cn / ${IMAGE}:${VERSION}-cn"
    echo "面板版请再跑 deploy/build-allinone.sh（见仓库 deploy/ 目录）"
else
    echo "已产出 /tmp/msr-<arch>.oci.tar；ARM 机器可用:"
    echo "  skopeo copy oci-archive:/tmp/msr-arm64.oci.tar docker-archive:/tmp/msr-arm64.docker.tar"
    echo "  docker load -i /tmp/msr-arm64.docker.tar"
fi
