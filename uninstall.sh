#!/bin/bash

# 高斯数据库卸载脚本
# 根据uninstall.log中的手工卸载步骤自动执行卸载过程
# 优化版本：提高健壮性，添加更好的错误处理和条件检查
# 主要功能：
# 1. 数据库应用卸载（通过gs_uninstall）
# 2. 环境清理（通过gs_postuninstall或手动清理）
# 3. 可选的/opt目录删除功能
# 4. 配置文件备份功能
# 5. 增强的错误处理和用户提示

# 不使用set -e，因为我们需要对错误进行更精细的控制，确保清理步骤能够执行

# 默认不删除/opt目录
DELETE_OPT=false
BACKUP_ENABLED=false
BACKUP_DIR="/tmp/opengauss_backup_$(date +%Y%m%d_%H%M%S)"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --delete-opt)
            DELETE_OPT=true
            shift
            ;;
        --backup)
            BACKUP_ENABLED=true
            shift
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --delete-opt    删除整个/opt目录"
            echo "  --backup        在卸载前备份关键配置文件"
            echo "  -h, --help      显示此帮助信息"
            exit 0
            ;;
        *)
            print_error "未知参数: $1"
            print_info "用法: $0 [--delete-opt] [--backup] [--help]"
            exit 1
            ;;
    esac
done

# 记录执行开始时间
START_TIME=$(date +%s)

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
        print_warning "用户 'omm' 不存在，可能高斯数据库未安装或已被卸载"
        return 1
    fi
    print_info "验证用户 'omm' 存在"
    return 0
}

# 创建备份
create_backup() {
    if [ "$BACKUP_ENABLED" = true ]; then
        print_info "开始备份关键配置文件..."
        mkdir -p "$BACKUP_DIR"
        
        # 备份配置文件
        if [ -d "/opt/software/openGauss" ]; then
            cp -r /opt/software/openGauss/* "$BACKUP_DIR/" 2>/dev/null || print_warning "部分配置文件备份失败"
            print_info "配置文件已备份到 $BACKUP_DIR"
        else
            print_warning "未找到配置文件目录，跳过备份"
        fi
    fi
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
    
    # 先尝试查找gs_uninstall命令的准确路径
    local GS_UNINSTALL_PATH
    GS_UNINSTALL_PATH=$(su - omm -c "command -v gs_uninstall 2>/dev/null")
    
    if [ -n "$GS_UNINSTALL_PATH" ]; then
        print_info "找到gs_uninstall命令: $GS_UNINSTALL_PATH"
        print_info "执行gs_uninstall --delete-data..."
        su - omm -c "$GS_UNINSTALL_PATH --delete-data" || {
            print_error "gs_uninstall命令执行失败"
            return 1
        }
    else
        # 如果找不到命令，尝试从常见路径查找
        local COMMON_PATHS=("/opt/software/openGauss/app/bin/gs_uninstall"
                          "/usr/local/opengauss/app/bin/gs_uninstall")
        
        local found=false
        for path in "${COMMON_PATHS[@]}"; do
            if [ -x "$path" ]; then
                print_info "从常见路径找到gs_uninstall: $path"
                su - omm -c "$path --delete-data" || {
                    print_error "使用 $path 执行失败"
                    continue
                }
                found=true
                break
            fi
        done
        
        if [ "$found" = false ]; then
            print_error "找不到gs_uninstall命令，无法执行数据库卸载"
            return 1
        fi
    fi
    
    print_info "高斯数据库应用程序卸载成功"
    return 0
}

# 删除/opt目录的函数
# 注意：此操作非常危险，将删除整个/opt目录下的所有内容
remove_opt_directory() {
    # 检查/opt目录是否存在，避免不必要的错误提示
    if [ ! -d "/opt" ]; then
        print_info "/opt 目录不存在，无需删除"
        return 0
    fi
    
    # 显示严重警告，确保用户了解操作的危险性
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
    rm -rf /opt 2>/dev/null
    if [ $? -eq 0 ]; then
        print_info "/opt 目录已成功删除"
    else
        print_error "删除 /opt 目录时出错，请检查权限"
        return 1
    fi
    
    return 0
}

# 清理环境
cleanup_environment() {
    print_info "开始清理环境..."
    
    # 尝试找到gs_postuninstall脚本的准确路径
    local GS_POSTUNINSTALL
    local CONFIG_FILE
    
    # 尝试多个可能的路径
    local POSTUNINSTALL_PATHS=("/opt/software/openGauss/script/gs_postuninstall"
                             "/usr/local/opengauss/script/gs_postuninstall")
    
    local CONFIG_PATHS=("/opt/software/openGauss/cluster_config.xml"
                      "/usr/local/opengauss/cluster_config.xml")
    
    # 查找有效的gs_postuninstall路径
    for path in "${POSTUNINSTALL_PATHS[@]}"; do
        if [ -x "$path" ]; then
            GS_POSTUNINSTALL="$path"
            print_info "找到gs_postuninstall脚本: $GS_POSTUNINSTALL"
            break
        fi
    done
    
    # 查找有效的配置文件路径
    for path in "${CONFIG_PATHS[@]}"; do
        if [ -f "$path" ]; then
            CONFIG_FILE="$path"
            print_info "找到配置文件: $CONFIG_FILE"
            break
        fi
    done
    
    # 如果找到gs_postuninstall和配置文件，尝试执行
    if [ -n "$GS_POSTUNINSTALL" ] && [ -n "$CONFIG_FILE" ]; then
        print_info "执行gs_postuninstall清理环境..."
        $GS_POSTUNINSTALL -U omm -X $CONFIG_FILE --delete-user || {
            print_warning "gs_postuninstall执行失败，尝试手动清理基本环境..."
            manual_cleanup
        }
    else
        print_warning "无法找到gs_postuninstall脚本或配置文件，直接进行手动清理"
        manual_cleanup
    fi
    
    # 如果指定了删除/opt目录选项
    if [ "$DELETE_OPT" = true ]; then
        remove_opt_directory
    fi
    
    # 清理可能的残留文件和目录
    additional_cleanup
    
    print_info "环境清理完成"
    return 0
}

# 手动清理环境
# 当gs_postuninstall执行失败或不存在时，使用此函数进行手动清理
manual_cleanup() {
    print_info "执行手动清理环境..."
    
    # 删除omm用户（如果存在）
    # 使用userdel -r删除用户及其主目录
    if id -u omm >/dev/null 2>&1; then
        print_info "删除用户 'omm'..."
        userdel -r omm >/dev/null 2>&1 || print_warning "无法删除用户 'omm'，可能需要手动清理"
    fi
    
    # 删除相关目录
    # 尝试清理多个可能的安装路径和日志目录
    print_info "删除OpenGauss相关目录..."
    rm -rf /opt/software/openGauss >/dev/null 2>&1 || true
    rm -rf /usr/local/opengauss >/dev/null 2>&1 || true
    rm -rf /var/log/omm >/dev/null 2>&1 || true
    rm -rf /home/omm >/dev/null 2>&1 || true
    
    # 删除可能的环境变量文件
    # 清理/etc/profile.d目录中可能存在的OpenGauss环境变量脚本
    rm -f /etc/profile.d/opengauss* >/dev/null 2>&1 || true
    
    print_info "手动清理完成"
}

# 额外清理步骤
# 清理一些可能被遗漏的残留文件和目录
additional_cleanup() {
    print_info "执行额外清理步骤..."
    
    # 清理系统临时文件中可能的残留
    # 使用find命令查找并删除/tmp目录中与OpenGauss相关的临时目录
    # 注意：使用-type d只删除目录，避免删除重要文件
    find /tmp -name "*opengauss*" -o -name "*omm*" -type d -exec rm -rf {} \; 2>/dev/null || true
    
    # 清理可能的cron任务
    # 删除omm用户可能的定时任务配置
    rm -f /var/spool/cron/omm >/dev/null 2>&1 || true
    
    # 检查并清理可能的Om目录（根据日志中发现的/om目录）
    # 从卸载日志中看到系统有/om目录，需要进行清理
    if [ -d "/om" ]; then
        print_info "发现/om目录，进行清理..."
        rm -rf /om >/dev/null 2>&1 || print_warning "无法删除/om目录"
    fi
    
    print_info "额外清理完成"
}

# 主函数
# 脚本的入口点，协调执行各个卸载步骤
main() {
    print_info "=== 高斯数据库卸载脚本 ==="
    print_info "开始时间: $(date)"
    
    # 检查root权限
    # 卸载过程需要root权限以执行各种系统操作
    check_root
    
    # 创建备份（如果启用）
    # 在卸载前备份配置文件，以便后续需要时恢复
    create_backup
    
    # 显示删除/opt选项状态
    # 警告用户已启用危险的/opt目录删除选项
    if [ "$DELETE_OPT" = true ]; then
        print_warning "⚠️  注意：已启用删除 /opt 目录选项 ⚠️"
    fi
    
    # 检查omm用户是否存在
    # 使用变量记录检查结果，避免重复调用函数
    OMM_USER_EXISTS=false
    check_omm_user && OMM_USER_EXISTS=true
    
    if [ "$OMM_USER_EXISTS" = false ]; then
        print_warning "继续清理可能存在的残留文件..."
    fi
    
    # 执行卸载（只有当omm用户存在且gs_uninstall可用时）
    # 只有在必要条件满足时才尝试数据库卸载
    if [ "$OMM_USER_EXISTS" = true ] && check_gs_uninstall; then
        uninstall_database
    else
        print_warning "跳过数据库卸载步骤，直接清理环境"
    fi
    
    # 清理环境
    # 无论卸载是否成功，都尝试清理环境
    cleanup_environment
    
    # 计算执行时间
    # 记录脚本执行用时，提供性能参考
    END_TIME=$(date +%s)
    EXECUTION_TIME=$((END_TIME - START_TIME))
    
    print_info ""
    print_info "=== 卸载完成 ==="
    print_info "结束时间: $(date)"
    print_info "总执行时间: ${EXECUTION_TIME}秒"
    
    if [ "$DELETE_OPT" = true ]; then
        print_info "高斯数据库已成功卸载，/opt目录已被删除"
    else
        print_info "高斯数据库已成功卸载，所有相关文件和用户已清理"
    fi
    
    if [ "$BACKUP_ENABLED" = true ]; then
        print_info "配置文件已备份到: $BACKUP_DIR"
    fi
    
    print_info ""
    print_info "使用说明："
    print_info "1. 如果需要删除 /opt 目录，请使用 $0 --delete-opt"
    print_info "2. 如果需要备份配置文件，请使用 $0 --backup"
    print_info "3. 如需帮助，请使用 $0 --help"
}

# 执行主函数
main