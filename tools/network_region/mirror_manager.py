"""
镜像源管理模块。
提供更新和配置各种镜像源的功能。
"""
import json
from loguru import logger
from pathlib import Path
from typing import Dict, Any
import tomllib 
from rich.console import Console
from rich.panel import Panel

from .config_loader import NetworkLocation, load_config, get_default_pip_mirror, get_default_docker_mirror

# 创建rich控制台实例
console = Console()


class MirrorManager:
    """镜像源管理器"""
    
    def __init__(self, network_location: NetworkLocation = None):
        """
        初始化镜像源管理器
        
        Args:
            network_location: 网络位置，如果为None则自动检测
        """
        from .network import check_network_location
        
        self.network_location = network_location or check_network_location()
        self.config = load_config()
        logger.info(f"Mirror manager initialized with network location: {self.network_location}")
        console.print(Panel(f"[bold green]网络位置检测为: {self.network_location}[/bold green]"))
    
    def update_all_mirrors(self) -> Dict[str, bool]:
        """
        更新所有镜像源配置
        
        Returns:
            Dict[str, bool]: 各类镜像源更新结果
        """
        console.print("[bold blue]正在更新所有镜像源...[/bold blue]")
        
        results = {
            "uv": self.update_uv_mirror(),
            "docker": self.update_docker_mirror()
        }
        
        # 使用rich显示结果
        for mirror_type, success in results.items():
            status = "[bold green]成功[/bold green]" if success else "[bold red]失败[/bold red]"
            console.print(f"  {mirror_type}: {status}")
        
        logger.info(f"All mirrors update results: {results}")
        return results
    
    def update_uv_mirror(self) -> bool:
        """
        更新UV镜像源配置
        
        Returns:
            bool: 更新是否成功
        """
        try:
            # 用户级配置目录
            user_config_dir = Path.home() / ".config" / "uv"
            user_config_dir.mkdir(parents=True, exist_ok=True)
            user_config_file = user_config_dir / "uv.toml"
            
            # 获取默认镜像源
            default_mirror = get_default_pip_mirror(self.network_location)
            
            # 读取现有配置或创建新配置
            config_data = {}
            if user_config_file.exists():
                try:
                    with open(user_config_file, "rb") as f:
                        config_data = tomllib.load(f)
                except Exception as e:
                    logger.warning(f"Failed to load existing UV config: {e}")
            
            # 更新配置
            if "index" not in config_data:
                config_data["index"] = []
            
            # 检查是否已有默认镜像源
            default_index_exists = False
            for idx, index in enumerate(config_data["index"]):
                if index.get("default", False):
                    config_data["index"][idx]["url"] = default_mirror
                    default_index_exists = True
                    break
            
            # 如果没有默认镜像源，添加一个
            if not default_index_exists:
                config_data["index"].append({
                    "url": default_mirror,
                    "default": True
                })
            
            # 保存配置 - 由于 tomllib 只支持读取，我们需要手动写入 TOML 格式
            with open(user_config_file, "w", encoding="utf-8") as f:
                # 写入索引配置
                for i, index in enumerate(config_data.get("index", [])):
                    f.write("[[index]]\n")
                    for key, value in index.items():
                        if isinstance(value, bool):
                            f.write(f"{key} = {value}\n")  # Removed str(value).lower()
                        elif isinstance(value, (int, float)):
                            f.write(f"{key} = {value}\n")
                        else:
                            f.write(f'{key} = "{value}"\n')
                    if i < len(config_data.get("index", [])) - 1:
                        f.write("\n")
            
            logger.info(f"UV mirror updated successfully: {default_mirror}")
            console.print(f"[green]UV镜像源已更新: {default_mirror}[/green]")
            return True
            
        except Exception as e:
            logger.error(f"Failed to update UV mirror: {e}")
            console.print(f"[red]UV镜像源更新失败: {str(e)}[/red]")
            return False
    
    def update_docker_mirror(self) -> bool:
        """
        更新Docker镜像源配置
        
        Returns:
            bool: 更新是否成功
        """
        try:
            # Docker配置目录
            docker_config_dir = Path.home() / ".docker"
            docker_config_dir.mkdir(parents=True, exist_ok=True)
            docker_config_file = docker_config_dir / "config.json"
            
            # 获取默认镜像源
            default_mirror = get_default_docker_mirror(self.network_location)            
            # 读取现有配置或创建新配置
            config_data = {}
            if docker_config_file.exists():
                try:
                    with open(docker_config_file, "r", encoding="utf-8") as f:
                        config_data = json.load(f)
                except Exception as e:
                    logger.warning(f"Failed to load existing Docker config: {e}")
            
            # 更新配置
            if not default_mirror:
                # 如果没有默认镜像源，删除镜像源配置
                if "registry-mirrors" in config_data:
                    del config_data["registry-mirrors"]
                    logger.info("Removed Docker registry mirrors configuration")
                    console.print("[yellow]已移除Docker镜像源配置[/yellow]")
            else:
                # 更新镜像源配置
                config_data["registry-mirrors"] = [default_mirror]
                logger.info(f"Updated Docker registry mirror to: {default_mirror}")
                console.print(f"[green]Docker镜像源已更新: {default_mirror}[/green]")
            
            # 保存配置
            with open(docker_config_file, "w", encoding="utf-8") as f:
                json.dump(config_data, f, indent=2)
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to update Docker mirror: {e}")
            console.print(f"[red]Docker镜像源更新失败: {str(e)}[/red]")
            return False


def get_mirror_status() -> Dict[str, Any]:
    """
    获取当前镜像源状态
    
    Returns:
        Dict[str, Any]: 镜像源状态信息
    """
    from .network import check_network_location
    import subprocess
    import re
    
    network_location = check_network_location()
    
    # 检查UV配置
    uv_config_file = Path.home() / ".config" / "uv" / "uv.toml"
    uv_mirror = None
    if uv_config_file.exists():
        try:
            with open(uv_config_file, "rb") as f:
                config_data = tomllib.load(f)
                for index in config_data.get("index", []):
                    if index.get("default", False):
                        uv_mirror = index.get("url")
                        break
        except Exception as e:
            logger.error(f"Error reading UV config: {e}")
    
    # 如果UV配置不存在，尝试读取pip配置
    pip_mirror = None
    if not uv_mirror:
        try:
            # 使用subprocess运行pip config list命令
            result = subprocess.run(
                ["pip", "config", "list"], 
                capture_output=True, 
                text=True, 
                check=False
            )
            if result.returncode == 0:
                # 使用正则表达式提取index-url
                match = re.search(r"global\.index-url=['\"]([^'\"]+)['\"]", result.stdout)
                if match:
                    pip_mirror = match.group(1)
        except Exception as e:
            logger.error(f"Error reading pip config: {e}")
    
    # 检查Docker配置
    docker_mirror = None
    
    # 1. 首先检查用户级配置
    docker_config_file = Path.home() / ".docker" / "config.json"
    if docker_config_file.exists():
        try:
            with open(docker_config_file, "r", encoding="utf-8") as f:
                config_data = json.load(f)
                # 检查 registry-mirrors 配置
                mirrors = config_data.get("registry-mirrors", [])
                if mirrors:
                    docker_mirror = mirrors[0]
                    logger.debug(f"Found Docker mirror in user config: {docker_mirror}")
        except Exception as e:
            logger.error(f"Error reading Docker user config: {e}")
    
    # 2. 如果用户级配置中没有找到，检查系统级配置
    if not docker_mirror:
        system_docker_config = Path("/etc/docker/daemon.json")
        if system_docker_config.exists():
            try:
                with open(system_docker_config, "r", encoding="utf-8") as f:
                    config_data = json.load(f)
                    mirrors = config_data.get("registry-mirrors", [])
                    if mirrors:
                        docker_mirror = mirrors[0]
                        logger.debug(f"Found Docker mirror in system config: {docker_mirror}")
            except Exception as e:
                logger.error(f"Error reading Docker system config: {e}")
    
    status = {
        "network_location": network_location,
        "uv_mirror": uv_mirror,
        "pip_mirror": pip_mirror,
        "docker_mirror": docker_mirror,
        "recommended_uv_mirror": get_default_pip_mirror(network_location),
        "recommended_docker_mirror": get_default_docker_mirror(network_location)
    }
    
    # 使用rich美化输出
    console.print(Panel("[bold]镜像源状态[/bold]"))
    console.print(f"网络位置: [cyan]{network_location}[/cyan]")
    
    # 显示UV镜像信息
    if uv_mirror:
        console.print(f"当前UV镜像: [cyan]{uv_mirror}[/cyan]")
    elif pip_mirror:
        console.print(f"当前UV镜像: [cyan]未设置 (使用pip配置: {pip_mirror})[/cyan]")
    else:
        console.print("当前UV镜像: [cyan]未设置[/cyan]")
    
    # 根据网络位置显示不同的推荐信息
    if network_location == NetworkLocation.CHINA:
        console.print(f"推荐UV镜像: [green]{status['recommended_uv_mirror']}[/green]")
        console.print(f"当前Docker镜像: [cyan]{docker_mirror or '未设置'}[/cyan]")
        console.print(f"推荐Docker镜像: [green]{status['recommended_docker_mirror'] or '默认'}[/green]")
    else:
        console.print("推荐UV镜像: [green]默认[/green]")
        console.print(f"当前Docker镜像: [cyan]{docker_mirror or '未设置'}[/cyan]")
        console.print("推荐Docker镜像: [green]默认[/green]")
    
    return status
