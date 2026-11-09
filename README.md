> **Current version v1.1.2 (112).** Targets Steam Windows build 26407122 and pins the same Loader 1.0.6 / WINMM format 2 binaries as CCB Toolkit 2.0.40-beta. The user confirmed the package works in game. See the [dependency fingerprints](native/provenance.json) and [validation record](CURRENT_STATE.md).

### Build v1.1.2

Use Windows x64, VS 2022 Build Tools, Python and `pefile`. Run `tools\build_native.cmd` first, then use actual paths in the following commands. Choose a fresh output directory.

```powershell
python tools/package_shared_loader.py --out build/v1.1.2/CityStateFounder --loader-dir '<CCB Toolkit 2.0.40-beta>/Binaries/Win64' --game-dir '<Civilization VI install>' --reference-xp2 '<archived official XP2 DLL>'
python tools/audit_csf.py --src build/v1.1.2/CityStateFounder
````

Install the resulting package folder. The earlier v1.0.6 proxy instructions below document the historical release.

> 2026-10-28：已更新原公开工坊条目3808178854至 v1.1.1 / 111，内置公共WINMM1.0.3与城邦插件。订阅回归及当前部署状态先读 [CURRENT_STATE.md](CURRENT_STATE.md)。下方1.0.6代理包与早期进度均属历史；完整需求保留，联机未测。

> 2026-10-26：工坊仅完成本地准备，线上未上传。新版包真源为 `../torelease/Workshop_1.0.6/CityStateFounder`；含版本文案与许可补正，核心/建邦玩法未改。本机游戏运行中，未覆写其Mods。联机验收按用户指令暂缓，仍未测；新内置核心路由仍缺干净游戏加载证据。见 `docs/WORKSHOP_DRAFT_2026-10-26.md` 与 `docs/research/current_release_state_20261026.json`。

> 2026-10-25: v1.0.6 bundles the XP2 proxy inside the MOD. Copy the complete `CityStateFounder` folder into Mods; clean machines need no official XML or game-directory DLL changes. See [portable test instructions](docs/PORTABLE_TEST.zh-CN.md). Build/loader-fixture/registration/package checks passed; real gameplay and independent multiplayer remain pending. Older manual-install instructions below are historical.

# CityStateFounder — 城邦缔造者

## 2026-10-23 身份、原生能力与复杂验收推进

当前开发版已在 XP2、零开局城邦、不开氏族模式下完成真实空槽登记与同文明副本。配套原生桥通过官方玩家就绪通知注册能力；名称/颜色、城防、接触、使者均读回，生产界面请求已改走原生同步操作并验证单位归属/位置与持久防重。

后续修复了运行时新城邦缺少AI回合任务的问题：按官方转换链在建城后单次装配，不手动指定生产或补兵。35种候选与副本在同一人类控制对局形成38城，原生任务均保持单份；正式自动创建的纳斯卡连续20回合后已自然生产单位并继续建造。293条离线安全断言通过。最终自动版本的冷重启读档正在检查；副本真实城市名的引擎后备命名、真鼠标链、容量边界和独立多人仍需各自验收。

阿卡德宗主能力已有正反战斗数值及真实攻击证据，任务已有训练/科技/市政正反奖励闭环，最终档已跨进程重启及+1/+5/+20回合验证。详细场景与限制见 [当前检查点](docs/research/identity_defense_checkpoint_2026-10-23.md) 和 [中文入口](README.zh-CN.md)。完整14组/131条需求仍保留；独立主客机缺第二端，其它未完成项不折算通过。MOD尚未完成整体交付，也未发布。下方接触阶段记录是历史基线，不能覆盖本段状态。

## 2026-10-23 接触与使者修复（优先于下方历史记录）

- 用户确认：阿卡德城市可以建出，点击城市条不再崩溃，但仍不能交互或打开城邦面板。上一轮调试回读同样为 `HasMet=false / GetTokensReceived(0)=0`，故不接受“完整城邦已完成”的旧结论。
- 当前源码将接触与建邦使者奖励移到 Gameplay 队列的建城后阶段：用官方场景的 `SetHasMet` 与 `GiveFreeTokenToPlayer`，读回双方接触、目标收到的使者和发起者库存；UI 不再用 `GIVE_INFLUENCE_TOKEN` 花掉玩家库存。先接触，再额外给 1 个建邦奖励；引擎自带的首次接触奖励另计。
- `CSF_Founding_<slot>` 随存档记录目标和奖励尝试；未知结果不自动重发。城市已建而外交/奖励未确认时明确报部分失败，不再次建城。`CompleteFounding(slot, owner)` 仅恢复已有吻合记录，不适用于没有建邦记录的历史城市。
- 本轮采用约束：知识库 `lua-contexts.md` 的 UI/Gameplay 写权限边界、`persistence-and-sync.md` 的同档属性与本机缓存区别、`civ6-citystate-player-api.md` 的实际状态取证；官方调用例为 `AlexanderScenario.lua:13-27`、`WarMachineScenario.lua:72-83`。Gameplay 写入、同档重载幂等、静默失败负对照分别验证，不能据此声称独立多人已通过。
- 离线检查 166/166，面板 7/7，颜色适配 5/5，工具回归10/10；四个改动 Lua 语法通过，审计OK113/WARN16/ERR0；29 个运行文件部署哈希一致。**完整 14 组/131 条需求仍未完成**，包括能力数值、同文明副本、颜色全局一致性、任务完成和独立多人。完整本轮记录见 `docs/research/contact_envoy_checkpoint_2026-10-23.md`。
- XP2 不开氏族真机：阿卡德 slot 23 在 (32,18) 建城，双向接触为 true，目标使者 2（引擎首次接触 1 + MOD 奖励 1）、库存 0；普通派使者目标 2→3、库存 1→0、宗主变为玩家0。完整退出 PID26280 后以新进程 PID2352 读同档，城市/接触/使者3/宗主0/奖励Done均保留，恢复调用不重复奖励。部署后的原生详情页显示加成、任务数1；再正常派使者到4，自动刷新且该读档局未发现颜色空值或 UI Runtime Error。建邦和面板打开仍由调试器调用真实回调，不等于实际鼠标点击验收；这一存档含辅助作弊菜单，纯净新局另验。
- 原生 UI 颜色改为当前 CityStates Context 的 UI 代理，只适配 GetPlayerColors，保留官方 XP2 查询和操作。旧 debug.getupvalue 补私有表方案在实机 debug=nil 下不能运行，已撤下；安全取色预先捕获原始引擎接口，避免代理递归。全引擎 UI 颜色缓存仍未修好，不能外推其他 UI/兼容 MOD。
- 扩展生命周期发现旧 C6FW 异常记录器未注销，重新开局触发失效回调与递归；已修复并本地构建，XP2 依赖部署 SHA256 由 F9152569... 切为 5341DCE3...。修复后的重复新局验收另记，不用存读档通过掩盖这个缺陷。
- 无辅助 MOD 的组914、核心5341DCE3：零开局连续读回配置0/存活城邦0，56个空槽均为状态2且无文明/领袖，所有候选 unavailable。强制调试提交负对照返回 `no_free_slot`、单位保留、城邦仍0、回合额度未消耗。**零开局下运行时建邦仍 FAIL**，不能为绕过而增加开局数量。该边界需要独立的关闭槽身份登记路线。
- 同进程从零开局退回主菜单、再开3城邦新局已进入玩法；纯净新局真实队列建出阿卡德23，双向接触true、使者2、库存0、单位已消耗，城邦数3→4。原生城市条回调 `OnCityBannerClick(23,65536)` 从关闭状态触发原生详情，读回可见、阿卡德、使者2、任务1；没有运行中加载补丁。此为回调链验收，自动鼠标输入仍未通过。证据入口 `docs/research/runtime_contact_2026-10-23.jsonl` 与 `runtime_contact_clean_banner_2026-10-23.png`。
- DS 只读任务 `0b2f9d539e8a42c289ef9da5eb2cea7c` 已加载 billion-context 0.1.191，但以 PermissionError/EPIPE 失败，无有效交付；主 GPT 接手，未回退官方 API。

## 2026-10-16：新版验收入口（优先于下方历史说明）

2026-10-19 已完成 XP2 新局受控运行：官方 Expansion1/Expansion2/BarbarianClansMode 加载，C6FW Lua 桥注册；通过正式 `FoundCityStateByCiv` 路径激活 Antananarivo 的预注册槽 55，并由 `C6FW.CreateCityNative` 在 `(37,18)` 建城。读回为 1 城、归属正确、`CanReceiveInfluence=true`、非主文明、非蛮族；自动过一回合后仍保持。完整 14 组/131 条业务验收仍 BLOCKED；同文明副本、颜色完整 UI、存读档、多人和官方转换执行器尚未结案。

- 正式传输：交接包 `tools/tuner_strict.js`；统一 CLI `tools/c6.js` 已接入。构造/import 不连接；一次会话只建一条连接，动态精确查询 context，随机请求标记确认命令完成。超时/断开/坏帧立即停止，不重发未知结果的操作。只读预检还会记录 C6FW `GetNativeSlotStatus(slot)`，用原生槽位状态和 Lua 状态交叉核对。
- 游戏动作需要显式 `--execute`。`status` 默认只看操作系统进程/监听表，不连接端口；没有执行、环境不足或缺证据用 **BLOCKED / 退出码 3**。工具查询完成的 0、`COMMANDS_COMPLETED` 和业务验收 PASS 是不同结果。
- `c6.js session --job <job.json> --out <全新目录> --execute` 在**同一进程/连接**里执行已审核的 Lua 步骤；开连接前检查全部文件 SHA256、路径与步骤 ID。每步原始返回、context、请求标记与哈希落盘；遇失败停止。它不自动开游戏、杀进程、部署或更换核心。
- `CityStateFounder/tools/csf_acceptance.py` 只做离线证据判读。计划、run UUID、构建/模组绑定、样本 JSON 原件和 SHA256 必须匹配；自报 PASS 文本不能替代断言。任何必需项缺证据阻止整体通过；人工夹具全过也只得 `OFFLINE_ONLY / 3`。
- 完整需求矩阵：`CityStateFounder/docs/research/csf_acceptance_plan_v2.json`，14 组 / 131 条比较。覆盖开局数量、未出现城邦、同文明副本、失败隔离、队列重入、六表及 +1/+5/+20 回合、原版与副本能力数值及正负对照、任务外交、视觉、完整退出后的存读档、独立主客机、容量/候选池与官方氏族转换对照。
- 证据一致性判读器不能自行证明 JSON 来自真实游戏；最终验收仍要主 GPT 核对原始捕获、实际加载核心、截图和独立客户端。视觉审核标志不能由 DS 自行填 true 代替目视复核。当前六表只读组件尚未绑定 Lua，多人请求链尚未闭环，这些缺口必须保持 BLOCKED 或有明确反证时 FAIL。

离线准备：在 CityStateFounder 目录运行 `python tools/prepare_csf_acceptance.py --out docs/research/<新的run目录>`。输出固定计划、全新 run、空证据、源码清单及**未执行的只读预检 job**；目录已存在即拒绝覆盖。这一步返回 0 只表示准备完成。再把该目录的 plan/run/evidence 交给 `csf_acceptance.py`，空证据必须得到 BLOCKED/3。

游戏可用后的顺序：先抓当前安装包和实际核心基线、保留备份 → 仅执行只读预检 → 新局数量/失败分支 → 官方蛮族氏族正常转换正对照 → 契约明确后的隔离原生实验 → 生命周期/存读档/视觉 → 独立多人。当前开发源码已部署到本机 Mods 目录；C6FW XP2 代理 DLL 保持安装以提供正式 slot 建城能力。每个地图/mod/候选池组合独立记录覆盖，不把一局结果外推全部组合。

历史 `cs_probe.py`（除 `--list`）、`cs_persist.py`、`cs_auto.py`、`cs_u2.py`、`cs_u567.py`、`cs_u567_single.py`、`cs_session.py`、`_auto_verify.py`、`_eval_lua.py` 和 `CSF_DLL_验收.lua` 均已阻断默认执行，保留源码追溯。不要从其旧说明恢复“只读探针”或“完整验收”的结论。旧 smoke 已退役（包括 -Execute），恒退出 3；它拆步重连且多处以文本命中覆盖失败，不再作为正式运行入口。历史判读分支已加固，保留供追溯。

离线验证命令：

```powershell
# CityStateFounder 目录
python tools/test_csf_test_tools.py
python -m unittest discover -s tools -p test_csf_acceptance.py
python tools/test_csf_safety.py
python tools/test_duplicate_registration.py
python tools/audit_csf.py
# AI-Civ6-Test-Workflow 目录（均为假 socket / 假会话）
node --test tools/test_tuner_strict.js tools/test_c6_acceptance.js tools/test_c6_session.js
```

下方旧示例命令、退出码与已验证声明均是历史。与本节冲突时按本节执行。

### 2026-10-19 受控运行结果（未完成业务验收）

- 首次 C6FW 本地切换把 `PackageId` 指到未安装的 C6FW mod 包，`Modding.log` 明确报 `Failed to load GameCore DLL` 并回滚。已修正 `C6FW/scripts/install.ps1`：Base/XP1/XP2 保留官方包 GUID，只替换 `DllPrefix`；随后启动能加载 C6FW 模块并进入 InGame。
- 运行组切换到 `A6FOG_CLEAN`（905，仅 C6FW + CityStateFounder），避免 CCB 大型 mod 组干扰。前端 `APP` 握手、动态状态表和 MainMenu 命令完成；真实日志出现 CityStateFounder/ InGame UI 初始化。
- 进入 InGame 后 FireTuner 由 4318 顺延到 4319；固定 4318 会误判通道死亡。严格工具已加入只读 `netstat` 发现、APP 先握手、同会话等待和显式观察重连，且不会重发已完成的开局/业务命令。
- 当前仍未拿到 GameCore 只读预检的完整证据，14 组/131 条业务条件均未执行；本轮结论是 **BLOCKED**。详细原始状态见 `docs/research/runtime_observations_2026-10-19.json`。
- 运行窗口后的工具修复：session 现在会在观察步骤按 `netstat` 端口候选逐个 APP 握手，并要求目标 context 真实出现后才接受连接；C6FW 安装先校验 DLL、保持官方包 GUID，并以无 BOM UTF-8 写配置。下一轮仍需新鲜游戏窗口验证。 本轮随后用 4318/4319 两个候选做了观察重连，仍未拿到 InGame APP/LSQ 响应，因此业务矩阵继续 BLOCKED。
- 本轮游戏已停止；C6FW 配置/DLL 保留安装状态供下一次受控窗口复用，没有发布工坊。原始正式路径证据见 `docs/research/runtime_slot_native_create_2026-10-19.json`。


> **能力试验型 MOD**：验证「玩家建立城邦」这条能力是否可实现，为将来移植到某文明 / 某领袖的具体能力做准备。
>
> **当前阶段（2026-10-15 复核）**：已有 Lua/UI/SQL 原型与依赖 C6FW 的原生激活路径，尚不能视为完整需求已验收。下文早期可行性结论与“最终交付状态”保留作历史，当前实现边界以本节为准。

## 当前修复与研究状态（2026-10-15）

- 需求仍是：保留玩家指定的开局在场城邦数；游戏中建立该局允许的城邦，支持同文明副本，并具备真实城邦机制。运行中增加城邦不等于违背“开局数量不变”；仅复活原有城邦不能替代完整需求。
- **开局实验已从加载清单撤下**：移除 AdvancedSetup 的替换/导入/文件注册，以及两个 CCB 地图覆盖脚本的导入。`LoadScreenClose` 不再隐藏开局城邦或补造休眠城邦，公共 `ForceReserve` 也明确拒绝执行。历史实验源码仍留作追溯，不再进入运行包。此修复不能撤销旧存档或开局设置缓存已经发生的数量改动；下次新局应核对自己指定的数量。
- **建城结果改为实际取证**：Create 抛错、静默零城或目标格没有目标玩家的城市均返回失败；原生 nil/0/false 不能当成功。必须在 Create 前清走使节的既有约束保留。激活后失败的槽记录隔离属性，禁止用 SetAlive(0)/UninitializePlayer 猜测回滚。只有成功才记录本回合额度；队列增加重入保护。副本路径已开启并改为 Cities:Create 后目标格归属复查，但仍未经过真机验收。
- **覆盖范围与生命周期待验收**：按同文明寻找未激活槽，只证明该局确有相应槽的目标可尝试；不能推导任意候选池、任意重复次数都可用。需要核对原生存活列表一致性、外交/使者/宗主/任务、失败后再次尝试、重启读档和多人跨端一致性。已有早期存活/读档记录必须对应到具体路线与构建。
- **原生桥已切到氏族链的静态对齐版本**：C6FW 本地构建现在要求目标槽的原生状态为 5，先用签名保护的 `0x16B840(cfg,1)` 写成活动槽，再传入氏族路径的原始 `0x169EE0` 值与 `flags=1`；子系统索引按官方氏族链取 `0x1E5460()->entry+0xB8`，0/-1 时用签名保护的 `0x64E6C0` 默认类型索引，并调用官方 `0x2FA9A0(player,1)` 重建 23 张玩家列表；旧的容量限制预检、手工追加 `+0x1650/+0x1AA0` 和直接写 `player+0x258` 已删除。主请求路径会把最终 `(x,y)` 传给 `0x2FAB60` 写入玩家起始位置。Lua 现在先用 `GetAlive` 只读确认，只有旧桥未发布时才兜底 `SetAlive`，避免在新桥上重复重建列表；随后用 `GetPlayerSnapshot(slot)` 严格核对目标字段和全局/城邦列表成员。这个版本只完成静态对齐和本地构建，未部署、未实机验收；氏族专属尾段、官方建城函数和颜色/外交/存读档仍未闭环。
- **官方转换链的新方向**：本机 XP2 静态证据定位到 `0x61FDD0` 的转换执行器，调用 `0x2FA9A0(player, alive)` 后者会调用 `0x307250` 重建分类玩家列表。它比“写 alive 字节 + 手抄两张表”更接近官方路径，应作为下一轮隔离实验重点。完整转换器内部取第一个状态 5 的配置槽，不能直接替代指定文明/副本需求；没有发现对应的执行转换 Lua 绑定。新地址尚未加入默认运行路径。
- **多人请求尚无闭环**：`src/UI/CSF_Panel.lua:333-340` 经 `ExposedMembers` 调本机 `RequestFound`，由 Gameplay 的本机队列消费。跨 VM 不等于跨机器；另有网络化的发使者操作不能自动复制前面的激活/建城。需要独立设计并验收请求、执行与结果的跨端一致性。
- **颜色调查要承接，不能重置**：T-118 已记录过旧 AddPlayer 路径的刷新失败，10-11 又加了 slot 激活后的刷新热键；应核对实验结果、顺序和前后配色，不再称“从未试过”。原生层的完整激活应与 UI 缓存刷新分别验证。
- **源码副本分叉**：本轮 modinfo、两个核心 Lua、离线回归与研究证据已同步 `_repo`，尚未提交/推送；历史面板等文件的分叉仍保留，不能把 Git clean 或核心文件同步视为整个源码树已经等同。

验证入口：`python tools/test_csf_safety.py`（需要 lupa，执行真实项目 Lua 和受控引擎桩）；`tools/audit_csf.py`；知识库 `tools/lua_check.cjs src`。原生配对列表回归在 C6FW `tools/test_csf_alive_lists.cpp`。离线回归不等于游戏行为验收，完整能力仍需新局数量、目标格/归属、视野渲染、过回合、外交/使者/宗主/任务、存读档与多人跨端测试。

上一阶段已部署安全基线为 v1.0.4（modinfo 整数版本 104）。当时 135 项 Lua/清单离线断言、18 项 C++ 配对列表断言通过，Lua 语法 src 11/11 + harness 1/1，审计 OK 108 / WARN 18 / ERR 0。Create 前必须清走使节，因此之后才失败时，使节可能已消耗、目标槽也可能被隔离；没有承诺无损回滚。22 个运行文件已同步本地 Mods/staging，3 个实验脚本已从部署移除，旧包在 `release/CityStateFounder_v1.0.3_before_20261015_safety.zip`。此为历史交付记录；当前开发源码版本见下节。工坊未更新，原生 DLL 未替换当前 GhostFix 核心。

原生研究证据：`docs/research/clans_native_disassembly_2026-10-15.json`，由 `python tools/inspect_clans_chain.py` 只读生成；脚本校验完整 DLL SHA256 后才解析固定小段。历史索引未记录镜像哈希，不能据此把全部历史注释视为当前二进制的事实。

## 静态续开发：等待游戏空闲后再实测

- 本阶段不启动/控制游戏、不连 FireTuner、不改 Mods、staging、工坊或 GameCore 配置；已部署/staging 的 v1.0.4 运行文件 22/22 保留原样。**开发源码已升 v1.0.5 / 105，未打包部署**，与 v1.0.4 不再要求整树 SHA 相同。DS 执行有界反汇编、登记研究和只读组件实现，主 GPT 独立核对并修正错误推断。
- **删掉两处掩盖失败的补写**：C6FW 原生桥不再强写 `player+0x83A=1` 和 `player+0xD8=slot`。初始化器 `0x2F8450` 自己置标志，构造器 `0x2F1510` 自己写槽号；现在必须读回正确值才继续。注册返回值也必须与槽表中的对象一致。
- **激活函数旧解释作废**：`0x2F9350` 只消费 Player*，内部两个门禁可直接返回；不再给它传“激活索引”或把正常返回记成完整激活。`0x16A300` 实际返回配置字符串的类型 key，DEFAULT/UNDEFINED 是 -1/0 哨兵；给 `0x2C9B10` 的这个值与 `0x2F9350` 是两回事。旧桥错误地把 cfg 传给默认上下文查询的分支已停用，遇哨兵先拒绝，不猜上下文。
- **诊断组件已接入只读预检**：C6FW `src/lua/csf_player_snapshot.h` 只经受 SEH 保护的读取回调检查两组共六张表，包含旧桥漏补的 `+0x1878`，分别报告读取状态、真实指针/槽号集合一致性、每张表 shape 和坏成员计数。38 项人工内存断言通过，含地址回绕、同 ID 不同对象、满表、重复成员、不可读目标。XP2 构建现在注册 `C6FW.GetPlayerSnapshot([slot])`：无参调用供预检逐字段落盘，带 slot 调用还会读回目标 `+0xD8/+0x258/+0x83A` 及六张表中的成员命中；Lua 激活门禁必须显式比较这些字段，不能依赖 Lua 的数字真值。它仍不替代完整游戏验收，也不执行写操作。API 已完成本地构建，尚未在真实游戏窗口验收。
- **副本旧 SQL 路线已否决，原生身份路线仍未结案**：当前二进制的 `0x22A930` 读取 DuplicateCivilizations，`0x2269B0` 在已核对路径中用关系扩大“已使用”拒绝集合；自配对不能证明共存。因而 v1.0.5 已撤下旧 SQL 的 action/Files 注册，旧源文件加废弃说明。研究 SQL 保留在 `docs/research/duplicate_registration_candidate.sql`，不能加载；`tools/_write_dup.py` 一键写源码/部署脚本已退役，只返回错误且不写文件。这个结论只否定旧关系表方案，不能替代对原生 PlayerConfiguration 身份写入顺序和运行期重复检查的验证；精确同文明副本仍保持关闭，生成器和 SQLite 测试只证明研究产物语义，不证明游戏副本功能。
- **原生身份写入顺序已补成可重复静态证据**：XP2 的 `0x16B660` 是领袖写入函数，`0x16B280` 是文明写入函数，`0x16ABC0` 负责 SQL 一致性检查后的配置刷新；官方随机身份选择器 `0x22C1B0` 的顺序是“领袖 → 文明 → 刷新”，并且发生在 `0x3077C0` 注册玩家之前。`0x3077C0` 的有界窗口只调用 `0x2F8450` 构造/初始化玩家，不重复这三个身份写入。这个结果支持下一轮“先改休眠 SlotConfig、再注册”的受控实验设计，但仍不能证明同文明副本能通过运行期排重、存读档或多人同步。可复核报告：`docs/research/clans_identity_setter_static_2026-10-19.json`；脚本：`tools/inspect_identity_setters.py`。
- **休眠槽身份预配置接口已完成本地构建**：C6FW 新增 `PreparePlayerIdentity(slot, civilizationType, leaderType)`，只接受原生状态 5 且没有游戏侧 Player 的槽，按领袖→文明→刷新顺序写入并确认状态仍为 5；它不注册、不发布 alive，副本路径随后仍必须走 `ActivatePlayer`、列表快照和颜色读回。Lua 副本逻辑已移除 `UninitializePlayer/AddPlayer/SetPlayerLeader`，改为使用该接口和原生激活链；当前已开启副本候选与严格建城路径，等待真机验收。
- **下一轮副本实验已写成停止条件清单**：`docs/research/clans_identity_experiment_plan_2026-10-19.json` 固定了身份写入前后读回、原生列表门禁、失败隔离、负对照、存读档和多人验收条件；当前只完成静态准备，未注册可变更身份 API，也不允许在游戏不可测试时提前部署。
- **玩家记录第二字段也曾命名错误**：Lua 绑定 `GetHandicapTypeID → 0x169EE0` 已从本机指令核对；旧代码把它称为文明 ID，实际是难度配置值。代码已更名，不能再用该字段给新槽指定文明。目标文明/领袖的槽配置、氏族 raw 值与开局规范化值的读取契约须分别处理。
- **不能继续沿用的旧断言**：`0x2F9790` 比较 TRIBE，`0x2F97F0` 比较 FREE_CITIES，并非旧注释里的“主文明/城邦”；城邦表来自排除这些类型后的分支。`.pdata` 的 CHAININFO 续块也不能当成独立相邻函数，工具已按链归并。历史 48/48 槽快照只对当时那局成立，不外推当前 mod 组合或高主文明数。

当前研究仍未把“玩家记录第二字段的两种取值”“氏族与开局不同默认上下文”“运行期别名表如何刷新”混为一条已验收路线。完整副本、配色复用、使者/宗主/任务、存读档和多人需求照旧保留。复核证据见 `docs/research/clans_static_review_round2_2026-10-15.json` 与 `clans_static_corrections_2026-10-15.json`；原生构建仅保存在 C6FW `build/`。

当前静态门禁：Lua/清单 145 项、SQL 5 组、原生快照 38 项与旧配对列表 18 项通过；Lua 12/12；审计 OK 110 / WARN 18 / ERR 0。游戏行为、渲染、存读档和多人均未在本阶段验证。下一步条件与未证项见 `docs/research/clans_native_experiment_plan_2026-10-15.json`。

---

## 一句话定义

新增一个以游戏内**开拓者**为原型（复用属性 / 美术 / 建模）的「特殊开拓者」单位。它**不能建立普通城市**，而是**建立一个城邦（City-State）**；并提供一个**独立 UI 面板**，动态列出当前存档可用的城邦（图标 + 本地化名称 + 宗主加成文本），供玩家选择。

---

## 目录结构

```
CityStateFounder/
├── README.md            本文件
├── 实现思路.md           ⭐ 先读这个：完整技术链路，每句话标注"已验证/未验证"
├── 实现计划.md           ⭐ 开工指南：环境准备 + S0~S7 步骤规格 + 数据定义 + U2 验证流程
├── 设计文档.md           最终落地效果 + 硬约束 + 方案选型 + 架构 + 原型计划
├── 决策记录.md           决策台账（D-xx 已定 / T-xx 技术裁决 / P-xx 待定）
├── tools/                探针与提取工具（FireTuner 探针、U2 测试、持久化测试、二进制绑定提取）
├── 调研参考/             第三方资料（含 Free City States 关键源码副本）
├── src/                  当前开发源码（实际运行包由 modinfo 清单决定）
└── _repo/                私有 Git 镜像；历史上与外层 src 分叉，见当前状态说明
```

调研报告归档在工作区既有的探索报告目录：

- `..\思路探索报告\07_自选城邦MOD_游戏数据与UI源码检视.md` — 游戏本体数据定义与 UI 源码检视
- `..\思路探索报告\09_自选城邦MOD_运行时API实测与可行性裁决.md` — **运行时 API 实测（FireTuner）+ 二进制绑定提取 + 可行性裁决**（含一处**重大更正声明**）

---

## 关键结论速览

| 问题 | 结论 |
|---|---|
| **运行时为城邦玩家创建城市？** | ✅ **可行且已实测通过**：`Players[id]:GetCities():Create(x, y)`（Script/GameCore 上下文）。Firaxis 官方澳洲场景自己在用（`AustraliaScenario.lua:1344-1346`），本项目也已在真实对局中实测成功 |
| **能激活一个 0 城休眠城邦？** | ✅ **已实测**：城邦 10 从 **0 城 → 1 城**，归属正确、玩家存活 |
| **预留城邦怎么"不落地"？** | ✅ **有现成解法**：`UnitManager.InitUnit(csID, "UNIT_SETTLER", -1, -1)`（**地图外生成**）+ 杀掉地图上单位 —— 见 `Free City States [Revived]` 源码 |
| 运行时创建原本未在地图上的城邦？ | 原生休眠槽激活已有原型；任意候选池覆盖与副本仍待验收，不能退化为仅复活旧城邦 |
| 运行时新增玩家？ | 普通 PlayerManager 无通用 AddPlayer；WorldBuilder 模块及原生链应分别验证，旧 Lua 路线失败不能证明所有原生方案不可能 |
| 两个玩家共用同一城邦类型（重复城邦）？ | ✅ **可行**（MirrorMap 已实现，见 `决策记录.md` T-11） |
| 城邦名字区分？ | ✅ 可行（UI 后缀包裹官方界面，MirrorMap 已实现，T-14） |
| 面板（图标 + 名称 + 加成）？ | ✅ 可行（配置库 `CityStates` 表 + `DB.ConfigurationQuery` + 官方弹窗模板） |
| 特殊开拓者不能建普通城？ | ✅ `FoundCity` 是 `Units` 表布尔列，新单位置 0 即可 |
| 建城时地块不合法？ | ⚠️ `Create` **静默失败**（不报错也不建城）→ 必须自己校验（T-27） |

---

## 三项专项研究结论（2026-09-22 第二轮实测）

### U1 — 槽位上限（决定能力次数上限）

| 层级 | 数值 | 来源 |
|---|---|---|
| 引擎硬上限 | **`GameDefines.MAX_PLAYERS = 64`**（槽 0–63） | 实测 |
| 主文明硬上限 | **`GameDefines.MAX_MAJOR_CIVS = 22`** | 实测 |
| 保留槽 | 62 = 蛮族，63 = 自由城市 | 实测 |
| **城邦槽上限** | **64 − 主文明数 − 2**（6 主文明 → **56**；12 主文明 → 50） | 推算 |
| 前端滑条 | 由 `MapSizes.MaxCityStates` 决定（HUGE = 24） | `MapSizes.xml` |
| **能否突破滑条** | ✅ **能** —— mod 可写配置库（见下） | 实测 |

> ⭐ **附带推翻一条知识库结论**：知识库称"mod 无法写入配置库"。**实测与 modinfo 交叉验证证明这是错的**——
> `<FrontEndActions>` 里的 `<UpdateDatabase>` 写**配置库**，`<InGameActions>` 里的写**玩法库**。
> 官方/DLC 实例：`Babylon_ConfigData.xml`、`VikingsLandmarks_Config.xml`、`Expansion1_Config.xml` 全在 `FrontEndActions` 下。
> 运行时实证：本机 `MapSizes` 实测含 mod 新增的 `MAPSIZE_ENORMOUS  MaxCityStates=60`。

### U3 — 原生性（"看不出问题的原生城邦"）

✅ **通过**。实测建出的城邦：

```
CanReceiveInfluence() = true          ← 引擎认它是真城邦（可收使者）
IsMajor() = false   IsBarbarian() = false
LeaderTypeName = LEADER_MINOR_CIV_<名称>
CivTypeName    = CIVILIZATION_<名称>
GameInfo.Leaders[lt].InheritFrom = LEADER_MINOR_CIV_<类别>   ← 城邦类别正确
图标 = ICON_CIVILIZATION_<名称>
```

**名字后缀**：`ReplaceUIScript` 包裹官方 `CityStates` 界面，改 `kCityState.Name`（MirrorMap 有完整实现可抄）。

### U4 — 持久化

✅ **通过**。建城 → `Network.SaveGame` → **完全杀掉游戏进程** → 重启 → `Network.LoadGame`（`ok=true res=true`）→ **逐字段一致**（Turn / SEED / 城邦 6 的 1 城 @(2,22) id=65536 pop=1 / 其余城邦 0 城 / 城市总数）。

### ⬜ 仍需原型验证

**U2**（休眠城邦能稳定存活多久 —— **现在最大的未知**）、**U5**（重复城邦的界面表现）、**U6**（城邦建城后会不会自行扩张）、**U7**（使者/宗主/任务是否全自动挂接）、**U8**（一局能激活几次）。

---

## 相关项目先例

| 先例 | 借鉴什么 |
|---|---|
| **`ChineseCiv6BalanceMirrorMapDemo`**（本机 `D:\A-Developing\main\civ6\CCB\` 与部署区） | "同一张图两个能力完全相同的城邦"（两玩家共用同一 `CivilizationType`）、地图脚本替换、官方城邦界面包裹与名字后缀 |
| **`Free City States [Revived]`**（工坊 2545191213，本机已下载） | ⭐ **同构先例**：预留城邦槽 → 游戏中后期激活。关键源码副本在 `调研参考\FreeCityStates_2545191213_关键源码\` |
| **Firaxis 官方澳洲场景**（`DLC\AustraliaScenario\`） | ⭐ `Players[id]:GetCities():Create(x,y)` 的一手用法 |

---

## 历史交付声明（2026-10-04；不代表当前完整验收，见顶部复审要点）

**用户语义（验收标准）**：
> ① **不干涉开局城邦数量**（玩家要多少用多少）
> ② 用 **DLL 底层操作**在对局中新增城邦：
>    **(a)** 地图生成时没出现过、但该局允许存在的城邦
>    **(b)** 场上已存在城邦的**副本**（能力+颜色复用，只有名字/ID 不同）

**两条代码路径已具备，完整运行态仍待验收**（详见 `docs/交付说明书_最终版.md`）：

| 要求 | 状态 |
|---|---|
| ① 不干涉城邦数量 | ✅ `CSF_EXTRA_DORMANT_COUNT = 0`，全库无 `CITY_STATE_COUNT` 改动 |
| (a) 激活没出现过的城邦 | ✅ `C6FW.ActivatePlayer` + `SetAlive` → `IsAlive=true`、16 子系统初始化、放单位成功、不崩 |
| (b) 同一城邦重复出现 | 🟡 原生身份/激活/建城与 UI 路径已实现；完整能力、外交、存读档和多人仍 BLOCKED |

**核心机制**：**Lua 配置身份 + DLL 负责激活**
```
① C6FW.ActivatePlayer(slot)                  DLL：创建 + 16 子系统
② PlayerManager:SetPlayerSlotStatus(slot,1)  Lua：槽位 5 → 1
③ C6FW.SetAlive(slot, 1)                     DLL：置 IsAlive（player+0x258）
④ CSF_ApplyCityStateColor(slot)              补色（旗标另有三级兜底）
⑤ UnitManager.InitUnit(slot,"UNIT_SETTLER",x,y)  引擎在城邦回合自建
```

**为什么必须 DLL**：Lua 的 `InitializePlayer` 走 `FUN_180617370` 那道门，
对槽位状态 5 **直接 return**，**从不调用 `FUN_1802f9350`**（16 个子系统）。
→ 玩家是半成品 → 点下一回合**原生崩溃**。

**⚠️ 部署要求**：需要 C6FW（`C6FW\scripts\install.ps1`，自带备份+回滚）。
**测完必须 `uninstall.ps1` 回滚**（C6FW 与其它 GameCore DLL mod 互斥）。
