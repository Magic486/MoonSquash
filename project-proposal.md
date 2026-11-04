# MoonSquash：SquashFS 4 镜像工具库

2026-11-05；全新项目；本地开发，发布身份待定。该方案替代上层目录此前的 FLAC 扩展建议。

目标：为 MoonBit 提供可复用的 SquashFS 4 文件系统镜像读取、构建、提取、查询、差异和结构校验能力。面向固件、只读 Linux 系统镜像和离线制品检查。核心格式逻辑用 MoonBit，压缩算法可复用明确披露的宿主/生态实现。

完整范围：superblock 与特性检查；元数据块流；基本/扩展 inode；目录、文件数据、fragment、稀疏块、硬链接与符号链接；UID/GID、xattr、设备与特殊文件建模；随机文件读取；树遍历与安全导出；确定性镜像布局和构建；结构一致性校验与镜像差异；CLI、公开 API 和独立消费。

压缩支持按实际验证逐种标注。首个贯通目标是 uncompressed 和 gzip 镜像；不能把这一阶段当完整比赛交付。后续加入 xz/zstd/lz4 等可用适配，并显式拒绝缺失解压器。FFI 只做 I/O 与压缩，不调用 unsquashfs 代替核心实现。

架构：有界随机读取 → superblock/metadata → inode/directory/data/fragment → filesystem API → verify/diff/extract；构建端：输入树 → inode/目录布局 → 数据及元数据编码 → 索引及 superblock。

阶段：M1 官方镜像读取贯通；M2 构建并让官方 unsquashfs 消费；M3 完成链接/属性/特殊对象与语义校验；M4 差分、导出、性能边界、包消费和申报证据。每阶段如实更新 README，不把计划写成已完成。

验证使用独立 mksquashfs/unsquashfs：官方生成→MoonSquash读；MoonSquash生成→官方列目录和解包；比较文件 bytes、类型、权限和链接关系。Linux 在独立临时目录操作普通镜像文件，无需挂载或修改宿主系统。

赛事官网 2026-11-05 源码仍显示十月，十一月时间和次数未核实；不依此阻塞本地开发。项目规模以完整镜像工作流和文件系统语义衡量，不以行数作为通过保证。
