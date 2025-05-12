#!/bin/bash

# 修复版磁盘I/O监控脚本
# 修复了语法错误，保留有效功能

# 使用方法: 
# ./disk_monitor_fixed.sh [设备名称] [分区号]
# 例如: ./disk_monitor_fixed.sh mmcblk0 2

# 检查sysstat是否安装
if ! command -v iostat &> /dev/null; then
    echo "错误: 未找到iostat命令"
    echo "请先安装sysstat: sudo apt-get install sysstat"
    exit 1
fi

# 解析参数
DEVICE=${1:-"mmcblk0"}
PARTITION=${2:-"2"}
FULL_DEVICE="/dev/$DEVICE"
PARTITION_DEVICE="/dev/${DEVICE}p${PARTITION}"

# 检查设备和分区是否存在
if [ ! -b "$FULL_DEVICE" ]; then
    echo "警告: 设备 $FULL_DEVICE 不存在"
    FULL_DEVICE=""
fi

if [ ! -b "$PARTITION_DEVICE" ]; then
    echo "警告: 分区 $PARTITION_DEVICE 不存在"
    # 尝试其他常见的分区命名格式
    if [ -b "/dev/${DEVICE}${PARTITION}" ]; then
        PARTITION_DEVICE="/dev/${DEVICE}${PARTITION}"
        echo "找到了分区: $PARTITION_DEVICE"
    else
        PARTITION_DEVICE=""
    fi
fi

# 获取CPU使用情况
get_cpu_usage() {
    cpu_stat=$(top -bn1 | grep "Cpu(s)")
    idle=$(echo "$cpu_stat" | awk '{print $8}' | cut -d% -f1)
    cpu_usage=$(echo "scale=1; 100 - $idle" | bc)
    echo "$cpu_usage"
}

# 获取内存使用情况
get_memory_usage() {
    mem_info=$(free -m)
    total=$(echo "$mem_info" | grep Mem | awk '{print $2}')
    used=$(echo "$mem_info" | grep Mem | awk '{print $3}')
    
    usage=$(echo "scale=1; $used * 100 / $total" | bc)
    
    echo "$usage"
}

# 使用直接的/proc/diskstats方法获取I/O信息 - 修复版
get_diskstats_io() {
    local dev=$1
    if [ -z "$dev" ]; then
        echo "0.0000|0.0000"
        return
    fi
    
    # 从设备路径中提取设备名
    local dev_name=$(basename $dev)
    
    # 获取初始状态
    local initial_stats=$(grep "$dev_name" /proc/diskstats 2>/dev/null)
    if [ -z "$initial_stats" ]; then
        echo "0.0000|0.0000"
        return
    fi
    
    # 使用awk更可靠地提取字段
    local read_sectors_1=$(echo "$initial_stats" | awk '{print $6}')
    local write_sectors_1=$(echo "$initial_stats" | awk '{print $10}')
    
    # 确保我们有有效的数字
    if ! [[ "$read_sectors_1" =~ ^[0-9]+$ ]]; then
        read_sectors_1=0
    fi
    if ! [[ "$write_sectors_1" =~ ^[0-9]+$ ]]; then
        write_sectors_1=0
    fi
    
    # 等待一小段时间
    sleep 1
    
    # 获取新状态
    local new_stats=$(grep "$dev_name" /proc/diskstats 2>/dev/null)
    if [ -z "$new_stats" ]; then
        echo "0.0000|0.0000"
        return
    fi
    
    # 再次使用awk提取字段
    local read_sectors_2=$(echo "$new_stats" | awk '{print $6}')
    local write_sectors_2=$(echo "$new_stats" | awk '{print $10}')
    
    # 确保我们有有效的数字
    if ! [[ "$read_sectors_2" =~ ^[0-9]+$ ]]; then
        read_sectors_2=0
    fi
    if ! [[ "$write_sectors_2" =~ ^[0-9]+$ ]]; then
        write_sectors_2=0
    fi
    
    # 计算差值 - 使用更安全的方法
    local read_diff=0
    local write_diff=0
    
    # 安全计算读取差值
    if [ "$read_sectors_2" -ge "$read_sectors_1" ]; then
        read_diff=$((read_sectors_2 - read_sectors_1))
    else
        # 处理计数器重置的情况
        read_diff=$read_sectors_2
    fi
    
    # 安全计算写入差值
    if [ "$write_sectors_2" -ge "$write_sectors_1" ]; then
        write_diff=$((write_sectors_2 - write_sectors_1))
    else
        # 处理计数器重置的情况
        write_diff=$write_sectors_2
    fi
    
    # 转换为MB/s (一个扇区通常是512字节，即0.0005MB)
    local read_mb=$(echo "scale=4; $read_diff * 0.0005" | bc)
    local write_mb=$(echo "scale=4; $write_diff * 0.0005" | bc)
    
    echo "$read_mb|$write_mb"
}

# 获取PostgreSQL进程的信息
get_pg_info() {
    if pgrep postgres > /dev/null; then
        pg_proc_count=$(pgrep postgres | wc -l)
        pg_cpu=$(ps aux | grep postgres | grep -v grep | awk '{sum+=$3} END {printf "%.1f", sum}')
        pg_mem=$(ps aux | grep postgres | grep -v grep | awk '{sum+=$4} END {printf "%.1f", sum}')
        echo "$pg_proc_count|$pg_cpu|$pg_mem"
    else
        echo "0|0.0|0.0"
    fi
}

# 获取PostgreSQL数据目录
get_pg_data_dir() {
    # 尝试通过pg_config获取
    if command -v pg_config &> /dev/null; then
        pg_config --sharedir | sed 's/share$/data/'
    else
        # 尝试常见位置
        for dir in /var/lib/postgresql /var/lib/pgsql /usr/local/pgsql/data
        do
            if [ -d "$dir" ]; then
                echo "$dir"
                return
            fi
        done
        # 默认
        echo "/var/lib/postgresql"
    fi
}

# 获取PostgreSQL数据目录的磁盘空间使用情况
get_pg_disk_usage() {
    local pg_dir=$(get_pg_data_dir)
    if [ -d "$pg_dir" ]; then
        df -h "$pg_dir" | tail -1 | awk '{print $5}' | tr -d '%'
    else
        echo "0"
    fi
}

# 输出表头
print_header() {
    echo "时间戳,CPU使用率%,内存使用率%,PG进程数,PG_CPU%,PG内存%,设备($DEVICE)读取MB/秒,设备($DEVICE)写入MB/秒,分区($(basename $PARTITION_DEVICE))读取MB/秒,分区($(basename $PARTITION_DEVICE))写入MB/秒,PG数据目录使用率%"
}

# 输出单行监控数据
print_data_line() {
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    cpu_usage=$(get_cpu_usage)
    mem_usage=$(get_memory_usage)
    pg_info=$(get_pg_info)
    
    # 使用修复版的方法获取I/O数据
    device_io=$(get_diskstats_io "$FULL_DEVICE")
    partition_io=$(get_diskstats_io "$PARTITION_DEVICE")
    
    # 解析PostgreSQL信息
    pg_count=$(echo $pg_info | cut -d'|' -f1)
    pg_cpu=$(echo $pg_info | cut -d'|' -f2)
    pg_mem=$(echo $pg_info | cut -d'|' -f3)
    
    # 解析设备I/O信息
    device_rmbs=$(echo $device_io | cut -d'|' -f1)
    device_wmbs=$(echo $device_io | cut -d'|' -f2)
    
    # 解析分区I/O信息
    partition_rmbs=$(echo $partition_io | cut -d'|' -f1)
    partition_wmbs=$(echo $partition_io | cut -d'|' -f2)
    
    # 获取PostgreSQL数据目录的磁盘使用率
    pg_disk_usage=$(get_pg_disk_usage)
    
    # 输出CSV格式的单行数据
    echo "$timestamp,$cpu_usage,$mem_usage,$pg_count,$pg_cpu,$pg_mem,$device_rmbs,$device_wmbs,$partition_rmbs,$partition_wmbs,$pg_disk_usage"
}

# 显示系统信息
show_system_info() {
    echo "系统信息："
    uname -a
    echo ""
    
    echo "磁盘布局："
    lsblk
    echo ""
    
    echo "磁盘挂载点："
    df -h
    echo ""
    
    pg_data_dir=$(get_pg_data_dir)
    echo "PostgreSQL数据目录: $pg_data_dir"
    if [ -d "$pg_data_dir" ]; then
        df -h "$pg_data_dir" | head -1
        df -h "$pg_data_dir" | tail -1
    fi
    echo ""
}

# 显示信息并开始监控
echo "改进的磁盘I/O监控脚本 - 修复版"
echo "============================="

# 显示系统信息
show_system_info

echo "监控设备: $FULL_DEVICE"
echo "监控分区: $PARTITION_DEVICE"
echo "按 Ctrl+C 停止监控"
echo ""

# 输出CSV表头
print_header

# 主循环，每秒输出一行数据
while true; do
    print_data_line
    sleep 2  # 每2秒采样一次
done
