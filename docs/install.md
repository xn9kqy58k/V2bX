# 安装和更新：照着做就行

脚本是 [scripts/install.sh](../scripts/install.sh)，发行包来自 [xn9kqy58k/V2bX Releases](https://github.com/xn9kqy58k/V2bX/releases)。所有程序下载地址都属于这个仓库；正常下载时 GitHub 可能重定向到自己的文件分发域名。

## 先准备什么

支持 Linux；需要 root 权限、Bash、`curl` 或 `wget`、`unzip` 和 coreutils。脚本会检查工具是否存在，不会自动升级系统或换内核。

常见缺依赖的安装方式，按自己的发行版选一条：

```sh
# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y bash curl unzip coreutils

# Rocky / AlmaLinux / Fedora 等使用 dnf 的发行版
sudo dnf install -y bash curl unzip coreutils
```

如果你已是 root，去掉 `sudo`。其他发行版请使用自己的包管理器安装同名工具。

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/xn9kqy58k/V2bX/dev_new/scripts/install.sh -o install-v2bx.sh &&
sudo bash install-v2bx.sh install
```

默认位置：

| 内容 | 位置 |
| --- | --- |
| 程序 | `/usr/local/bin/V2bX` |
| 配置 | `/etc/V2bX/config.json` |
| 首次配置样例 | `/etc/V2bX/config.json.example` |
| 服务文件 | `/etc/systemd/system/V2bX.service` |

第一次安装只生成样例，不会用占位的面板地址启动。复制样例为 `config.json`，填好面板地址、密钥、节点编号、类型，再执行 `sudo systemctl enable --now V2bX.service`。
已有配置、数据和自定义服务文件不会被覆盖。已有服务如果指向别的程序位置，脚本会提示核对目录，避免“看起来更新了，实际仍在运行旧程序”。

## 更新或回到指定版本

```sh
sudo bash install-v2bx.sh update
sudo bash install-v2bx.sh update --version v0.4.2
```

不指定版本时取最新正式 Release；指定的标签必须已经有对应架构的发行包和 `.sha256` 校验文件。
更新前校验包的 SHA-256，并试运行新程序。下载、校验或试运行失败时不替换旧程序；替换后服务重启失败会尝试恢复旧程序和原有运行状态。
服务显示运行不代表面板、证书和节点都配置正确，更新后仍要查看日志。

运行本维护版后还可使用 `sudo V2bX update`。这个命令会识别当前程序的真实目录；自定义配置目录时加 `--config-dir /你的目录`。

## 程序原来不在默认位置

先确认原服务使用的程序和配置位置，再传入对应目录。例如程序为 `/opt/V2bX/V2bX`：

```sh
sudo bash install-v2bx.sh update --install-dir /opt/V2bX --config-dir /opt/V2bX-config
```

没有 systemd，或者希望自己控制重启时使用 `--no-service`。这时只更新文件，运行中的旧进程需要你手动重启：

```sh
sudo bash install-v2bx.sh update --install-dir /opt/V2bX --config-dir /opt/V2bX-config --no-service
```

`bash install-v2bx.sh --help` 可以查看全部参数，包括服务文件目录 `--service-dir` 和非交互兼容选项 `--yes`。

## 辅助数据和容器

发行包里的 GeoIP / GeoSite 数据取自本仓库 `example` 中已有的文件，不在安装时从第三方下载。
脚本只补充配置目录中缺失的辅助文件，不会用发行包覆盖你的自定义 DNS、路由或数据库。
Docker 部署继续按 README 重建镜像和容器更新；脚本不负责更新宿主机内核。相关说明见 [Linux 安全处理说明](security/CVE-2026-98432.md)。
