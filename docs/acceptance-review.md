# 本地验收准备复核

日期：2026-11-05；项目：MoonSquash 0.3.0；拟参赛月份：十一月。用户已指定账号 Magic486，仓库 https://github.com/Magic486/MoonSquash，模块 Magic486/moonsquash；发布状态见 release.md。

**状态：README 明示范围内的 0.3 本地候选版本已实现并验证；公开发布验证见 release.md；正式报名和官方审核均未执行。** 技术自查不代表主办方通过。严格复查的缺陷、修复与剩余风险见 [strict-review.md](strict-review.md)。

规则来源：[赛事官网](https://moonbitlang.github.io/Hackathon2026/)及[官方页面源码](https://github.com/moonbitlang/Hackathon2026/blob/main/src/App.tsx)。2026-11-05 调研时官方源码仍显示十月；不能沿用十月截止时间或提交次数作为十一月已确认规则。该不确定性只影响报名，不阻塞本地开发。

| 要点 | 本地证据与结论 |
|---|---|
| 真实用途 | Linux 固件、只读系统与制品镜像的构建、检查、提取和版本比较；README 与 demo |
| 生态新增 | Mooncakes 元数据和公开 GitHub 检索未发现直接同类 MoonBit 实现；检索范围与不确定性见三份生态报告 |
| 功能规模 | 镜像读写、文件系统对象与属性、六种压缩适配、压缩元数据、流式构建、差异、校验、打包和提取；形成可用工作流 |
| MoonBit 核心 | 布局、inode/目录/fragment/owner/xattr/export、范围读取、校验和差异在 MoonBit；宿主 I/O、算法库与属性操作披露 |
| 可运行/可复用 | CLI、公开 mbti、Wasm-GC 示例、独立 ZIP 消费工程 |
| 实机/独立验证 | 服务器从源码编译；六压缩双向 oracle；约 201 MiB、2403 个文件路径的合成数据集；公开 OpenWrt 镜像 1225 文件对照；缺陷复现及修复验证；详见 review-0.3 证据 |
| 许可与来源 | Apache-2.0；格式资料、系统库、AI 辅助范围见 THIRD_PARTY；无上游 GPL 实现源码导入 |
| 开发记录 | 真实本地研究、首版、功能扩展、验证与文档历史；未补造公开开发时间 |
| 分发 | 实际 ZIP 排除本地缓存、私有资料和 PDF；独立消费验证；Git/PDF 仅本地保存 |
| 边界 | 偏移/单文件 <2 GiB；流式构建默认 4 GiB 累计预算、内存便利 API 128 MiB；UTF-8 路径、提取不应用特权操作，均明确披露 |

后续平台事项：按用户指定的 Magic486 身份发布，运行公开 CI 并完成 registry 版本安装验证；核实十一月规则并由真实参赛者补充报名信息。没有虚构公开链接、个人资料或官方结论。

参赛者需理解并能讲解架构、压缩边界、硬链接与 fragment、xattr out-of-line、结构校验范围，以及官方对照发现的两个兼容性问题。规模以这些可用能力和证据说明，不以行数承诺通过。
