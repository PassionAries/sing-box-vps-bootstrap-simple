#!/usr/bin/env bash
# 原样执行文档里的服务端投影函数；只读公开夹具，不进行 SSH 或真实配置访问。
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source-path=SCRIPTDIR source=../scripts/connect-vps.sh
source "$ROOT/scripts/connect-vps.sh"
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
TEMP=$(mktemp -d)
trap 'rm -rf -- "$TEMP"' EXIT
WORK="$TEMP/work"; mkdir "$WORK"
COUNT=0
pass() { COUNT=$((COUNT + 1)); printf 'PASS %s\n' "$1"; }
reject() { if ("$@") > "$TEMP/rejected" 2>&1; then printf 'Expected rejection\n' >&2; exit 1; fi; }
if [[ $(uname -s) != Darwin ]]; then
    file_info() { stat -c '%u %a %h' "$1"; }
    file_size() { stat -c '%s' "$1"; }
fi
sed -n '/^project_ss2022() {$/,/^}$/p' "$ROOT/docs/private-handoff.md" > "$TEMP/projection.sh"
[[ -s $TEMP/projection.sh ]]
bash -n "$TEMP/projection.sh"
# 过滤器由文档提供，测试临时目录的已校验代码；不能另维护一份不同的过滤器。
# shellcheck disable=SC1091
source "$TEMP/projection.sh"
for version in 1.14.0 1.14.2; do
    project_ss2022 "$ROOT/examples/$version/server.example.json" > "$TEMP/export.json"
    private_file "$TEMP/export.json"
    jq -e 'keys==["inbounds"] and (.inbounds|length)==1 and
        (.inbounds[0]|keys)==["listen_port","method","network","password","type"]' "$TEMP/export.json" >/dev/null
    render_client "$TEMP/export.json" inbounds.0.password 203.0.113.7 en4 "$TEMP/client.json"
    jq -r '.inbounds[0].password' "$ROOT/examples/$version/server.example.json" > "$TEMP/expected-key"
    jq -r '.outbounds[0].password' "$TEMP/client.json" > "$TEMP/imported-key"
    cmp "$TEMP/expected-key" "$TEMP/imported-key"
done
pass 'single and dual protocol sources export only SS2022 fields and import the unchanged key'

# 输入增加任意秘密字段也不能穿透白名单；REALITY 私钥本来就在双协议夹具中。
jq '.unknown_secret="synthetic-private-marker" | .inbounds[0].extra={private_key:"synthetic-private-marker"}' \
    "$ROOT/examples/1.14.2/server.example.json" > "$TEMP/extra.json"
project_ss2022 "$TEMP/extra.json" > "$TEMP/minimal.json"
cmp "$TEMP/minimal.json" "$TEMP/export.json"
if grep -Eq 'private_key|PrivateKey|synthetic-private-marker|vless' "$TEMP/minimal.json"; then exit 1; fi
pass 'REALITY private key and unknown nested secrets never enter the export'

for filter in '.inbounds=[]' '.inbounds += [.inbounds[0]]' '.inbounds[0].method="wrong"' \
    '.inbounds[0].listen_port=8443' '.inbounds[0].network="udp"' '.inbounds[0].password="bad"'; do
    jq "$filter" "$ROOT/examples/1.14.2/server.example.json" > "$TEMP/bad.json"
    reject project_ss2022 "$TEMP/bad.json"
done
printf '{invalid' > "$TEMP/bad.json"
reject project_ss2022 "$TEMP/bad.json"
cat "$ROOT/examples/1.14.2/server.example.json" "$ROOT/examples/1.14.2/server.example.json" > "$TEMP/bad.json"
reject project_ss2022 "$TEMP/bad.json"
pass 'ambiguous inbound, invalid protocol/key/JSON and multiple documents are refused'
printf 'Private handoff checks passed: %s\n' "$COUNT"
