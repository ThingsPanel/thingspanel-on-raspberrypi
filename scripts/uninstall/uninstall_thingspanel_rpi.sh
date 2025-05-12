#!/bin/bash

# ThingsPanel清理脚本
# 用于清理安装残留和进程

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 安装目录
INSTALL_DIR="/home/pi/thingspanel"

# 打印信息函数
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 确认是否继续操作
confirm_action() {
    local message=$1
    local default=${2:-"y"}
    local prompt
    if [ "$default" = "y" ]; then prompt="[Y/n]"; else prompt="[y/N]"; fi
    read -p "$message $prompt " response
    response=${response:-$default}
    if [[ $response =~ ^[Yy]$ ]]; then return 0; else return 1; fi
}

# 清理Docker服务相关问题
cleanup_docker_service() {
    print_info "正在检查Docker服务状态..."
    
    # 检查是否有停止但未删除的容器
    local stopped_containers=$(docker ps -a --filter "status=exited" --filter "status=dead" | grep -E "redis|postgres|timescale|thingspanel" | awk '{print $1}')
    if [ -n "$stopped_containers" ]; then
        print_warning "发现已停止的ThingsPanel相关容器"
        if confirm_action "是否移除这些已停止的容器?"; then
            for container in $stopped_containers; do
                docker rm -f $container 2>/dev/null
                print_info "已移除Docker容器: $container"
            done
            print_success "已停止的ThingsPanel相关容器已移除"
        else
            print_warning "已跳过容器移除"
        fi
    else
        print_info "未发现已停止的ThingsPanel相关容器"
    fi
    
    # 检查是否有docker-proxy遗留进程
    print_info "检查docker-proxy遗留进程..."
    local docker_proxy_pids=$(ps aux | grep docker-proxy | grep -v grep | awk '{print $2}')
    if [ -n "$docker_proxy_pids" ]; then
        print_warning "发现docker-proxy遗留进程: $docker_proxy_pids"
        if confirm_action "是否终止这些docker-proxy进程?"; then
            for pid in $docker_proxy_pids; do
                sudo kill -9 $pid 2>/dev/null
                print_info "已终止docker-proxy进程 PID: $pid"
            done
            print_success "docker-proxy遗留进程已终止"
        else
            print_warning "已跳过docker-proxy进程终止"
        fi
    else
        print_info "未发现docker-proxy遗留进程"
    fi
    
    # 如果发现问题，尝试重启Docker服务
    if [ -n "$stopped_containers" ] || [ -n "$docker_proxy_pids" ]; then
        if confirm_action "是否重启Docker服务以解决潜在问题?"; then
            print_info "正在重启Docker服务..."
            if command -v systemctl &> /dev/null; then
                sudo systemctl restart docker
            else
                sudo service docker restart
            fi
            print_info "等待Docker服务重启完成 (5秒)..."
            sleep 5
            print_success "Docker服务已重启"
        fi
    fi
}

# 清理Redis进程
cleanup_redis() {
    print_info "正在查找运行中的Redis进程..."
    local redis_pids=$(ps aux | grep redis-server | grep -v grep | awk '{print $2}')
    if [ -n "$redis_pids" ]; then
        print_warning "发现正在运行的Redis进程: $redis_pids"
        if confirm_action "是否终止这些Redis进程?"; then
            print_info "正在终止Redis进程..."
            for pid in $redis_pids; do
                sudo kill -9 $pid 2>/dev/null
                print_info "已终止Redis进程 PID: $pid"
            done
            print_success "Redis进程已终止"
        else
            print_warning "已跳过Redis进程终止"
        fi
    else
        print_info "未发现正在运行的Redis进程"
    fi
    
    # 清理Redis Docker容器
    local redis_containers=$(docker ps -a | grep -E "redis|tp-redis" | awk '{print $1}')
    if [ -n "$redis_containers" ]; then
        print_warning "发现Redis相关Docker容器"
        if confirm_action "是否移除这些Docker容器?"; then
            for container in $redis_containers; do
                docker rm -f $container 2>/dev/null
                print_info "已移除Docker容器: $container"
            done
            print_success "Redis相关Docker容器已移除"
        else
            print_warning "已跳过Redis容器移除"
        fi
    else
        print_info "未发现Redis相关Docker容器"
    fi
}

# 清理PostgreSQL/TimescaleDB进程
cleanup_postgres() {
    print_info "正在查找运行中的PostgreSQL/TimescaleDB进程..."
    local postgres_pids=$(ps aux | grep -E "postgres|timescale" | grep -v grep | awk '{print $2}')
    if [ -n "$postgres_pids" ]; then
        print_warning "发现正在运行的PostgreSQL/TimescaleDB进程: $postgres_pids"
        print_warning "这些进程可能是系统关键进程，不建议直接终止"
        if confirm_action "仍然要终止这些PostgreSQL/TimescaleDB进程? (不推荐)"; then
            print_info "正在终止PostgreSQL/TimescaleDB进程..."
            for pid in $postgres_pids; do
                sudo kill -9 $pid 2>/dev/null
                print_info "已终止PostgreSQL/TimescaleDB进程 PID: $pid"
            done
            print_success "PostgreSQL/TimescaleDB进程已终止"
        else
            print_warning "已跳过PostgreSQL/TimescaleDB进程终止"
        fi
    else
        print_info "未发现正在运行的PostgreSQL/TimescaleDB进程"
    fi
    
    # 特别检查5432端口的占用情况
    print_info "特别检查PostgreSQL/TimescaleDB端口(5432)..."
    if netstat -tuln | grep -q ":5432 "; then
        print_warning "端口5432仍然被占用"
        local port_pids=$(sudo lsof -i:5432 -t 2>/dev/null)
        if [ -n "$port_pids" ]; then
            print_warning "以下进程正在占用端口5432: $port_pids"
            if confirm_action "是否终止这些进程以释放端口5432?"; then
                for pid in $port_pids; do
                    sudo kill -9 $pid 2>/dev/null
                    print_info "已终止进程 PID: $pid"
                done
                print_success "占用端口5432的进程已终止"
                # 检查端口是否已释放
                if netstat -tuln | grep -q ":5432 "; then
                    print_warning "端口5432仍然被占用，可能需要重启系统或Docker服务"
                else
                    print_success "端口5432已成功释放"
                fi
            else
                print_warning "已跳过进程终止"
            fi
        else
            print_warning "无法确定占用端口5432的进程，可能需要重启Docker服务或系统"
        fi
    else
        print_info "端口5432未被占用"
    fi
    
    # 清理TimescaleDB Docker容器
    local timescale_containers=$(docker ps -a | grep -E "timescale|postgres" | awk '{print $1}')
    if [ -n "$timescale_containers" ]; then
        print_warning "发现TimescaleDB相关Docker容器"
        if confirm_action "是否移除这些Docker容器?"; then
            for container in $timescale_containers; do
                docker rm -f $container 2>/dev/null
                print_info "已移除Docker容器: $container"
            done
            print_success "TimescaleDB相关Docker容器已移除"
        else
            print_warning "已跳过TimescaleDB容器移除"
        fi
    else
        print_info "未发现TimescaleDB相关Docker容器"
    fi
}

# 清理PM2进程
cleanup_pm2() {
    print_info "正在检查PM2进程..."
    if command -v pm2 &> /dev/null; then
        local pm2_procs=$(pm2 list | grep -E "gmqtt|backend")
        if [ -n "$pm2_procs" ]; then
            print_warning "发现ThingsPanel相关PM2进程"
            if confirm_action "是否终止并移除这些PM2进程?"; then
                pm2 delete gmqtt 2>/dev/null
                pm2 delete backend 2>/dev/null
                pm2 save 2>/dev/null
                print_success "ThingsPanel相关PM2进程已移除"
            else
                print_warning "已跳过PM2进程移除"
            fi
        else
            print_info "未发现ThingsPanel相关PM2进程"
        fi
    else
        print_info "PM2未安装，跳过PM2进程清理"
    fi
}

# 清理Nginx配置
cleanup_nginx() {
    print_info "正在检查Nginx配置..."
    if [ -f "/etc/nginx/sites-enabled/thingspanel" ]; then
        print_warning "发现ThingsPanel的Nginx配置"
        if confirm_action "是否移除ThingsPanel的Nginx配置?"; then
            sudo rm -f /etc/nginx/sites-enabled/thingspanel
            sudo rm -f /etc/nginx/sites-available/thingspanel
            if [ -d "/var/www/html/thingspanel" ]; then
                if confirm_action "是否移除ThingsPanel的Web文件?"; then
                    sudo rm -rf /var/www/html/thingspanel
                    print_success "ThingsPanel的Web文件已移除"
                fi
            fi
            # 重启Nginx
            if systemctl is-active --quiet nginx; then
                print_info "正在重启Nginx..."
                sudo systemctl restart nginx
            fi
            print_success "ThingsPanel的Nginx配置已移除"
        else
            print_warning "已跳过Nginx配置移除"
        fi
    else
        print_info "未发现ThingsPanel的Nginx配置"
    fi
}

# 清理安装目录
cleanup_install_dir() {
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "发现ThingsPanel安装目录: $INSTALL_DIR"
        if confirm_action "是否完全删除ThingsPanel安装目录?"; then
            rm -rf $INSTALL_DIR
            print_success "ThingsPanel安装目录已删除"
        else
            print_warning "已跳过安装目录删除"
        fi
    else
        print_info "未发现ThingsPanel安装目录"
    fi
}

# 清理网络连接
cleanup_network() {
    print_info "正在检查网络连接..."
    # 检查端口占用
    local ports=("1883" "5432" "6379" "9999" "80")
    local occupied_ports=()
    for port in "${ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            occupied_ports+=($port)
        fi
    done
    if [ ${#occupied_ports[@]} -gt 0 ]; then
        print_warning "以下ThingsPanel相关端口仍然被占用: ${occupied_ports[*]}"
        print_info "可以使用以下命令查看详情: sudo lsof -i:<端口号>"
        print_info "例如: sudo lsof -i:6379"
        if confirm_action "是否尝试释放这些端口?"; then
            for port in "${occupied_ports[@]}"; do
                print_info "正在释放端口 $port..."
                # 首先尝试找出占用端口的docker-proxy进程
                local docker_proxy_pids=$(sudo netstat -tnlp 2>/dev/null | grep ":$port " | grep "docker-proxy" | awk '{print $7}' | cut -d'/' -f1)
                if [ -n "$docker_proxy_pids" ]; then
                    print_warning "发现docker-proxy进程占用端口 $port: $docker_proxy_pids"
                    for pid in $docker_proxy_pids; do
                        sudo kill -9 $pid 2>/dev/null
                        print_info "已终止docker-proxy进程 PID: $pid"
                    done
                fi
                # 然后尝试杀死所有占用该端口的进程
                sudo lsof -i:$port -t | xargs -r sudo kill -9
            done
            print_success "端口已尝试释放，如果有系统服务可能会自动重启"
            # 如果端口仍被占用，尝试重启Docker服务
            local still_occupied=false
            for port in "${occupied_ports[@]}"; do
                if netstat -tuln | grep -q ":$port "; then
                    still_occupied=true
                    break
                fi
            done
            if [ "$still_occupied" = true ]; then
                print_warning "部分端口仍然被占用，尝试重启Docker服务..."
                if command -v systemctl &> /dev/null; then
                    sudo systemctl restart docker
                else
                    sudo service docker restart
                fi
                print_info "Docker服务已重启，等待5秒后检查端口状态..."
                sleep 5
                for port in "${occupied_ports[@]}"; do
                    if netstat -tuln | grep -q ":$port "; then
                        print_warning "端口 $port 仍然被占用，可能需要手动处理"
                    else
                        print_success "端口 $port 已成功释放"
                    fi
                done
            fi
        else
            print_warning "已跳过端口释放"
        fi
    else
        print_info "未发现ThingsPanel相关端口占用"
    fi
}

# 清理Docker存储卷
cleanup_docker_volumes() {
    print_info "正在检查Docker存储卷..."
    local volumes=$(docker volume ls | grep -E "redis|timescale|postgres|thingspanel" | awk '{print $2}')
    if [ -n "$volumes" ]; then
        print_warning "发现ThingsPanel相关Docker存储卷"
        if confirm_action "是否移除这些Docker存储卷? (可能导致数据丢失)"; then
            for volume in $volumes; do
                docker volume rm $volume 2>/dev/null
                print_info "已移除Docker存储卷: $volume"
            done
            print_success "ThingsPanel相关Docker存储卷已移除"
        else
            print_warning "已跳过Docker存储卷移除"
        fi
    else
        print_info "未发现ThingsPanel相关Docker存储卷"
    fi
}

# 主函数
main() {
    print_info "======================================================"
    print_info "        ThingsPanel 清理脚本                         "
    print_info "======================================================"
    if ! confirm_action "此脚本将清理ThingsPanel的安装残留，包括进程、容器和文件。是否继续?"; then
        print_warning "用户取消，退出脚本"
        exit 0
    fi
    # 执行清理操作
    cleanup_docker_service
    cleanup_pm2
    cleanup_redis
    cleanup_postgres
    cleanup_nginx
    cleanup_docker_volumes
    cleanup_network
    cleanup_install_dir
    print_success "======================================================"
    print_success "ThingsPanel清理完成!"
    print_success "======================================================"
    # 检查是否仍有服务运行
    print_info "执行最终检查..."
    print_info "Docker容器:"
    docker ps -a | grep -E "redis|postgres|timescale|thingspanel" || echo "未发现ThingsPanel相关容器"
    print_info "进程检查:"
    ps aux | grep -E "redis|postgres|timescale|gmqtt|backend" | grep -v grep || echo "未发现ThingsPanel相关进程"
    print_info "网络端口:"
    netstat -tuln | grep -E ':(80|9999|1883|5432|6379)' || echo "未发现ThingsPanel相关端口"
    print_success "======================================================"
}

# 执行主函数
main
