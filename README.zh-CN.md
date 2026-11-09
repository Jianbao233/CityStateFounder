> **当前版本 v1.1.2（112）**。适配 Steam Windows 构建 26407122，采用与 CCB 工具箱 2.0.40-beta 一致的 Loader 1.0.6 / WINMM format2。用户已确认实机可用。完整依赖哈希见 [构建来源](native/provenance.json)，验收范围见 [当前状态](CURRENT_STATE.md)。

### 构建 v1.1.2

在 Windows x64 环境准备 VS 2022 Build Tools、Python 和 `pefile`。执行 `tools\build_native.cmd` 构建城邦插件，再执行以下命令，路径参数指向实际文件。`--out` 使用新目录。

```powershell
python tools/package_shared_loader.py --out build/v1.1.2/CityStateFounder --loader-dir '<CCB 工具箱 2.0.40-beta>/Binaries/Win64' --game-dir '<文明 VI 安装目录>' --reference-xp2 '<旧版官方 XP2 DLL 备份>'
python tools/audit_csf.py --src build/v1.1.2/CityStateFounder
```

打包器核对 Shell、Runtime、HookAPI 和新旧官方核心的指纹。完整成品目录用于安装。下文为历史开发记录，其中 v1.0.6 私有代理打包流程属于旧版。

> 2026-10-28：已更新原公开工坊条目3808178854至 v1.1.1 / 111，内置公共WINMM1.0.3与城邦插件。订阅回归及当前部署状态先读 [CURRENT_STATE.md](CURRENT_STATE.md)。下方1.0.6代理包与早期进度均属历史；完整需求保留，联机未测。

> 2026-10-26：工坊仅完成本地准备，线上未上传。新版包真源为 `../torelease/Workshop_1.0.6/CityStateFounder`；含版本文案与许可补正，核心/建邦玩法未改。本机游戏运行中，未覆写其Mods。联机验收按用户指令暂缓，仍未测；新内置核心路由仍缺干净游戏加载证据。见 `docs/WORKSHOP_DRAFT_2026-10-26.md` 与 `docs/research/current_release_state_20261026.json`。

> 2026-10-25 当前测试包：v1.0.6 已改为 MOD 内置 XP2 核心。直接复制完整 `CityStateFounder` 文件夹到测试机 Mods，不再要求修改官方 XML / 复制 DLL 到游戏目录。安装条件、旧手工安装迁移与核心冲突见 [测试包说明](docs/PORTABLE_TEST.zh-CN.md)。新加载形态仅完成编译、独立加载夹具、静态配置和哈希验收，游戏内与双端联机仍待用户验证。下方旧版手工安装描述是历史。

# CityStateFounder — 城邦缔造者

## 2026-10-23：当前开发版状态

以下状态优先于后文历史记录。完整需求仍保留在 `docs/research/csf_acceptance_plan_v2.json`（14组、131条）；MOD 尚未完成整体验收、未发布。

- 已在 Windows《风云变幻》规则、开局城邦数量0、不开蛮族氏族模式下，按正式请求登记空槽并建出独立同文明城邦。没有预留开局城邦、增加开局数量或替换其它文明身份。
- 依赖配套 C6FW XP2 原生桥，必须同时具备 `PrepareClosedCityState`、`ActivatePlayer`、`CreateCityNative`、`SetCityStateIdentityText`、`PublishCityStateReady`、`InitializeCityStateTurnTasks` 和快照/颜色接口。旧桥缺少完成接口时提前拒绝。原生地址仅绑定已核验的官方 XP2 DLL SHA256 `324c51e9ea3531758842e16c69e6cddbefbb226c5b675c3d6e60111646c2e98c`；不要把此开发版当作所有规则集和核心版本通用的纯 Lua 模组。
- 官方玩家就绪通知负责注册文明、领袖继承链及通用能力；按真实 modifier 实例读回，避免重放造成叠加。建邦同时验证名称、原生城防、双向接触和额外使者；读档不会再次发奖。
- 官方AI回合任务装配与能力通知分别处理；真实任务完整才结束建邦，只对三组空向量单次补齐，已有或部分任务不重放。零开局同一人类控制对局已有38城、35种候选，正式自动建城后连续20回合自然生产单位和建筑，无手工队列/造兵。最新安全回归293/293；最终自动版的完整重启读档正在验证。
- 正式界面请求走原生 `EXECUTE_SCRIPT` 操作，Gameplay 校验发起玩家及使节类型/位置，持久防重并恢复待处理请求。本机 ExposedMembers 诊断接口不能证明网络同步。
- 已验证阿卡德原版/副本的宗主取得、撤销、多个来源互不误删及不叠加；有实际城墙攻击正反对照、三类任务及奖励、完整跨进程读档、+1/+5/+20回合六表与AI生产证据。每项的适用场景和未测项见 `docs/research/identity_defense_checkpoint_2026-10-23.md`，不外推全部候选、地图及模组组合。
- 非法距离现在在登记前拒绝；自动找地不再降低引擎排除半径或绕过地形/归属。原生激活后的失败保持隔离，已发布失败槽的前端身份可恢复，避免拖坏官方城邦面板。
- 扩大实机候选检查发现并修正六个自定义城邦重复声明已继承类别 Trait 的数据缺陷，保留共享能力并避免双倍使者加成；补齐游戏内自定义名称文本注册。全部候选及旧档已有重复效果的恢复尚需继续验收，不能据新建用例通过外推。

独立主客机验收仍待第二端；正常退出、候选独特能力/容量边界、副本真实城市名和真鼠标交互等未结项继续保留，不能仅凭建城成功或离线测试通过宣布交付完成。

## 2026-10-16：新版验收入口（优先于下方历史说明）

2026-10-19 已完成一次 XP2 新局真实建邦验收：正式 `FoundCityStateByCiv` 路径激活 Antananarivo 预注册槽 55，并由 `C6FW.CreateCityNative` 在 `(37,18)` 建出归属正确的城市；读回为 1 城、可收使者，自动过一回合后仍保持。完整业务矩阵仍 BLOCKED；同文明副本、存读档、多人和官方转换执行器尚未结案。

- 正式传输：交接包 `tools/tuner_strict.js`；统一 CLI `tools/c6.js` 已接入。构造/import 不连接；一次会话只建一条连接，动态精确查询 context，随机请求标记确认命令完成。超时/断开/坏帧立即停止，不重发未知结果的操作。
- 游戏动作需要显式 `--execute`。`status` 默认只看操作系统进程/监听表，不连接端口；没有执行、环境不足或缺证据用 **BLOCKED / 退出码 3**。工具查询完成的 0、`COMMANDS_COMPLETED` 和业务验收 PASS 是不同结果。
- `c6.js session --job <job.json> --out <全新目录> --execute` 在**同一进程/连接**里执行已审核的 Lua 步骤；开连接前检查全部文件 SHA256、路径与步骤 ID。每步原始返回、context、请求标记与哈希落盘；遇失败停止。它不自动开游戏、杀进程、部署或更换核心。
- `CityStateFounder/tools/csf_acceptance.py` 只做离线证据判读。计划、run UUID、构建/模组绑定、样本 JSON 原件和 SHA256 必须匹配；自报 PASS 文本不能替代断言。任何必需项缺证据阻止整体通过；人工夹具全过也只得 `OFFLINE_ONLY / 3`。
- 完整需求矩阵：`CityStateFounder/docs/research/csf_acceptance_plan_v2.json`，14 组 / 128 条比较。覆盖开局数量、未出现城邦、同文明副本、失败隔离、队列重入、六表及 +1/+5/+20 回合、原版与副本能力数值及正负对照、任务外交、视觉、完整退出后的存读档、独立主客机、容量/候选池与官方氏族转换对照。
- 证据一致性判读器不能自行证明 JSON 来自真实游戏；最终验收仍要主 GPT 核对原始捕获、实际加载核心、截图和独立客户端。视觉审核标志不能由 DS 自行填 true 代替目视复核。当前六表只读组件尚未绑定 Lua，多人请求链尚未闭环，这些缺口必须保持 BLOCKED 或有明确反证时 FAIL。

离线准备：在 CityStateFounder 目录运行 `python tools/prepare_csf_acceptance.py --out docs/research/<新的run目录>`。输出固定计划、全新 run、空证据、源码清单及**未执行的只读预检 job**；目录已存在即拒绝覆盖。这一步返回 0 只表示准备完成。再把该目录的 plan/run/evidence 交给 `csf_acceptance.py`，空证据必须得到 BLOCKED/3。

游戏可用后的顺序：先抓当前安装包和实际核心基线、保留备份 → 仅执行只读预检 → 新局数量/失败分支 → 官方蛮族氏族正常转换正对照 → 契约明确后的隔离原生实验 → 生命周期/存读档/视觉 → 独立多人。当前开发源码已部署，C6FW XP2 代理 DLL 保持安装供正式 slot 建城使用。每个地图/mod/候选池组合独立记录覆盖，不把一局结果外推全部组合。

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
- 当前仍未拿到 GameCore 只读预检的完整证据，14 组/128 条业务条件均未执行；本轮结论是 **BLOCKED**。详细原始状态见 `docs/research/runtime_observations_2026-10-19.json`。
- 运行窗口后的工具修复：session 现在会在观察步骤按 `netstat` 端口候选逐个 APP 握手，并要求目标 context 真实出现后才接受连接；C6FW 安装先校验 DLL、保持官方包 GUID，并以无 BOM UTF-8 写配置。下一轮仍需新鲜游戏窗口验证。 本轮随后用 4318/4319 两个候选做了观察重连，仍未拿到 InGame APP/LSQ 响应，因此业务矩阵继续 BLOCKED。
- 游戏已停止，C6FW 官方配置/DLL 已回滚，Mods.sqlite 当前组恢复为原来的自动组；没有发布工坊。


> **能力试验型 MOD**：验证「玩家建立城邦」这条能力是否可实现，为将来移植到某文明 / 某领袖的具体能力做准备。
>
> **当前阶段（2026-10-15 复核）**：已有 Lua/UI/SQL 原型与依赖 C6FW 的原生激活路径，尚不能视为完整需求已验收。下文早期可行性结论与“最终交付状态”保留作历史，当前实现边界以本节为准。

## 当前修复与研究状态（2026-10-15）

- 需求仍是：保留玩家指定的开局在场城邦数；游戏中建立该局允许的城邦，支持同文明副本，并具备真实城邦机制。运行中增加城邦不等于违背“开局数量不变”；仅复活原有城邦不能替代完整需求。
- **开局实验已从加载清单撤下**：移除 AdvancedSetup 的替换/导入/文件注册，以及两个 CCB 地图覆盖脚本的导入。`LoadScreenClose` 不再隐藏开局城邦或补造休眠城邦，公共 `ForceReserve` 也明确拒绝执行。历史实验源码仍留作追溯，不再进入运行包。此修复不能撤销旧存档或开局设置缓存已经发生的数量改动；下次新局应核对自己指定的数量。
- **建城结果改为实际取证**：Create 抛错、静默零城或目标格没有目标玩家的城市均返回失败；原生 nil/0/false 不能当成功。必须在 Create 前清走使节的既有约束保留。激活后失败的槽记录隔离属性，禁止用 SetAlive(0)/UninitializePlayer 猜测回滚。只有成功才记录本回合额度；队列增加重入保护。副本开关仍关闭，不能据此声称完整需求已实现。
- **覆盖范围与生命周期待验收**：按同文明寻找未激活槽，只证明该局确有相应槽的目标可尝试；不能推导任意候选池、任意重复次数都可用。需要核对原生存活列表一致性、外交/使者/宗主/任务、失败后再次尝试、重启读档和多人跨端一致性。已有早期存活/读档记录必须对应到具体路线与构建。
- **原生桥先堵假成功**：两张存活列表先同时检查容量、计数与目标成员关系，再发布；查索引、初始化、激活、列表写入等失败均不再返回成功。不自行分配引擎内存；这不是完整事务或生命周期证明。当前城邦桥仍是 XP2 专用实现，其他规则集 DLL 编译通过不代表该能力可用。
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
- **诊断组件已准备**：C6FW `src/lua/csf_player_snapshot.h` 只经读取回调检查两组共六张表，包含旧桥漏补的 `+0x1878`，分别报告读取状态、真实指针/槽号集合一致性与目标字段。38 项人工内存断言通过，含地址回绕、同 ID 不同对象、满表、重复成员、不可读目标；它不判断“完整激活”，没有接入 Lua 或自动执行。
- **副本旧路线已否决**：当前二进制的 `0x22A930` 读取 DuplicateCivilizations，`0x2269B0` 用关系扩大“已使用”拒绝集合；它是排重别名表，不是共存白名单。在这条路径中自配对冗余，补齐 24 条到全部城邦也不能开启副本。因此 v1.0.5 已撤下旧 SQL 的 action/Files 注册，旧源文件加废弃说明。研究 SQL 保留在 `docs/research/duplicate_registration_candidate.sql`，已标为“启用方案否决、仅负对照”，不能加载；`tools/_write_dup.py` 一键写源码/部署脚本已退役，只返回错误且不写文件。生成器仅用于研究，5 组 SQLite 测试证明 SQL/原子输出语义，不证明游戏副本功能。
- **玩家记录第二字段也曾命名错误**：Lua 绑定 `GetHandicapTypeID → 0x169EE0` 已从本机指令核对；旧代码把它称为文明 ID，实际是难度配置值。代码已更名，不能再用该字段给新槽指定文明。目标文明/领袖的槽配置、氏族 raw 值与开局规范化值的读取契约须分别处理。
- **不能继续沿用的旧断言**：`0x2F9790` 比较 TRIBE，`0x2F97F0` 比较 FREE_CITIES，并非旧注释里的“主文明/城邦”；城邦表来自排除这些类型后的分支。`.pdata` 的 CHAININFO 续块也不能当成独立相邻函数，工具已按链归并。历史 48/48 槽快照只对当时那局成立，不外推当前 mod 组合或高主文明数。

当前研究仍未把“玩家记录第二字段的两种取值”“氏族与开局不同默认上下文”“运行期别名表如何刷新”混为一条已验收路线。完整副本、配色复用、使者/宗主/任务、存读档和多人需求照旧保留。复核证据见 `docs/research/clans_static_review_round2_2026-10-15.json` 与 `clans_static_corrections_2026-10-15.json`；原生构建仅保存在 C6FW `build/`。

v1.0.5 静态门禁：Lua/清单 135 项、SQL 5 组、原生快照 38 项与旧配对列表 18 项通过；Lua 12/12；审计 OK 107 / WARN 18 / ERR 0。游戏行为、渲染、存读档和多人均未在本阶段验证。下一步条件与未证项见 `docs/research/clans_native_experiment_plan_2026-10-15.json`。

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

**两条都已实现**（详见 `docs/交付说明书_最终版.md`）：

| 要求 | 状态 |
|---|---|
| ① 不干涉城邦数量 | ✅ `CSF_EXTRA_DORMANT_COUNT = 0`，全库无 `CITY_STATE_COUNT` 改动 |
| (a) 激活没出现过的城邦 | ✅ `C6FW.ActivatePlayer` + `SetAlive` → `IsAlive=true`、16 子系统初始化、放单位成功、不崩 |
| (b) 同一城邦重复出现 | ✅ 实测 `AKKAD II` + `AKKAD III`（同一文明两个玩家） |

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
