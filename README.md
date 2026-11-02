# V2bX（自维护版）

[![Linux 与 Docker 检查](https://github.com/xn9kqy58k/V2bX/actions/workflows/security-regression.yml/badge.svg)](https://github.com/xn9kqy58k/V2bX/actions/workflows/security-regression.yml)
[![多平台构建](https://github.com/xn9kqy58k/V2bX/actions/workflows/release.yml/badge.svg)](https://github.com/xn9kqy58k/V2bX/actions/workflows/release.yml)

这是我们自己维护的 V2bX，用来把 V2board 兼容面板和节点服务器连起来。
支持 Xray、sing-box、Hysteria2 多种核心，以及节点管理、流量统计、限速、在线 IP 限制和证书管理。具体协议能否使用，还取决于面板和所选核心。

[我们的仓库](https://github.com/xn9kqy58k/V2bX) · [版本下载](https://github.com/xn9kqy58k/V2bX/releases) · [构建下载](https://github.com/xn9kqy58k/V2bX/actions/workflows/release.yml) · [问题反馈](https://github.com/xn9kqy58k/V2bX/issues) · [提交记录](https://github.com/xn9kqy58k/V2bX/commits/dev_new/) · [配套 Xray 补丁](https://github.com/xn9kqy58k/xray-core/tree/security/v2bx-mptcp-go1273-backport)

当前维护分支是 `dev_new`。安装、更新和反馈都以本仓库为准。

## 每次优化都改了什么

这里按维护批次记录。以后每轮优化都在最上面新增一条，直接说明改了什么、有什么用、升级时要做什么。

### 2026-11-02 · 第二次优化：减少出错停机，改善构建

- **配置暂时写坏，也先让节点继续跑。** 新配置先完整读取、解析，成功后才替换旧配置。JSON 写错或保存到一半时，不再清空旧配置并触发重启。
- **文件监听出错会收好尾。** 启动监听失败时释放资源；监听关闭后取消还没执行的重载；重载回调顺序执行，避免挤在一起。
- **日志路径填错，也能继续看日志。** 日志文件打不开时改用标准输出，不再把空文件对象交给日志系统；退出时关闭打开的日志文件。
- **退出时关掉当前正在使用的核心。** 热重载和退出互相协调，避免关到旧核心，或退出过程中又启动一个新核心。
- **Docker 少做重复工作。** 改业务代码时可以复用已下载的依赖，同一台构建机还可复用 Go 编译缓存；ARM64 镜像的 Go 程序改为在构建机上交叉编译。Git 历史、临时文件和本地构建产物不再带进构建上下文。
- **提交检查和发布分开。** PR 只验证 Docker 构建；正式发布或手动发布时才上传镜像。自动检查增加配置、日志和 AMD64 / ARM64 容器启动验证。
- **说明文档归我们自己维护。** 首页的仓库、下载、反馈、构建和核心补丁链接全部指向我们的账号；配置说明和安全处理说明也放进本仓库。

升级时：替换二进制或重建镜像，然后重启服务。配置字段和默认配置路径不变，不需要为了这次优化重写配置。构建优化没有做固定倍数的提速承诺，实际耗时取决于机器和缓存。

### 2026-11-02 · 第一次优化：降低 Linux 内核漏洞的暴露面

- **默认不用 MPTCP 监听。** 针对 CVE-2026-98432，关闭 Go 的默认 MPTCP，并把 Xray 的对应监听防护移植到我们维护的核心。
- **升级编译工具时，把兼容补丁一起带上。** 构建统一使用 Go 1.27.3，修正 Vision 使用 TLS 缓冲区的兼容问题。
- **保留原来的多核心和 KCP 功能。** 没有直接套用会删除旧功能、打乱现有依赖的整套新版核心。
- **增加实际监听检查。** 在 Linux 上创建 socket，验证最终使用的是普通 TCP；同时检查 TLS 兼容和多核心合并构建。

升级时：部署新程序后重启 V2bX。这只是应用层缓解，服务器还需要安装修复后的 Linux 内核并重启。具体步骤见 [Linux 安全处理说明](docs/security/CVE-2026-98432.md)。

## 下载与安装

优先查看[我们的版本下载页](https://github.com/xn9kqy58k/V2bX/releases)。如果还没有适合的发布版本，可到[多平台构建页面](https://github.com/xn9kqy58k/V2bX/actions/workflows/release.yml)，选择最近成功的构建，在 Artifacts 中下载对应系统和 CPU 的文件；下载构建产物通常需要登录 GitHub。

安装或更新前备份现有程序和 `/etc/V2bX` 配置目录。替换程序后，使用你原来的服务管理方式重启。配置样例见 [example/config.json](example/config.json)，日常操作见[使用说明](docs/usage.md)。

旧上游的一键安装脚本仍会下载上游产物，不能保证包含这里的维护补丁。请从本仓库下载或构建。

## 从源码构建

需要 Go 1.27.3 或更高版本。下面是 Linux / macOS 的命令：

```sh
git clone --branch dev_new https://github.com/xn9kqy58k/V2bX.git
cd V2bX
mkdir -p build_assets
version=$(git rev-parse --short HEAD)
module=$(go list -m)
GOEXPERIMENT=jsonv2 CGO_ENABLED=0 go build -mod=readonly -trimpath \
  -o build_assets/V2bX \
  -tags "sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor" \
  -ldflags "-X ${module}/cmd.version=${version} -s -w -buildid=" .
```

生成的程序在 `build_assets/V2bX`。先用 `build_assets/V2bX version` 确认可以启动，再替换服务器上的程序。

## 使用 Docker

在本仓库目录构建镜像：

```sh
docker build -t v2bx:local .
```

确认 `/etc/V2bX/config.json` 已按自己的面板、节点和证书信息配置好，再在 Linux 服务器启动：

```sh
docker run -d --name v2bx --restart unless-stopped --network host \
  -v /etc/V2bX:/etc/V2bX v2bx:local
```

镜像默认运行 `V2bX server --config /etc/V2bX/config.json`。修改配置后先查看日志；更新程序需要重建镜像并重建容器。容器与宿主机共用内核，内核漏洞仍需在宿主机处理。

## 遇到问题

到[我们的问题反馈页](https://github.com/xn9kqy58k/V2bX/issues)说明系统、CPU 架构、程序版本、使用的核心，以及相关报错。发配置前请去掉面板密钥、证书私钥和账号信息。

## 来源与授权

本项目保留原有提交历史、版权声明和 [MPL-2.0 许可证](LICENSE)。上游项目和依赖作者的贡献见[来源与致谢](docs/ACKNOWLEDGEMENTS.md)。
