"""
network_region 包
提供网络区域检测和相关配置功能
"""

# 从config_loader模块导出所有内容
from .config_loader import (
    NetworkLocation,
    get_config_path,
    load_config,
    reload_config,
    update_config,
    get_apt_mirrors,
    get_pip_mirrors,
    get_docker_mirrors,
    get_default_pip_mirror,
    get_default_docker_mirror,
    setup_uv_mirror
)

# 从network模块导出所有内容
from .network import (
    check_network_location,
    check_internet_connection
)

# 从mirror_manager模块导出所有内容
from .mirror_manager import (
    MirrorManager,
    get_mirror_status
)

# 定义包的公开API
__all__ = [
    'NetworkLocation',
    'get_config_path',
    'load_config',
    'reload_config',
    'update_config',
    'get_apt_mirrors',
    'get_pip_mirrors',
    'get_docker_mirrors',
    'get_default_pip_mirror',
    'get_default_docker_mirror',
    'check_network_location',
    'check_internet_connection',
    'MirrorManager',
    'get_mirror_status',
    'setup_uv_mirror'
]

PACKAGE_VERSION = '1.1.0'