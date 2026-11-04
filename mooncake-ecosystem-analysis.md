# Mooncakes 查重

2026-11-05 读取 https://mooncakes.io/api/v0/modules ，对模块名、描述、关键词检索 squashfs/ext4/ext2/btrfs/erofs/filesystem image/journald/systemd 等；本次未发现 SquashFS 直接实现。不是全量源码审计，也不能证明未发布项目不存在。

压缩和二进制工具不是同类完整文件系统库。此前已发现 OCI 镜像构建/分析、ELF、WIT、Netlink、cgroup 等直接相关模块，因此选择 SquashFS 缺口进一步验证。原始 registry 索引在父目录 .research 本地保存，不纳入分发。
