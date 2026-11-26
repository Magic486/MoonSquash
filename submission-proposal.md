# MoonSquash 项目申报书

**1、项目名称** MoonSquash：基于 MoonBit 的 SquashFS 4 文件系统镜像读写与分析工具库。

**2、项目简介** 面向固件开发与离线制品检查，提供 SquashFS 镜像读取、构建、打包、提取、校验与版本差异分析。当前版本 0.3.2，交付可复用 MoonBit API 和九个 CLI 命令。

**3、项目方向与通用性** 系统软件、文件系统与开发工具方向。基于通用 SquashFS 4 格式，适用于嵌入式根文件系统、只读应用镜像、归档检查与持续集成；库支持 JS/Wasm-GC，CLI 使用 JS，Linux 工作流已实测。

**4、预期使用场景**

- **固件检查与配置提取：** 开发者输入 OpenWrt 等系统的 SquashFS 根文件系统镜像，查看目录、文件及属性并提取所需内容，得到可检查的配置和文件；设备节点与特权操作以省略报告说明。
- **只读应用镜像构建：** 构建流水线输入应用目录或声明式配置，设置权限、属主、时间、链接与扩展属性，流式生成压缩镜像并校验，输出可重复生成的发布制品。
- **升级差异与发布检查：** 维护者输入升级前后两个镜像，比较文件增删、内容、权限、属主、属性和链接关系，输出按路径解释的变化清单，辅助核对配置遗漏和非预期权限变更。

**5、拟实现的核心功能** 覆盖十四类 inode 读取、目录及元数据表、稀疏文件、fragment、硬链接、符号链接、UID/GID、扩展属性及导出索引；提供范围读取、确定性流式构建、数据与元数据压缩、安全提取、损坏校验和语义差异。适配 gzip、xz、zstd、lz4、lzo、旧式 LZMA。已通过两种后端各 24 项库测试、官方工具双向对照、约 201 MiB 合成规模测试，以及真实 OpenWrt 的 1225 文件与 224 符号链接对照。当前镜像偏移及单文件小于 2 GiB，字符串路径要求 UTF-8。

**6、项目类型与原创说明** 原创实现，采用 Apache-2.0 许可证。核心文件系统解析、布局生成、校验和差异逻辑由 MoonBit 独立实现，AI 辅助开发；Node/Python 与系统压缩库承担宿主操作和算法适配，依赖范围在仓库 THIRD_PARTY.md 披露。

**7、参考项目及许可证** 非移植项目。参考 [Linux SquashFS 格式文档](https://docs.kernel.org/filesystems/squashfs.html)和 [squashfs-tools](https://github.com/plougher/squashfs-tools) 的磁盘结构定义（相关参考文件为 GPL-2.0-or-later）；未复制或链接其 C 实现，mksquashfs/unsquashfs 仅用于独立验证。

**8、GitHub 仓库及开发记录** 参赛仓库：[Magic486/MoonSquash](https://github.com/Magic486/MoonSquash)，保留不少于 10 个有效开发提交。0.3.2 已完成 Linux 服务器复验，修复稀疏统计、压缩数据与读取接口校验缺口；[本轮证据](https://github.com/Magic486/MoonSquash/blob/master/docs/test-evidence/review-0.3.2.md)、[CI 与发布状态](https://github.com/Magic486/MoonSquash/blob/master/docs/release.md)可核查。本材料不代表已获官方审核通过。
