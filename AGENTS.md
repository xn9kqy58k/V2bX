# 维护约定

- 本仓库由 `xn9kqy58k/V2bX` 维护，默认分支是 `dev_new`，上游通过 `upstream` 保留。
- 每轮功能修改、问题修复或构建优化，都要同步更新 README 的“每次优化都改了什么”。新记录放最前面，用中文大白话说明改了什么、有什么用、升级时要做什么。使用当前任务的用户日期；同一天多轮修改按批次区分。
- README 的仓库、下载、构建、反馈等入口使用我们自己的真实链接。第三方项目归属和参考来源放在 `docs/ACKNOWLEDGEMENTS.md` 或对应说明中，保留原许可证与版权声明，不伪造不存在的自有仓库链接。
- 不凭猜测写提速倍数、兼容性或测试通过结论。未经实际验证的结果要明确说明。
- 保持现有多核心兼容；更换核心或依赖之前，确认不会静默删除 KCP 等现有功能。不要仅为了改链接重命名 Go 模块路径。
- 构建需要 Go 1.27.3 及 `GOEXPERIMENT=jsonv2`。配置测试可运行 `go test -mod=readonly -timeout=60s ./conf`；日志测试可运行 `go test -mod=readonly -timeout=30s -run '^TestConfigureLogOutput' ./cmd`。
- 不直接运行无限制的 `go test ./...`；部分上游测试会启动服务或需要外部面板。Linux socket、TLS、多核心和 Docker 的验证入口是 `.github/workflows/security-regression.yml`。
