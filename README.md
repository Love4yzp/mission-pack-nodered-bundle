# Mission Pack NodeRED Bundle

Captible devices:

- R1000 Series
- ReTerminal [Testing]

You can make your own central node. 

You should directly install this program on the supported devices.

~~Run the program locally to download the bundle, you need to ensure that the device you want to install is in the same local network and supports ssh. This supports multiple devices to install software at the same time.~~

Only Support Ubuntu and Raspberry Pi.
Ubuntu: 22.04
Raspberry Pi: 11(bullseye) and 12(bookworm)

## 功能

### 网络区域检测和镜像源管理

自动检测网络位置（国内/国外）并更新相应的镜像源配置：
- Python UV 镜像源配置
- Docker 镜像源配置

```bash
# 检测网络位置
python main.py network detect

# 查看当前镜像源状态
python main.py network status

# 更新镜像源配置
python main.py network update
```

### Docker 安装工具

提供 Docker 安装检测和自动安装功能，根据网络位置选择合适的安装源：

```bash
# 检查 Docker 是否已安装
python main.py docker check

# 安装 Docker（自动检测网络位置）
python main.py docker install

# 在国内网络环境安装 Docker
python main.py docker install --location china

# 自动执行安装命令（仅支持 Linux 和 macOS）
python main.py docker install --auto-execute