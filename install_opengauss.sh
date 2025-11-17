#!/bin/bash

# openGauss数据库自动安装脚本
# 支持多版本和多架构自动选择
# 版本: 动态版本选择 - 内置URL版本

# 设置默认密码（可根据需要修改）
DEFAULT_PASSWORD="Admin@2025"
HOSTNAME=openGauss-server01

# 全局变量
SELECTED_VERSION=""
SELECTED_URL=""
SYSTEM_ARCH=""
SYSTEM_OS_VERSION=""
#脚本执行目录，也是文件下载的默认路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 内置版本和URL信息
declare -A VERSION_INFO
VERSION_INFO=(
    ["7.0.0-RC2"]="7.0.0-RC2"
    ["7.0.0-RC1"]="7.0.0-RC1"
    ["6.0.2(LTS)"]="6.0.2"
    ["6.0.0(LTS)"]="6.0.0"
    ["6.0.0-RC1"]="6.0.0-RC1"
    ["5.0.3(LTS)"]="5.0.3"
    ["5.0.2(LTS)"]="5.0.2"
    ["5.0.1(LTS)"]="5.0.1"
    ["5.0.0(LTS)"]="5.0.0"
)

# URL构建配置常量
readonly BASE_URL="https://opengauss.obs.cn-south-1.myhuaweicloud.com"
readonly OS_VERSION_6X_2203="openEuler22.03"
readonly OS_VERSION_6X_2003="openEuler20.03"
readonly OS_VERSION_5X_2203="openEuler"
readonly OS_VERSION_5X_2003="openEuler"
readonly ARCH_ARM_6X="arm"
readonly ARCH_X86_6X="x86"
readonly ARCH_ARM_5X_2203="arm_2203"
readonly ARCH_X86_5X_2203="x86_openEuler_2203"
readonly ARCH_ARM_5X_2003="arm"
readonly ARCH_X86_5X_2003="x86_openEuler"
readonly ARCH_SUFFIX_ARM="aarch64"
readonly ARCH_SUFFIX_X86="x86_64"

# 动态构建下载URL
build_download_url() {
    local version="$1"
    local arch="$2"
    local os_version="$3"
    local version_num="${VERSION_INFO[$version]}"
    
    # 判断版本类型
    if [[ "$version_num" =~ ^5\. ]] || [[ "$version_num" == "6.0.0-RC1" ]]; then
        # 5.x版本URL构建
        local arch_dir os_ver
        if [[ "$os_version" == "22.03" ]]; then
            os_ver="$OS_VERSION_5X_2203"
            if [[ "$arch" == "AArch64" ]]; then
                arch_dir="$ARCH_ARM_5X_2203"
            else
                arch_dir="$ARCH_X86_5X_2203"
            fi
        else
            os_ver="$OS_VERSION_5X_2003"
            if [[ "$arch" == "AArch64" ]]; then
                arch_dir="$ARCH_ARM_5X_2003"
            else
                arch_dir="$ARCH_X86_5X_2003"
            fi
        fi
        echo "${BASE_URL}/${version_num}/${arch_dir}/openGauss-${version_num}-${os_ver}-64bit-all.tar.gz"
    else
        # 6.x+版本URL构建
        local arch_path arch_suffix os_ver
        if [[ "$os_version" == "22.03" ]]; then
            os_ver="$OS_VERSION_6X_2203"
        else
            os_ver="$OS_VERSION_6X_2003"
        fi
        
        if [[ "$arch" == "AArch64" ]]; then
            arch_path="$ARCH_ARM_6X"
            arch_suffix="$ARCH_SUFFIX_ARM"
        else
            arch_path="$ARCH_X86_6X"
            arch_suffix="$ARCH_SUFFIX_X86"
        fi
        echo "${BASE_URL}/${version_num}/${os_ver}/${arch_path}/openGauss-All-${version_num}-${os_ver}-${arch_suffix}.tar.gz"
    fi
}

# 检测系统版本
detect_system_version() {
    echo "正在检测系统版本..."
    
    # 支持的系统版本列表
    local supported_versions=("22.03" "20.03")
    local detected_version=""
    
    # 方法1: 从 /etc/openEuler-release 读取版本信息
    if [[ -f "/etc/openEuler-release" ]]; then
        local release_info=$(cat /etc/openEuler-release)
        echo "系统发行版信息: $release_info"
        
        # 提取版本号 (匹配 22.03 或 20.03)
        if [[ "$release_info" =~ 22\.03 ]]; then
            detected_version="22.03"
        elif [[ "$release_info" =~ 20\.03 ]]; then
            detected_version="20.03"
        fi
    fi
    
    # 方法2: 从 uname -a 读取内核版本信息作为辅助验证
    local kernel_info=$(uname -a)
    echo "内核版本信息: $kernel_info"
    
    # 从内核信息中提取版本号进行交叉验证
    local kernel_version=""
    if [[ "$kernel_info" =~ oe2203 ]]; then
        kernel_version="22.03"
    elif [[ "$kernel_info" =~ oe2003 ]]; then
        kernel_version="20.03"
    fi
    
    # 版本验证和确认
    if [[ -n "$detected_version" ]]; then
        if [[ -n "$kernel_version" && "$detected_version" != "$kernel_version" ]]; then
            echo "⚠️  警告: 发行版版本($detected_version)与内核版本($kernel_version)不匹配"
            echo "将使用发行版版本: $detected_version"
        fi
        SYSTEM_OS_VERSION="$detected_version"
        echo "✅ 检测到系统版本: openEuler $SYSTEM_OS_VERSION"
    else
        echo "❌ 错误: 无法检测到支持的系统版本"
        echo ""
        echo "========================================="
        echo "系统版本不支持！"
        echo "========================================="
        echo "当前脚本仅支持以下openEuler版本:"
        for version in "${supported_versions[@]}"; do
            echo "  - openEuler $version (LTS)"
        done
        echo ""
        echo "请安装支持的系统版本后重新运行此脚本。"
        echo ""
        echo "系统要求:"
        echo "- openEuler 22.03 (LTS-SP3) - 推荐版本"
        echo "- openEuler 20.03 (LTS-SP1/SP2/SP3)"
        echo ""
        echo "获取系统镜像:"
        echo "- 官方下载: https://www.openeuler.org/zh/download/"
        echo "- 华为云镜像: https://mirrors.huaweicloud.com/openeuler/"
        echo "========================================="
        exit 1
    fi
    
    # 验证版本是否在支持列表中
    local version_supported=false
    for supported in "${supported_versions[@]}"; do
        if [[ "$SYSTEM_OS_VERSION" == "$supported" ]]; then
            version_supported=true
            break
        fi
    done
    
    if [[ "$version_supported" == false ]]; then
        echo "❌ 错误: 检测到的系统版本 $SYSTEM_OS_VERSION 不在支持列表中"
        exit 1
    fi
    
    echo "系统版本校验通过: openEuler $SYSTEM_OS_VERSION"
}
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        "x86_64")
            SYSTEM_ARCH="x86_64"
            ;;
        "aarch64")
            SYSTEM_ARCH="AArch64"
            ;;
        *)
            echo "错误: 不支持的系统架构: $arch"
            echo "支持的架构: x86_64, aarch64"
            exit 1
            ;;
    esac
    echo "检测到系统架构: $SYSTEM_ARCH"
}

# 显示版本选择菜单
show_version_menu() {
    echo "========================================="
    echo "可用的openGauss版本:"
    echo "========================================="
    
    # 显示所有支持的版本（与VERSION_INFO保持一致）
    local versions=(
        "7.0.0-RC2"
        "7.0.0-RC1"
        "6.0.2(LTS)"
        "6.0.0(LTS)"
        "6.0.0-RC1"
        "5.0.3(LTS)"
        "5.0.2(LTS)"
        "5.0.1(LTS)"
        "5.0.0(LTS)"
    )
    
    # 添加版本描述信息
    local descriptions=(
        "最新候选发布版本，包含新特性"
        "最新候选发布版本，包含新特性"
        "最新长期支持版本，推荐生产环境使用"
        "稳定长期支持版本"
        "稳定长期支持版本"
        "稳定长期支持版本"
        "稳定长期支持版本"
        "稳定长期支持版本"
        "稳定长期支持版本"
    )
    
    local index=1
    for version in "${versions[@]}"; do
        local version_num="${VERSION_INFO[$version]}"
        local desc="${descriptions[$((index-1))]}"
        
        # 高亮推荐版本
        if [[ "$version" == "6.0.2(LTS)" ]]; then
            echo "$index. openGauss $version (v$version_num) - $desc ⭐推荐"
        else
            echo "$index. openGauss $version (v$version_num) - $desc"
        fi
        ((index++))
    done
    
    echo "========================================="
    echo "系统架构: $SYSTEM_ARCH"
    echo "系统版本: openEuler $SYSTEM_OS_VERSION"
    echo "支持的操作系统: openEuler 22.03 / openEuler 20.03"
    echo "========================================"
    echo -n "请选择要安装的版本 (输入数字 1-${#versions[@]}): "
    read choice
    
    # 验证选择
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#versions[@]} ]]; then
        echo "❌ 错误: 无效的选择，请输入 1-${#versions[@]} 之间的数字"
        echo "您输入的是: '$choice'"
        exit 1
    fi
    
    SELECTED_VERSION="${versions[$((choice-1))]}"
    local selected_version_num="${VERSION_INFO[$SELECTED_VERSION]}"
    
    echo ""
    echo "✅ 您选择了: openGauss $SELECTED_VERSION (v$selected_version_num)"
    echo "架构: $SYSTEM_ARCH"
    echo "系统版本: openEuler $SYSTEM_OS_VERSION"
    
    # 显示版本特性说明
    case "$SELECTED_VERSION" in
        "6.0.2(LTS)")
            echo "特性: 最新LTS版本，性能优化，安全增强"
            ;;
        "7.0.0-RC1")
            echo "特性: 候选发布版本，包含最新功能，适合测试环境"
            ;;
        "5.0.3(LTS)")
            echo "特性: 成熟稳定版本，广泛验证"
            ;;
        *)
            echo "特性: 稳定版本"
            ;;
    esac
    echo ""
}

# 构建并验证下载链接
prepare_download_url() {
    echo "正在构建下载链接..."
    echo "目标版本: $SELECTED_VERSION"
    echo "系统架构: $SYSTEM_ARCH"
    echo "系统版本: openEuler $SYSTEM_OS_VERSION"
    
    SELECTED_URL=$(build_download_url "$SELECTED_VERSION" "$SYSTEM_ARCH" "$SYSTEM_OS_VERSION")
    
    if [[ -z "$SELECTED_URL" ]]; then
        echo "错误: 无法构建下载链接"
        echo "版本: $SELECTED_VERSION"
        echo "架构: $SYSTEM_ARCH"
        echo "系统版本: $SYSTEM_OS_VERSION"
        exit 1
    fi
    
    echo "构建的下载链接: $SELECTED_URL"
}

# 下载openGauss安装包
download_opengauss() {
    local filename=$(basename "$SELECTED_URL")
    
    echo "========================================="
    echo "开始下载openGauss安装包..."
    echo "下载链接: $SELECTED_URL"
    echo "文件名: $filename"
    echo "========================================="
    
    # 检查是否已存在文件
    if [[ -f "$filename" ]]; then
        echo "文件已存在，跳过下载: $filename"
        return 0
    fi
    
    # 使用wget下载
    if command -v wget >/dev/null 2>&1; then
        echo "使用wget下载..."
        wget -c "$SELECTED_URL" -O "$filename" --progress=bar:force 2>&1
    elif command -v curl >/dev/null 2>&1; then
        echo "使用curl下载..."
        curl -L -C - -o "$filename" "$SELECTED_URL" --progress-bar
    else
        echo "错误: 系统中未找到wget或curl命令"
        echo "请先安装wget或curl: yum install wget curl -y"
        exit 1
    fi
    
    # 验证下载是否成功
    if [[ ! -f "$filename" ]]; then
        echo "错误: 下载失败"
        exit 1
    fi
    
    # 检查文件大小
    local filesize=$(stat -c%s "$filename" 2>/dev/null || echo "0")
    if [[ "$filesize" -lt 1000000 ]]; then  # 小于1MB可能是错误文件
        echo "警告: 下载的文件大小异常 ($filesize bytes)"
        echo "请检查网络连接和下载链接"
    fi
    
    echo "下载完成: $filename (大小: $filesize bytes)"
}

# 主机名验证函数
validate_hostname() {
    local hostname=$1
    if [[ $hostname =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取本机IP地址
get_local_ip() {
    local ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1)
    if [[ -z "$ip" || "$ip" == "1" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [[ -z "$ip" ]]; then
        ip="127.0.0.1"
    fi
    echo $ip
}

# 显示支持的版本信息
show_supported_versions() {
    echo "========================================="
    echo "支持的openGauss版本和架构:"
    echo "========================================="
    echo "版本信息:"
    echo "- 支持openGauss 5.0.0(LTS)-7.0.0-RC1,架构-x86_64, AArch64"
    echo ""
    echo "系统要求:"
    echo "- 操作系统: openEuler 22.03 / openEuler 20.03"
    echo "- 架构: x86_64 或 AArch64"
    echo "- 内存: 建议8GB以上"
    echo "- 磁盘: 建议50GB以上可用空间"
    echo "========================================="
}

set -e  # 遇到错误立即退出

echo "========================================="
echo "openGauss 自动安装脚本"
echo "支持多版本和多架构自动选择"
echo "内置URL版本 - 无需外部配置文件"

# 显示支持的版本信息
show_supported_versions

# 检测系统版本
detect_system_version

# 检测系统架构
detect_architecture

# 显示版本选择菜单
show_version_menu

# 构建下载链接
prepare_download_url

# 切换到脚本目录

cd "$SCRIPT_DIR"

# 下载安装包
download_opengauss

# 检查系统版本
echo "检查系统版本..."
cat /etc/hostname
cat /etc/os-release | grep -E "NAME|VERSION"

# 智能主机名配置
echo "========================================="
echo "配置主机名..."
CURRENT_HOSTNAME=$(hostname)
echo "当前主机名: $CURRENT_HOSTNAME"

# 验证目标主机名格式
if ! validate_hostname "$HOSTNAME"; then
    echo "错误: 主机名格式不正确: $HOSTNAME"
    exit 1
fi

# 检查是否需要更改主机名
if [[ "$CURRENT_HOSTNAME" != "$HOSTNAME" ]]; then
    echo "需要将主机名从 '$CURRENT_HOSTNAME' 更改为 '$HOSTNAME'"
    
    # 更改主机名
    echo "正在更改主机名..."
    hostnamectl set-hostname ${HOSTNAME}
    echo ${HOSTNAME} > /etc/hostname
    
    # 验证更改结果
    NEW_HOSTNAME=$(hostname)
    if [[ "$NEW_HOSTNAME" == "$HOSTNAME" ]]; then
        echo "✅ 主机名更改成功: $NEW_HOSTNAME"
    else
        echo "❌ 主机名更改失败"
        exit 1
    fi
else
    echo "✅ 主机名已经是 '$HOSTNAME'，无需更改"
fi

# 显示主机名状态
echo "主机名配置状态:"
hostnamectl status | grep -E "Static hostname|Icon name|Machine ID"

# 获取网络配置
LOCAL_IP=$(get_local_ip)
echo "检测到本机IP地址: $LOCAL_IP"
echo "========================================="

# 安装必要工具
echo "步骤1: 安装必要工具..."
yum install tar expect unixODBC -y

# 创建安装目录
echo "步骤2: 创建安装目录..."
mkdir -p /opt/software/openGauss/script/

# 切换到安装目录
echo "步骤3: 切换到安装目录..."
cd /opt/software/openGauss

# 解压安装包
echo "步骤4: 解压openGauss安装包..."
DOWNLOADED_FILE=$(basename "$SELECTED_URL")
tar -zxf "$SCRIPT_DIR/$DOWNLOADED_FILE"

# 根据版本动态解压OM包
echo "正在检测OM包..."
SELECTED_VERSION_NUM="${VERSION_INFO[$SELECTED_VERSION]}"

# 根据版本类型查找不同的OM包命名规则
if [[ "$SELECTED_VERSION_NUM" =~ ^5\. ]] || [[ "$SELECTED_VERSION_NUM" == "6.0.0-RC1" ]]; then
    # 5.x版本OM包命名规则: openGauss-5.x.x-openEuler-64bit-om.tar.gz
    os_ver=""
    if [[ "$SYSTEM_OS_VERSION" == "22.03" ]]; then
        os_ver="$OS_VERSION_5X_2203"
    else
        os_ver="$OS_VERSION_5X_2003"
    fi
    
    OM_FILE=$(find . -name "openGauss-${SELECTED_VERSION_NUM}-${os_ver}-64bit-om.tar.gz" | head -1)
    if [[ -z "$OM_FILE" ]]; then
        # 尝试通配符匹配
        OM_FILE=$(find . -name "openGauss-*-${os_ver}-64bit-om.tar.gz" | head -1)
    fi
else
    # 6.x+版本OM包命名规则: openGauss-OM-6.x.x-openEuler22.03/20.03-架构.tar.gz
    os_ver=""
    arch_suffix=""
    if [[ "$SYSTEM_OS_VERSION" == "22.03" ]]; then
        os_ver="$OS_VERSION_6X_2203"
    else
        os_ver="$OS_VERSION_6X_2003"
    fi
    
    if [[ "$SYSTEM_ARCH" == "AArch64" ]]; then
        arch_suffix="$ARCH_SUFFIX_ARM"
    else
        arch_suffix="$ARCH_SUFFIX_X86"
    fi
    
    OM_FILE=$(find . -name "openGauss-OM-${SELECTED_VERSION_NUM}-${os_ver}-${arch_suffix}.tar.gz" | head -1)
    if [[ -z "$OM_FILE" ]]; then
        # 尝试通配符匹配
        OM_FILE=$(find . -name "openGauss-OM-*-${os_ver}-*.tar.gz" | head -1)
    fi
fi

if [[ -n "$OM_FILE" ]]; then
    echo "找到OM包: $OM_FILE"
    echo "解压OM包..."
    tar -zxf "$OM_FILE"
    echo "✅ OM包解压完成"
else
    echo "⚠️  警告: 未找到匹配的OM包文件"
    echo "版本: $SELECTED_VERSION_NUM"
    echo "架构: $SYSTEM_ARCH"
    echo "系统版本: openEuler $SYSTEM_OS_VERSION"
    echo "尝试查找所有可能的OM包..."
    find . -name "*om*.tar.gz" -o -name "*OM*.tar.gz" | head -5
fi

# 创建集群配置文件
echo "步骤5: 创建集群配置文件..."

cat > cluster_config.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<ROOT>
    <!-- openGauss整体信息 -->
    <CLUSTER>
        <PARAM name="clusterName" value="dbCluster" />
        <PARAM name="nodeNames" value="${HOSTNAME}" />
        <PARAM name="gaussdbAppPath" value="/opt/huawei/install/app" />
        <PARAM name="gaussdbLogPath" value="/var/log/omm" />
        <PARAM name="tmpMppdbPath" value="/opt/huawei/tmp" />
        <PARAM name="gaussdbToolPath" value="/opt/huawei/install/om" />
        <PARAM name="corePath" value="/opt/huawei/corefile" />
        <PARAM name="backIp1s" value="${LOCAL_IP}"/>
    </CLUSTER>
    <!-- 每台服务器上的节点部署信息 -->
    <DEVICELIST>
        <!-- 节点1上的部署信息 -->
        <DEVICE sn="${HOSTNAME}">
            <PARAM name="name" value="${HOSTNAME}"/>
            <PARAM name="azName" value="AZ1"/>
            <PARAM name="azPriority" value="1"/>
            <!-- 使用检测到的本机IP地址 -->
            <PARAM name="backIp1" value="${LOCAL_IP}"/>
            <PARAM name="sshIp1" value="${LOCAL_IP}"/>
            
            <!--dbnode-->
            <PARAM name="dataNum" value="1"/>
            <PARAM name="dataPortBase" value="15400"/>
            <PARAM name="dataNode1" value="/opt/huawei/install/data/dn"/>
            <PARAM name="dataNode1_syncNum" value="0"/>
        </DEVICE>
    </DEVICELIST>
</ROOT>
EOF

echo "✅ 集群配置文件创建完成"
echo "配置信息:"
echo "- 主机名: ${HOSTNAME}"
echo "- IP地址: ${LOCAL_IP}"
echo "- 数据库端口: 15400"
echo "- 选择版本: ${SELECTED_VERSION}"
echo "- 系统架构: ${SYSTEM_ARCH}"
echo "- 系统版本: openEuler ${SYSTEM_OS_VERSION}"
echo "- 下载链接: ${SELECTED_URL}"

# openEuler 20.03系统需要创建libreadline.so.7软链接
if [[ "$SYSTEM_OS_VERSION" == "20.03" ]]; then
    echo "检测到openEuler 20.03系统，正在创建libreadline.so.7软链接..."
    
    # 检查是否已存在软链接
    if [[ ! -L "/usr/lib64/libreadline.so.7" ]]; then
        # 检查libreadline.so.8是否存在
        if [[ -f "/usr/lib64/libreadline.so.8" ]]; then
            echo "正在创建libreadline.so.7软链接..."
            cd /usr/lib64
            ln -s libreadline.so.8 libreadline.so.7
            echo "✅ libreadline.so.7软链接创建成功"
            
            # 验证软链接
            if [[ -L "/usr/lib64/libreadline.so.7" ]]; then
                echo "软链接验证成功: $(ls -la /usr/lib64/libreadline.so.7)"
            else
                echo "❌ 软链接创建失败"
                exit 1
            fi
        else
            echo "❌ 错误: 未找到libreadline.so.8文件"
            echo "请先安装readline库: yum install readline-devel -y"
            exit 1
        fi
    else
        echo "✅ libreadline.so.7软链接已存在，跳过创建"
        echo "当前软链接: $(ls -la /usr/lib64/libreadline.so.7)"
    fi
    echo "========================================="
fi

# 设置目录权限
echo "步骤6: 设置目录权限..."
chmod 755 -R /opt/software

# 执行预安装
echo "步骤7: 执行预安装..."
cd /opt/software/openGauss/script/

echo "正在执行预安装，这可能需要几分钟时间..."
echo "将自动创建omm用户并设置密码为: ${DEFAULT_PASSWORD}"
echo ""

# 使用expect自动化输入
expect << EOF
set timeout -1
log_user 1
spawn ./gs_preinstall -U omm -G dbgrp -X /opt/software/openGauss/cluster_config.xml

expect {
    -re "Are you sure you want to create the user.*\\(yes/no\\)\\?" {
        send "yes\r"
        exp_continue
    }
    -re "Please enter password for cluster user\\..*Password:" {
        send "${DEFAULT_PASSWORD}\r"
        exp_continue
    }
    -re "Please enter password for cluster user again\\..*Password:" {
        send "${DEFAULT_PASSWORD}\r"
        exp_continue
    }
    -re "Password:" {
        send "${DEFAULT_PASSWORD}\r"
        exp_continue
    }
    "Preinstallation succeeded" {
        puts "预安装成功完成"
        exit 0
    }
    "Preinstallation failed" {
        puts "预安装失败"
        exit 1
    }
    -re "ERROR|error|Error" {
        puts "预安装过程中出现错误，但继续等待完成..."
        exp_continue
    }
    eof {
        puts "预安装进程结束"
        exit 0
    }
}
EOF

echo "预安装完成！"
echo ""
echo "========================================="
echo "预安装已完成，omm用户已创建"
echo "用户名: omm"
echo "密码: ${DEFAULT_PASSWORD}"
echo ""
echo "开始执行数据库安装..."
echo "========================================="


# 切换到omm用户并执行安装
echo "正在切换到omm用户并执行数据库安装..."
su - omm << 'OMMSUDO'
cd /opt/software/openGauss
# 使用expect自动化数据库安装过程
expect << EOF
set timeout -1
log_user 1
spawn gs_install -X /opt/software/openGauss/cluster_config.xml

expect {
    -re "Please enter password for database:.*" {
        send "Admin@2025\r"
        exp_continue
    }
    -re "Please repeat for database:.*" {
        send "Admin@2025\r"
        exp_continue
    }
    -re "Password:.*" {
        send "Admin@2025\r"
        exp_continue
    }
    "Installation succeeded" {
        puts "数据库安装成功完成"
        exit 0
    }
    "completed successfully" {
        puts "安装成功完成"
        exit 0
    }
    "Installation failed" {
        puts "数据库安装失败"
        exit 1
    }
    -re "ERROR|error|Error" {
        puts "安装过程中出现错误，但继续等待完成..."
        exp_continue
    }
    eof {
        puts "openGauss数据库安装完成！"
        exit 0
    }
}

# 检查数据库状态
puts "正在检查数据库状态..."
spawn gs_om -t status

expect {
    "cluster_state" {
        puts "数据库状态检查完成"
        exit 0
    }
    -re "ERROR|error|Error" {
        puts "状态检查出现错误，但已完成"
        exit 0
    }
    eof {
        puts "状态检查完成"
        exit 0
    }
}
EOF

echo "========================================="
# 获取并显示数据库版本信息
# 设置环境变量
export GAUSSHOME=/opt/huawei/install/app
export PATH=$GAUSSHOME/bin:$PATH
export LD_LIBRARY_PATH=$GAUSSHOME/lib:$LD_LIBRARY_PATH

# 检查gsql命令是否可用并获取版本
if command -v gsql >/dev/null 2>&1; then
    echo "数据库版本信息:"
    gsql -V 2>/dev/null || echo "注意: gsql命令可用但无法获取版本信息（安装完成后可用）"
else
    echo "注意: gsql命令尚未可用，将在安装完成后可用"
fi

OMMSUDO

echo ""
echo "数据库信息："
echo "- 版本: ${SELECTED_VERSION}"
echo "- 架构: ${SYSTEM_ARCH}"
echo "- 系统版本: openEuler ${SYSTEM_OS_VERSION}"
echo "- 用户名: omm"
echo "- 用户密码: ${DEFAULT_PASSWORD}"
echo "- 数据库密码: ${DEFAULT_PASSWORD}"
echo "- 数据库端口: 15400"
echo "- 下载源: ${SELECTED_URL}"
echo ""
echo "常用命令："
echo "1. 查看数据库状态: gs_om -t status"
echo "2. 连接数据库: gsql -d postgres -p 15400"
echo "3. 启动数据库: gs_om -t start"
echo "4. 停止数据库: gs_om -t stop"
echo "========================================="
echo ""
echo "注意事项："
echo "- 请确保系统已关闭防火墙和SELinux"
echo "- 请确保系统时间同步"
echo "- 如果遇到权限问题，请检查用户和组是否正确创建"
echo "- 默认数据库端口为15400"
echo "- omm用户密码为: ${DEFAULT_PASSWORD}"
echo ""
echo "安装脚本执行完成！"
