# 自建一体化镜像：上游 CN 一体化镜像 + 本仓库的 panel/
#
# 为什么需要它：`deploy/Dockerfile.all-in-one-docker` 只在上游镜像上补了个 docker CLI，
# 面板文件仍然来自上游镜像；容器启动时 entrypoint 会用镜像里的 /opt/panel-app 覆盖
# /opt/data，所以「热替换 index.html」在下次重启后就会丢失。本 Dockerfile 把本仓库的
# panel/ 固化进镜像，重启后依然是修好的版本。
#
# 构建（在仓库根目录执行，秒级完成）：
#   docker build -f deploy/local/Dockerfile -t ms-rewards:local .
#
# 想把 src/ 的改动（control-api 等）也带上，需要先用仓库根 Dockerfile 构建运行时（重，
# 要 npm ci + 下载 chromium），再用它当 BASE：
#   docker build -t ms-rewards:runtime .
#   docker build -f deploy/local/Dockerfile --build-arg BASE=ms-rewards:runtime -t ms-rewards:local .
ARG BASE=docker.io/wangxiangya/ms-rewards-v5:5-cn-allinone-docker
FROM ${BASE}

# 覆盖面板（README 文档页也会一起更新）
COPY panel/ /opt/panel-app/

RUN python3 -c "import ast,sys; ast.parse(open('/opt/panel-app/server.py').read())" \
    && grep -q 'Rewards 控制台' /opt/panel-app/index.html

LABEL org.opencontainers.image.title="ms-rewards-local"
LABEL org.opencontainers.image.description="v5 CN all-in-one with this fork's web panel baked in"
