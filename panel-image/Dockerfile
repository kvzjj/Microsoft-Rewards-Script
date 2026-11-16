# Microsoft Rewards 控制面板 —— 独立镜像
# 只含面板本体（标准库 Python，无第三方依赖），通过 HTTP 调用 ms-rewards 运行容器
FROM python:3.12-alpine

LABEL org.opencontainers.image.title="ms-rewards-panel" \
      org.opencontainers.image.description="Web control panel for Microsoft-Rewards-Script v5" \
      org.opencontainers.image.source="https://github.com/wangixangya/Microsoft-Rewards-Script" \
      org.opencontainers.image.licenses="MIT"

# Alpine 源：默认官方 CDN；国内自建可传 --build-arg APK_MIRROR=https://mirrors.aliyun.com/alpine。
# 指定镜像源时 update+add 失败会自动回落官方，避免一个源被墙/被挡就让整个 job 挂掉。
ARG APK_MIRROR=
RUN set -eux; \
    if [ -n "$APK_MIRROR" ]; then \
        sed -i "s|https://dl-cdn.alpinelinux.org/alpine|${APK_MIRROR}|g" /etc/apk/repositories; \
    fi; \
    if ! { apk update --no-progress && apk add --no-cache --no-progress tzdata ca-certificates curl docker-cli; }; then \
        echo "Alpine 源不可用，回落 dl-cdn.alpinelinux.org"; \
        [ -n "$APK_MIRROR" ] && sed -i "s|${APK_MIRROR}|https://dl-cdn.alpinelinux.org/alpine|g" /etc/apk/repositories; \
        sed -i "s|^https://[^/]*/alpine|https://dl-cdn.alpinelinux.org/alpine|g" /etc/apk/repositories; \
        apk update --no-progress; \
        apk add --no-cache --no-progress tzdata ca-certificates curl docker-cli; \
    fi; \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    echo "Asia/Shanghai" > /etc/timezone

# 代码放只读位置，运行期数据放 /opt/data（可挂卷持久化）
COPY panel/ /opt/panel-app/
COPY panel-image/entrypoint.sh /usr/local/bin/panel-entrypoint.sh
RUN chmod +x /usr/local/bin/panel-entrypoint.sh /opt/panel-app/*.sh 2>/dev/null || true

ENV PANEL_PORT=5310 \
    TZ=Asia/Shanghai \
    PYTHONUNBUFFERED=1 \
    PANEL_DATA=/opt/data

VOLUME ["/opt/data"]
EXPOSE 5310

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PANEL_PORT}/" -o /dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/panel-entrypoint.sh"]
