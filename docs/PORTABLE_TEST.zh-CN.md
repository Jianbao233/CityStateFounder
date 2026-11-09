# 城邦缔造者 v1.0.6：内置核心测试包

将完整 `CityStateFounder` 文件夹复制到测试机：

`文档\My Games\Sid Meier's Civilization VI\Mods\CityStateFounder`

完全退出并重新打开游戏，在“额外内容”启用“城邦缔造者 v1.0.6”。同一 GUID 只保留一份；旧版不要改后缀后继续留在 Mods 下。若从 ZIP 解压，确认 modinfo 在上述文件夹第一层，避免套两层 CityStateFounder。

包内已有 `Binaries/Win64/GameCore_XP2_CSF_FinalRelease.dll`，由 `Config/CSF_GameCores.sql` 选择它。干净测试机**不需要**复制文件进游戏目录、修改官方 XML、安装 C6FW/Codex/DSH 或编译环境；官方核心继续使用测试机游戏自带的一份，不随包分发。

## 测试条件

- 当前支持 Windows x64、风云变幻 XP2 规则集；日常保持蛮族氏族关闭。原生桥仍绑定已核对的官方 XP2 构建，其 SHA256 是 `324c51e9ea3531758842e16c69e6cddbefbb226c5b675c3d6e60111646c2e98c`，打包形式不等于跨版本支持。
- 房主与客机都复制同一个包，并启用一致的 DLC 和模组。包内 `BUILD_MANIFEST.json` 可核对版本及文件哈希。
- 独立 GhostFix、工具箱的可选反作弊核心、CE 等也会替换同一个 XP2 GameCore。本次测试先停用这些**核心替换功能/模组**；其余普通 Lua/SQL/UI 模组按原测试组合保留。当前包没有合并 GhostFix 尸体修复功能，不通过提高加载顺序伪称两套核心同时生效。
- 包内 `Logs/C6FW.log` 在原生 DLL 实际加载时生成；Lua/Modding 日志仍在 Firaxis 的用户日志目录。看到单位或菜单并不能证明原生核心已正确加载。

## 仅供之前做过手工安装的机器

如果已经按旧开发步骤改过游戏目录中的 `Expansion2_Config.xml`，需先还原那次对 GameCores 行的修改：其官方 `DllPrefix` 为 `GameCore_XP2`，原 `PackageId` 保持官方值。这个步骤只是清理**旧安装方式**；没有改过的测试机不需要做。

本机开发环境由主 Agent 定向还原该行并保留备份，用户不需要反复覆盖官方文件。停用新包之后能回到官方选择的前提，是没有其它核心模组或旧手工修改继续接管这一行。

## 本次先验证加载与最短操作

1. 用原先的开局城邦数量、不开蛮族氏族，进入 XP2 对局。
2. 建立一个原先没有的城邦，再建立同文明副本；查看城市条、面板、使者和正常城防。
3. 另存副本，正常退出，重新启动读取同一档，检查城邦/副本、使者与宗主状态，随后在 +1、+5、+20 回合复查。
4. 双端联机最后验：两端分别建邦、状态一致、保存重连、不重复执行。

当前已完成静态/打包检查不等于该部署形态的实机验收。出现 `Failed to load GameCore DLL` 或 `native_unavailable` 时先保留 Modding.log / Lua.log / 包内 Logs，不要补装旧版 DLL 或盲目修改官方文件。
