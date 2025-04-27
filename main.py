#!/usr/bin/env python3
"""
Mission Pack Node-RED Bundle 主程序
"""
import typer
from rich.console import Console

from tools.network_region.cli import app as network_region_app
from tools.install_docker import app as docker_app

# 创建主应用
app = typer.Typer(help="Mission Pack Node-RED Bundle 工具集")
console = Console()

# 添加子命令
app.add_typer(network_region_app, name="network", help="网络区域检测和镜像源管理")
app.add_typer(docker_app, name="docker", help="Docker 安装和管理")


@app.callback()
def main():
    """
    Mission Pack Node-RED Bundle 工具集
    """
    pass


if __name__ == "__main__":
    app()
