# 私密交接：只取客户端必要字段

服务端 `/etc/sing-box/config.json` 和 `reality-keypair.private` 均不得整份下载给客户端。
双协议服务端配置包含 REALITY 私钥；即使 Mac 文件为 0600，也不应扩大这把私钥的存放范围。
下列步骤是人工交接说明，不是新的远程下载或配置分发工具；只在已授权、核验 host key 的目标上执行。

## SS2022：在服务器生成最小投影

在 VPS 的 root 会话中执行下面代码。它只输出新建私密文件的路径，不回显密钥。
`mktemp` 排他创建 root 0600 文件，不覆盖既有文件。投影适用于单协议和双协议服务端；
只接受一个 SS2022 TCP 443 入站，并按白名单新建对象，不复制其他入站或未知字段。
此函数由 `tests/handoff-unit.sh` 原样提取测试，不维护另一份测试专用过滤器。

```bash
set +x
set -euo pipefail
umask 077
project_ss2022() {
    jq -e -s '
      if length == 1 then .[0] else error("Expected one JSON document") end |
      [.inbounds[] | select(.type == "shadowsocks")] |
      if length == 1 then .[0] else error("Expected one SS2022 inbound") end |
      if .method == "2022-blake3-aes-128-gcm" and .listen_port == 443 and
         .network == "tcp" and (.password | type == "string") and
         (.password | test("^[A-Za-z0-9+/]{22}==$")) then
        {inbounds: [{type, method, listen_port, network, password}]}
      else error("Unsupported SS2022 input") end
    ' "$1"
}
export_file=$(mktemp /root/sing-box-ss2022.XXXXXXXX.json)
if ! project_ss2022 /etc/sing-box/config.json > "$export_file"; then
    rm -- "$export_file"
    exit 1
fi
printf 'Private SS2022 export: %s\n' "$export_file"
```

通过已核验主机身份的 SSH 与 `sudo -n` **只读取该投影文件**，输出直接进入 Mac 新建的
私密临时文件；不要直接在终端执行会回显正文的命令。服务端原配置权限保持不变，普通 SFTP
不能读取 root-only 文件，不能为下载放宽权限。Mac 输出目录须由当前用户控制且其他用户不可写，
最终文件为 0600；已有目标必须拒绝，成功检查后才排他发布。自动取回入口仍未实现。

投影在 Mac 保存为 `vps-config.json` 后，沿用 `connect-vps.sh setup VPS_IP /path/vps-config.json en4`。
它会继续验证密钥解码长度和规范 Base64；地址仍由操作者明确提供。真实 SSH 取回、完整组合部署
与手机导入不因本次合成投影测试而计为通过。

## REALITY：单独交接客户端字段

客户端所需字段仅为 VPS 地址、8443、UUID、`xtls-rprx-vision`、server name、REALITY 公钥及 short ID。
公钥从服务器对应本次部署的公私钥记录中仅提取 `PublicKey`；记录与当前服务配置的对应关系需核对。
**不复制 `PrivateKey`、`tls.reality.private_key` 或整份公私钥记录。**
已有 [双协议模板](../examples/1.14.2/README.md) 继续用于生成私密候选；自动 REALITY 参数导出和三端
配置生成不属于本次修复。SS2022 投影不携带 REALITY 参数，也不会改变默认协议或切换正在运行的客户端。
