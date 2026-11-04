# GitHub 与格式资料

2026-11-05 GitHub repository search `squashfs language:MoonBit`、`squashfs moonbit` 均返回 total_count=0；搜索引擎亦未发现直接 MoonBit 实现。搜索只涵盖可索引公开仓库。

上游参考：https://github.com/plougher/squashfs-tools ，mksquashfs/unsquashfs 是成熟 C 工具，作为独立 oracle，不算本项目实现。格式资料：https://docs.kernel.org/filesystems/squashfs.html 及上游 squashfs_fs.h。独立根据磁盘格式实现，不复制 GPL 实现代码。

目标 Linux 环境已确认存在 mksquashfs 4.7.5、unsquashfs、Node.js、GCC。仅使用测试生成的镜像和文件，不采集服务器私有文件。
