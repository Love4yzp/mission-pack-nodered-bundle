"""
命令行界面模块。
提供命令行工具来管理镜像源配置。
"""
import typer
from typing import Optional
from rich.console import Console

from .config_loader import NetworkLocation
from .network import check_network_location, check_internet_connection
from .mirror_manager import MirrorManager, get_mirror_status

# 创建Typer应用
app = typer.Typer(help="网络区域检测和镜像源管理工具")
console = Console()


@app.command("detect")
def detect_network():
    """
    检测当前网络位置
    """
    if not check_internet_connection():
        console.print("[bold red]无法连接到互联网，请检查网络连接[/bold red]")
        raise typer.Exit(code=1)
    
    location = check_network_location()
    console.print(f"当前网络位置: [bold green]{location}[/bold green]")


@app.command("status")
def show_status():
    """
    显示当前镜像源状态
    """
    get_mirror_status()  # 这个函数内部已经有美化输出


@app.command("update")
def update_mirrors(
    location: Optional[str] = typer.Option(
        None, "--location", "-l", 
        help="指定网络位置 (china/global/unknown)，不指定则自动检测"
    ),
    uv_only: bool = typer.Option(
        False, "--uv-only", help="仅更新UV镜像源"
    ),
    docker_only: bool = typer.Option(
        False, "--docker-only", help="仅更新Docker镜像源"
    )
):
    """
    更新镜像源配置
    """
    # 检查网络连接
    if not check_internet_connection():
        console.print("[bold red]无法连接到互联网，请检查网络连接[/bold red]")
        raise typer.Exit(code=1)
    
    # 解析网络位置
    net_location = None
    if location:
        try:
            net_location = NetworkLocation(location.lower())
        except ValueError:
            console.print(f"[bold red]无效的网络位置: {location}[/bold red]")
            console.print("有效的网络位置: china, global, unknown")
            raise typer.Exit(code=1)
    
    # 创建镜像管理器
    mirror_manager = MirrorManager(net_location)
    
    # 根据选项更新镜像源
    if uv_only:
        success = mirror_manager.update_uv_mirror()
        if not success:
            raise typer.Exit(code=1)
    elif docker_only:
        success = mirror_manager.update_docker_mirror()
        if not success:
            raise typer.Exit(code=1)
    else:
        results = mirror_manager.update_all_mirrors()
        if not all(results.values()):
            raise typer.Exit(code=1)
    
    console.print("[bold green]镜像源更新完成[/bold green]")


if __name__ == "__main__":
    app()
