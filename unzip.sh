# ---------- 全局配置 ----------
DOWNLOAD_DIR="/sdcard/Download"
QQ_DIR="/sdcard/Download/QQ"
OUTPUT_BASE="/sdcard/Download"

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[信息]${NC} $1"; }
warn()  { echo -e "${YELLOW}[提示]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }

# 1. 检查并安装 7zip
check_and_install_7zip() {
    if command -v 7zz &> /dev/null; then
        info "已检测到 7z，跳过安装。"
        return 0
    fi

    info "未检测到 7z，正在尝试自动安装 7zip（首次可能需要几十秒）..."

    INSTALL_LOG=$(pkg install 7zip -y 2>&1)
    if command -v 7zz &> /dev/null; then
        info "7zip 安装成功。"
        return 0
    else
        error "7zip 自动安装失败！报错如下（如有需要，可尝试将报错截图后，问ai解决）"
        echo "----------------------------------------"
        echo "$INSTALL_LOG"
        echo "----------------------------------------"
        warn "你也可以尝试手动执行：pkg install 7zip"
        exit 1
    fi
}

# 2. 申请存储权限
ensure_storage() {
    if [ ! -d "$HOME/storage" ]; then
        info "正在申请存储权限，请在弹窗中点“允许”..."
        termux-setup-storage
        sleep 2
    fi
}

# 3. 选择压缩包所在目录
choose_directory() {
    while true; do
        echo ""
        echo "请选择压缩包来源："
        echo "  1) 浏览器/其他下载  ->  $DOWNLOAD_DIR"
        echo "  2) QQ 保存的文件    ->  $QQ_DIR"
        echo "  q) 退出脚本"
        read -p "请输入 1 或 2 [默认1]: " choice

        # 回车默认 1
        [ -z "$choice" ] && choice="1"

        case "$choice" in
            1)
                if [ ! -d "$DOWNLOAD_DIR" ]; then
                    error "找不到下载目录：$DOWNLOAD_DIR"
                    warn "请确认已授予 Termux 存储权限。"
                    continue
                fi
                WORK_DIR="$DOWNLOAD_DIR"
                info "工作目录已设为：$WORK_DIR"
                return 0
                ;;
            2)
                # 若QQ 保存目录不存在就自动建
                if [ ! -d "$QQ_DIR" ]; then
                    mkdir -p "$QQ_DIR"
                    if [ ! -d "$QQ_DIR" ]; then
                        error "无法创建目录：$QQ_DIR"
                        warn "请确认已授予 Termux 存储权限。"
                        continue
                    fi
                    info "已自动创建目录：$QQ_DIR"
                fi
                WORK_DIR="$QQ_DIR"
                info "工作目录已设为：$WORK_DIR"
                return 0
                ;;
            q|Q)
                info "已退出。"
                exit 0
                ;;
            *)
                warn "输入无效，请输入 1、2 或 q。"
                ;;
        esac
    done
}

# 4. 收集目录下的压缩包（含分卷识别）
collect_archives() {
    cd "$WORK_DIR" || return 1
    ARCHIVES=()
    while IFS= read -r -d '' f; do
        base=$(basename "$f")
        # 非首个分卷跳过（.7z.002 这种）
        if [[ "$base" =~ \.7z\.[0-9]{3}$ ]] && [[ ! "$base" =~ \.7z\.001$ ]]; then
            continue
        fi
        ARCHIVES+=("$base")
    done < <(find . -maxdepth 1 -type f \
        \( -iname "*.7z" -o -iname "*.7z.001" \
        -o -iname "*.zip" -o -iname "*.rar" \
        -o -iname "*.tar" -o -iname "*.tar.gz" \
        -o -iname "*.tgz" -o -iname "*.tar.bz2" \
        -o -iname "*.tar.xz" -o -iname "*.gz" \) -print0)

    return 0
}

# 5. 解压指定文件
extract_file() {
    local target="$1"
    local base
    base=$(basename "$target")
    local name="${base%.7z.001}"
    name="${name%.7z}"
    name="${name%.zip}"
    name="${name%.rar}"
    name="${name%.tar.gz}"
    name="${name%.tgz}"
    name="${name%.tar.bz2}"
    name="${name%.tar.xz}"
    name="${name%.tar}"
    name="${name%.gz}"

    local rand=$RANDOM
    local out_dir="${OUTPUT_BASE}/${name}_extracted_${rand}"

    info "正在解压：$base"
    info "输出目录：$out_dir"
    mkdir -p "$out_dir"

    if 7zz x "$target" -o"$out_dir" -y; then
        info "解压完成！文件位于：$out_dir"
        return 0
    else
        error "解压失败，可能原因：文件损坏 / 密码错误 / 分卷不全。"
        return 1
    fi
}

# 6. 主流程
main_flow() {
    collect_archives
    if [ ${#ARCHIVES[@]} -eq 0 ]; then
        error "当前目录没有找到任何压缩包。"
        warn "请确认文件已放在：$WORK_DIR"
        exit 1
    fi

    while true; do
        echo ""
        read -p "请输入压缩包名字（可只输入一部分，q 退出，回车列出所有压缩包）: " keyword
        [ "$keyword" = "q" ] || [ "$keyword" = "Q" ] && { info "已退出。"; exit 0; }

        # 模糊匹配
        MATCHES=()
        for f in "${ARCHIVES[@]}"; do
            if [[ "$f" == *"$keyword"* ]]; then
                MATCHES+=("$f")
            fi
        done

        # ---------- 情况 A：唯一命中 ----------
        if [ ${#MATCHES[@]} -eq 1 ]; then
            echo ""
            info "找到匹配：${MATCHES[0]}"
            read -p "是你要解压的压缩包吗？(y/n): " ans
            case "$ans" in
                y|Y)
                    extract_file "${MATCHES[0]}"
                    return 0
                    ;;
                n|N)
                    warn "重新输入名字"
                    continue
                    ;;
                q|Q)
                    info "已退出。"; exit 0
                    ;;
                *)
                    warn "请输入 y 或 n。"
                    continue
                    ;;
            esac
        fi

        # ---------- 情况 B：多个命中 ----------
        if [ ${#MATCHES[@]} -gt 1 ]; then
            echo ""
            info "匹配到多个压缩包："
            for i in "${!MATCHES[@]}"; do
                echo "  $((i+1))) ${MATCHES[$i]}"
            done
            echo "  0) 重新输入名字"
            echo "  q) 退出"
            read -p "请输入编号: " idx

            if [ "$idx" = "q" ] || [ "$idx" = "Q" ]; then
                info "已退出。"; exit 0
            fi
            if [ "$idx" = "0" ]; then
                continue
            fi
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le ${#MATCHES[@]} ]; then
                extract_file "${MATCHES[$((idx-1))]}"
                return 0
            else
                warn "编号无效，请重新选择。"
                continue
            fi
        fi

        # ---------- 情况 C：一个都没匹配到 ----------
        warn "没有找到名字包含「$keyword」的压缩包。"
        warn "下面是当前目录所有压缩包，请直接选编号："
        echo ""
        for i in "${!ARCHIVES[@]}"; do
            echo "  $((i+1))) ${ARCHIVES[$i]}"
        done
        echo "  0) 重新输入名字"
        echo "  q) 退出"
        read -p "请输入编号: " idx

        if [ "$idx" = "q" ] || [ "$idx" = "Q" ]; then
            info "已退出。"; exit 0
        fi
        if [ "$idx" = "0" ]; then
            continue
        fi
        if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le ${#ARCHIVES[@]} ]; then
            extract_file "${ARCHIVES[$((idx-1))]}"
            return 0
        else
            warn "编号无效，请重新选择。"
            continue
        fi
    done
}

#head
echo "============================================"
echo "          一键解压脚本 (By MK.)"
echo "============================================"
ensure_storage
check_and_install_7zip
choose_directory
main_flow
echo ""