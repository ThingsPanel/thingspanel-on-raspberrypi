# ThingsPanel on Raspberry Pi

这个项目提供了在树莓派上安装、配置和监控 ThingsPanel 的完整解决方案。ThingsPanel 是一个开源的物联网平台，本项目旨在简化其在树莓派上的部署和管理过程。

## 功能特性

- 一键安装 ThingsPanel 及其依赖
- 系统性能监控
- PostgreSQL 数据库 I/O 监控
- 完整的安装和卸载脚本
- 详细的性能优化指南

## 系统要求

- Raspberry Pi 4B (推荐 4GB 或 8GB 内存版本)
- Raspberry Pi OS (64位版本)
- 至少 16GB SD 卡
- 稳定的网络连接

## 快速开始

1. 克隆仓库：
```bash
git clone https://github.com/yourusername/thingspanel-on-raspberrypi.git
cd thingspanel-on-raspberrypi
```

2. 运行安装脚本：
```bash
chmod +x scripts/install/install_thingspanel_rpi.sh
./scripts/install/install_thingspanel_rpi.sh
```

3. 访问 ThingsPanel：
安装完成后，在浏览器中访问 `http://<树莓派IP地址>:8000`

## 监控功能

项目包含两个监控脚本：

- `monitor_system.sh`: 监控系统资源使用情况
- `pg_io_monitor.sh`: 监控 PostgreSQL 数据库 I/O 性能

使用方法：
```bash
# 系统监控
./scripts/monitor/monitor_system.sh

# 数据库 I/O 监控
./scripts/monitor/pg_io_monitor.sh
```

## 卸载

如果需要卸载 ThingsPanel，可以使用提供的卸载脚本：

```bash
chmod +x scripts/uninstall/uninstall_thingspanel_rpi.sh
./scripts/uninstall/uninstall_thingspanel_rpi.sh
```

## 文档

- [安装指南](docs/install-guide.md)
- [性能测试报告](docs/performance.md)

## 贡献

欢迎提交 Issue 和 Pull Request 来帮助改进这个项目。

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件 