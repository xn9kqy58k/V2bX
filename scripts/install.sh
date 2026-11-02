#!/usr/bin/env bash

usage() {
    cat <<'EOF'
用法：bash install.sh [install|update] [选项]

只下载 xn9kqy58k/V2bX 自己发布的 Linux 程序，不下载上游安装脚本。
默认执行 install；不指定版本时下载最新正式 Release。全程不需要交互。

  --version TAG       安装指定 Release 标签（或 latest）
  --install-dir DIR   程序目录，默认 /usr/local/bin
  --config-dir DIR    配置目录，默认 /etc/V2bX
  --service-dir DIR   systemd 单元目录，默认 /etc/systemd/system
  --no-service        不创建、启用或重启 systemd 服务
  --yes, -y           确认非交互执行（兼容自动部署）
  --help, -h          显示帮助

需要 root、Bash、curl 或 wget、unzip、sha256sum 和常见 coreutils
（包括 mktemp、timeout、cp、mv）。不会自动安装依赖或升级系统。
首次只生成 config.json.example；填好面板配置并保存为 config.json 后再启动。
更新保留配置；原子替换程序，下载、校验或重启失败会保留/恢复旧程序。
EOF
}

fail() { printf '错误：%s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

# Keep this pure so the release asset mapping can be tested without changing a host.
release_arch() {
    local machine=$1 bits=${2:-} endian=${3:-}
    case "$machine" in
        x86_64|amd64) [[ "$bits" == 32 ]] && printf 'linux-32\n' || printf 'linux-64\n' ;;
        i386|i486|i586|i686|x86) printf 'linux-32\n' ;;
        aarch64|arm64) [[ "$bits" == 32 ]] && printf 'linux-arm32-v7a\n' || printf 'linux-arm64-v8a\n' ;;
        armv8l|armv7*) printf 'linux-arm32-v7a\n' ;;
        armv6*) printf 'linux-arm32-v6\n' ;;
        armv5*) printf 'linux-arm32-v5\n' ;;
        mips|mips64)
            [[ "$endian" == little || "$endian" == big ]] || return 1
            if [[ "$machine" == mips64 && "$bits" != 32 ]]; then
                [[ "$endian" == little ]] && printf 'linux-mips64le\n' || printf 'linux-mips64\n'
            else
                [[ "$endian" == little ]] && printf 'linux-mips32le\n' || printf 'linux-mips32\n'
            fi ;;
        mipsel|mipsle) printf 'linux-mips32le\n' ;;
        mips64el|mips64le) [[ "$bits" == 32 ]] && printf 'linux-mips32le\n' || printf 'linux-mips64le\n' ;;
        ppc64le|ppc64el) printf 'linux-ppc64le\n' ;;
        ppc64) printf 'linux-ppc64\n' ;;
        riscv64) printf 'linux-riscv64\n' ;;
        s390x) printf 'linux-s390x\n' ;;
        *) return 1 ;;
    esac
}

detect_arch() {
    local machine bits='' endian='' elf_data
    machine=$(uname -m)
    if command -v getconf >/dev/null 2>&1; then bits=$(getconf LONG_BIT 2>/dev/null || true); fi
    case "$machine" in
        mips|mips64)
            command -v od >/dev/null 2>&1 || fail 'MIPS 架构检测还需要 od（coreutils）。'
            elf_data=$(od -An -tu1 -j5 -N1 /bin/sh)
            case "${elf_data//[[:space:]]/}" in 1) endian=little ;; 2) endian=big ;; esac ;;
    esac
    release_arch "$machine" "$bits" "$endian" || fail "没有可确认兼容的 Linux 安装包：$machine / $bits 位。"
}

validate_dir() {
    local path=$1
    [[ "$path" == /* && "$path" != / ]] || fail '目录参数必须是非根目录的绝对路径。'
    case "$path" in
        *$'\n'*|*$'\r'*|*'"'*|*'\'*|*'$'*|*'%'*) fail '目录不能包含换行、引号、反斜杠、$ 或 %。' ;;
    esac
}

download() {
    local url=$1 destination=$2
    case "$url" in https://github.com/xn9kqy58k/V2bX/releases/*) ;; *) fail '拒绝从非自有 Release 下载。' ;; esac
    if command -v curl >/dev/null 2>&1; then
        timeout 300 curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
            --connect-timeout 15 --max-time 300 --retry 2 --output "$destination" "$url"
    else
        timeout 300 wget --https-only --timeout=30 --tries=3 --output-document="$destination" "$url"
    fi
}

verify_archive() {
    local archive=$1 checksum=$2 expected='' filename='' extra='' line='' count=0 actual
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        [[ -n "$line" ]] || continue
        count=$((count + 1))
        read -r expected filename extra <<<"$line"
    done <"$checksum"
    [[ "$count" == 1 && "$expected" =~ ^[[:xdigit:]]{64}$ && -z "$extra" ]] || return 1
    [[ "${filename#\*}" == "${archive##*/}" ]] || return 1
    actual=$(sha256sum -- "$archive")
    [[ "${actual%% *}" == "${expected,,}" ]]
}

# The standalone installer embeds the same default unit as scripts/V2bX.service.
render_service() {
    local bin_dir=$1 conf_dir=$2
    cat <<EOF
[Unit]
Description=V2bX node server
Wants=network-online.target
After=network-online.target
ConditionPathExists=$conf_dir/config.json

[Service]
Type=simple
WorkingDirectory="$conf_dir"
ExecStart="$bin_dir/V2bX" server --config "$conf_dir/config.json"
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
}

systemd_available() {
    command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

verify_existing_service() {
    local target=$1 details remainder executable canonical_executable canonical_target
    details=$(systemctl show --property=ExecStart --value V2bX.service) || fail '读不到已有服务的启动路径；请核对服务或使用 --no-service。'
    [[ "$details" == '{ path='* && "$details" == *' ; argv[]='* ]] || fail '无法确认自定义服务的启动程序；请自行核对并使用 --no-service。'
    remainder=${details#'{ path='}
    [[ "$remainder" != *'{ path='* ]] || fail '已有服务包含多个启动命令，请自行核对并使用 --no-service。'
    executable=${remainder%%' ; argv[]='*}
    [[ "$executable" == /* ]] || fail '已有服务未使用可确认的绝对启动路径，请使用 --no-service。'
    [[ "$executable" == "$target" ]] && return 0
    canonical_executable=$(readlink -f -- "$executable") || fail '无法解析已有服务路径，请使用 --install-dir 原安装目录或 --no-service。'
    canonical_target=$(readlink -f -- "$target") || fail '无法解析目标程序路径，请使用 --install-dir 原安装目录或 --no-service。'
    # Replacing a symlink at target would not update another path to its old referent.
    [[ ! -L "$target" && "$canonical_executable" == "$canonical_target" ]] || fail "已有服务启动的是 $executable；请使用 --install-dir 指定该程序原目录，或使用 --no-service 手动接管。"
}

write_example() {
    [[ -e "$config_dir/config.json" || -e "$config_dir/config.json.example" ]] && return 0
    (umask 077; set -o noclobber; cat >"$config_dir/config.json.example" <<'EOF'
{
  "Log": { "Level": "info", "Output": "" },
  "Cores": [{ "Type": "sing", "Log": { "Level": "info", "Timestamp": true } }],
  "Nodes": [{
    "Core": "sing", "ApiHost": "https://your-panel.example", "ApiKey": "CHANGE_ME",
    "NodeID": 1, "NodeType": "vless", "Timeout": 30,
    "ListenIP": "0.0.0.0", "SendIP": "0.0.0.0"
  }]
}
EOF
    )
}

install_auxiliary() {
    local name target
    for name in geoip.dat geosite.dat geoip.db geosite.db dns.json route.json custom_inbound.json custom_outbound.json; do
        target="$config_dir/$name"
        [[ ! -e "$target" && ! -L "$target" ]] || continue
        if unzip -p "$work_dir/$asset" "$name" >"$work_dir/$name" 2>/dev/null; then
            # noclobber also protects a file created by another process just now.
            (umask 022; set -o noclobber; cat "$work_dir/$name" >"$target")
        fi
    done
}

rollback() {
    note '安装没有完成，正在恢复旧程序和服务。' >&2
    if [[ "$restart_attempted" == 1 ]]; then systemctl stop V2bX.service || true; fi
    if [[ -n "$binary_backup" ]]; then
        mv -f -- "$binary_backup" "$binary" || { note "自动回滚失败，请保留并手动恢复：$binary_backup" >&2; return 1; }
        binary_backup=''
    else
        rm -f -- "$binary"
    fi
    if [[ "$unit_changed" == 1 ]]; then
        rm -f -- "$unit"
        systemctl daemon-reload || true
    fi
    if [[ "$enabled_by_installer" == 1 ]]; then systemctl disable V2bX.service || true; fi
    if [[ "$was_active" == 1 ]]; then
        systemctl restart V2bX.service || note '旧程序已恢复，但旧服务未能启动，请检查 journalctl -u V2bX。' >&2
    fi
}

cleanup_install() {
    local status=$?
    trap - EXIT
    if [[ "$committed" != 1 && "$binary_changed" == 1 ]]; then rollback || status=1; fi
    [[ -z "$staged_binary" ]] || rm -f -- "$staged_binary"
    [[ -z "$staged_unit" ]] || rm -f -- "$staged_unit"
    # Retain backups if rollback itself failed, so an operator can still recover.
    if [[ "$committed" == 1 || "$binary_changed" == 0 ]]; then
        [[ -z "$binary_backup" ]] || rm -f -- "$binary_backup"
    fi
    if [[ -n "$work_dir" && "$work_dir" == */v2bx-install.* && -d "$work_dir" ]]; then rm -rf -- "$work_dir"; fi
    exit "$status"
}

main() (
    set -euo pipefail
    action=install version=latest install_dir=/usr/local/bin config_dir=/etc/V2bX service_dir=/etc/systemd/system no_service=0
    work_dir='' staged_binary='' staged_unit='' binary_backup=''
    binary_changed=0 unit_changed=0 committed=0 restart_attempted=0 was_active=0 was_enabled=0 enabled_by_installer=0
    if [[ "${1:-}" == install || "${1:-}" == update ]]; then action=$1; shift; fi
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version|--install-dir|--config-dir|--service-dir)
                [[ $# -ge 2 && -n "$2" ]] || fail "$1 缺少参数。"
                case "$1" in --version) version=$2 ;; --install-dir) install_dir=$2 ;; --config-dir) config_dir=$2 ;; --service-dir) service_dir=$2 ;; esac
                shift 2 ;;
            --no-service) no_service=1; shift ;;
            --yes|-y) shift ;;
            --help|-h) usage; return 0 ;;
            *) fail "未知参数：$1（使用 --help 查看用法）" ;;
        esac
    done
    [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail '版本标签只能包含字母、数字、点、下划线和减号。'
    validate_dir "$install_dir"; validate_dir "$config_dir"; validate_dir "$service_dir"
    [[ $(uname -s) == Linux ]] || fail '这个安装脚本只支持 Linux。'
    [[ $(id -u) == 0 ]] || fail '请使用 sudo 或 root 执行安装。'
    for dependency in unzip sha256sum mktemp timeout cp mv mkdir chmod rm ln sleep readlink; do
        command -v "$dependency" >/dev/null 2>&1 || fail "缺少依赖：$dependency，请先用发行版包管理器安装。"
    done
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || fail '请先安装 curl 或 wget。'
    arch=$(detect_arch)
    asset="V2bX-$arch.zip"
    binary="$install_dir/V2bX" unit="$service_dir/V2bX.service"
    [[ "$action" != update || -f "$binary" ]] || fail "找不到已安装程序：$binary，请先执行 install。"
    use_systemd=0
    if [[ "$no_service" == 0 ]] && systemd_available; then
        use_systemd=1
        loaded_fragment=$(systemctl show --property=FragmentPath --value V2bX.service) || fail '读不到已有服务位置；请检查 systemd 或使用 --no-service。'
        if [[ -n "$loaded_fragment" && "$loaded_fragment" != "$unit" ]]; then
            canonical_fragment=$(readlink -f -- "$loaded_fragment") || fail '无法确认已有服务位置，请使用 --service-dir 原服务目录或 --no-service。'
            canonical_unit=$(readlink -f -- "$unit") || fail '无法确认目标服务位置，请使用 --service-dir 原服务目录或 --no-service。'
            [[ "$canonical_fragment" == "$canonical_unit" ]] || fail "已有服务来自 $loaded_fragment；请使用 --service-dir 指定原服务目录，或使用 --no-service。"
        fi
        if [[ -n "$loaded_fragment" || -e "$unit" || -L "$unit" ]]; then verify_existing_service "$binary"; fi
    fi
    if [[ "$version" == latest ]]; then
        release_url=https://github.com/xn9kqy58k/V2bX/releases/latest/download
    else
        release_url="https://github.com/xn9kqy58k/V2bX/releases/download/$version"
    fi
    trap cleanup_install EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/v2bx-install.XXXXXX")
    note "下载自有 Release：$asset（$version）"
    download "$release_url/$asset" "$work_dir/$asset" || fail '程序下载失败，旧程序未改动；请确认该版本有对应资产。'
    download "$release_url/$asset.sha256" "$work_dir/$asset.sha256" || fail 'SHA256 文件下载失败，旧程序未改动。'
    verify_archive "$work_dir/$asset" "$work_dir/$asset.sha256" || fail 'SHA256 校验失败，旧程序未改动。'
    mkdir -p -- "$install_dir" "$config_dir"
    staged_binary=$(mktemp "$install_dir/.V2bX.new.XXXXXX")
    entry=V2bX
    case "$arch" in linux-mips32*) entry=V2bX_softfloat ;; esac
    unzip -p "$work_dir/$asset" "$entry" >"$staged_binary" || fail "压缩包缺少 $entry 或解压失败，旧程序未改动。"
    [[ -s "$staged_binary" ]] || fail '解压得到空程序，旧程序未改动。'
    chmod 755 "$staged_binary"
    timeout 15 "$staged_binary" version >/dev/null || fail '新程序无法在本机运行，旧程序未改动。'
    if [[ -e "$binary" || -L "$binary" ]]; then
        binary_backup=$(mktemp "$install_dir/.V2bX.rollback.XXXXXX")
        cp -Pp -- "$binary" "$binary_backup"
    fi
    if [[ "$use_systemd" == 1 ]]; then
        if systemctl is-active --quiet V2bX.service; then was_active=1; fi
        if systemctl is-enabled --quiet V2bX.service; then was_enabled=1; fi
        mkdir -p -- "$service_dir"
        if [[ ! -e "$unit" && ! -L "$unit" ]]; then
            staged_unit=$(mktemp "$service_dir/.V2bX.service.new.XXXXXX")
            render_service "$install_dir" "$config_dir" >"$staged_unit"
            chmod 644 "$staged_unit"
        else
            note "保留已有服务文件：$unit（自定义路径时请核对其中的 ExecStart）。"
        fi
    fi
    mv -f -- "$staged_binary" "$binary"
    staged_binary='' binary_changed=1
    write_example
    install_auxiliary
    if [[ "$use_systemd" == 1 ]]; then
        if [[ -n "$staged_unit" ]]; then
            ln -- "$staged_unit" "$unit"
            unit_changed=1
            rm -f -- "$staged_unit"
            staged_unit=''
            systemctl daemon-reload
        fi
        if [[ -f "$config_dir/config.json" ]]; then
            if [[ "$action" == install ]]; then
                if [[ "$was_enabled" == 0 ]]; then enabled_by_installer=1; fi
                systemctl enable V2bX.service
            fi
            if [[ "$action" == install || "$was_active" == 1 ]]; then
                restart_attempted=1
                systemctl restart V2bX.service
                sleep 1
                systemctl is-active --quiet V2bX.service || fail '新服务未保持运行，将恢复旧程序。'
            else
                note '原服务未运行，本次更新也不自动启动。需要时执行：systemctl start V2bX.service'
            fi
        fi
    else
        note '本次未管理 systemd 服务；若旧进程正在运行，请手动重启。手动启动命令：'
        printf '  %q server --config %q\n' "$binary" "$config_dir/config.json"
    fi
    committed=1
    note "已安装：$binary；已有配置保持不变。"
    if [[ ! -f "$config_dir/config.json" ]]; then
        note "尚未启动服务。请编辑 $config_dir/config.json.example 的面板地址、密钥、节点等信息，保存为 config.json 后再启动。"
    fi
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
