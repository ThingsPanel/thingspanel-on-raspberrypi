#!/bin/bash

# ThingsPanel树莓派一键安装脚本
# 作者: Junhong

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 安装目录
INSTALL_DIR="/home/pi/thingspanel"
LOG_FILE="$INSTALL_DIR/install.log"

# 创建日志目录和文件
mkdir -p $INSTALL_DIR
touch $LOG_FILE

# 打印带颜色的信息
print_info() {
    # 在完全自动模式下，只记录日志不输出到控制台
    if [ "${AUTO_MODE}" = "true" ] && [ "${VERBOSE}" != "true" ]; then
        echo "[INFO] $1" >> $LOG_FILE
    else
        echo -e "${BLUE}[INFO]${NC} $1"
        echo "[INFO] $1" >> $LOG_FILE
    fi
}

print_success() {
    # 在完全自动模式下，只记录日志不输出到控制台
    if [ "${AUTO_MODE}" = "true" ] && [ "${VERBOSE}" != "true" ]; then
        echo "[SUCCESS] $1" >> $LOG_FILE
    else
        echo -e "${GREEN}[SUCCESS]${NC} $1"
        echo "[SUCCESS] $1" >> $LOG_FILE
    fi
}

print_warning() {
    # 在完全自动模式下，只记录日志不输出到控制台
    if [ "${AUTO_MODE}" = "true" ] && [ "${VERBOSE}" != "true" ]; then
        echo "[WARNING] $1" >> $LOG_FILE
    else
        echo -e "${YELLOW}[WARNING]${NC} $1"
        echo "[WARNING] $1" >> $LOG_FILE
    fi
}

print_error() {
    # 错误信息始终输出到控制台
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> $LOG_FILE
}

# 检查命令执行状态
check_status() {
    if [ $? -eq 0 ]; then
        print_success "$1"
    else
        print_error "$2"
        exit 1
    fi
}

# 检查Docker容器是否存在
check_container_exists() {
    local container_name=$1
    
    # 检查容器是否存在
    if docker ps -a | grep -q "$container_name"; then
        print_warning "发现已存在的容器 '$container_name'，请手动处理！"
        print_warning "可以使用以下命令删除：docker rm -f $container_name"
        print_warning "或者使用不同的容器名称"
        return 1
    fi
    return 0
}

# 检查端口是否已被占用
check_port_occupied() {
    local port=$1
    if netstat -tuln | grep -q ":$port "; then
        return 0  # 端口已被占用
    else
        return 1  # 端口未被占用
    fi
}

# 检查Docker容器是否正在运行
check_container_running() {
    local name_pattern=$1
    if docker ps | grep -q "$name_pattern"; then
        return 0  # 容器正在运行
    else
        return 1  # 容器未运行
    fi
}

# 检查进程是否运行
check_process_running() {
    local process_name=$1
    if pgrep -f "$process_name" > /dev/null; then
        return 0  # 进程正在运行
    else
        return 1  # 进程未运行
    fi
}

# 确认是否继续操作
confirm_action() {
    local message=$1
    local default=${2:-"y"}
    
    # 如果设置了AUTO_MODE，则静默自动确认
    if [ "${AUTO_MODE}" = "true" ]; then
        return 0
    fi
    
    # 如果设置了AUTO_YES，则自动确认但显示信息
    if [ "${AUTO_YES}" = "true" ]; then
        print_info "$message [自动确认]"
        return 0
    fi
    
    local prompt
    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    read -p "$message $prompt " response
    response=${response:-$default}
    
    if [[ $response =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# 创建安装目录
setup_environment() {
    print_info "创建安装目录..."
    sudo chown -R pi:pi $INSTALL_DIR
    mkdir -p $INSTALL_DIR/logs
    
    # 创建日志目录
    print_info "创建日志目录..."
    mkdir -p $INSTALL_DIR/logs
    chmod -R 755 $INSTALL_DIR/logs
    
    check_status "安装环境准备完成" "创建安装目录失败"
}

# 更新系统
update_system() {
    print_info "更新系统..."
    sudo apt update
    sudo apt upgrade -y
    check_status "系统更新完成" "系统更新失败"
}

# 安装必要工具
install_tools() {
    print_info "安装必要工具..."
    sudo apt install -y curl wget git build-essential
    check_status "工具安装完成" "工具安装失败"
}

# 安装Docker
install_docker() {
    print_info "检查Docker是否已安装..."
    if command -v docker &> /dev/null; then
        print_warning "Docker已安装，跳过此步骤"
    else
        print_info "安装Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker pi
        sudo systemctl enable docker
        sudo systemctl start docker
        check_status "Docker安装完成" "Docker安装失败"
    fi
}

# 检测ARM架构并设置GOARCH
detect_arm_arch() {
    print_info "正在检测系统架构..."
    local arch=$(uname -m)
    
    if [[ "$arch" == "aarch64" ]]; then
        print_info "检测到64位ARM架构 (aarch64)"
        ARM_ARCH="arm64"
    elif [[ "$arch" == "armv7l" || "$arch" == "armv6l" ]]; then
        print_info "检测到32位ARM架构 ($arch)"
        ARM_ARCH="arm"
    else
        print_warning "未知架构: $arch，默认使用arm64"
        ARM_ARCH="arm64"
    fi
    
    print_info "设置GOARCH=$ARM_ARCH"
}

# 安装Go
install_go() {
    print_info "检查Go是否已安装..."
    if command -v go &> /dev/null; then
        GO_VERSION=$(go version | awk '{print $3}')
        print_warning "Go已安装，版本: $GO_VERSION"
    else
        print_info "安装Go 1.22.1..."
        
        # 根据架构选择Go安装包
        if [ "$ARM_ARCH" = "arm64" ]; then
            wget https://go.dev/dl/go1.22.1.linux-arm64.tar.gz -O /tmp/go1.22.1.linux-arm.tar.gz
        else
            wget https://go.dev/dl/go1.22.1.linux-armv6l.tar.gz -O /tmp/go1.22.1.linux-arm.tar.gz
        fi
        
        sudo tar -C /usr/local -xzf /tmp/go1.22.1.linux-arm.tar.gz
        
        # 设置Go环境变量
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
        echo 'export GOPATH=$HOME/go' >> ~/.profile
        # 设置Go架构环境变量
        echo "export GOARCH=$ARM_ARCH" >> ~/.profile
        source ~/.profile
        
        # 设置Go代理
        go env -w GO111MODULE=on
        go env -w GOPROXY=https://goproxy.cn
        
        check_status "Go安装完成" "Go安装失败"
    fi
}

# 获取占用端口的进程信息
get_port_processes() {
    local port=$1
    local result=$(sudo lsof -i:$port -t 2>/dev/null)
    local docker_proxy=$(ps aux | grep docker-proxy | grep ":$port" | grep -v grep | awk '{print $2}')
    
    if [ -n "$docker_proxy" ]; then
        # 如果存在docker-proxy进程，优先返回这些
        echo "$docker_proxy"
    else
        # 否则返回lsof查找到的进程
        echo "$result"
    fi
}

# 尝试释放端口
try_release_port() {
    local port=$1
    local max_attempts=$2
    local wait_time=$3
    
    print_info "尝试释放端口 $port..."
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        print_info "尝试 $attempt/$max_attempts 释放端口 $port"
        
        # 检查是否有docker-proxy进程
        local docker_proxy_pids=$(ps aux | grep docker-proxy | grep ":$port" | grep -v grep | awk '{print $2}')
        if [ -n "$docker_proxy_pids" ]; then
            print_warning "发现docker-proxy进程占用端口 $port: $docker_proxy_pids"
            for pid in $docker_proxy_pids; do
                sudo kill -9 $pid 2>/dev/null
                print_info "已终止docker-proxy进程 PID: $pid"
            done
            
            # 如果有docker-proxy进程，尝试重启docker服务
            print_info "尝试重启Docker服务以释放端口..."
            if command -v systemctl &> /dev/null; then
                sudo systemctl restart docker
            else
                sudo service docker restart
            fi
            print_info "等待Docker服务重启完成 ($wait_time 秒)..."
            sleep $wait_time
        fi
        
        # 杀死所有占用该端口的进程
        local port_pids=$(sudo lsof -i:$port -t 2>/dev/null)
        if [ -n "$port_pids" ]; then
            print_warning "发现进程占用端口 $port: $port_pids"
            for pid in $port_pids; do
                sudo kill -9 $pid 2>/dev/null
                print_info "已终止进程 PID: $pid"
            done
            sleep 2
        fi
        
        # 检查端口是否已释放
        if ! check_port_occupied $port; then
            print_success "端口 $port 已成功释放"
            return 0
        fi
        
        print_warning "端口 $port 仍被占用，等待..."
        sleep $wait_time
        attempt=$((attempt + 1))
    done
    
    print_error "端口 $port 无法释放，已尝试 $max_attempts 次"
    print_info "占用端口 $port 的进程信息:"
    sudo lsof -i:$port || echo "无法获取进程信息"
    ps aux | grep docker-proxy | grep ":$port" | grep -v grep || echo "未发现docker-proxy进程"
    
    return 1
}

# 检查容器是否存在并尝试移除
check_and_remove_container() {
    local container_pattern=$1
    local force=$2
    
    # 查找所有匹配的容器
    local containers=$(docker ps -a | grep "$container_pattern" | awk '{print $1}')
    if [ -n "$containers" ]; then
        print_warning "发现匹配的容器: $containers"
        
        if [ "$force" = "true" ] || confirm_action "是否移除这些容器?"; then
            for container in $containers; do
                print_info "正在移除容器 $container"
                docker rm -f $container 2>/dev/null
                if [ $? -eq 0 ]; then
                    print_success "容器 $container 已成功移除"
                else
                    print_error "移除容器 $container 失败"
                fi
            done
            return 0
        else
            print_warning "跳过容器移除"
            return 1
        fi
    fi
    
    return 0
}

# 修改install_timescaledb函数，解决容器启动失败问题
install_timescaledb() {
    print_info "检查TimescaleDB是否已安装..."
    
    # 检查TimescaleDB端口是否已被占用
    if check_port_occupied 5432; then
        print_warning "检测到端口5432已被占用，可能已有PostgreSQL/TimescaleDB服务在运行"
        
        # 检查是否有TimescaleDB容器在运行
        if check_container_running "timescaledb"; then
            TIMESCALE_CONTAINER=$(docker ps | grep timescaledb | awk '{print $NF}')
            print_success "检测到TimescaleDB容器正在运行: $TIMESCALE_CONTAINER，跳过安装"
            return 0
        else
            # 端口被占用但不是Docker容器，询问是否强制安装
            if confirm_action "端口5432被占用但未找到TimescaleDB容器，是否尝试强制释放端口并安装？"; then
                # 尝试移除所有相关容器
                check_and_remove_container "timescaledb" true
                check_and_remove_container "postgres" true
                
                # 尝试释放端口
                if ! try_release_port 5432 5 5; then
                    print_error "无法释放端口5432，安装失败"
                    print_info "请尝试运行清理脚本后再重试安装: bash thingspanel_cleanup.sh"
                    print_info "或者手动重启系统后再试"
                    exit 1
                fi
            else
                print_warning "跳过TimescaleDB安装"
                return 0
            fi
        fi
    fi
    
    print_info "安装TimescaleDB..."
    
    # 使用时间戳生成唯一容器名称
    local timescale_container="timescaledb-$(date +%s)"
    print_info "使用容器名称: $timescale_container"
    
    mkdir -p $INSTALL_DIR/timescaledb/data
    
    # 检查端口是否仍然被占用
    if check_port_occupied 5432; then
        print_error "端口5432仍然被占用，无法启动TimescaleDB容器"
        print_info "请尝试运行清理脚本后再重试安装: bash thingspanel_cleanup.sh"
        exit 1
    fi
    
    # 创建自定义的初始化脚本目录
    mkdir -p $INSTALL_DIR/timescaledb/init
    
    # 创建自定义的初始化脚本，跳过timescaledb_tune步骤
    cat > $INSTALL_DIR/timescaledb/init/000_install_timescaledb.sh << 'EOF'
#!/bin/bash
set -e

echo "安装TimescaleDB扩展..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS timescaledb;
    CREATE EXTENSION IF NOT EXISTS btree_gist;
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
EOSQL
echo "TimescaleDB扩展安装完成"
EOF
    
    chmod +x $INSTALL_DIR/timescaledb/init/000_install_timescaledb.sh
    
    # 启动容器，使用自定义的初始化脚本而不是默认的
    print_info "启动TimescaleDB容器..."
    docker run --name $timescale_container -p 5432:5432 \
    -e TZ=Asia/Shanghai \
    -e POSTGRES_DB=ThingsPanel \
    -e POSTGRES_USER=postgres \
    -e POSTGRES_PASSWORD=postgresThingsPanel \
    -v $INSTALL_DIR/timescaledb/data:/var/lib/postgresql/data \
    -v $INSTALL_DIR/timescaledb/init:/docker-entrypoint-initdb.d \
    -d timescale/timescaledb:latest-pg14
    
    # 检查容器是否成功启动
    sleep 5 # 等待容器启动
    if ! docker ps | grep -q "$timescale_container"; then
        print_error "TimescaleDB容器未能成功启动"
        docker logs $timescale_container 2>/dev/null || echo "无法获取容器日志"
        print_info "尝试移除失败的容器..."
        docker rm -f $timescale_container 2>/dev/null
        
        # 如果容器无法启动，可能是端口问题或其他问题
        print_warning "检查是否有其他隐藏的PostgreSQL相关进程..."
        ps aux | grep -E "postgres|timescale" | grep -v grep
        
        print_warning "检查网络端口状态..."
        netstat -tuln | grep 5432
        
        # 尝试使用更基础的PostgreSQL镜像
        print_warning "尝试使用基础PostgreSQL镜像作为备选方案..."
        docker run --name postgres-$timescale_container -p 5432:5432 \
        -e TZ=Asia/Shanghai \
        -e POSTGRES_DB=ThingsPanel \
        -e POSTGRES_USER=postgres \
        -e POSTGRES_PASSWORD=postgresThingsPanel \
        -v $INSTALL_DIR/timescaledb/data:/var/lib/postgresql/data \
        -d postgres:14-alpine
        
        sleep 5 # 等待容器启动
        if ! docker ps | grep -q "postgres-$timescale_container"; then
            print_error "备选PostgreSQL容器也未能成功启动"
            docker logs postgres-$timescale_container 2>/dev/null || echo "无法获取容器日志"
            print_error "TimescaleDB/PostgreSQL安装失败"
            exit 1
        else
            print_warning "使用基础PostgreSQL作为替代品，某些TimescaleDB功能可能不可用"
            timescale_container="postgres-$timescale_container"
        fi
    fi
    
    # 等待数据库初始化
    print_info "等待数据库初始化 (30秒)..."
    sleep 30
    
    # 再次验证容器状态
    if ! docker ps | grep -q "$timescale_container"; then
        print_error "数据库容器在等待期间停止了"
        docker logs $timescale_container
        exit 1
    fi
    
    print_success "数据库安装完成"
}

# 安装Redis
install_redis() {
    print_info "检查Redis是否已安装..."
    
    # 检查Redis端口是否已被占用
    if check_port_occupied 6379; then
        print_warning "检测到端口6379已被占用，可能已有Redis服务在运行"
        
        # 检查是否有Redis容器在运行
        if check_container_running "redis"; then
            REDIS_CONTAINER=$(docker ps | grep redis | awk '{print $NF}')
            print_success "检测到Redis容器正在运行: $REDIS_CONTAINER，跳过安装"
            return 0
        else
            # 端口被占用但不是Docker容器，询问是否强制安装
            if confirm_action "端口6379被占用但未找到Redis容器，是否尝试强制释放端口并安装？"; then
                # 尝试移除所有相关容器
                check_and_remove_container "redis" true
                check_and_remove_container "tp-redis" true
                
                # 尝试释放端口
                if ! try_release_port 6379 5 5; then
                    print_error "无法释放端口6379，安装失败"
                    print_info "请尝试运行清理脚本后再重试安装: bash thingspanel_cleanup.sh"
                    print_info "或者手动重启系统后再试"
                    exit 1
                fi
            else
                print_warning "跳过Redis安装"
                return 0
            fi
        fi
    fi
    
    print_info "安装Redis..."
    
    # 使用时间戳生成唯一容器名称
    local redis_container="tp-redis-$(date +%s)"
    print_info "使用容器名称: $redis_container"
    
    mkdir -p $INSTALL_DIR/redis/data
    mkdir -p $INSTALL_DIR/redis/conf
    mkdir -p $INSTALL_DIR/redis/logs
    
    # 检查端口是否仍然被占用
    if check_port_occupied 6379; then
        print_error "端口6379仍然被占用，无法启动Redis容器"
        print_info "请尝试运行清理脚本后再重试安装: bash thingspanel_cleanup.sh"
        exit 1
    fi
    
    # 启动容器
    print_info "启动Redis容器..."
    docker run --name $redis_container \
    -v $INSTALL_DIR/redis/data:/data \
    -v $INSTALL_DIR/redis/conf:/usr/local/etc/redis \
    -v $INSTALL_DIR/redis/logs:/logs \
    -d -p 6379:6379 redis redis-server --requirepass redis
    
    # 检查容器是否成功启动
    sleep 5 # 等待容器启动
    if ! docker ps | grep -q "$redis_container"; then
        print_error "Redis容器未能成功启动"
        docker logs $redis_container 2>/dev/null || echo "无法获取容器日志"
        print_info "尝试移除失败的容器..."
        docker rm -f $redis_container 2>/dev/null
        
        print_warning "检查网络端口状态..."
        netstat -tuln | grep 6379
        
        # 尝试再次释放端口
        print_warning "尝试再次清理端口和进程..."
        try_release_port 6379 3 3
        
        print_error "Redis安装失败"
        print_info "请尝试运行以下命令进行清理后再重试安装:"
        print_info "1. bash thingspanel_cleanup.sh"
        print_info "2. sudo systemctl restart docker"
        print_info "3. 如果问题仍然存在，尝试重启系统"
        exit 1
    fi
    
    print_success "Redis安装完成"
}

# 安装GMQTT
install_gmqtt() {
    print_info "检查GMQTT是否已安装..."
    
    # 检查GMQTT端口是否已被占用
    if check_port_occupied 1883; then
        print_warning "检测到端口1883已被占用，可能已有MQTT服务在运行"
        
        # 检查PM2是否在运行GMQTT
        if pm2 list | grep -q "gmqtt"; then
            print_success "检测到GMQTT服务正在通过PM2运行，跳过安装"
            return 0
        else
            # 端口被占用但不是PM2管理的GMQTT，询问是否强制安装
            if confirm_action "端口1883被占用但未找到GMQTT服务，是否尝试强制释放端口并安装？"; then
                print_info "尝试停止所有占用1883端口的进程..."
                sudo lsof -i:1883 -t | xargs -r sudo kill -9
                sleep 2
            else
                print_warning "跳过GMQTT安装"
                return 0
            fi
        fi
    fi
    
    print_info "安装GMQTT..."
    cd $INSTALL_DIR
    
    # 如果目录已存在但未跳过安装，先删除
    if [ -d "$INSTALL_DIR/thingspanel-gmqtt" ]; then
        print_warning "GMQTT目录已存在，正在删除..."
        rm -rf "$INSTALL_DIR/thingspanel-gmqtt"
    fi
    
    # 检查数据库连接
    print_info "检查数据库服务..."
    if ! docker ps | grep -q "timescaledb"; then
        print_warning "TimescaleDB容器未运行，尝试启动..."
        install_timescaledb
    fi
    
    # 确保数据库连接正常
    if ! check_database_connection; then
        print_error "无法连接到数据库，请先确保TimescaleDB正常运行"
        if confirm_action "是否仍然继续安装GMQTT? (不推荐)"; then
            print_warning "继续安装，但GMQTT可能无法正常工作"
        else
            print_error "安装已取消，请先解决数据库连接问题"
            return 1
        fi
    fi
    
    # 我们只支持从源码编译，无需下载预编译包
    print_info "从源码编译GMQTT..."
    mkdir -p $INSTALL_DIR/thingspanel-gmqtt
    mkdir -p $INSTALL_DIR/thingspanel-gmqtt/cmd/gmqttd
    cd $INSTALL_DIR/thingspanel-gmqtt
    
    # 克隆源码
    print_info "克隆GMQTT源码..."
    git clone --depth=1 https://github.com/ThingsPanel/thingspanel-gmqtt.git .
    
    # 如果源码获取失败
    if [ $? -ne 0 ]; then
        print_error "克隆GMQTT源码失败"
        return 1
    fi
    
    # 检查Go环境
    if ! command -v go &> /dev/null; then
        print_error "未安装Go编译环境，无法从源码编译"
        return 1
    fi
    
    # 编译GMQTT
    print_info "编译GMQTT..."
    cd $INSTALL_DIR/thingspanel-gmqtt
    go build -o cmd/gmqttd/gmqttd cmd/gmqttd/main.go
    
    if [ $? -ne 0 ]; then
        print_error "GMQTT编译失败"
        return 1
    fi
    
    # 创建配置文件
    print_info "创建GMQTT配置文件..."
    cd $INSTALL_DIR/thingspanel-gmqtt/cmd/gmqttd
    cat > $INSTALL_DIR/thingspanel-gmqtt/cmd/gmqttd/thingspanel.yml << EOL
db:
  redis:
    # redis连接字符串
    conn: 127.0.0.1:6379
    # redis数据库号
    db_num: 1
    # redis密码
    password: "redis"
  psql:
    psqladdr: "127.0.0.1"
    psqlport: 5432
    psqldb: ThingsPanel
    psqluser: postgres
    psqlpass: postgresThingsPanel
mqtt:
  # root用户的密码
  broker: localhost:1883
  password: "root"
  plugin_password: "plugin"
EOL

    # 创建启动脚本
    print_info "创建GMQTT启动脚本..."
    # 修改GMQTT启动脚本，确保它使用正确的配置文件
cat > $INSTALL_DIR/thingspanel-gmqtt/cmd/gmqttd/gmqtt.sh << EOL
#!/bin/bash
cd $INSTALL_DIR/thingspanel-gmqtt/cmd/gmqttd

# 确保日志目录存在
mkdir -p $INSTALL_DIR/logs

# 打印配置文件内容进行调试
echo "thingspanel.yml 配置:"
cat thingspanel.yml

# 检查Redis连接
echo "检查Redis连接..."
redis-cli -h 127.0.0.1 -p 6379 -a redis ping || {
    echo "Redis连接失败! 尝试重启Redis..."
    docker restart \$(docker ps | grep redis | awk '{print \$1}')
    sleep 5
}

# 启动GMQTT
./thingspanel-gmqtt start -c thingspanel.yml
EOL

    chmod +x $INSTALL_DIR/thingspanel-gmqtt/cmd/gmqttd/gmqtt.sh
    
    # 安装PM2
    print_info "检查Node.js和PM2是否已安装..."
    if ! command -v npm &> /dev/null; then
        print_info "安装Node.js..."
        curl -sL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt install -y nodejs
    fi
    
    if ! command -v pm2 &> /dev/null; then
        print_info "安装PM2..."
        sudo npm install pm2 -g
    fi
    
    # 停止和删除已有的PM2进程
    if pm2 list | grep -q "gmqtt"; then
        print_warning "已有GMQTT进程正在运行，正在重启..."
        pm2 delete gmqtt 2>/dev/null
    fi
    
    # 检查端口是否仍然被占用
    if check_port_occupied 1883; then
        print_error "端口1883仍然被占用，无法启动GMQTT服务"
        print_info "请手动释放端口后重试，可以使用 'sudo lsof -i:1883' 查看占用进程"
        return 1
    fi
    
    # 使用PM2启动GMQTT
    print_info "使用PM2启动GMQTT..."
    pm2 start gmqtt.sh --name gmqtt
    pm2 save
    
    # 等待GMQTT启动
    print_info "等待GMQTT启动..."
    
    COUNTER=0
    MAX_RETRY=12  # 60秒超时
    GMQTT_STARTED=false
    
    while [ $COUNTER -lt $MAX_RETRY ]; do
        if check_port_occupied 1883; then
            print_success "GMQTT已启动，端口1883已监听"
            GMQTT_STARTED=true
            break
        fi
        
        print_info "GMQTT启动中，等待5秒... ($COUNTER/$MAX_RETRY)"
        sleep 5
        COUNTER=$((COUNTER + 1))
    done
    
    if [ "$GMQTT_STARTED" = false ]; then
        print_warning "GMQTT启动超时，请检查日志: pm2 logs gmqtt"
        # 我们不退出，继续安装其他组件
        return 1
    fi
    
    print_success "GMQTT源码编译版安装完成"
    return 0
}

# 检查数据库连接
check_database_connection() {
    print_info "检查数据库连接..."
    
    # 获取数据库容器名称
    local db_container=$(docker ps | grep timescaledb | awk '{print $NF}')
    
    if [ -z "$db_container" ]; then
        print_warning "未找到运行中的TimescaleDB容器"
        return 1
    fi
    
    print_info "发现TimescaleDB容器: $db_container"
    
    # 检查容器是否正在运行
    if ! docker ps | grep -q "$db_container"; then
        print_warning "TimescaleDB容器不在运行状态"
        return 1
    fi
    
    # 尝试连接数据库
    print_info "尝试连接到数据库..."
    if docker exec $db_container psql -U postgres -c "SELECT 1" >/dev/null 2>&1; then
        print_success "数据库连接成功"
        return 0
    else
        print_warning "无法连接到数据库"
        
        # 检查容器日志
        print_info "检查容器日志..."
        docker logs --tail 20 $db_container
        
        # 尝试重启容器
        if confirm_action "是否尝试重启TimescaleDB容器?"; then
            print_info "重启TimescaleDB容器..."
            docker restart $db_container
            
            # 等待容器启动
            print_info "等待数据库启动..."
            sleep 15
            
            # 再次尝试连接
            if docker exec $db_container psql -U postgres -c "SELECT 1" >/dev/null 2>&1; then
                print_success "数据库重启后连接成功"
                return 0
            else
                print_error "数据库重启后仍然无法连接"
                return 1
            fi
        fi
        
        return 1
    fi
}

# 安装预编译的ThingsPanel后台
install_prebuilt_backend() {
    print_info "检查ThingsPanel后台是否已安装..."
    
    # 检查后台API端口是否已被占用
    if check_port_occupied 9999; then
        print_warning "检测到端口9999已被占用，可能已有后台服务在运行"
        
        # 检查PM2是否在运行backend
        if pm2 list | grep -q "backend"; then
            print_success "检测到后台服务正在通过PM2运行，跳过安装"
            return 0
        else
            # 端口被占用但不是PM2管理的backend，询问是否强制安装
            if confirm_action "端口9999被占用但未找到后台服务进程，是否尝试强制释放端口并安装？"; then
                print_info "尝试停止所有占用9999端口的进程..."
                sudo lsof -i:9999 -t | xargs -r sudo kill -9
                sleep 2
            else
                print_warning "跳过后台服务安装"
                return 0
            fi
        fi
    fi
    
    print_info "安装预编译ThingsPanel后台..."
    cd $INSTALL_DIR
    
    # 如果目录已存在但未跳过安装，先删除
    if [ -d "$INSTALL_DIR/thingspanel-backend-community" ]; then
        print_warning "Backend目录已存在，正在删除..."
        rm -rf "$INSTALL_DIR/thingspanel-backend-community"
    fi
    
    # 创建目录
    mkdir -p $INSTALL_DIR/thingspanel-backend-community
    cd $INSTALL_DIR/thingspanel-backend-community
    
    # 下载预编译包
    print_info "下载预编译包..."
    wget -O backend.tar.gz "https://github.com/ThingsPanel/thingspanel-backend-community/releases/download/latest/thingspanel-backend-community-linux-arm64.tar.gz"
    
    # 解压预编译包
    print_info "解压预编译包..."
    tar -xzf backend.tar.gz
    rm backend.tar.gz
    
    # 确保linux-arm64目录存在（基于日志观察，二进制文件可能在此目录）
    if [ -d "linux-arm64" ] && [ -f "linux-arm64/thingspanel-backend-community" ]; then
        print_info "检测到预编译二进制文件位于linux-arm64目录中..."
        chmod +x linux-arm64/thingspanel-backend-community
    else
        print_error "无法找到预编译二进制文件，安装失败"
        print_info "目录结构:"
        ls -la
        exit 1
    fi
    
# 找到脚本中创建后端配置文件的部分（install_prebuilt_backend函数中）
# 将原来的配置文件创建代码替换为以下内容：

# 创建配置文件目录
mkdir -p configs
cat > configs/conf.yml << EOL
service:
  http: 
    host: 0.0.0.0
    port: 9999

log:
  adapter_type: 2
  maxdays: 7
  level: debug
  maxlines: 10000

jwt:
  key: 1hj5b0sp9

db:
  psql:
    host: 127.0.0.1
    port: 5432
    dbname: ThingsPanel
    username: postgres
    password: postgresThingsPanel
    time_zone: Asia/Shanghai
    idle_conns: 5
    open_conns: 50
    log_level: 4
    slow_threshold: 200

  redis:
    conn: 127.0.0.1:6379
    db_num: 1
    password: "redis"

grpc:
  tptodb_server: 127.0.0.1:50052
  tptodb_type: NONE  # 改为小写的none

mqtt_server: gmqtt

mqtt:
  access_address: 127.0.0.1:1883
  broker: 127.0.0.1:1883
  user: root
  pass: root
  channel_buffer_size: 10000
  write_workers: 10
  telemetry:
    publish_topic: devices/telemetry/control/
    subscribe_topic: devices/telemetry
    gateway_subscribe_topic: gateway/telemetry
    gateway_publish_topic: gateway/telemetry/control/%s
    pool_size: 100
    batch_size: 100
    qos: 0
  attributes:
    subscribe_topic: devices/attributes/+
    publish_response_topic: devices/attributes/response/
    publish_topic: devices/attributes/set/
    subscribe_response_topic: devices/attributes/set/response/+
    publish_get_topic: devices/attributes/get/
    gateway_subscribe_topic: gateway/attributes/+
    gateway_publish_response_topic: gateway/attributes/response/%s/%s
    gateway_publish_topic: gateway/attributes/set/%s/%s
    gateway_subscribe_response_topic: gateway/attributes/set/response/+
    gateway_publish_get_topic: gateway/attributes/get/%s
    qos: 1
  commands:
    publish_topic: devices/command/
    subscribe_topic: devices/command/response/+
    gateway_subscribe_topic: gateway/command/response/+
    gateway_publish_topic: gateway/command/%s/%s
    qos: 1
  events:
    subscribe_topic: devices/event/+
    publish_topic: devices/event/response/
    gateway_subscribe_topic: gateway/event/+
    gateway_publish_topic: gateway/event/response/%s/%s
    qos: 1
  ota:
    publish_topic: ota/devices/infrom/
    subscribe_topic: ota/devices/progress
    qos: 1

automation_task_confg:
  once_task_limit: 100
  periodic_task_limit: 100

ota:
  download_address: http://127.0.0.1
EOL
# 创建增强版后端启动脚本
create_backend_startup_script $INSTALL_DIR

    # 复制配置文件到linux-arm64目录（如果该目录存在配置目录）
    if [ -d "linux-arm64/configs" ]; then
        cp configs/conf.yml linux-arm64/configs/
    fi

    # 获取数据库容器名称
    DB_CONTAINER=$(docker ps | grep timescaledb | awk '{print $NF}')
    REDIS_CONTAINER=$(docker ps | grep tp-redis | awk '{print $NF}')
    
    print_info "数据库容器: $DB_CONTAINER"
    print_info "Redis容器: $REDIS_CONTAINER"
    
    # 检查数据库连接
    # 检查数据库是否已启动
    print_info "检查数据库服务..."
    if ! docker ps | grep -q "timescaledb"; then
        print_warning "TimescaleDB容器未运行，尝试启动..."
        install_timescaledb
    fi
    
    # 确保数据库连接正常
    if ! check_database_connection; then
        print_error "无法连接到数据库，请先确保TimescaleDB正常运行"
        if confirm_action "是否仍然继续安装后端服务? (不推荐)"; then
            print_warning "继续安装，但后端服务可能无法正常工作"
        else
            print_error "安装已取消，请先解决数据库连接问题"
            return 1
        fi
    fi
    
    # 创建启动脚本，指向正确的二进制文件位置
    cat > backend.sh << EOL
#!/bin/bash
cd $INSTALL_DIR/thingspanel-backend-community

# 确保日志目录存在
mkdir -p files/logs
mkdir -p $INSTALL_DIR/logs

# 检查二进制文件位置并启动
if [ -f "./linux-arm64/thingspanel-backend-community" ]; then
    cd linux-arm64
    ./thingspanel-backend-community
else
    # 如果找不到预期位置的二进制文件，尝试查找其他可能位置
    echo "\$(date) - ERROR: 找不到后端二进制文件" >> $INSTALL_DIR/logs/backend_error.log
    find . -name "thingspanel-backend-community" -type f -executable >> $INSTALL_DIR/logs/backend_error.log
    exit 1
fi
EOL
    
    chmod +x backend.sh
    
    # 停止和删除已有的PM2进程
    if pm2 list | grep -q "backend"; then
        print_warning "已有Backend进程正在运行，正在重启..."
        pm2 delete backend 2>/dev/null
    fi
    
    # 检查端口是否仍然被占用
    if check_port_occupied 9999; then
        print_error "端口9999仍然被占用，无法启动后台服务"
        print_info "请手动释放端口后重试，可以使用 'sudo lsof -i:9999' 查看占用进程"
        exit 1
    fi
    
    # 使用PM2启动后台
    pm2 start backend.sh --name backend
    pm2 save
    
    # 等待后端启动并检查
    print_info "等待后端服务启动..."
    
    COUNTER=0
    MAX_RETRY=24  # 120秒超时
    BACKEND_STARTED=false
    
    while [ $COUNTER -lt $MAX_RETRY ]; do
        if check_port_occupied 9999; then
            print_success "后端服务已启动，端口9999已监听"
            BACKEND_STARTED=true
            break
        fi
        
        print_info "后端启动中，等待5秒... ($COUNTER/$MAX_RETRY)"
        sleep 5
        COUNTER=$((COUNTER + 1))
    done
    
    if [ "$BACKEND_STARTED" = false ]; then
        print_warning "后端启动超时，请检查日志:"
        print_warning "PM2日志: pm2 logs backend"
        print_warning "应用日志: cat $INSTALL_DIR/thingspanel-backend-community/files/logs/app.log"
        
        # 我们不退出，继续安装其他组件
    else
        # 检查端口是否开放
        print_info "测试后端API..."
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:9999/api/version; then
            print_success "后端API测试成功"
        else
            print_warning "后端API测试失败，请检查日志"
        fi
    fi
    
    # 开放防火墙端口
    print_info "配置防火墙..."
    sudo ufw allow 9999/tcp 2>/dev/null || true
    
    check_status "ThingsPanel预编译后台安装完成" "ThingsPanel预编译后台安装失败"
}

# 安装预编译的GMQTT
install_prebuilt_gmqtt() {
    print_info "检查GMQTT是否已安装..."
    
    # 检查GMQTT端口是否已被占用
    if check_port_occupied 1883; then
        print_warning "检测到端口1883已被占用，可能已有MQTT服务在运行"
        
        # 检查PM2是否在运行GMQTT
        if pm2 list | grep -q "gmqtt"; then
            print_success "检测到GMQTT服务正在通过PM2运行，跳过安装"
            return 0
        else
            # 端口被占用但不是PM2管理的GMQTT，询问是否强制安装
            if confirm_action "端口1883被占用但未找到GMQTT服务，是否尝试强制释放端口并安装？"; then
                print_info "尝试停止所有占用1883端口的进程..."
                sudo lsof -i:1883 -t | xargs -r sudo kill -9
                sleep 2
            else
                print_warning "跳过GMQTT安装"
                return 0
            fi
        fi
    fi
    
    print_info "安装预编译GMQTT..."
    cd $INSTALL_DIR
    
    # 如果目录已存在但未跳过安装，先删除
    if [ -d "$INSTALL_DIR/thingspanel-gmqtt" ]; then
        print_warning "GMQTT目录已存在，正在删除..."
        rm -rf "$INSTALL_DIR/thingspanel-gmqtt"
    fi
    
    # 检查数据库连接
    print_info "检查数据库服务..."
    if ! docker ps | grep -q "timescaledb"; then
        print_warning "TimescaleDB容器未运行，尝试启动..."
        install_timescaledb
    fi
    
    # 确保数据库连接正常
    if ! check_database_connection; then
        print_error "无法连接到数据库，请先确保TimescaleDB正常运行"
        if confirm_action "是否仍然继续安装GMQTT? (不推荐)"; then
            print_warning "继续安装，但GMQTT可能无法正常工作"
        else
            print_error "安装已取消，请先解决数据库连接问题"
            return 1
        fi
    fi
    
    # 创建目录
    mkdir -p $INSTALL_DIR/thingspanel-gmqtt
    mkdir -p $INSTALL_DIR/thingspanel-gmqtt/cmd/gmqttd
    cd $INSTALL_DIR/thingspanel-gmqtt
    
    # 下载预编译包
    print_info "下载预编译包..."
    wget -O gmqtt.tar.gz "https://github.com/ThingsPanel/thingspanel-gmqtt/releases/download/latest/thingspanel-gmqtt-linux-arm64.tar.gz"
    
    # 解压预编译包
    print_info "解压预编译包..."
    tar -xzf gmqtt.tar.gz
    rm gmqtt.tar.gz
    
    # 处理解压后的文件夹结构
    print_info "处理解压后的文件..."
    if [ -d "linux-arm64" ]; then
        print_info "发现linux-arm64目录，正在移动文件..."
        # 检查是否有二进制文件
        if [ -f "linux-arm64/thingspanel-gmqtt" ]; then
            # 二进制文件在顶层
            print_info "在linux-arm64目录中发现二进制文件，移动到cmd/gmqttd目录..."
            mkdir -p cmd/gmqttd
            mv linux-arm64/thingspanel-gmqtt cmd/gmqttd/
            
            # 检查配置文件
            if [ -f "linux-arm64/default_config.yml" ]; then
                mv linux-arm64/default_config.yml cmd/gmqttd/
            fi
            if [ -f "linux-arm64/thingspanel.yml" ]; then
                mv linux-arm64/thingspanel.yml cmd/gmqttd/
            fi
            
            # 移动可能存在的certs目录
            if [ -d "linux-arm64/certs" ]; then
                mv linux-arm64/certs cmd/gmqttd/
            else
                mkdir -p cmd/gmqttd/certs
            fi
            
            rm -rf linux-arm64
        elif [ -d "linux-arm64/cmd" ] && [ -d "linux-arm64/cmd/gmqttd" ]; then
            # 目录结构已经是 linux-arm64/cmd/gmqttd
            print_info "发现预期目录结构，直接使用..."
            cp -r linux-arm64/cmd ./
            rm -rf linux-arm64
        else
            # 查找二进制文件
            BINARY_PATH=$(find linux-arm64 -name "thingspanel-gmqtt" -type f | head -1)
            if [ -n "$BINARY_PATH" ]; then
                print_info "找到二进制文件: $BINARY_PATH"
                DIR_PATH=$(dirname "$BINARY_PATH")
                if [ "$DIR_PATH" != "linux-arm64" ]; then
                    print_info "复制目录结构: $DIR_PATH"
                    mkdir -p cmd/gmqttd
                    cp -r "$DIR_PATH"/* cmd/gmqttd/
                else
                    print_info "二进制文件在顶层，创建标准目录结构..."
                    mkdir -p cmd/gmqttd
                    mv "$BINARY_PATH" cmd/gmqttd/
                    # 查找配置文件
                    find linux-arm64 -name "*.yml" -exec cp {} cmd/gmqttd/ \;
                    # 查找certs目录
                    if [ -d "linux-arm64/certs" ]; then
                        cp -r linux-arm64/certs cmd/gmqttd/
                    else
                        mkdir -p cmd/gmqttd/certs
                    fi
                fi
            else
                print_error "在解压后的目录中找不到thingspanel-gmqtt二进制文件"
                print_info "目录结构:"
                find linux-arm64 -type f | sort
                return 1
            fi
            rm -rf linux-arm64
        fi
    fi
    
    # 检查二进制文件
    if [ -f "cmd/gmqttd/thingspanel-gmqtt" ]; then
        print_info "发现GMQTT二进制文件: cmd/gmqttd/thingspanel-gmqtt"
        chmod +x cmd/gmqttd/thingspanel-gmqtt
        # 创建启动脚本
        print_info "创建GMQTT启动脚本..."
        cat > cmd/gmqttd/gmqtt.sh << EOL
#!/bin/bash
cd $INSTALL_DIR/thingspanel-gmqtt/cmd/gmqttd

# 确保日志目录存在
mkdir -p $INSTALL_DIR/logs

# 启动GMQTT
./thingspanel-gmqtt start -c default_config.yml
EOL
        chmod +x cmd/gmqttd/gmqtt.sh
    else
        print_error "未找到预期的二进制文件，安装失败"
        find . -type f -executable
        return 1
    fi
    
    # 配置文件
    cd cmd/gmqttd
    print_info "检查配置文件..."
    if [ -f "thingspanel.yml" ]; then
        print_info "使用预编译包中的配置文件: thingspanel.yml"
    elif [ -f "default_config.yml" ]; then
        print_info "使用预编译包中的配置文件: default_config.yml"
        cp default_config.yml thingspanel.yml
    else
        print_info "创建新的配置文件..."
        cat > thingspanel.yml << EOL
db:
  redis:
    conn: 127.0.0.1:6379
    db_num: 1
    password: "redis"
  psql:
    psqladdr: "127.0.0.1"
    psqlport: 5432
    psqldb: ThingsPanel
    psqluser: postgres
    psqlpass: postgresThingsPanel
mqtt:
  broker: localhost:1883
  password: "root"
  plugin_password: "plugin"
EOL
    fi
    
    # 安装PM2
    print_info "检查Node.js和PM2是否已安装..."
    if ! command -v npm &> /dev/null; then
        print_info "安装Node.js..."
        curl -sL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt install -y nodejs
    fi
    
    if ! command -v pm2 &> /dev/null; then
        print_info "安装PM2..."
        sudo npm install pm2 -g
    fi
    
    # 停止和删除已有的PM2进程
    if pm2 list | grep -q "gmqtt"; then
        print_warning "已有GMQTT进程正在运行，正在重启..."
        pm2 delete gmqtt 2>/dev/null
    fi
    
    # 检查端口是否仍然被占用
    if check_port_occupied 1883; then
        print_error "端口1883仍然被占用，无法启动GMQTT服务"
        print_info "请手动释放端口后重试，可以使用 'sudo lsof -i:1883' 查看占用进程"
        return 1
    fi
    
    # 使用PM2启动GMQTT
    print_info "使用PM2启动GMQTT..."
    pm2 start gmqtt.sh --name gmqtt
    pm2 save
    
    # 等待GMQTT启动
    print_info "等待GMQTT启动..."
    
    COUNTER=0
    MAX_RETRY=12  # 60秒超时
    GMQTT_STARTED=false
    
    while [ $COUNTER -lt $MAX_RETRY ]; do
        if check_port_occupied 1883; then
            print_success "GMQTT已启动，端口1883已监听"
            GMQTT_STARTED=true
            break
        fi
        
        print_info "GMQTT启动中，等待5秒... ($COUNTER/$MAX_RETRY)"
        sleep 5
        COUNTER=$((COUNTER + 1))
    done
    
    if [ "$GMQTT_STARTED" = false ]; then
        print_warning "GMQTT启动超时，请检查日志: pm2 logs gmqtt"
        # 我们不退出，继续安装其他组件
        return 1
    fi
    
    print_success "GMQTT预编译版安装完成"
    return 0
}

# 安装ThingsPanel前端
install_frontend() {
    print_info "检查ThingsPanel前端是否已安装..."
    
    # 检查Nginx是否已安装和运行
    if command -v nginx &> /dev/null && systemctl is-active --quiet nginx; then
        # 检查Nginx配置
        if [ -f "/etc/nginx/sites-enabled/thingspanel" ]; then
            print_success "检测到Nginx已安装且ThingsPanel配置已存在"
            
            # 验证Nginx配置
            if sudo nginx -t &>/dev/null; then
                print_success "Nginx配置有效，跳过前端安装"
                
                # 检查前端文件是否存在
                if [ -d "/var/www/html/thingspanel" ] && [ -f "/var/www/html/thingspanel/index.html" ]; then
                    print_success "前端文件已存在，跳过安装"
                    return 0
                else
                    print_warning "Nginx配置正常但前端文件不存在或不完整，将重新部署前端文件"
                fi
            else
                print_warning "Nginx配置无效，将重新配置"
            fi
        fi
    else
        print_info "Nginx未安装或未运行，将进行安装"
    fi
    
    print_info "安装ThingsPanel前端..."
    cd $INSTALL_DIR
    
    # 安装nginx
    sudo apt install -y nginx
    
    # 开放防火墙端口
    print_info "配置防火墙..."
    sudo ufw allow 80/tcp 2>/dev/null || true
    
    # 下载最新的前端包
    print_info "下载前端包..."
    mkdir -p $INSTALL_DIR/frontend
    cd $INSTALL_DIR/frontend
    
    # 清理旧文件
    rm -rf $INSTALL_DIR/frontend/*
    
    # 安装必要的解压工具
    if ! command -v unzip &> /dev/null || ! command -v tar &> /dev/null; then
        print_info "安装解压工具..."
        sudo apt install -y unzip tar
    fi
    
    # 安装网络工具
    print_info "安装网络工具..."
    sudo apt install -y net-tools curl
    
    # 优先使用直接下载dist.tar.gz方式
    print_info "尝试直接下载dist.tar.gz..."
    if wget -O dist.tar.gz "https://github.com/ThingsPanel/thingspanel-frontend-community/releases/download/latest/dist.tar.gz"; then
        print_success "下载dist.tar.gz成功，正在解压..."
        tar -xzf dist.tar.gz
        check_status "解压前端文件成功" "解压前端文件失败"
    else
        print_warning "直接下载dist.tar.gz失败，尝试从gitee克隆仓库..."
        
        # 尝试从gitee克隆
        if git clone https://gitee.com/ThingsPanel/thingspanel-frontend-community.git; then
            print_success "从gitee克隆成功"
            cd thingspanel-frontend-community
            
            # 安装依赖并构建
            print_info "安装依赖并构建前端..."
            npm install -g pnpm
            pnpm install
            pnpm build
            
            # 使用构建后的dist目录
            if [ -d "dist" ]; then
                cp -r dist/* ../
            else
                print_error "构建失败，未找到dist目录"
                exit 1
            fi
            
            cd ..
            # 清理仓库目录
            rm -rf thingspanel-frontend-community
        else
            print_warning "从gitee克隆失败，尝试从GitHub克隆仓库..."
            
            # 最后尝试GitHub
            if git clone https://github.com/ThingsPanel/thingspanel-frontend-community.git; then
                print_success "从GitHub克隆成功"
                cd thingspanel-frontend-community
                
                # 安装依赖并构建
                print_info "安装依赖并构建前端..."
                npm install -g pnpm
                pnpm install
                pnpm build
                
                # 使用构建后的dist目录
                if [ -d "dist" ]; then
                    cp -r dist/* ../
                else
                    print_error "构建失败，未找到dist目录"
                    exit 1
                fi
                
                cd ..
                # 清理仓库目录
                rm -rf thingspanel-frontend-community
            else
                print_error "所有方式尝试都失败，无法获取前端代码"
                exit 1
            fi
        fi
    fi
    
    # 复制到Nginx目录
    print_info "复制前端文件到Nginx目录..."
    sudo mkdir -p /var/www/html/thingspanel
    sudo rm -rf /var/www/html/thingspanel/*
    sudo cp -r * /var/www/html/thingspanel/
    
    # 配置Nginx
    print_info "配置Nginx..."
    cat > /tmp/thingspanel.conf << EOL
server {
    listen 80 default_server;
    server_name _;
    charset utf-8;
    client_max_body_size 10m;
    root /var/www/html/thingspanel;
  
    gzip on;
    gzip_min_length 1k;
    gzip_comp_level 6;
    gzip_types text/plain application/javascript application/x-javascript text/css application/xml text/javascript application/x-httpd-php image/jpeg image/gif image/png;
    gzip_vary on;
    gzip_disable "MSIE [1-6]\.";

    # 调试日志
    error_log /var/log/nginx/thingspanel-error.log debug;
    access_log /var/log/nginx/thingspanel-access.log;

    location /api {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-real-ip \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$host;
        
        # 设置超时
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        
        # 后端API地址
        proxy_pass http://127.0.0.1:9999;
        
        # 错误处理
        proxy_intercept_errors on;
        error_page 502 = @backend_down;
    }
    
    # 后端服务不可用的错误处理
    location @backend_down {
        add_header Content-Type application/json;
        return 503 '{"error": "Backend service is currently unavailable. Please check the system status."}';
    }
    
    location /ws {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-real-ip \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$host;
        proxy_pass http://127.0.0.1:9999;
    }
    
    location /files {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-real-ip \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$host;
        proxy_pass http://127.0.0.1:9999;
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Credentials' 'true';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
        add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
    }
  
    location / {
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }
}
EOL

    sudo mv /tmp/thingspanel.conf /etc/nginx/sites-available/thingspanel
    sudo ln -sf /etc/nginx/sites-available/thingspanel /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # 重启Nginx
    sudo nginx -t
    sudo systemctl restart nginx
    
    # 检查Nginx状态
    print_info "检查Nginx状态..."
    sudo systemctl status nginx
    
    # 检查后端服务是否可访问
    print_info "测试后端API服务..."
    curl -s -o /dev/null -w "%{http_code}" http://localhost:9999/api/version || echo "无法连接到后端服务"
    
    check_status "ThingsPanel前端安装完成" "ThingsPanel前端安装失败"
    
    # 添加一个完成后的自动检查
    print_info "执行最终检查..."
    sleep 5
    
    # 检查所有服务是否运行
    print_info "检查所有服务状态..."
    print_info "Docker容器:"
    docker ps
    print_info "PM2进程:"
    pm2 list
    print_info "网络端口:"
    netstat -tuln | grep -E ':(80|9999|1883|5432|6379)' || echo "未发现必要端口"
    
    # 提供故障排除提示
    print_info "如果启动后遇到502错误，请尝试执行以下命令:"
    print_info "1. 重启后端: pm2 restart backend"
    print_info "2. 重启GMQTT: pm2 restart gmqtt"
    print_info "3. 重启Nginx: sudo systemctl restart nginx"
    print_info "4. 检查后端日志: tail -f $INSTALL_DIR/thingspanel-backend-community/files/logs/app.log"
}

# 安装完成后显示信息
show_completion_info() {
    print_success "==================================================="
    print_success "ThingsPanel安装完成!"
    print_success "==================================================="
    print_success "访问地址: http://$(hostname -I | awk '{print $1}')"
    print_success "默认账号密码:"
    print_success "- 系统管理员: super@super.cn / 123456"
    print_success "- 租户管理员: tenant@tenant.cn / 123456"
    print_success "==================================================="
    print_success "安装日志: $LOG_FILE"
    print_success "==================================================="
    print_warning "如果遇到502错误，请检查后端服务状态:"
    print_warning "1. 查看PM2状态: pm2 list"
    print_warning "2. 查看PM2日志: pm2 logs backend"
    print_warning "3. 查看应用日志: cat $INSTALL_DIR/thingspanel-backend-community/files/logs/app.log"
    
    if [ "$USE_PREBUILT" = "true" ]; then
        print_info "当前使用预编译版本，如需从源码编译，请使用'-b'参数重新运行脚本"
    else
        print_info "当前从源码编译，如需使用预编译版本，请使用'-p'参数重新运行脚本"
        print_warning "4. 查看编译日志: cat $INSTALL_DIR/logs/backend_build.log"
    fi
    
    print_warning "==================================================="
    print_warning "常见问题解决方案:"
    print_warning "1. 重启后端: pm2 restart backend"
    print_warning "2. 重启GMQTT: pm2 restart gmqtt"
    print_warning "3. 重启所有服务:"
    print_warning "   pm2 restart all"
    print_warning "   sudo systemctl restart nginx"
    print_warning "==================================================="
    print_warning "当前架构设置: GOARCH=$ARM_ARCH"
    print_warning "系统架构: $(uname -m)"
    print_success "==================================================="
}

# 显示脚本用法
show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -y, --yes         自动模式，所有提示默认yes"
    echo "  -a, --auto        完全自动模式，不显示任何提示，自动安装所有组件"
    echo "  -c, --components  指定要安装的组件，用逗号分隔 (redis,timescaledb,gmqtt,backend,frontend)"
    echo "  -s, --skip        指定要跳过的组件，用逗号分隔 (redis,timescaledb,gmqtt,backend,frontend)"
    echo "  -v, --verbose     详细模式，即使在自动模式下也显示所有输出"
    echo "  -p, --prebuilt    使用预编译的二进制文件 (默认启用)"
    echo "  -b, --build       从源码编译 (不推荐在低性能设备上使用)"
    echo "  -h, --help        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -a                     完全自动安装所有组件"
    echo "  $0 -c redis,backend       只安装Redis和后端"
    echo "  $0 -s frontend            安装除前端外的所有组件"
    echo "  $0 -y -s redis            安装除Redis外的所有组件，提示自动选择yes"
    echo "  $0 -a -v                  完全自动安装所有组件，但显示详细输出"
    echo "  $0 -b                     从源码编译而不是使用预编译的二进制文件"
    echo ""
    exit 0
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            -a|--auto)
                AUTO_MODE=true
                AUTO_YES=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -p|--prebuilt)
                USE_PREBUILT=true
                shift
                ;;
            -b|--build)
                USE_PREBUILT=false
                shift
                ;;
            -c|--components)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "错误: --components 选项需要参数"
                    exit 1
                fi
                COMPONENTS="$2"
                # 转换为数组
                IFS=',' read -r -a COMPONENTS_ARRAY <<< "$COMPONENTS"
                shift 2
                ;;
            -s|--skip)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "错误: --skip 选项需要参数"
                    exit 1
                fi
                SKIP_COMPONENTS="$2"
                # 转换为数组
                IFS=',' read -r -a SKIP_COMPONENTS_ARRAY <<< "$SKIP_COMPONENTS"
                shift 2
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                echo "未知选项: $1"
                show_usage
                ;;
        esac
    done
}
# 修改后端启动脚本，添加更多的环境变量配置
create_backend_startup_script() {
    local install_dir=$1
    
    cat > $INSTALL_DIR/thingspanel-backend-community/backend.sh << EOL
#!/bin/bash
cd $INSTALL_DIR/thingspanel-backend-community

# 确保日志目录存在
mkdir -p files/logs
mkdir -p $INSTALL_DIR/logs

# Redis配置 - 使用正确的环境变量名称
# 禁用自动加载Redis配置或GRPC初始化
export GOTP_DB_GRPC_TPTODB_TYPE="none"
# 打印Redis状态
echo "检查Redis状态..."
redis-cli -h 127.0.0.1 -p 6379 -a redis ping || {
    echo "Redis连接失败! 请确保Redis已正确启动"
    echo "尝试重启Redis..."
    docker restart \$(docker ps -a | grep redis | awk '{print \$1}')
    sleep 5
    redis-cli -h 127.0.0.1 -p 6379 -a redis ping || echo "Redis仍然无法连接"
}

# 检查二进制文件位置并启动
if [ -f "./linux-arm64/thingspanel-backend-community" ]; then
    cd linux-arm64
    echo "启动后端服务..."
    
    # 使用显式配置启动，完全绕过配置文件
    ./thingspanel-backend-community
else
    # 如果找不到预期位置的二进制文件，尝试查找其他可能位置
    echo "\$(date) - ERROR: 找不到后端二进制文件" >> $INSTALL_DIR/logs/backend_error.log
    find . -name "thingspanel-backend-community" -type f -executable >> $INSTALL_DIR/logs/backend_error.log
    exit 1
fi
EOL
    
    chmod +x $install_dir/thingspanel-backend-community/backend.sh
    print_success "创建了增强版后端启动脚本"
}

# 检查组件是否应该被安装
should_install_component() {
    local component=$1
    
    # 如果指定了组件列表，检查组件是否在列表中
    if [[ -n "$COMPONENTS" ]]; then
        for c in "${COMPONENTS_ARRAY[@]}"; do
            if [[ "$c" == "$component" ]]; then
                return 0  # 组件在列表中，应该安装
            fi
        done
        return 1  # 组件不在列表中，不应该安装
    fi
    
    # 如果指定了跳过组件列表，检查组件是否在列表中
    if [[ -n "$SKIP_COMPONENTS" ]]; then
        for c in "${SKIP_COMPONENTS_ARRAY[@]}"; do
            if [[ "$c" == "$component" ]]; then
                return 1  # 组件在跳过列表中，不应该安装
            fi
        done
    fi
    
    # 默认应该安装
    return 0
}

# 主函数
main() {
    echo "======================================================"
    echo "        ThingsPanel for Raspberry Pi 一键安装脚本        "
    echo "======================================================"
    echo "版本: 1.0.0"
    echo "自动模式: ${AUTO_YES:-false}"
    echo "完全自动模式: ${AUTO_MODE:-false}"
    echo "详细输出: ${VERBOSE:-false}"
    echo "使用预编译版本: ${USE_PREBUILT:-true}"
    
    if [[ -n "$COMPONENTS" ]]; then
        echo "安装组件: $COMPONENTS"
    fi
    
    if [[ -n "$SKIP_COMPONENTS" ]]; then
        echo "跳过组件: $SKIP_COMPONENTS"
    fi
    
    echo "======================================================" 
    
    # 安装必要工具
    sudo apt install -y net-tools curl lsof
    
    # 检测ARM架构
    detect_arm_arch
    
    setup_environment
    update_system
    install_tools
    install_docker
    install_go
    
    # 首先安装数据库组件，确保它们先启动
    # 安装Redis
    if should_install_component "redis"; then
        install_redis
        
        # 等待Redis启动
        print_info "等待Redis启动..."
        sleep 5
    else
        print_warning "跳过Redis安装"
    fi
    
    # 安装数据库
    if should_install_component "timescaledb"; then
        install_timescaledb
        
        # 等待数据库启动
        print_info "等待数据库启动..."
        sleep 10
    else
        print_warning "跳过TimescaleDB安装"
    fi
    
    # 然后安装应用组件，这些组件依赖于数据库
    # 安装GMQTT
    if should_install_component "gmqtt"; then
        if [ "$USE_PREBUILT" = "true" ]; then
            install_prebuilt_gmqtt
        else 
            install_gmqtt
        fi
        
        # 等待GMQTT启动
        print_info "等待GMQTT启动..."
        sleep 5
    else
        print_warning "跳过GMQTT安装"
    fi
    
    # 安装后端
    if should_install_component "backend"; then
        if [ "$USE_PREBUILT" = "true" ]; then
            install_prebuilt_backend
        else
            install_backend
        fi
    else
        print_warning "跳过ThingsPanel后台安装"
    fi
    
    # 最后安装前端，它依赖于后端
    if should_install_component "frontend"; then
        install_frontend
    else
        print_warning "跳过ThingsPanel前端安装"
    fi
    
    show_completion_info
}

# 初始化全局变量
AUTO_YES=false
AUTO_MODE=false
VERBOSE=false
COMPONENTS=""
SKIP_COMPONENTS=""
# 组件数组
COMPONENTS_ARRAY=()
SKIP_COMPONENTS_ARRAY=()
# 默认ARM架构
ARM_ARCH="arm64"
# 默认使用预编译二进制
USE_PREBUILT=true

# 解析命令行参数
parse_args "$@"

# 执行主函数
main 