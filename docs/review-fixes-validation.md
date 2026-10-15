# 2026-10-16 审查修复验证

审查基线 `7ac581edec71267c2a354e8cfcc57bdc4a3440da`。本批只修复五个审查问题，
保留独立 Bash 入口、普通备份与有限标记；不增加控制器、远程配置分发或 Mac 安装器。
不修改固定部署版本、代理策略或真实设备。

| 问题 | 修复 | 回归路径 |
| --- | --- | --- |
| 主 unit 标记掩盖 drop-in/身份覆盖 | 核对有效 FragmentPath、DropInPaths、User/Group；最终核对实际 UID/GID | 函数覆盖各拒绝条件；VM 实际 root drop-in，预检拒绝且 PID/配置不变 |
| 发布后中断丢失重启需求 | 服务文件 rename 前持久化 restart-required，完整健康验证后清除 | 函数在 rename 前中断；VM 配置发布后 SIGKILL、验证失败、重试及再次幂等执行 |
| 安装入口绕过维护 pending | 两入口互相拒绝另一入口未完成的操作 | 安装 VM 与升级 VM 在已有 pending 时验证拒绝；安装未完成时维护拒绝 |
| 最新 Homebrew 与精确版本检查冲突 | 分开 reviewed 与 compatibility 检查和结果目录；固定核心仅下载至 CI 临时目录 | 合成版本/失败检查回归；Mac CI 对固定 1.14.2 与实际 Homebrew 稳定核心分别 check 四份配置 |
| 整份导出扩大 REALITY 私钥存放范围 | 文档采用服务端 SS2022 字段白名单；REALITY 私钥/整份 keypair 明确禁止下载 | 原样提取文档函数，覆盖单/双协议、未知秘密字段、非法输入与原密钥导入 |

## 本机检查

Darwin 25.6.0 arm64、Python 3.9.6、Homebrew Bash 5.3.20、ShellCheck 0.11.0。
以下命令从仓库根目录运行，全部 exit 0：

```sh
for f in scripts/*.sh tests/*.sh; do /opt/homebrew/bin/bash -n "$f"; done
/opt/homebrew/bin/shellcheck -x scripts/*.sh tests/*.sh
/usr/bin/python3 -B tests/profile_check_test.py
/usr/bin/python3 -B tests/client_profiles_test.py
/usr/bin/python3 -B tests/reality_profiles_test.py
/opt/homebrew/bin/bash tests/handoff-unit.sh
/opt/homebrew/bin/bash tests/hardening-unit.sh
/opt/homebrew/bin/bash -c 'jq() { /opt/homebrew/bin/jq "$@"; }; source tests/maintenance-unit.sh'
/usr/bin/python3 -B tests/check_client_profiles.py --binary /opt/sing-box/1.14.2/sing-box --mode reviewed --output /private/tmp/sing-box-review-fixes/native-reviewed
git diff --check
```

合计 39 项/组函数与策略测试；维护测试仅为 Mac 适配现有 Homebrew jq 路径。
原生 1.14.2 的 server、macos、android、ios 四份配置 check 均 exit 0，未启动 TUN。
本机没有 Homebrew sing-box，未安装依赖或改动现用程序；完整 `client-unit.sh` 与 Linux root 单元测试交由 CI。

## CI / VM

本次候选 CI 尚未运行。VM 回归和当前 Homebrew 原生检查：**NOT RUN**，将在推送后追加实际结果。
已有历史 VM 结果不冒充本次修复的运行证据。

## 未覆盖范围

真实 VPS、Mac 服务切换、手机运行、真实 SSH 私密取回、完整组合部署和硬件断电：**NOT RUN**。
SIGKILL 测试覆盖进程强制终止；不等同于块设备断电耐久性实验。文档投影测试只使用公开合成输入。
服务文件发布失败后的重试仍需操作者先核查错误；新增标记不使 APT、账号和 swap 获得通用回滚能力。
