"""
配置加载器模块。
负责从YAML文件加载配置信息。
"""
from pathlib import Path
from typing import Dict, Any, Optional, List, Union
import yaml
from enum import Enum
from loguru import logger

class NetworkLocation(str, Enum):
    """网络位置枚举"""
    CHINA = "china"
    GLOBAL = "global"
    UNKNOWN = "unknown"


class ConfigManager:
    """配置管理器"""
    
    _instance = None
    _config_cache = None
    
    def __new__(cls):
        """单例模式"""
        if cls._instance is None:
            cls._instance = super(ConfigManager, cls).__new__(cls)
        return cls._instance
    
    def __init__(self):
        """初始化配置管理器"""
        if self._config_cache is None:
            self._config_cache = self._load_config()
    
    def get_config_path(self) -> Path:
        """
        获取配置文件路径
        
        Returns:
            Path: 配置文件路径
        """
        # 首先检查项目根目录下的config目录
        base_dir = Path(__file__).parent.parent
        config_path = base_dir / "config" / "mirrors.yaml"
        
        if config_path.exists():
            return config_path
        
        logger.warning(f"No mirrors.yaml found in {config_path}, creating empty config")
        return None
    
    def _load_config(self) -> Dict[str, Any]:
        """
        加载配置
        
        Returns:
            Dict: 配置字典
        """
        config_path = self.get_config_path()
        
        if not config_path:
            return {}
        
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                config = yaml.safe_load(f) or {}
                logger.debug(f"Loaded config from {config_path}")
                return config
        except (FileNotFoundError, yaml.YAMLError) as e:
            logger.error(f"Error loading config: {e}")
            return {}
    
    def reload_config(self) -> Dict[str, Any]:
        """
        重新加载配置
        
        Returns:
            Dict: 配置字典
        """
        self._config_cache = self._load_config()
        return self._config_cache
    
    def get_config(self) -> Dict[str, Any]:
        """
        获取配置
        
        Returns:
            Dict: 配置字典
        """
        return self._config_cache
    
    def update_config(self, new_config: Dict[str, Any]) -> bool:
        """
        更新配置
        
        Args:
            new_config: 新的配置字典
            
        Returns:
            bool: 更新是否成功
        """
        try:
            config_path = self.get_config_path()
            with open(config_path, "w", encoding="utf-8") as f:
                yaml.dump(new_config, f)
            self._config_cache = new_config
            logger.info(f"Updated config at {config_path}")
            return True
        except Exception as e:
            logger.error(f"Error updating config: {e}")
            return False


# 创建全局配置管理器实例
_config_manager = ConfigManager()


def get_config_path() -> Path:
    """
    获取配置文件路径
    
    Returns:
        Path: 配置文件路径
    """
    return _config_manager.get_config_path()


def load_config() -> Dict[str, Any]:
    """
    加载配置
    
    Returns:
        Dict: 配置字典
    """
    return _config_manager.get_config()


def reload_config() -> Dict[str, Any]:
    """
    重新加载配置
    
    Returns:
        Dict: 配置字典
    """
    return _config_manager.reload_config()


def update_config(new_config: Dict[str, Any]) -> bool:
    """
    更新配置
    
    Args:
        new_config: 新的配置字典
        
    Returns:
        bool: 更新是否成功
    """
    return _config_manager.update_config(new_config)


def get_mirrors_for_location(mirror_type: str, location: NetworkLocation) -> Union[List, Dict]:
    """
    获取指定类型和位置的镜像源
    
    Args:
        mirror_type: 镜像源类型，如 'apt_mirrors', 'pip_mirrors', 'docker_mirrors'
        location: 网络位置
        
    Returns:
        Union[List, Dict]: 镜像源列表或字典
    """
    config = load_config()
    return config.get(mirror_type, {}).get(location, [] if mirror_type != 'apt_mirrors' else {})


def get_apt_mirrors(location: NetworkLocation, distro: str = "ubuntu", version: Optional[str] = None) -> list:
    """
    获取APT镜像源
    
    Args:
        location: 网络位置
        distro: 发行版，默认为ubuntu
        version: 发行版版本，如果为None则返回所有版本
        
    Returns:
        list: 镜像源列表
    """
    mirrors = get_mirrors_for_location('apt_mirrors', location)
    
    if distro not in mirrors:
        return []
    
    if version:
        return mirrors.get(distro, {}).get(version, [])
    return mirrors.get(distro, {})


def get_pip_mirrors(location: NetworkLocation) -> list:
    """
    获取PIP镜像源
    
    Args:
        location: 网络位置
        
    Returns:
        list: 镜像源列表
    """
    return get_mirrors_for_location('pip_mirrors', location)


def get_docker_mirrors(location: NetworkLocation) -> list:
    """
    获取Docker镜像源
    
    Args:
        location: 网络位置
        
    Returns:
        list: 镜像源列表
    """
    return get_mirrors_for_location('docker_mirrors', location)


def get_default_mirror(mirror_type: str, location: NetworkLocation, default_value: str = "") -> str:
    """
    获取默认镜像源
    
    Args:
        mirror_type: 镜像源类型，如 'default_pip_mirror', 'default_docker_mirror'
        location: 网络位置
        default_value: 默认值
        
    Returns:
        str: 默认镜像源
    """
    config = load_config()
    mirrors = config.get(mirror_type, {})
    return mirrors.get(location, mirrors.get(NetworkLocation.GLOBAL, default_value))


def get_default_pip_mirror(location: NetworkLocation) -> str:
    """
    获取默认PIP镜像源
    
    Args:
        location: 网络位置
        
    Returns:
        str: 默认镜像源
    """
    return get_default_mirror('default_pip_mirror', location, "")


def get_default_docker_mirror(location: NetworkLocation) -> str:
    """
    获取默认Docker镜像源
    
    Args:
        location: 网络位置
        
    Returns:
        str: 默认镜像源
    """
    return get_default_mirror('default_docker_mirror', location, "")


def setup_uv_mirror(location: Optional[NetworkLocation] = None):
    """
    设置UV镜像源配置
    
    Args:
        location: 网络位置，如果为None则自动检测
    """
    from .mirror_manager import MirrorManager
    
    mirror_manager = MirrorManager(location)
    mirror_manager.update_uv_mirror()