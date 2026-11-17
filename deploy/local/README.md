# 本仓库自建部署（长期基线）

这个目录是**本 fork 的部署基线**：从本仓库的 `panel/` 构建一体化镜像，交付一台可长期运行的
Microsoft Rewards v5 实例（运行时 + 中文面板 + docker CLI，单容器）。

## 为什么不能直接用上游镜像

`deploy/Dockerfile.all-in-one-docker` 只在上游镜像上补 docker CLI，**面板文件仍来自上游镜像**；
而容器启动时 `entrypoint-allinone.sh` 会用镜像里的 `/opt/panel-app/` 覆盖 `/opt/data/`。
所以「把修好的 `index.html` 拷进容器」在下次重启后就没了，必须把 `panel/` 打进镜像。

```
docker build -f deploy/local/Dockerfile -t ms-rewards:local .
```

`src/`（runtime）的改动不在这条链路上：本 Dockerfile 只覆盖面板。要让 `src/` 的修复生效，
先用仓库根 `Dockerfile` 构建运行时，再拿它当 BASE：

```
docker build -t ms-rewards:runtime .                                  # 重：npm ci + chromium
docker build -f deploy/local/Dockerfile --build-arg BASE=ms-rewards:runtime -t ms-rewards:local .
```

## 起服务

```bash
docker build -f deploy/local/Dockerfile -t ms-rewards:local .
cp deploy/local/env.example .env      # 填 API_TOKEN / PANEL_PASSWORD（.env 不会入库）
docker compose --env-file .env -f deploy/local/compose.yaml up -d
# 面板：http://<host>:5310
```

`--env-file .env` 是必需的：compose 的 `${API_TOKEN:?}` 之类占位符从它取值；
`env_file: ../../.env` 只负责把变量注入容器。

## 已包含的修复

| 提交 | 内容 |
| --- | --- |
| `fix(panel): partial 运行不再显示为「异常」` | 账号状态列改读 `lastStatus`：`completed → 正常`、`partial → 部分完成`、`failed → 异常`、`cancelled → 已取消`，悬停显示未确认明细；运行日志表同样映射。control-api `/accounts` 增加 `lastStatus` / `lastReason`，`lastError` 只在失败时返回 |

## 待办（已知问题）

- `SIGN_IN_METHOD_PICKER` 登录失败：`classifySignInMethod()` 仅靠 SVG 路径签名识别「密码」磁贴，
  页面结构一变就认不出，随后因容器内无 stdin 直接 abort，且不重试。修复思路：磁贴文案兜底匹配
  （密码 / Password / …）+ 该状态重试一次。
- 「连续成功」列恒为 0：`successStreak` 只统计 `success === true`，`partial` 不计入。

## 注意

- `.env`、`config/`、`sessions/`、`diagnostics/` 含凭据与 Cookie，**不要提交**（已在 `.gitignore`）。
- 挂 `/var/run/docker.sock` 等于把宿主 root 权限交给容器，仅限内网可信环境。
- 面板里添加/删除账号会自动 `docker run` 重建容器（走面板自己的 `env.list`），与 `docker compose up -d`
  会互相覆盖 env：**日常用面板管理，改配置后再用 compose 对齐一次**。
