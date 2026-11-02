# 项目来源与致谢

本维护仓库来自 [wyx2685/V2bX](https://github.com/wyx2685/V2bX)，保留上游 Git 提交历史和 MPL-2.0 许可证。
原项目基于 XrayR 修改，并集成多个独立开源项目；本仓库的维护改动不改变这些项目的作者和版权归属。

感谢原 README 中列出的项目：

- [Project X](https://github.com/XTLS/)
- [V2Fly](https://github.com/v2fly)
- [VNet-V2ray](https://github.com/ProxyPanel/VNet-V2ray)
- [Air-Universe](https://github.com/crossfw/Air-Universe)
- [XrayR](https://github.com/XrayR/XrayR)
- [sing-box](https://github.com/SagerNet/sing-box)

本仓库使用的 Xray 定向补丁在[我们维护的核心分支](https://github.com/xn9kqy58k/xray-core/tree/security/v2bx-mptcp-go1273-backport)中，参考了 [v2node](https://github.com/wyx2685/v2node) 和 Xray 上游的相关修复。
具体安全来源与限制见 [CVE-2026-98432 处理说明](security/CVE-2026-98432.md)。
