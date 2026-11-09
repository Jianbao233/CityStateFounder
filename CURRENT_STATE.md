# 城邦缔造者当前状态

## 2026-11-09 · v1.1.2（112）实机确认与 Git 基线

用户确认 v1.1.2 实际可用。当天日志显示官方 XP2 精确哈希校验通过，原生插件 `OnLoad ready v1.1.2`，马斯喀特副本建城请求返回 `ok=true`。逐项存读档和独立联机结果未单独报告。本机包 30 个文件与原验收包逐哈希一致。

CCB 工具箱 2.0.40-beta（240）采用同一套兼容 Loader 1.0.6 / WINMM format2。已逐字节核对 Shell 和 Runtime，并将版本、来源及完整哈希记入 [native/provenance.json](native/provenance.json)。固定官方游戏构建为 26407122。`src` 的模组清单、XP2 路由和版本文本使用实际验收包的字节，打包入口为 `tools/package_shared_loader.py`。

发布物、游戏 DLL、运行日志与本机验收备份留在本地。Git v1.1.2 记录源码和构建依赖指纹。线上工坊此前发布版本为 v1.1.1。

## 2026-11-07：v1.1.2已部署，交用户手测

用户明确授权“你部署就行了，又不用打开游戏，我自己测”，本次仅豁免纯文件部署内存门槛；真实进程检查、FIFO和lease互斥保留，共享队列源码/配置未改。已在原订阅目录F:/Steam/steamapps/workshop/content/289070/3808178854原位部署112，30/30文件SHA核对通过，GUID唯一，旧版完整ZIP与既有日志保留。未改配置/Mods.sqlite/官方核心/现有WINMM1.0.6，未启动游戏或Tuner，lease已释放。线上工坊仍111，未上传。

本轮回退及部署证据：`build/acceptance/20261106-build26407122/deployed-20261107-000349`。真实新版加载、建邦/副本/使者/城防和冷重启读档仍等待用户结果；不能把部署校验转记为游戏验收。下方11月6日“未部署”描述为历史准备状态。

## 2026-11-06：新游戏构建适配候选 v1.1.2 / 112

已读取「CCB工具箱 2.0 （新项目）」最新发布回执：其2.0.38-beta随包使用CCB兼容Loader1.0.6。本项目候选同步相同Shell/Runtime字节及原HookAPI，不复制工具箱业务插件；未修改公共加载器源码。旧公开v1.1.1与完整需求保留，本轮没有工坊上传、实际Mods部署、游戏启动或FireTuner操作。用户此前要求实机由其手测，本轮已请求测试窗口，尚未得到回复。

当前安装Steam build26407122：DX11 d1a0cfd4…491ebe、DX12 1adb1a2b…6b39417、XP2 092abfbb…f7c41f。原XP2 324c51e9…46c2e98c与新核心逐节比较：.text/.data/.pdata/.gfids/.tls/.rsrc/.reloc字节相同、段布局相同、157导出及完整导入相同；.rdata仅533处编译工作目录ID、3处调试时间戳、CodeView GUID和导出时间戳变化，逐项规范后全部相同。未用“同版本号”或只改哈希代替核对。原生桥所需11个HKS导出在当前HKS存在。

`native/csf_supported_cores.h`只接受上述新旧两个完整哈希，原官方路径验证和运行时指令签名保留。建邦、身份、接触、使者、城防、能力及AI链均未改；升级插件版本避免旧DLL在同名选举中胜出。候选打包器验证Loader完整哈希/来源报告、相同HookAPI、真实安装PE和插件112版本/导出；过期插件或被改依赖直接拒绝。

本地候选：`../torelease/Build26407122_1.1.2/CityStateFounder`，30文件、8137156字节；ZIP `../release/CityStateFounder_v1.1.2_build26407122_candidate_20261106.zip`。相对正式111，仅Shell、Runtime、插件、版本文本和说明/清单共8文件变化，全部玩法Lua/SQL/UI及开局城邦设置保持相同。归档逐成员SHA回读通过。

离线验证：新旧PE及负对照3项、真实插件ABI/包体及失败保护6项、生产哈希门禁C++正负例、既有建邦安全Lua回归、面板请求17项、城邦UI颜色18项、副本注册5项通过。静态PE与HKS导出一致不能证明真实加载/重启/建邦/读档通过。当前构建实机与双端联机仍未测，旧版本成功记录不转记为112通过。

知识采用：`native-loader-framework.md`的“GameCore精确构建/HookAPI与插件协议/生命周期”及`native-reverse-sources.md`的“当前二进制身份/指令与字段核对”落在完整PE比较、两项哈希门禁、原API不变和包体拒绝检查；没有改变开局数量，也没有把旧c6se DLL误作公共插件。完整需求仍以既有14组131条计划及用户后续取消排序/暂缓联机为准。

下一轮请用户完整退出后启动112，确认正常升级提示及自动重启，建立原版与同文明副本，派遣使者/打开城邦详情、核对城防非负；存档完全重启后复查身份/使者/能力与自然过回合。不要与订阅111形成重复GUID；部署需取得共享lease和先做整包回退。111专用`prepare_shared_workshop.py`不得用于112并沿用旧验收标记。该历史工具现已在任何写入前强制验证111冻结整包指纹；新版及同版本被改包都会拒绝，python -O下3项负对照回归通过，工坊workspace未被触碰。当前证据在`build/acceptance/20261106-build26407122/`。

## 已公开版本 v1.1.1（2026-10-28，历史基线）

**v1.1.1 / modinfo111 已更新原公开工坊条目3808178854，真实订阅包回归通过。** 用户明确保持公开、跳过本次私密上传阶段；Loader再分发许可已确认。17:00:08 API回读public、8109780 B、diff空，中英文标题与长说明逐字一致，封面URL保留。

订阅内容30文件逐SHA与正式staging一致，DownloadItem真实回调OK/app289070，无本地副本替代。自然首装79184→自动重启86172，实际WINMM1.0.3及工坊目录CityStateFounder.dll入模块；新进程读取此前+20终档T22，零开局/氏族关闭，日内瓦原版6/副本7六表有效、9/9使者、25/25城防、2/2自然产出单位保持。正式面板request3建立阿卡德8成功，建邦使者2/城防18/16原生能力root；正常UI操作派遣使者后2→3、库存1→0、宗主0，城防19。原生城邦列表、详情和关系回调无错。最后79184/86172/Reporter在17:13:44全部正常退出0，无强杀。

v1.1.0初次公开订阅实测保留FAIL：公共Runtime在hooks前模块快照失败，插件未载。公共源增加仅ERROR_BAD_LENGTH有界重试（128次、10ms），其他/持续失败仍拒绝并记录错误码，WINMM升级1.0.3。原故障没记Win32码，所以ERROR_BAD_LENGTH是机制推断；不把它冒充原始实测错误码。故障注入/安全31、安装更新35、格式10、旧回归56、转发371/系统优先370及非游戏休眠通过。冻结1.0.2和旧1.0.1字节不改，新输出PVPCore/build/shared_loader_winmm_candidate/patch-1.0.3。

玩法插件SHA仍2c99b3544a0a590efc8874c7cf3fb9615c4802815a04933fb02dde710c02aa41；1.1.0的完整新进程读档+20、日内瓦能力正反数值、旧满容量拒绝证据保留。1.1.1读取该T22档并补首装/新城邦/使者，不冒充再跑一遍+20或全部131项。最终Lua运行错误与Loader拒绝均无；官方DLC XML及CurrentClickouts本地化警告分类留档，不称所有日志零警告。

最终发布真源：../torelease/Workshop_1.1.1_final2/CityStateFounder。归档ZIP CityStateFounder_v1.1.1_shared_loader_20261028_165503.zip，SHA be025fef88053809dea8cf491e6be6a6310f29443d478429319d4c026c72f2e9。源码native/与tools/package_shared_loader.py；src/modinfo106仍为保留旧代理线，不能直接部署冒充111。准备脚本保留已有public状态。

环境已恢复：原组918、三配置原SHA，其他组逻辑diff0，官方XML未改；本批WINMM和3资源归档撤回，游戏/Reporter0进程，lease已释放。工坊订阅保留，原组城邦禁用；本地副本完整移至C:/Users/Jianbao/Documents/CSF-LocalBackup-20261028，避免重复GUID。若以后玩城邦，启用订阅版并按首装重启提示操作；旧GameCore替换组合不兼容。

完整需求继续保留。排序按用户取消，任务外交用户确认，独立联机本轮明确不测。未穷举全部能力/组合/旧档；候选行鼠标注入不可靠，本轮面板回调不能称全物理点击验收。

证据：docs/research/current_release_state_20261028.json、build/acceptance/20261028-workshop-public/；前版完整本机证据build/acceptance/20261028-shared-loader/。

## 2026-10-29 用户混合项目环境只读排查

用户在测试其它项目，当前组918同时启用工具箱202（旧VERSION1.0.1/format1）和工坊城邦111（WINMM1.0.3/format2）。上一局83344的Shell记录Loader缺失、安装跳过或失败，退回官方核心；读盘无winmm/version/dxgi入口、无本轮Loader日志。进程在枚举模块前由外部退出，未获得实时模块清单。源码明确拒绝启用旧Runtime/旧Shell模板，符合当前组合；具体拒绝文字原日志缺失，不能伪造为已记录原因。候选元数据54不代表可用54，缺C6FW桥时全部native_unavailable被UI滤空，提示尚未区分原生缺失。只读未连接Tuner、未修改部署或其它项目；后续应统一兼容公共WINMM包并做组合验收，不强改LoadOrder/绕过保护。证据build/acceptance/20261029-enabled-loader-conflict/diagnosis.json。

通用能力贡献待办：按用户“先记着”，暂缓公共化实现；保留玩家只读诊断、城邦生命周期、能力/AI初始化、身份显示及验收工具提炼方向，继续以既有兼容范围为准。
