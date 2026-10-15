#!/usr/bin/bash
# Linux 函数测试：只调用被 source 的安装函数，不进入 main，不运行 APT 或服务操作。
# 需要 GNU stat/sha256sum/base64；以 root 运行才覆盖 root-owned 路径检查。
# 所有密钥均为本次合成数据，只保存在 mktemp 私有目录中，退出后删除。
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source-path=SCRIPTDIR source=../scripts/prepare-vps.sh
source "$ROOT/scripts/prepare-vps.sh"
TEMP=$(mktemp -d)
trap 'rm -rf -- "$TEMP"' EXIT
COUNT=0
pass() { COUNT=$((COUNT + 1)); printf 'PASS %s\n' "$1"; }
# 负向用例在子 shell 中执行，因为生产 die 会 exit；失败输出留在临时文件，避免泄密。
reject() { if ("$@") >"$TEMP/rejection" 2>&1; then say 'Expected rejection.'; exit 1; fi; }

# 固定支持架构与信任常量，未知架构必须在安装之前被拒绝。
artifact_for_arch amd64
[[ $ARCHIVE_SIZE == 32302424 && $BINARY_SIZE == 91951072 && $ARCHIVE_URL == *linux_amd64.deb ]]
artifact_for_arch arm64
[[ $ARCHIVE_SIZE == 29564014 && $BINARY_SIZE == 86012408 && $ARCHIVE_URL == *linux_arm64.deb ]]
reject artifact_for_arch riscv64
pass 'fixed architectures and artifact locks'

# 用短合成文件分别验证大小、摘要和链接拒绝，不下载实际软件。
printf fixture > "$TEMP/blob"
DIGEST=$(sha256sum "$TEMP/blob" | cut -d ' ' -f 1)
matches_artifact "$TEMP/blob" 7 "$DIGEST"
reject matches_artifact "$TEMP/blob" 8 "$DIGEST"
printf altered > "$TEMP/blob"
reject matches_artifact "$TEMP/blob" 7 "$DIGEST"
ln -s "$TEMP/blob" "$TEMP/link"
reject matches_artifact "$TEMP/link" 7 "$DIGEST"
pass 'size, digest and symlink rejection'

# 渲染真实 jq 模板，检查协议/监听/MUX/路由，并逐字节比较重跑前后的密钥和配置。
openssl rand -base64 16 > "$TEMP/key"
render_config "$TEMP/key" "$TEMP/config.json"
jq -e '.inbounds|length==1' "$TEMP/config.json" >/dev/null
jq -e '.inbounds[0] | .listen=="0.0.0.0" and .listen_port==443 and .network=="tcp" and
  .method=="2022-blake3-aes-128-gcm" and .multiplex.enabled==true' "$TEMP/config.json" >/dev/null
jq -e '.outbounds==[{"type":"direct","tag":"direct"}] and .route.final=="direct"' "$TEMP/config.json" >/dev/null
pass 'single-user TCP 443 configuration and direct outbound'

CONFIG="$TEMP/config.json" WORK="$TEMP/reuse"
mkdir "$WORK"
prepare_key
cmp "$TEMP/key" "$WORK/key"
render_config "$WORK/key" "$TEMP/repeated.json"
cmp "$CONFIG" "$TEMP/repeated.json"
pass 'repeat retains exact key and configuration'

# 非法旧密钥应失败且保留原配置，不能以生成新密钥来掩盖问题。
jq '.inbounds[0].password="bad"' "$CONFIG" > "$TEMP/bad.json"
CONFIG="$TEMP/bad.json"
reject prepare_key
[[ $(jq -r '.inbounds[0].password' "$CONFIG") == bad ]]
pass 'invalid existing key is refused instead of replaced'

# 普通用户运行时明确 SKIP，不能把未执行的 root 权限用例计入通过数量。
if (( EUID == 0 )); then
    safe_path "$TEMP/blob"
    reject safe_path "$TEMP/link"
    chmod 0666 "$TEMP/blob"
    reject safe_path "$TEMP/blob"
    chmod 0600 "$TEMP/blob"
    ln "$TEMP/blob" "$TEMP/hardlink"
    reject safe_path "$TEMP/blob"
    pass 'root-file permissions, symlinks and hardlinks'
else
    printf 'SKIP root-owned file checks (run with sudo in CI)\n'
fi

# 有效 unit 不能只靠磁盘文件里的归属注释；独立覆盖各拒绝条件。
EFFECTIVE_FRAGMENT=$UNIT EFFECTIVE_DROPS='' EFFECTIVE_USER=sing-box EFFECTIVE_GROUP=sing-box
systemctl() {
    case "$4" in
        FragmentPath) printf '%s\n' "$EFFECTIVE_FRAGMENT" ;;
        DropInPaths) printf '%s\n' "$EFFECTIVE_DROPS" ;;
        User) printf '%s\n' "$EFFECTIVE_USER" ;;
        Group) printf '%s\n' "$EFFECTIVE_GROUP" ;;
        *) return 1 ;;
    esac
}
check_service_layout
EFFECTIVE_DROPS=/etc/systemd/system/sing-box.service.d/override.conf
reject check_service_layout
EFFECTIVE_DROPS='' EFFECTIVE_USER=root
reject check_service_layout
EFFECTIVE_USER=sing-box EFFECTIVE_GROUP=root
reject check_service_layout
EFFECTIVE_GROUP=sing-box EFFECTIVE_FRAGMENT=/usr/lib/systemd/system/sing-box.service
reject check_service_layout
unset -f systemctl
pass 'effective unit path, drop-ins, user and group validation'

if (( EUID == 0 )); then
    RESTART_REQUIRED="$TEMP/install-restart-required"
    MAINTENANCE_PENDING="$TEMP/maintenance-pending"
    CONFIG="$TEMP/published.json"
    printf 'before\n' > "$CONFIG"
    printf 'after\n' > "$TEMP/candidate"
    BACKUP="$TEMP/backups"; mkdir "$BACKUP"
    check_pending_operations
    # 在真实发布函数的 rename 前中断：标记存在，旧文件仍在。
    eval "$(declare -f mark_restart_required | sed '1s/mark_restart_required/real_mark_restart_required/')"
    # 由生产 publish_file 间接调用此故障替身。
    # shellcheck disable=SC2329
    mark_restart_required() { real_mark_restart_required; exit 97; }
    reject publish_file "$TEMP/candidate" "$CONFIG" 0600 root
    [[ $(cat "$CONFIG") == before && -f $RESTART_REQUIRED ]]
    unset -f mark_restart_required
    eval "$(declare -f real_mark_restart_required | sed '1s/real_mark_restart_required/mark_restart_required/')"
    publish_file "$TEMP/candidate" "$CONFIG" 0600 root
    [[ $(cat "$CONFIG") == after && $(stat -c %a "$RESTART_REQUIRED") == 600 ]]
    check_pending_operations
    # 相同文件不能自行消耗待重启记录。
    publish_file "$TEMP/candidate" "$CONFIG" 0600 root
    [[ -f $RESTART_REQUIRED ]]
    printf 'unknown\n' > "$RESTART_REQUIRED"
    reject check_pending_operations
    rm "$RESTART_REQUIRED"
    printf 'unfinished maintenance\n' > "$MAINTENANCE_PENDING"
    reject check_pending_operations
    rm "$MAINTENANCE_PENDING"
    pass 'durable marker precedes publication, survives retry and refuses unknown/pending state'
fi

# 直接执行真实 CLI，但只使用帮助和非法参数；这几条路径应在预检/安装前返回。
"$ROOT/scripts/prepare-vps.sh" --help > "$TEMP/help"
reject "$ROOT/scripts/prepare-vps.sh" --unknown
reject "$ROOT/scripts/prepare-vps.sh" --upgrade-system extra
pass 'help and invalid CLI return before installation'
printf 'Unit checks passed: %s\n' "$COUNT"
