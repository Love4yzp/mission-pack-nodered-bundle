#!/usr/bin/env python3
"""
Docker 安装脚本模块。
提供检测 Docker 是否安装以及安装 Docker 的功能。
"""
import platform
import subprocess
from typing import Optional, Tuple, Dict, List
import typer
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from tools.network_region.network import check_network_location, check_internet_connection
from tools.network_region.config_loader import NetworkLocation

# 创建Typer应用
app = typer.Typer(help="Docker 安装工具")
console = Console()

# 定义不同系统的 Docker 安装命令
DOCKER_INSTALL_COMMANDS: Dict[str, Dict[NetworkLocation, List[str]]] = {
    "Darwin": {  # macOS
        NetworkLocation.CHINA: [
            "brew install --cask docker",
        ],
        NetworkLocation.GLOBAL: [
            "brew install --cask docker",
        ],
        NetworkLocation.UNKNOWN: [
            "brew install --cask docker",
        ],
    },
    "Linux": {
        NetworkLocation.CHINA: [
            "curl -fsSL https://get.docker.com -o get-docker.sh",
            "sed -i 's/download.docker.com/mirrors.aliyun.com\\/docker-ce/g' get-docker.sh",
            "sh get-docker.sh",
            "rm get-docker.sh",
            "sudo systemctl enable docker",
            "sudo systemctl start docker",
        ],
        NetworkLocation.GLOBAL: [
            "curl -fsSL https://get.docker.com -o get-docker.sh",
            "sh get-docker.sh",
            "rm get-docker.sh",
            "sudo systemctl enable docker",
            "sudo systemctl start docker",
        ],
        NetworkLocation.UNKNOWN: [
            "curl -fsSL https://get.docker.com -o get-docker.sh",
            "sed -i 's/download.docker.com/mirrors.aliyun.com\\/docker-ce/g' get-docker.sh",
            "sh get-docker.sh",
            "rm get-docker.sh",
            "sudo systemctl enable docker",
            "sudo systemctl start docker",
        ],
    },
    "Windows": {
        NetworkLocation.CHINA: [
            "echo 请访问 https://mirrors.aliyun.com/docker-toolbox/windows/docker-desktop/ 下载 Docker Desktop 安装程序",
            "echo 安装完成后，请按照 https://developer.aliyun.com/article/1294592 配置镜像加速",
        ],
        NetworkLocation.GLOBAL: [
            "echo 请访问 https://www.docker.com/products/docker-desktop/ 下载 Docker Desktop 安装程序",
        ],
        NetworkLocation.UNKNOWN: [
            "echo 请访问 https://mirrors.aliyun.com/docker-toolbox/windows/docker-desktop/ 下载 Docker Desktop 安装程序",
            "echo 安装完成后，请按照 https://developer.aliyun.com/article/1294592 配置镜像加速",
        ],
    },
}


def check_docker_installed() -> bool:
    """
    检查 Docker 是否已安装
    
    Returns:
        bool: 如果 Docker 已安装则返回 True，否则返回 False
    """
    try:
        result = subprocess.run(
            ["docker", "--version"], 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE,
            text=True,
            check=False
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


def get_system_info() -> Tuple[str, str]:
    """
    获取系统信息
    
    Returns:
        Tuple[str, str]: 系统类型和版本
    """
    system = platform.system()
    version = platform.version()
    return system, version


def display_install_instructions(commands: List[str]) -> None:
    """
    显示安装指令
    
    Args:
        commands: 安装命令列表
    """
    table = Table(title="Docker 安装指令")
    table.add_column("步骤", style="cyan")
    table.add_column("命令", style="green")
    
    for i, cmd in enumerate(commands, 1):
        table.add_row(f"{i}", cmd)
    
    console.print(table)


@app.command("check")
def check_docker():
    """
    检查 Docker 是否已安装
    """
    if check_docker_installed():
        version_output = subprocess.run(
            ["docker", "--version"], 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE,
            text=True,
            check=False
        ).stdout.strip()
        
        console.print(Panel(
            f"[bold green]Docker 已安装[/bold green]\n{version_output}",
            title="Docker 状态检查",
            border_style="green"
        ))
    else:
        console.print(Panel(
            "[bold red]Docker 未安装[/bold red]",
            title="Docker 状态检查",
            border_style="red"
        ))


@app.command("install")
def install_docker(
    location: Optional[str] = typer.Option(
        None, "--location", "-l", 
        help="指定网络位置 (china/global/unknown)，不指定则自动检测"
    ),
    auto_execute: bool = typer.Option(
        False, "--auto-execute", "-y", 
        help="自动执行安装命令（仅支持 Linux 和 macOS）"
    )
):
    """
    安装 Docker
    """
    # 检查是否已安装
    if check_docker_installed():
        console.print("[bold yellow]Docker 已安装，无需重新安装[/bold yellow]")
        return
    
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
    else:
        net_location = check_network_location()
        console.print(f"当前网络位置: [bold green]{net_location}[/bold green]")
    
    # 获取系统信息
    system, version = get_system_info()
    console.print(f"系统类型: [bold blue]{system}[/bold blue], 版本: [bold blue]{version}[/bold blue]")
    
    # 检查是否支持当前系统
    if system not in DOCKER_INSTALL_COMMANDS:
        console.print(f"[bold red]不支持的系统类型: {system}[/bold red]")
        console.print("支持的系统类型: Linux, macOS (Darwin), Windows")
        raise typer.Exit(code=1)
    
    # 获取安装命令
    install_commands = DOCKER_INSTALL_COMMANDS[system][net_location]
    
    # 显示安装指令
    console.print("\n[bold]Docker 安装指令:[/bold]")
    display_install_instructions(install_commands)
    
    # 自动执行（仅支持 Linux 和 macOS）
    if auto_execute and system in ["Linux", "Darwin"]:
        console.print("\n[bold yellow]开始自动安装 Docker...[/bold yellow]")
        for cmd in install_commands:
            console.print(f"执行: [bold cyan]{cmd}[/bold cyan]")
            try:
                process = subprocess.run(
                    cmd, 
                    shell=True, 
                    stdout=subprocess.PIPE, 
                    stderr=subprocess.PIPE,
                    text=True,
                    check=True
                )
                console.print(process.stdout)
            except subprocess.CalledProcessError as e:
                console.print(f"[bold red]命令执行失败: {e}[/bold red]")
                console.print(e.stderr)
                raise typer.Exit(code=1)
        
        console.print("[bold green]Docker 安装完成！[/bold green]")
    elif auto_execute and system == "Windows":
        console.print("\n[bold yellow]Windows 系统不支持自动安装，请按照上述指令手动安装[/bold yellow]")
    

if __name__ == "__main__":
    app()
