#!/bin/bash

# 高斯数据库卸载脚本
# 根据uninstall.log中的手工卸载步骤自动执行卸载过程

set -e  # 遇到错误时退出脚本

# 默认不删除/opt目录
DELETE_OPT=false

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --delete-opt)
            DELETE_OPT=true
            shift
            ;;
        *)
            print_error "未知参数: $1"
            print_info "用法: $0 [--delete-opt]"
            exit 1
            ;;
    esac
done

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以root用户运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "请以root用户运行此脚本"
        exit 1
    fi
}

# 检查omm用户是否存在
check_omm_user() {
    if ! id -u omm >/dev/null 2>&1; then
        print_error "用户 'omm' 不存在，可能高斯数据库未安装或已被卸载"
        return 1
    fi
    return 0
}

# 检查gs_uninstall命令是否可用
check_gs_uninstall() {
    su - omm -c "command -v gs_uninstall" >/dev/null 2>&1 || {
        print_error "gs_uninstall命令不可用，可能高斯数据库未正确安装"
        return 1
    }
    return 0
}

# 检查gs_postuninstall脚本是否存在
check_gs_postuninstall() {
    if [ ! -f "/opt/software/openGauss/script/gs_postuninstall" ]; then
        print_warning "gs_postuninstall脚本不存在于默认路径，将尝试从环境变量查找"
        return 1
    fi
    return 0
}

# 检查配置文件是否存在
check_config_file() {
    if [ ! -f "/opt/software/openGauss/cluster_config.xml" ]; then
        print_warning "配置文件不存在于默认路径，将尝试从环境变量查找"
        return 1
    fi
    return 0
}

# 执行数据库卸载
uninstall_database() {
    print_info "开始卸载高斯数据库..."
    
    # 以omm用户身份执行gs_uninstall命令
    print_info "执行gs_uninstall --delete-data..."
    su - omm -c "gs_uninstall --delete-data" || {
        print_error "gs_uninstall命令执行失败"
        return 1
    }
    
    print_info "高斯数据库应用程序卸载成功"
    return 0
}

# 删除/opt目录的函数
remove_opt_directory() {
    # 显示严重警告
    print_error "=================================================="
    print_error "⚠️  危险操作警告 ⚠️"
    print_error "=================================================="
    print_error "您正在尝试删除整个 /opt 目录！"
    print_error "此操作将删除该目录下的所有文件和子目录！"
    print_error "此操作无法撤销！"
    print_error "请确保您理解此操作的后果！"
    print_error "=================================================="
    
    # 只保留一次确认
    read -p "您确定要删除整个 /opt 目录吗？(yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        print_info "取消删除 /opt 目录操作"
        return 0
    fi
    
    # 执行删除操作
    print_info "开始删除 /opt 目录..."
    rm -rf /opt
    if [ $? -eq 0 ]; then
        print_info "/opt 目录已成功删除"
    else
        print_error "删除 /opt 目录时出错"
        return 1
    fi
    
    return 0
}

# 清理环境
cleanup_environment() {
    print_info "开始清理环境..."
    
    # 设置gs_postuninstall路径和配置文件路径
    local GS_POSTUNINSTALL="/opt/software/openGauss/script/gs_postuninstall"
    local CONFIG_FILE="/opt/software/openGauss/cluster_config.xml"
    
    # 执行gs_postuninstall命令
    print_info "执行gs_postuninstall清理环境..."
    $GS_POSTUNINSTALL -U omm -X $CONFIG_FILE --delete-user || {
        print_warning "gs_postuninstall执行失败，尝试清理基本环境..."
        
        # 如果gs_postuninstall执行失败，尝试手动清理一些基本内容
        print_info "尝试手动清理基本环境..."
        
        # 删除用户（如果存在）
        if id -u omm >/dev/null 2>&1; then
            userdel -r omm >/dev/null 2>&1 || print_warning "无法删除用户 'omm'"
        fi
        
        # 删除相关目录
        rm -rf /opt/software/openGauss >/dev/null 2>&1 || true
        rm -rf /var/log/omm >/dev/null 2>&1 || true
    }
    
    # 如果指定了删除/opt目录选项
    if [ "$DELETE_OPT" = true ]; then
        remove_opt_directory
    fi
    
    print_info "环境清理完成"
    return 0
}

# 主函数
main() {
    print_info "=== 高斯数据库卸载脚本 ==="
    
    # 检查root权限
    check_root
    
    # 显示删除/opt选项状态
    if [ "$DELETE_OPT" = true ]; then
        print_warning "⚠️  注意：已启用删除 /opt 目录选项 ⚠️"
    fi
    
    # 检查前提条件
    check_omm_user || {
        print_warning "继续清理可能存在的残留文件..."
    }
    
    # 执行卸载
    if check_omm_user && check_gs_uninstall; then
        uninstall_database
    else
        print_warning "跳过数据库卸载步骤，直接清理环境"
    fi
    
    # 清理环境
    cleanup_environment
    
    print_info ""
    print_info "=== 卸载完成 ==="
    if [ "$DELETE_OPT" = true ]; then
        print_info "高斯数据库已成功卸载，/opt目录已被删除"
    else
        print_info "高斯数据库已成功卸载，所有相关文件和用户已清理"
    fi
    print_info "用法提示：如果需要删除 /opt 目录，请使用 $0 --delete-opt"
}

# 执行主函数
main