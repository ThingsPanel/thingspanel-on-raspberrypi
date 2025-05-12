#!/bin/bash

# 修复版系统监控脚本 - 只监控CPU、内存和磁盘I/O
# 每秒输出一行包含关键系统指标的数据

# 使用方法: 
# ./monitor_fixed.sh [设备名称]
# 例如: ./monitor_fixed.sh mmcblk0

# 检查sysstat是否安装
if ! command -v iostat &> /dev/null; then
    echo "错误: 未找到iostat命令"
    echo "请先安装sysstat: sudo apt-get install sysstat"
    exit 1
fi

# 确定要监控的设备名称
DEVICE=${1:-"mmcblk0"}

# 获取CPU使用情况 (只返回总体使用率)
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
    
    # 计算使用百分比
    usage=$(echo "scale=1; $used * 100 / $total" | bc)
    
    echo "$usage"
}

# 获取磁盘I/O信息 (修复版)
get_disk_io() {
    # 先检查设备是否存在
    if [ ! -b "/dev/$DEVICE" ] && [ ! -b "/dev/block/$DEVICE" ]; then
        echo "警告: 设备 $DEVICE 可能不存在"
        echo "0.0|0.0"
        return
    fi
    
    # 使用直接的命令来获取读写速率
    # 方法1: 尝试使用iostat
    if iostat -mxy "/dev/$DEVICE" 1 2 >/dev/null 2>&1; then
        # 如果iostat支持直接指定设备路径
        iostat_out=$(iostat -mxy "/dev/$DEVICE" 1 2 | tail -3 | head -1)
        read_mb=$(echo "$iostat_out" | awk '{print $6}')
        write_mb=$(echo "$iostat_out" | awk '{print $7}')
        
        # 如果获取成功
        if [[ -n "$read_mb" && -n "$write_mb" ]]; then
            echo "$read_mb|$write_mb"
            return
        fi
    fi
    
    # 方法2: 尝试使用不同的方式解析iostat输出
    iostat_out=$(iostat -mx 1 2 | grep -A 20 "Device" | grep -w "$DEVICE")
    if [[ -n "$iostat_out" ]]; then
        # 获取字段数量，以便动态调整
        fields=$(echo "$iostat_out" | awk '{print NF}')
        
        # 根据字段数量调整读写字段的位置
        if [[ $fields -ge 6 ]]; then
            read_mb=$(echo "$iostat_out" | awk '{print $6}')
            write_mb=$(echo "$iostat_out" | awk '{print $7}')
            
            if [[ -n "$read_mb" && -n "$write_mb" ]]; then
                echo "$read_mb|$write_mb"
                return
            fi
        fi
    fi
    
    # 方法3: 使用/proc/diskstats来获取磁盘I/O信息
    if grep -q "$DEVICE" /proc/diskstats; then
        # 获取当前状态
        read1=$(grep "$DEVICE" /proc/diskstats | awk '{print $6}')
        write1=$(grep "$DEVICE" /proc/diskstats | awk '{print $10}')
        
        # 等待1秒
        sleep 1
        
        # 获取1秒后的状态
        read2=$(grep "$DEVICE" /proc/diskstats | awk '{print $6}')
        write2=$(grep "$DEVICE" /proc/diskstats | awk '{print $10}')
        
        # 计算每秒读写的扇区数
        read_sectors=$(( read2 - read1 ))
        write_sectors=$(( write2 - write1 ))
        
        # 转换为MB/s (一个扇区通常是512字节，即0.0005MB)
        read_mb=$(echo "scale=2; $read_sectors * 0.0005" | bc)
        write_mb=$(echo "scale=2; $write_sectors * 0.0005" | bc)
        
        echo "$read_mb|$write_mb"
        return
    fi
    
    # 如果所有方法都失败，返回0
    echo "0.0|0.0"
}

# 输出表头
print_header() {
    echo "时间戳,CPU使用率%,内存使用率%,磁盘读取MB/秒,磁盘写入MB/秒"
}

# 输出单行监控数据
print_data_line() {
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    cpu_usage=$(get_cpu_usage)
    mem_usage=$(get_memory_usage)
    disk_io=$(get_disk_io)
    
    # 解析磁盘I/O信息
    disk_rmbs=$(echo $disk_io | cut -d'|' -f1)
    disk_wmbs=$(echo $disk_io | cut -d'|' -f2)
    
    # 输出CSV格式的单行数据
    echo "$timestamp,$cpu_usage,$mem_usage,$disk_rmbs,$disk_wmbs"
}

# 显示信息并开始监控
echo "ThingsPanel 系统监控 - 修复版"
echo "监控设备: $DEVICE"
echo "按 Ctrl+C 停止监控"
echo ""

# 尝试找到正确的设备名称
if [ ! -b "/dev/$DEVICE" ] && [ ! -b "/dev/block/$DEVICE" ]; then
    echo "警告: 未找到设备 $DEVICE，尝试列出可用的块设备:"
    lsblk -d | grep -v loop
    echo ""
    echo "建议使用上述列表中的名称作为设备参数"
    echo "继续使用 $DEVICE 作为设备名称..."
fi

# 输出CSV表头
print_header

# 主循环，每秒输出一行数据
while true; do
    print_data_line
    sleep 1
done
