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

实现提交 `2e006954e46adf6027363043b4eeb0b7a408253f` 的
[CI 38782314737](https://github.com/snkio027/sing-box-vps-bootstrap-simple/actions/runs/38782314737)
六项任务全部成功。已下载五个制品目录中的六份报告，核对 **28 条源码摘要** 与本批文件一致。
[脱敏汇总](evidence/review-fixes-20261016.json) 只记录环境、断言数量、退出码和源码摘要。
后续报告提交只修改证据文档，不改变这些已测源文件；最终提交的检查状态另见 PR。

| 场景 | 结果 |
| --- | --- |
| Ubuntu 静态、root 函数与策略检查 | 58 项/组通过；语法、ShellCheck 均成功 |
| Mac CI，精确 1.14.2 | 官方归档与内部程序大小/SHA-256 均匹配；四份原生配置检查 exit 0 |
| Mac CI，Homebrew 稳定版 1.14.3 | 完整最小客户端组件测试通过；同四份配置 check 均 exit 0 |
| Ubuntu 24.04 amd64 KVM，1 GiB / 20 GiB 安装与协议维护 | 22 项断言，exit 0 |
| 相同规格，SSH socket 模式加固 | 20 项断言，exit 0 |
| 相同规格，SSH service 模式加固 | 19 项断言，exit 0 |
| 相同规格，初始未安装 UFW | 16 项断言，exit 0 |

合计 **77 项 VM 断言**。安装 VM 实际以 root drop-in 启动服务，再验证预检拒绝；
在配置发布后发送 SIGKILL，确认旧 PID 存活、磁盘配置已替换、待重启标记为 root:600，
维护入口拒绝插入，重试安装后 PID 改变且标记清除。另覆盖验证失败不清标记、随后重试和健康幂等执行。
原有 SS2022 / REALITY 的真实合成 HTTPS、错误凭据拒绝及维护文件恢复也继续通过。

Linux / 一次性 VM 的复现命令：

```sh
sudo bash tests/unit.sh
bash tests/client-unit.sh
bash tests/hardening-unit.sh
bash tests/maintenance-unit.sh
bash tests/handoff-unit.sh
python3 -B tests/profile_check_test.py
python3 -B tests/client_profiles_test.py
python3 -B tests/reality_profiles_test.py
sudo python3 -B tests/run_vm.py
sudo python3 -B tests/run_hardening_vm.py --ssh-mode socket --scenario standard
sudo python3 -B tests/run_hardening_vm.py --ssh-mode service --scenario standard
sudo python3 -B tests/run_hardening_vm.py --ssh-mode socket --scenario without-ufw
```

Mac CI 另执行 `check_client_profiles.py --mode compatibility --binary /opt/homebrew/bin/sing-box`；
reviewed 与 compatibility 分别保存结果，不能用较新版本通过替代固定版本证据。

首轮 `3e23d44` 的 CI 因 ShellCheck 将动态调用的测试替身标为不可达而失败，VM 未运行。
仅在该替身处补充带说明的 SC2317 豁免后重新执行全部检查；没有放宽生产检查或把首轮算为 PASS。

## 未覆盖范围

真实 VPS、Mac 服务切换、手机运行、真实 SSH 私密取回、完整组合部署和硬件断电：**NOT RUN**。
SIGKILL 测试覆盖进程强制终止；不等同于块设备断电耐久性实验。文档投影测试只使用公开合成输入。
服务文件发布失败后的重试仍需操作者先核查错误；新增标记不使 APT、账号和 swap 获得通用回滚能力。
