"""
网络工具模块。
提供检测网络位置和连接性的功能。
"""
import socket
import concurrent.futures
import requests
from requests.exceptions import RequestException
from loguru import logger
from typing import Dict, Tuple
from rich.progress import Progress, SpinnerColumn, TextColumn

from .config_loader import NetworkLocation

# 配置常量
HTTP_TIMEOUT = 0.5  # 单个域名最大等待时间（秒）
MAX_WORKERS = 5  # 最大并发检测数


def check_network_location() -> NetworkLocation:
    """
    通过并发测试中国和全球服务器的连接性来检测网络位置。
    修改后的逻辑：只要不是明确的 GLOBAL 网络环境，就默认使用中国的镜像源。
    
    Returns:
        NetworkLocation: 如果网络位于中国则返回CHINA，否则返回GLOBAL，如果无法确定则返回CHINA
    """
    china_domains = ["baidu.com", "taobao.com", "qq.com", "aliyun.com", "163.com"]
    global_domains = ["google.com", "facebook.com", "twitter.com", "github.com", "cloudflare.com"]
    
    with Progress(
        SpinnerColumn(),
        TextColumn("[bold blue]检测网络位置中...[/bold blue]"),
        transient=True
    ) as progress:
        progress.add_task("检测", total=None)
        
        # 使用线程池并发检测域名可达性
        with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            # 提交所有域名检测任务
            china_futures = {executor.submit(_http_head_fast, domain): domain for domain in china_domains}
            global_futures = {executor.submit(_http_head_fast, domain): domain for domain in global_domains}
            
            # 统计结果
            china_results = _count_successful_domains(china_futures)
            global_results = _count_successful_domains(global_futures)
    
    # 记录检测结果
    logger.info(f"Network detection results - \nChina: {china_results}, \nGlobal: {global_results}")
    
    # 修改后的判断逻辑：只要不是明确的 GLOBAL 就默认为 CHINA
    # 明确的 GLOBAL：全球域名可访问率高且中国域名可访问率低
    if global_results['success_rate'] > 0.6:
        logger.info("明确检测为全球网络环境")
        return NetworkLocation.GLOBAL
    else:
        # 其他所有情况都默认为中国网络环境
        if china_results['success_rate'] > 0.5:
            logger.info("检测到中国网络环境")
        else:
            logger.info("网络环境不明确，默认使用中国网络环境")
        return NetworkLocation.CHINA


def _count_successful_domains(futures_dict: Dict) -> Dict:
    """
    统计域名检测结果
    
    Args:
        futures_dict: 域名检测任务字典
        
    Returns:
        Dict: 包含成功率和平均响应时间的字典
    """
    total = len(futures_dict)
    successful = 0
    total_time = 0
    
    for future in concurrent.futures.as_completed(futures_dict):
        domain = futures_dict[future]
        try:
            success, response_time = future.result()
            if success:
                successful += 1
                total_time += response_time
        except Exception as e:
            logger.debug(f"Error checking domain {domain}: {e}")
    
    avg_time = total_time / successful if successful > 0 else 0
    success_rate = successful / total if total > 0 else 0
    
    return {
        'success_rate': success_rate,
        'avg_response_time': avg_time
    }


def _http_head_fast(domain: str) -> Tuple[bool, float]:
    """
    尝试对域名发起HEAD请求，超时极短。
    
    Args:
        domain: 要检测的域名
        
    Returns:
        Tuple[bool, float]: (是否成功, 响应时间)
    """
    import time
    start_time = time.time()
    try:
        requests.head(f"http://{domain}", timeout=HTTP_TIMEOUT)
        response_time = time.time() - start_time
        return True, response_time
    except RequestException:
        return False, 0


def check_internet_connection() -> bool:
    """
    检查是否有活跃的互联网连接。
    
    Returns:
        bool: 如果有活跃的互联网连接则返回True，否则返回False
    """
    test_domains = ["baidu.com", "google.com", "cloudflare.com", "aliyun.com"]
    
    with Progress(
        SpinnerColumn(),
        TextColumn("[bold blue]检测网络连接中...[/bold blue]"),
        transient=True
    ) as progress:
        progress.add_task("检测", total=None)
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            futures = {executor.submit(_check_socket_connection, domain): domain for domain in test_domains}
            
            for future in concurrent.futures.as_completed(futures):
                try:
                    if future.result():
                        return True
                except Exception:
                    pass
    
    return False


def _check_socket_connection(domain: str) -> bool:
    """
    检查与指定域名的套接字连接
    
    Args:
        domain: 要检测的域名
        
    Returns:
        bool: 如果连接成功则返回True，否则返回False
    """
    try:
        socket.create_connection((domain, 80), timeout=1)
        return True
    except (socket.timeout, socket.gaierror, ConnectionRefusedError):
        return False
