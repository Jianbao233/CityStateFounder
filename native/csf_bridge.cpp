// CityStateFounder native bridge. Derived from C6FW (MIT), source hashes in provenance.json.
// Shared Loader owns script hooks and unload order; this module owns no detour/thread.
#include <windows.h>
#include <cstdint>
#include <cstring>
#include <string>
#include "csf_player_snapshot.h"
#include "csf_log.h"
namespace c6fw {
namespace {
void* g_get_instance_fn = nullptr;
constexpr const char* kSetFieldExport = "?hksi_lua_setfield@@YAXPEAUlua_State@@HPEBD@Z";
// LUA_GLOBALSINDEX (-10002) puts the table into the global environment.
constexpr int kLuaGlobalsIndex = -10002;

using FnPushCclosure = void (*)(void* L, int (*fn)(void*), int nup, const char* name, int flags);
using FnCreateTable  = void (*)(void* L, int narr, int nrec);
using FnSetField     = void (*)(void* L, int idx, const char* name);
using FnPushInt      = void (*)(void* L, int v);
// NOTE: never use hks_obj_newlstringhashed for this. It returns a 16-byte
// HksObject struct; under the x64 ABI that requires a hidden return-buffer
// pointer in RCX, so a naive (L, s, len, hash) call misroutes every argument
// and writes through the lua_State pointer -> crash (observed 2026-08-06,
// GetModFingerprint). hksi_lua_pushfstring returns a plain const char* and
// pushes a formatted string onto the stack (standard lua_pushfstring).
using FnPushFstring  = const char* (*)(void* L, const char* fmt, ...);
// Argument/return helpers for closures that take parameters.
using FnGetTop      = int (*)(void* L);
using FnToLstring   = const char* (*)(void* L, int idx, std::uint64_t* len);
using FnPushNil     = void (*)(void* L);
using FnToUserdata  = void* (*)(void* L, int idx);
using FnToNumber    = double (*)(void* L, int idx);
using FnPushNumber  = void (*)(void* L, double v);

FnPushCclosure g_pushcclosure = nullptr;
FnCreateTable  g_createtable = nullptr;
FnSetField     g_setfield = nullptr;
FnPushInt      g_pushint = nullptr;
FnPushFstring  g_pushfstring = nullptr;
FnGetTop       g_gettop = nullptr;
FnToLstring    g_tolstring = nullptr;
FnPushNil      g_pushnil = nullptr;
FnToUserdata   g_touserdata = nullptr;  // unused for now (Plot uses GetInstance)
FnToNumber     g_tonumber = nullptr;
FnPushNumber   g_pushnumber = nullptr;

// The snapshot reader is deliberately the only place where this bridge reads
// arbitrary game memory. The parser in csf_player_snapshot.h remains
// platform-neutral for offline tests; this adapter adds the live-process SEH
// guard and reports a failed read instead of exposing a false success value.
bool csf_snapshot_reader(std::uintptr_t address, void* output, std::size_t size) {
    if (!address || !output || !size) return false;
    __try {
        std::memcpy(output, reinterpret_cast<const void*>(address), size);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool lua_check_string(void* L, int idx, std::string* out) {
    if (!g_tolstring || !g_gettop) return false;
    if (g_gettop(L) < idx) return false;
    std::uint64_t len = 0;
    const char* s = g_tolstring(L, idx, &len);
    if (!s) return false;
    out->assign(s, static_cast<std::size_t>(len));
    return true;
}
// ---------------------------------------------------------------------------
// CSF 城邦属性桥（2026-10-04）
// ---------------------------------------------------------------------------
// 背景：对局中实时激活的城邦（SetPlayerSlotStatus + InitializePlayer）**没有颜色**，
// 交互时原生崩溃。逆向结论（见 CityStateFounder/docs/DLL实时激活城邦_逆向进展.md）：
//   · 槽位状态与颜色是【同一属性表的两个属性】
//       getter 槽 = vtable +0x58，setter 槽 = vtable +0x130
//       颜色属性 ID     = DAT_180b8d654
//       槽位状态属性 ID = DAT_180b8d668
//   · 槽位状态有 Lua 包装（SetPlayerSlotStatus）→ Lua 能改
//   · **颜色 setter 没有 Lua 包装** → 必须由 DLL 代劳  ← 本桥存在的唯一理由
//
// 设计：**对象从 Lua 传进来**（PlayerConfigurations[slot] 本身就是它的 userdata），
// 用现成的 GetInstance(L, idx, 0) 取 C++ 指针 —— 与 plot_from_lua 同一套路。
// 这样 C++ 侧不必碰玩家数组/槽位映射，且任何 PlayerConfigurations 都能用。
//
// Lua 侧用法：
//   C6FW.GetPlayerColor(PlayerConfigurations[slot])         -> number
//   C6FW.SetPlayerColor(PlayerConfigurations[slot], color)  -> 1/nil
// ---------------------------------------------------------------------------
#if defined(C6FW_VARIANT) && C6FW_VARIANT == 2  // xp2
constexpr uintptr_t kGetPlayerColorRva = 0x169E90;  // FUN_180169e90(cfg) -> uint
constexpr uintptr_t kSetPlayerColorRva = 0x16B390;  // FUN_18016b390(cfg, uint)
// ★ 2026-10-06【按槽位查配置】—— 绕开 GetInstance 转换失败的问题
//   引擎自己的查法（FUN_180228580 里）：
//       FUN_1807d0780()            -> 配置管理器（= FUN_180044dd0() + 0x948）
//       FUN_1802209a0(mgr, index)  -> 数组查表拿配置
#else
constexpr uintptr_t kGetPlayerColorRva = 0;
constexpr uintptr_t kSetPlayerColorRva = 0;
#endif

// ★★ 2026-10-07【按槽位查配置 —— 修正版】无条件声明（所有变体都要能编译）
//
//   ❌ 旧写法（错的，会让游戏卡死）：
//        cfg = FUN_1802209a0(FUN_1807d0780(), slot)
//      查证 FUN_180228580 后发现：`FUN_1807d0780()` 是**文明表**（CivilizationType
//      表），`FUN_1802209a0` 是通用「vector 按下标取元素」，两者配对时第二个参数
//      是**文明索引**（FUN_180169ee0(cfg)），**不是玩家槽位**。
//      拿玩家槽位去索引文明表 → 越界拿到垃圾指针 → setter 跳 [垃圾+0x130] → 卡死。
//
//   ✅ 正确写法（引擎自己的取法，见 FUN_180617370 / FUN_180616d30 /
//      FUN_1806185f0 / FUN_1806172d0 / FUN_180619a00 五处一致）：
//        mgr  = FUN_180164c20()                 // 就是 `return DAT_180b8aa78;`
//        base = *(void**)(mgr + 0x90)           // PlayerConfiguration 数组基址
//        cfg  = (char*)base + slot * 0x20       // 步长 0x20，按玩家 ID 索引
//
//   颜色属性：DAT_180b8d654，值 = ColorType 索引（0xffffffff=无效, 0=UNDEFINED,
//   否则 FUN_180606270("COLOR_...") 的结果）。
constexpr uintptr_t kCfgMgrRva   = 0x164C20;  // FUN_180164c20 -> DAT_180b8aa78
constexpr uintptr_t kCfgArrayOff = 0x90;      // mgr + 0x90 = 数组基址指针
constexpr uintptr_t kCfgStride   = 0x20;      // 每个 PlayerConfiguration 32 字节
constexpr uintptr_t kStrToTypeRva = 0x606270; // FUN_180606270(const char*) -> uint
constexpr int       kMaxPlayerSlot = 0x40;    // 引擎自己也是 0x40 上限

void* g_cfg_mgr_fn = nullptr;
void* g_cfg_by_idx_fn = nullptr;
void* g_get_player_color_fn = nullptr;
void* g_set_player_color_fn = nullptr;
void* g_str_to_type_fn = nullptr;

void resolve_player_color_helpers(HMODULE core) {
    if (!core) return;
    if (kSetPlayerColorRva == 0) {
        c6fw_log("lua_bridge: player-color bridge skipped (XP2 only)");
        return;
    }
    if (!g_get_player_color_fn) {
        g_get_player_color_fn = reinterpret_cast<void*>(
            reinterpret_cast<std::uintptr_t>(core) + kGetPlayerColorRva);
        c6fw_log("lua_bridge: GetPlayerColor resolved @ %p", g_get_player_color_fn);
    }
    if (!g_set_player_color_fn) {
        g_set_player_color_fn = reinterpret_cast<void*>(
            reinterpret_cast<std::uintptr_t>(core) + kSetPlayerColorRva);
        c6fw_log("lua_bridge: SetPlayerColor resolved @ %p", g_set_player_color_fn);
    }
    if (!g_cfg_mgr_fn) {
        g_cfg_mgr_fn = reinterpret_cast<void*>(
            reinterpret_cast<std::uintptr_t>(core) + kCfgMgrRva);
        c6fw_log("lua_bridge: CfgMgr(164c20) resolved @ %p", g_cfg_mgr_fn);
    }
    if (!g_str_to_type_fn) {
        g_str_to_type_fn = reinterpret_cast<void*>(
            reinterpret_cast<std::uintptr_t>(core) + kStrToTypeRva);
        c6fw_log("lua_bridge: StrToType resolved @ %p", g_str_to_type_fn);
    }
    if (!g_cfg_by_idx_fn) {
        // 旧的错误取法（文明表按下标）已废弃，保留指针仅供诊断日志比对。
        g_cfg_by_idx_fn = reinterpret_cast<void*>(
            reinterpret_cast<std::uintptr_t>(core) + 0x2209A0);
        c6fw_log("lua_bridge: CfgByIdx(2209a0) legacy @ %p", g_cfg_by_idx_fn);
    }
}

// 按玩家槽位取 PlayerConfiguration*（正确版，见文件上方常量块注释）
void* player_config_by_slot(int slot) {
    if (!g_cfg_mgr_fn) {
        c6fw_log("C6FW cfg: manager accessor not resolved");
        return nullptr;
    }
    if (slot < 0 || slot >= kMaxPlayerSlot) {
        c6fw_log("C6FW cfg: bad slot %d", slot);
        return nullptr;
    }
    using MgrFn = void* (*)();
    void* mgr = reinterpret_cast<MgrFn>(g_cfg_mgr_fn)();
    if (!mgr) {
        c6fw_log("C6FW cfg: DAT_180b8aa78 is null (game not in a match?)");
        return nullptr;
    }
    void* base = *reinterpret_cast<void**>(
        reinterpret_cast<char*>(mgr) + kCfgArrayOff);
    if (!base) {
        c6fw_log("C6FW cfg: player-config array base is null");
        return nullptr;
    }
    return reinterpret_cast<char*>(base) + static_cast<std::size_t>(slot) * kCfgStride;
}

// PlayerConfigurations[i] 的 C++ 对象（GetInstance(L, idx, 0)，失败返回 null）
void* player_config_from_lua(void* L, int idx) {
    using GetInstanceFn = void* (*)(void*, int, int);
    GetInstanceFn fn = reinterpret_cast<GetInstanceFn>(g_get_instance_fn);
    if (!fn) {
        c6fw_log("C6FW player API: GetInstance not resolved (XP2 only?)");
        return nullptr;
    }
    return fn(L, idx, 0);
}

// C6FW.GetPlayerColor(playerConfig) -> number (nil on error)
int lua_get_player_color(void* L) {
    if (!g_pushint) return 0;
    void* cfg = player_config_from_lua(L, 1);
    if (!cfg) {
        c6fw_log("C6FW.GetPlayerColor: bad argument (PlayerConfigurations expected)");
        return 0;
    }
    using GetColorFn = unsigned (*)(void*);
    GetColorFn fn = reinterpret_cast<GetColorFn>(g_get_player_color_fn);
    if (!fn) {
        c6fw_log("C6FW.GetPlayerColor: getter not resolved (XP2 only?)");
        return 0;
    }
    unsigned v = fn(cfg);
    g_pushint(L, static_cast<int>(v));
    return 1;
}

// C6FW.SetPlayerColor(playerConfig, color) -> 1 (nil on error)
// 这是本桥的核心：颜色 setter 没有 Lua 包装，只能由 DLL 调。
int lua_set_player_color(void* L) {
    if (!g_tonumber || !g_pushint) return 0;
    void* cfg = player_config_from_lua(L, 1);
    if (!cfg) {
        c6fw_log("C6FW.SetPlayerColor: bad argument (PlayerConfigurations expected)");
        return 0;
    }
    using SetColorFn = void (*)(void*, unsigned);
    SetColorFn fn = reinterpret_cast<SetColorFn>(g_set_player_color_fn);
    if (!fn) {
        c6fw_log("C6FW.SetPlayerColor: setter not resolved (XP2 only?)");
        return 0;
    }
    unsigned before = 0;
    if (g_get_player_color_fn) {
        before = reinterpret_cast<unsigned (*)(void*)>(g_get_player_color_fn)(cfg);
    }
    unsigned v = static_cast<unsigned>(g_tonumber(L, 2));
    fn(cfg, v);
    unsigned after = 0;
    if (g_get_player_color_fn) {
        after = reinterpret_cast<unsigned (*)(void*)>(g_get_player_color_fn)(cfg);
    }
    c6fw_log("C6FW.SetPlayerColor: cfg=%p %u -> %u (asked %u)", cfg, before, after, v);
    g_pushint(L, 1);
    return 1;
}

// ---------------------------------------------------------------------------
// C6FW.GetPlayerColorBySlot(slot) -> number / nil     （只读，绝对安全）
// C6FW.SetPlayerColorBySlot(slot, color) -> 1 / nil
// C6FW.CopyPlayerColor(srcSlot, dstSlot) -> number / nil
// C6FW.ColorTypeIndex("COLOR_...") -> number / nil
//
//   ★ 2026-10-07 修正：**取配置对象的姿势以前是错的**（索引了文明表 → 卡死）。
//   现在统一走 player_config_by_slot()，即引擎自己的
//       cfg = *(void**)(DAT_180b8aa78 + 0x90) + slot * 0x20
//
//   颜色值语义（来自 FUN_180619a00 读 Players 表 Color 列）：
//       0xffffffff = 无效/未设      0 = UNDEFINED
//       其它       = FUN_180606270("COLOR_XXX") 得到的 ColorType 索引
// ---------------------------------------------------------------------------
int lua_get_player_color_by_slot(void* L) {
    if (!g_tonumber || !g_pushint) return 0;
    if (!g_cfg_mgr_fn || !g_get_player_color_fn) {
        c6fw_log("C6FW.GetPlayerColorBySlot: helpers not resolved (XP2 only?)");
        return 0;
    }
    int slot = static_cast<int>(g_tonumber(L, 1));
    void* cfg = player_config_by_slot(slot);
    if (!cfg) return 0;
    unsigned v = reinterpret_cast<unsigned (*)(void*)>(g_get_player_color_fn)(cfg);
    c6fw_log("C6FW.GetPlayerColorBySlot: slot %d cfg=%p color=%u", slot, cfg, v);
    g_pushint(L, static_cast<int>(v));
    return 1;
}

int lua_set_player_color_by_slot(void* L) {
    if (!g_tonumber || !g_pushint) return 0;
    if (!g_cfg_mgr_fn || !g_set_player_color_fn) {
        c6fw_log("C6FW.SetPlayerColorBySlot: helpers not resolved (XP2 only?)");
        return 0;
    }
    int slot = static_cast<int>(g_tonumber(L, 1));
    unsigned color = static_cast<unsigned>(g_tonumber(L, 2));
    void* cfg = player_config_by_slot(slot);
    if (!cfg) return 0;
    unsigned before = 0;
    if (g_get_player_color_fn) {
        before = reinterpret_cast<unsigned (*)(void*)>(g_get_player_color_fn)(cfg);
    }
    reinterpret_cast<void (*)(void*, unsigned)>(g_set_player_color_fn)(cfg, color);
    unsigned after = 0;
    if (g_get_player_color_fn) {
        after = reinterpret_cast<unsigned (*)(void*)>(g_get_player_color_fn)(cfg);
    }
    c6fw_log("C6FW.SetPlayerColorBySlot: slot %d cfg=%p %u -> %u (asked %u)",
             slot, cfg, before, after, color);
    g_pushint(L, static_cast<int>(after));
    return 1;
}

// 把 srcSlot 的颜色原样抄给 dstSlot —— 建邦后补色的主力接口。
int lua_copy_player_color(void* L) {
    if (!g_tonumber || !g_pushint) return 0;
    if (!g_cfg_mgr_fn || !g_get_player_color_fn || !g_set_player_color_fn) {
        c6fw_log("C6FW.CopyPlayerColor: helpers not resolved (XP2 only?)");
        return 0;
    }
    int src = static_cast<int>(g_tonumber(L, 1));
    int dst = static_cast<int>(g_tonumber(L, 2));
    void* cs = player_config_by_slot(src);
    void* cd = player_config_by_slot(dst);
    if (!cs || !cd) {
        c6fw_log("C6FW.CopyPlayerColor: src %d cfg=%p / dst %d cfg=%p", src, cs, dst, cd);
        return 0;
    }
    unsigned v = reinterpret_cast<unsigned (*)(void*)>(g_get_player_color_fn)(cs);
    reinterpret_cast<void (*)(void*, unsigned)>(g_set_player_color_fn)(cd, v);
    unsigned after = reinterpret_cast<unsigned (*)(void*)>(g_get_player_color_fn)(cd);
    c6fw_log("C6FW.CopyPlayerColor: %d(%p)=%u -> %d(%p)=%u",
             src, cs, v, dst, cd, after);
    g_pushint(L, static_cast<int>(after));
    return 1;
}

// "COLOR_STANDARD_RED" -> ColorType 索引（引擎自己的 FUN_180606270）
int lua_color_type_index(void* L) {
    if (!g_pushint) return 0;
    if (!g_str_to_type_fn) {
        c6fw_log("C6FW.ColorTypeIndex: StrToType not resolved (XP2 only?)");
        return 0;
    }
    std::string name;
    if (!lua_check_string(L, 1, &name) || name.empty()) {
        c6fw_log("C6FW.ColorTypeIndex: bad argument (string expected)");
        return 0;
    }
    unsigned v = reinterpret_cast<unsigned (*)(const char*)>(g_str_to_type_fn)(name.c_str());
    c6fw_log("C6FW.ColorTypeIndex: %s -> %u", name.c_str(), v);
    g_pushint(L, static_cast<int>(v));
    return 1;
}

// 前向声明：定义在下面的 CSF 激活桥一节里
void* game_player_from_slot(int slot);
void* g_civ_level_fn = nullptr;

// C6FW.GetCivLevelValue(slot) -> number
//   读该槽配置的「文明等级」属性值（引擎判定城邦用的就是它）。
//   CRC32 without final xor: FULL_CIV=0x253718b0, TRIBE=0xd959ec24,
//   FREE_CITIES=0x04e6b0a0, CITY_STATE=0xc2577075 (not the old labels).
int lua_get_civ_level_value(void* L) {
    if (!g_tonumber || !g_pushint) return 0;
    if (!g_civ_level_fn) {
        c6fw_log("C6FW.GetCivLevelValue: not resolved (XP2 only?)");
        return 0;
    }
    int slot = static_cast<int>(g_tonumber(L, 1));
    void* cfg = player_config_by_slot(slot);
    if (!cfg) return 0;
    unsigned v = 0;
    __try {
        v = reinterpret_cast<unsigned (*)(void*)>(g_civ_level_fn)(cfg);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.GetCivLevelValue: slot %d faulted", slot);
        return 0;
    }
    c6fw_log("C6FW.GetCivLevelValue: slot %d cfg=%p level=%u", slot, cfg, v);
    g_pushint(L, static_cast<int>(v));
    return 1;
}

// C6FW.GetPlayerField(slot, offset) -> number   读游戏侧玩家对象 player+offset 的 u32
int lua_get_player_field(void* L) {
    if (!g_tonumber || !g_pushint) return 0;
    int slot = static_cast<int>(g_tonumber(L, 1));
    int off = static_cast<int>(g_tonumber(L, 2));
    if (off < 0 || off > 0x2000) {
        c6fw_log("C6FW.GetPlayerField: bad offset %d", off);
        return 0;
    }
    void* player = game_player_from_slot(slot);
    if (!player) {
        c6fw_log("C6FW.GetPlayerField: slot %d has no player", slot);
        return 0;
    }
    unsigned v = 0;
    __try {
        v = *reinterpret_cast<unsigned*>(reinterpret_cast<char*>(player) + off);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.GetPlayerField: slot %d off %#x faulted", slot, off);
        return 0;
    }
    c6fw_log("C6FW.GetPlayerField: slot %d +%#x = %u", slot, off, v);
    g_pushint(L, static_cast<int>(v));
    return 1;
}

// C6FW.GetPlayerHighWater(slot) -> {a0=number,b8=number,d0=number}/nil
// Read-only capture of the three monotonic fields updated by the official
// Barbarian Clans post-activation tracker FUN_180623750.  The player owns a
// pointer at +0x710; its fields are read under SEH so a missing subsystem
// cannot become a false success or crash the Lua VM.
int lua_get_player_high_water(void* L) {
    if (!g_pushint || !g_createtable || !g_setfield || !g_tonumber) return 0;
    int slot = static_cast<int>(g_tonumber(L, 1));
    void* player = game_player_from_slot(slot);
    if (!player) return 0;
    std::uintptr_t highWater = 0;
    unsigned a0 = 0, b8 = 0, d0 = 0;
    __try {
        highWater = *reinterpret_cast<std::uintptr_t*>(
            reinterpret_cast<char*>(player) + 0x710);
        if (!highWater) return 0;
        a0 = *reinterpret_cast<unsigned*>(highWater + 0xA0);
        b8 = *reinterpret_cast<unsigned*>(highWater + 0xB8);
        d0 = *reinterpret_cast<unsigned*>(highWater + 0xD0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.GetPlayerHighWater: slot %d read fault code=0x%08X",
                 slot, static_cast<unsigned>(GetExceptionCode()));
        return 0;
    }
    g_createtable(L, 0, 3);
    g_pushint(L, static_cast<int>(a0));
    g_setfield(L, -2, "a0");
    g_pushint(L, static_cast<int>(b8));
    g_setfield(L, -2, "b8");
    g_pushint(L, static_cast<int>(d0));
    g_setfield(L, -2, "d0");
    c6fw_log("C6FW.GetPlayerHighWater: slot %d a0=%u b8=%u d0=%u",
             slot, a0, b8, d0);
    return 1;
}

extern void* g_slot_status_fn;
extern void* g_set_leader_type_fn;
extern void* g_set_civilization_type_fn;
extern void* g_refresh_identity_fn;
extern void* g_set_civ_level_fn;
extern void* g_set_slot_status_fn;
extern void* g_set_civ_short_text_fn;
extern void* g_set_civ_long_text_fn;
extern void* g_set_civ_adjective_fn;

bool native_set_city_state_identity_text(void* cfg, const char* shortText,
                                         const char* longText, const char* adjective) {
    if (!cfg || !g_civ_level_fn || !g_set_civ_short_text_fn ||
        !g_set_civ_long_text_fn || !g_set_civ_adjective_fn) return false;
    __try {
        if (reinterpret_cast<unsigned (*)(void*)>(g_civ_level_fn)(cfg) != 0xc2577075u)
            return false;
        using SetText = void (*)(void*, const char*);
        reinterpret_cast<SetText>(g_set_civ_short_text_fn)(cfg, shortText);
        reinterpret_cast<SetText>(g_set_civ_long_text_fn)(cfg, longText);
        reinterpret_cast<SetText>(g_set_civ_adjective_fn)(cfg, adjective);
        return true; // Caller must read the actual configuration back.
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// These are the official configuration string setters, not player identity
// retargeting. Only city-state-level configurations accept text updates.
int lua_set_city_state_identity_text(void* L) {
    if (!g_tonumber || !g_pushint || !g_gettop || g_gettop(L) < 4) return 0;
    int slot = static_cast<int>(g_tonumber(L, 1));
    if (slot < 0 || slot >= 62) return 0;
    std::string shortText, longText, adjective;
    if (!lua_check_string(L, 2, &shortText) || shortText.empty() ||
        !lua_check_string(L, 3, &longText) || longText.empty() ||
        !lua_check_string(L, 4, &adjective) || adjective.empty()) return 0;
    if (!native_set_city_state_identity_text(player_config_by_slot(slot),
                                            shortText.c_str(), longText.c_str(), adjective.c_str())) return 0;
    g_pushint(L, 1);
    return 1;
}

bool native_prepare_player_identity(void* cfg, int slot,
                                    const char* civilization, const char* leader,
                                    unsigned expectedStatus = 5u) {
    if (!cfg || !civilization || !leader || !g_slot_status_fn ||
        !g_set_leader_type_fn || !g_set_civilization_type_fn ||
        !g_refresh_identity_fn) {
        return false;
    }
    __try {
        const unsigned status = reinterpret_cast<unsigned (*)(void*)>(g_slot_status_fn)(cfg);
        if (status != expectedStatus) {
            c6fw_log("C6FW.PreparePlayerIdentity: slot %d rejected: native status=%u (need %u)",
                     slot, status, expectedStatus);
            return false;
        }
        using SetIdentityFn = void (*)(void*, const char*);
        using RefreshIdentityFn = void (*)(void*);
        reinterpret_cast<SetIdentityFn>(g_set_leader_type_fn)(cfg, leader);
        reinterpret_cast<SetIdentityFn>(g_set_civilization_type_fn)(cfg, civilization);
        reinterpret_cast<RefreshIdentityFn>(g_refresh_identity_fn)(cfg);
        const unsigned afterStatus = reinterpret_cast<unsigned (*)(void*)>(g_slot_status_fn)(cfg);
        if (afterStatus != expectedStatus) {
            c6fw_log("C6FW.PreparePlayerIdentity: slot %d refresh changed native status to %u",
                     slot, afterStatus);
            return false;
        }
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.PreparePlayerIdentity: slot %d native identity sequence faulted", slot);
        return false;
    }
}

// C6FW.PreparePlayerIdentity(slot, civilization_type, leader_type) -> 1/nil
//
// This is deliberately a preparation step, not an activation shortcut.  It
// only accepts a dormant native slot (status 5, no game-side Player object),
// then follows the order used by the official random identity selector:
// leader setter -> civilization setter -> configuration refresh.  It does
// not register a player, publish alive, rebuild lists, or claim that a
// duplicate civilization is valid.  The caller must run ActivatePlayer and
// the normal snapshot gates afterwards.
int lua_prepare_player_identity(void* L) {
    if (!g_tonumber || !g_pushint || !g_gettop || g_gettop(L) < 3 ||
        !g_set_leader_type_fn || !g_set_civilization_type_fn ||
        !g_refresh_identity_fn || !g_slot_status_fn) {
        c6fw_log("C6FW.PreparePlayerIdentity: identity helpers unavailable or arguments missing");
        return 0;
    }
    const int slot = static_cast<int>(g_tonumber(L, 1));
    std::string civilization;
    std::string leader;
    if (!lua_check_string(L, 2, &civilization) || civilization.empty() ||
        !lua_check_string(L, 3, &leader) || leader.empty()) {
        c6fw_log("C6FW.PreparePlayerIdentity: slot %d requires non-empty civilization and leader strings", slot);
        return 0;
    }
    if (slot < 0 || slot >= kMaxPlayerSlot) {
        c6fw_log("C6FW.PreparePlayerIdentity: bad slot %d", slot);
        return 0;
    }
    void* cfg = player_config_by_slot(slot);
    if (!cfg) return 0;
    if (game_player_from_slot(slot)) {
        c6fw_log("C6FW.PreparePlayerIdentity: slot %d already has a game-side player", slot);
        return 0;
    }

    if (!native_prepare_player_identity(cfg, slot, civilization.c_str(), leader.c_str())) return 0;
    c6fw_log("C6FW.PreparePlayerIdentity: slot %d leader=%s civilization=%s prepared while dormant",
             slot, leader.c_str(), civilization.c_str());
    g_pushint(L, 1);
    return 1;
}

// Closed slots in a zero-minor game have no identity or game-side Player.
// Configure them BEFORE registration, using the level setter called by the
// official WorldBuilder identity command (0x617CA0 -> 0x16B1B0).  In contrast
// to that command, do not call its automatic InitializePlayer in the middle
// of identity editing.  Activation remains a separate checked transaction.
bool native_prepare_closed_city_state(void* cfg, int slot,
                                     const char* civilization, const char* leader) {
    if (!cfg || !g_set_civ_level_fn || !g_set_slot_status_fn ||
        !g_civ_level_fn || !g_slot_status_fn) return false;
    unsigned status = 0, level = 0;
    __try {
        status = reinterpret_cast<unsigned (*)(void*)>(g_slot_status_fn)(cfg);
        level = reinterpret_cast<unsigned (*)(void*)>(g_civ_level_fn)(cfg);
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    if (status != 2u || level != 0u) {
        c6fw_log("C6FW.PrepareClosedCityState: slot %d rejected status=%u level=%u",
                 slot, status, level);
        return false;
    }
    if (!native_prepare_player_identity(cfg, slot, civilization, leader, 2u))
        return false;
    __try {
        using Setter = void (*)(void*, const char*);
        reinterpret_cast<Setter>(g_set_civ_level_fn)(cfg, "CIVILIZATION_LEVEL_CITY_STATE");
        level = reinterpret_cast<unsigned (*)(void*)>(g_civ_level_fn)(cfg);
        if (level != 0xc2577075u) return false;
        reinterpret_cast<void (*)(void*, int)>(g_set_slot_status_fn)(cfg, 5);
        status = reinterpret_cast<unsigned (*)(void*)>(g_slot_status_fn)(cfg);
        if (status != 5u) return false;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.PrepareClosedCityState: slot %d failed after identity preparation", slot);
        return false;
    }
    c6fw_log("C6FW.PrepareClosedCityState: slot %d configured as dormant city-state; no player registered", slot);
    return true;
}

int lua_prepare_closed_city_state(void* L) {
    if (!g_tonumber || !g_pushint || !g_gettop || g_gettop(L) < 3) return 0;
    const int slot = static_cast<int>(g_tonumber(L, 1));
    if (slot < 0 || slot >= 62 || game_player_from_slot(slot)) return 0;
    std::string civilization, leader;
    if (!lua_check_string(L, 2, &civilization) || civilization.empty() ||
        !lua_check_string(L, 3, &leader) || leader.empty()) return 0;
    if (!native_prepare_closed_city_state(player_config_by_slot(slot), slot,
                                          civilization.c_str(), leader.c_str())) return 0;
    g_pushint(L, 1);
    return 1;
}

// C6FW.GetNativeSlotStatus(slot) -> integer / nil
// Read the same SlotConfig property consumed by the official clan scanner
// (0x16A2B0), so runtime acceptance can compare native state with the Lua
// PlayerManager view without mutating the slot.
int lua_get_native_slot_status(void* L) {
    if (!g_tonumber || !g_pushint || !g_slot_status_fn) return 0;
    const int slot = static_cast<int>(g_tonumber(L, 1));
    void* cfg = player_config_by_slot(slot);
    if (!cfg) return 0;
    unsigned value = 0xffffffffu;
    __try {
        value = reinterpret_cast<unsigned (*)(void*)>(g_slot_status_fn)(cfg);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.GetNativeSlotStatus: slot %d read faulted", slot);
        return 0;
    }
    g_pushint(L, static_cast<int>(value));
    return 1;
}

// ---------------------------------------------------------------------------
// CSF 玩家激活桥（2026-10-04，第二轮）
// ---------------------------------------------------------------------------
// CSF registration bridge aligned with the statically recovered official clan
// conversion sequence. The later clan-specific tail and business acceptance
// remain separate; a return value certifies only the checked native steps here.
// RegisterPlayer(0x3077C0) invokes initialization(0x2F8450), which sets +0x83a.
// 0x2F9350 is conditional: early returns at 0x2F9360/0x2F9372 precede its
// subsystem calls. Its normal return alone does not prove initialization.
// Native SetAlive/rebuild is used; the old manual list/alive writes are gone.
// C6FW.ActivatePlayer(slot) -> 1/nil reports only this bridge's checked steps.
// C6FW.HasGamePlayer(slot) -> 1/nil reports object presence only.
#if defined(C6FW_VARIANT) && C6FW_VARIANT == 2  // xp2
constexpr uintptr_t kGameObjGetterRva  = 0x306B80;  // FUN_180306b80() -> 游戏对象（返回 DAT_180b8e140）
constexpr uintptr_t kActivatePlayerRva = 0x2F9350;  // conditional subsystem routine; verified input is Player*
constexpr uintptr_t kRegisterPlayerRva = 0x3077C0;  // FUN_1803077c0(游戏对象, &结构体) 创建+初始化玩家
constexpr uintptr_t kPublishPlayerReadyRva = 0x226E80; // official startup + clans +0x8E8 notification
constexpr uintptr_t kGameContextPointerRva = 0xB8AA68;
constexpr uintptr_t kSetAliveRebuildRva = 0x2FA9A0; // FUN_1802FA9A0(player, alive) + rebuild 23 lists
constexpr uintptr_t kSlotStatusRva    = 0x16A2B0;  // FUN_18016A2B0(cfg) -> native dormant-slot status
constexpr uintptr_t kSetSlotStatusRva = 0x16B840;  // FUN_18016B840(cfg, status)
constexpr uintptr_t kInitializedRva   = 0x2F9850;  // FUN_1802F9850(player) -> +0x83A gate
constexpr uintptr_t kClanIndexSourceRva = 0x1E5460; // FUN_1801E5460() -> official clan context entry
constexpr uintptr_t kDefaultTypeIndexRva = 0x64E6C0; // official clan fallback: default type index
constexpr uintptr_t kSetStartPositionRva = 0x2FAB60; // FUN_1802FAB60(player+0x778, player, xy)
constexpr uintptr_t kNativeCityCreateRva = 0x2649F0; // FUN_1802649F0(cityManager,args,xy,flag)
constexpr uintptr_t kEmptyBasicStringRva = 0x993B30; // EXP_GetEmptyBasicString()
constexpr uintptr_t kBasicStringAssignRva = 0x993700; // FUN_180993700(&resident, text)
constexpr uintptr_t kSetPlayerFieldRva = 0x2F9500;  // FUN_1802f9500(玩家对象) 事件订阅接线（转发 FUN_1802D6C40）
constexpr uintptr_t kTurnTaskAssemblyRva = 0x401FA0; // FUN_180401FA0(*(Player+0x6B0)) 回合任务/事件装配
// ⑥ 注册到子系统表（漏了这步 → InitUnit 会让游戏退出）
constexpr uintptr_t kCtxDefaultRva     = 0x164FF0;  // FUN_180164ff0(上下文) -> 默认索引
constexpr uintptr_t kSubsysSetRva      = 0x2C9B10;  // FUN_1802c9b10(子系统, 索引)
// ⑦ 加入玩家列表
constexpr uintptr_t kCheckARva         = 0x2F9790;  // FUN_1802f9790(玩家) -> bool
constexpr uintptr_t kPlayerListAGetRva = 0x0E31A0;  // legacy player-list accessor; same RVA as clans manager getter
constexpr uintptr_t kListAAddRva       = 0x0E4770;  // FUN_1800e4770(列表, 玩家)
constexpr uintptr_t kCheckBRva         = 0x2F97F0;  // FUN_1802f97f0(玩家) -> bool
constexpr uintptr_t kListBGetRva       = 0x1AD310;  // FUN_1801ad310() -> 列表
constexpr uintptr_t kListBAddRva       = 0x1AD430;  // FUN_1801ad430(列表, 玩家)
// Official Lua GetHandicapTypeID calls 0x169EE0. This record field is
// HANDICAP, not civilization or Player+0xd8. Startup normalizes it through
// the +0x948 table; clans passes the configuration value directly.
constexpr uintptr_t kHandicapTypeRva         = 0x169EE0;  // PlayerConfiguration.GetHandicapTypeID backend
constexpr uintptr_t kHandicapTableRva       = 0x7D0780;  // startup handicap normalization table (+0x948)
// ★ 2026-10-07【文明等级属性】—— 引擎判定"是不是城邦"读的就是它：
//   FUN_180169cd0(config) = 读配置属性 DAT_180b8d61c，返回其值（+8）
//   0x2f9790 compares TRIBE; 0x2f97f0 compares FREE_CITIES, not CITY_STATE.
//   注意：这个值**不是** FUN_180606270 那套字符串哈希，两套不通，只能直接读来比。
constexpr uintptr_t kCivLevelRva       = 0x169CD0;  // FUN_180169cd0(配置) -> 文明等级值
// Official random identity selector helpers.  These mutate a dormant
// PlayerConfiguration; they are intentionally separate from ActivatePlayer.
constexpr uintptr_t kSetLeaderTypeRva       = 0x16B660; // FUN_18016B660(cfg, LeaderType)
constexpr uintptr_t kSetCivilizationTypeRva = 0x16B280; // FUN_18016B280(cfg, CivilizationType)
constexpr uintptr_t kRefreshIdentityRva     = 0x16ABC0; // FUN_18016ABC0(cfg)
constexpr uintptr_t kSetCivLevelRva         = 0x16B1B0; // WorldBuilder level string + hash setter
constexpr uintptr_t kSetCivShortTextRva     = 0x16B260; // CIVILIZATION_SHORT_DESCRIPTION
constexpr uintptr_t kSetCivLongTextRva      = 0x16B190; // CIVILIZATION_DESCRIPTION
constexpr uintptr_t kSetCivAdjectiveRva    = 0x16ABA0; // CIVILIZATION_ADJECTIVE
// Official Barbarian Clans conversion chain (XP2).  The game calls this from
// ClansManager::DoTurnActivate: manager getter -> tribe entry -> conversion
// worker.  It performs the player publication, identity/state preparation,
// city creation and post-conversion cleanup as one engine-owned transaction.
constexpr uintptr_t kClansManagerGetterRva  = 0x0E31A0; // FUN_1800E31A0()
constexpr uintptr_t kClansTribeAtIndexRva   = 0x0E3200; // FUN_1800E3200(manager, index)
constexpr uintptr_t kClansConvertRva        = 0x61FDD0; // FUN_18061FDD0(manager, tribe, aux, count)
#else
constexpr uintptr_t kGameObjGetterRva  = 0;
constexpr uintptr_t kActivatePlayerRva = 0;
constexpr uintptr_t kRegisterPlayerRva = 0;
constexpr uintptr_t kPublishPlayerReadyRva = 0;
constexpr uintptr_t kGameContextPointerRva = 0;
constexpr uintptr_t kSetAliveRebuildRva = 0;
constexpr uintptr_t kSlotStatusRva    = 0;
constexpr uintptr_t kSetSlotStatusRva = 0;
constexpr uintptr_t kInitializedRva   = 0;
constexpr uintptr_t kClanIndexSourceRva = 0;
constexpr uintptr_t kDefaultTypeIndexRva = 0;
constexpr uintptr_t kSetStartPositionRva = 0;
constexpr uintptr_t kNativeCityCreateRva = 0;
constexpr uintptr_t kEmptyBasicStringRva = 0;
constexpr uintptr_t kBasicStringAssignRva = 0;
constexpr uintptr_t kSetPlayerFieldRva = 0;
constexpr uintptr_t kTurnTaskAssemblyRva = 0;
constexpr uintptr_t kCtxDefaultRva     = 0;
constexpr uintptr_t kSubsysSetRva      = 0;
constexpr uintptr_t kCheckARva         = 0;
constexpr uintptr_t kPlayerListAGetRva = 0;
constexpr uintptr_t kListAAddRva       = 0;
constexpr uintptr_t kCheckBRva         = 0;
constexpr uintptr_t kListBGetRva       = 0;
constexpr uintptr_t kListBAddRva       = 0;
constexpr uintptr_t kHandicapTypeRva         = 0;
constexpr uintptr_t kHandicapTableRva       = 0;
constexpr uintptr_t kCivLevelRva       = 0;
constexpr uintptr_t kSetLeaderTypeRva       = 0;
constexpr uintptr_t kSetCivilizationTypeRva = 0;
constexpr uintptr_t kRefreshIdentityRva     = 0;
constexpr uintptr_t kSetCivLevelRva         = 0;
constexpr uintptr_t kSetCivShortTextRva     = 0;
constexpr uintptr_t kSetCivLongTextRva      = 0;
constexpr uintptr_t kSetCivAdjectiveRva    = 0;
constexpr uintptr_t kClansManagerGetterRva  = 0;
constexpr uintptr_t kClansTribeAtIndexRva   = 0;
constexpr uintptr_t kClansConvertRva        = 0;
#endif

void* g_game_obj_getter_fn   = nullptr;
void* g_publish_player_ready_fn = nullptr;
void* g_game_context_pointer = nullptr;
void* g_activate_player_fn   = nullptr;
void* g_register_player_fn   = nullptr;
void* g_set_alive_rebuild_fn = nullptr;
void* g_slot_status_fn       = nullptr;
void* g_set_slot_status_fn   = nullptr;
void* g_initialized_fn       = nullptr;
void* g_clan_index_source_fn = nullptr;
void* g_default_type_index_fn = nullptr;
void* g_set_start_position_fn = nullptr;
void* g_native_city_create_fn = nullptr;
void* g_empty_basic_string_fn = nullptr;
void* g_basic_string_assign_fn = nullptr;
void* g_set_player_field_fn  = nullptr;
void* g_turn_task_assembly_fn = nullptr;
void* g_ctx_default_fn       = nullptr;
void* g_subsys_set_fn        = nullptr;
void* g_check_a_fn           = nullptr;
void* g_handicap_type_fn           = nullptr;
void* g_handicap_table_fn         = nullptr;
void* g_list_a_get_fn        = nullptr;
void* g_list_a_add_fn        = nullptr;
void* g_check_b_fn           = nullptr;
void* g_list_b_get_fn        = nullptr;
void* g_list_b_add_fn        = nullptr;
void* g_set_leader_type_fn       = nullptr;
void* g_set_civilization_type_fn = nullptr;
void* g_refresh_identity_fn      = nullptr;
void* g_set_civ_level_fn         = nullptr;
void* g_set_civ_short_text_fn    = nullptr;
void* g_set_civ_long_text_fn     = nullptr;
void* g_set_civ_adjective_fn     = nullptr;
void* g_clans_manager_getter_fn  = nullptr;
void* g_clans_tribe_at_index_fn  = nullptr;
void* g_clans_convert_fn         = nullptr;
bool g_clans_diagnostic_ready     = false;

bool native_signature_matches(void* address, const unsigned char* expected,
                              std::size_t size) {
    if (!address || !expected || !size) return false;
    __try {
        return std::memcmp(address, expected, size) == 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

// The official status setter runs before player registration. If a later
// checked step fails, restore only the SlotConfig status; never attempt an
// alive=0 or UninitializePlayer rollback on a partially-created Player.
int restore_slot_status_after_failure(void* cfg, int slot) {
    if (!cfg || !g_set_slot_status_fn || !g_slot_status_fn) return 0;
    __try {
        using SetSlotStatusFn = void (*)(void*, int);
        reinterpret_cast<SetSlotStatusFn>(g_set_slot_status_fn)(cfg, 5);
        const unsigned status = reinterpret_cast<unsigned (*)(void*)>(g_slot_status_fn)(cfg);
        c6fw_log("C6FW.ActivatePlayer: slot %d failure isolation restored native status=%u",
                 slot, status);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.ActivatePlayer: slot %d failure isolation status restore faulted", slot);
    }
    return 0;
}

int preserve_active_slot_after_failure(void* cfg, int slot) {
    unsigned observedStatus = 0xffffffffu;
    if (cfg && g_slot_status_fn) {
        __try {
            observedStatus = reinterpret_cast<unsigned (*)(void*)>(g_slot_status_fn)(cfg);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            observedStatus = 0xfffffffeu;
        }
    }
    c6fw_log("C6FW.ActivatePlayer: slot %d failed after native alive/rebuild; preserving status=%u (expected 1) and isolating slot",
             slot, observedStatus);
    return 0;
}

int fail_activate_after_stage(void* cfg, int slot, bool alivePublished) {
    return alivePublished
        ? preserve_active_slot_after_failure(cfg, slot)
        : restore_slot_status_after_failure(cfg, slot);
}

void resolve_csf_activate_helpers(HMODULE core) {
    if (!core) return;
    if (kActivatePlayerRva == 0) {
        c6fw_log("lua_bridge: player-activate bridge skipped (XP2 only)");
        return;
    }
    auto rva = [core](uintptr_t r) -> void* {
        return reinterpret_cast<void*>(reinterpret_cast<std::uintptr_t>(core) + r);
    };
    if (!g_game_obj_getter_fn) {
        g_game_obj_getter_fn = rva(kGameObjGetterRva);
        c6fw_log("lua_bridge: GameObjGetter resolved @ %p", g_game_obj_getter_fn);
    }
    if (!g_register_player_fn) {
        g_register_player_fn = rva(kRegisterPlayerRva);
        c6fw_log("lua_bridge: RegisterPlayer resolved @ %p", g_register_player_fn);
    }
    g_publish_player_ready_fn = rva(kPublishPlayerReadyRva);
    g_game_context_pointer = rva(kGameContextPointerRva);
    static const unsigned char publishReadySig[] = {
        0x40,0x53,0x55,0x41,0x56,0x48,0x83,0xEC,0x20,0x48,0x8B,0x59,0x08,0x4C,0x8B,0xF2};
    if (!native_signature_matches(g_publish_player_ready_fn,publishReadySig,sizeof(publishReadySig))) {
        g_publish_player_ready_fn=nullptr;
        g_game_context_pointer=nullptr;
    }
    if (!g_set_alive_rebuild_fn) {
        g_set_alive_rebuild_fn = rva(kSetAliveRebuildRva);
        c6fw_log("lua_bridge: SetAliveAndRebuild resolved @ %p", g_set_alive_rebuild_fn);
    }
    if (!g_slot_status_fn) g_slot_status_fn = rva(kSlotStatusRva);
    if (!g_set_slot_status_fn) g_set_slot_status_fn = rva(kSetSlotStatusRva);
    if (!g_initialized_fn) g_initialized_fn = rva(kInitializedRva);
    if (!g_clan_index_source_fn) g_clan_index_source_fn = rva(kClanIndexSourceRva);
    if (!g_default_type_index_fn) g_default_type_index_fn = rva(kDefaultTypeIndexRva);
    if (!g_set_start_position_fn) g_set_start_position_fn = rva(kSetStartPositionRva);
    if (!g_native_city_create_fn) g_native_city_create_fn = rva(kNativeCityCreateRva);
    if (!g_empty_basic_string_fn) g_empty_basic_string_fn = rva(kEmptyBasicStringRva);
    if (!g_basic_string_assign_fn) g_basic_string_assign_fn = rva(kBasicStringAssignRva);
    if (!g_set_player_field_fn) {
        g_set_player_field_fn = rva(kSetPlayerFieldRva);
        c6fw_log("lua_bridge: SetPlayerField resolved @ %p", g_set_player_field_fn);
    }
    // FUN_180401FA0 assembles the per-player turn-task/event subscriptions.
    // The expected bytes below were read from the pinned XP2 DLL on disk
    // (SHA256 324c51e9ea3531758842e16c69e6cddbefbb226c5b675c3d6e60111646c2e98c,
    // RVA 0x401FA0, pefile .text mapping), not guessed from the decompiler.
    // A reissued GameCore must fail closed instead of calling a nearby function.
    if (!g_turn_task_assembly_fn) {
        g_turn_task_assembly_fn = rva(kTurnTaskAssemblyRva);
    }
    static const unsigned char kTurnTaskAssemblySignature[] = {
        0x4C, 0x8B, 0xDC, 0x49, 0x89, 0x7B, 0x20, 0x55,
        0x48, 0x8B, 0xEC, 0x48, 0x83, 0xEC, 0x70, 0x48,
        0x8B, 0x81, 0x90, 0x00, 0x00, 0x00, 0x48, 0x8B,
        0xF9, 0x48, 0x85, 0xC0, 0x0F, 0x84, 0x80, 0x0C,
        0x00, 0x00, 0x48, 0x8B, 0x80, 0x50, 0x06, 0x00,
        0x00, 0x48, 0x8D, 0x4D, 0xC0, 0x48, 0x89, 0x45};
    if (!native_signature_matches(g_turn_task_assembly_fn,
                                  kTurnTaskAssemblySignature,
                                  sizeof(kTurnTaskAssemblySignature))) {
        c6fw_log("lua_bridge: turn-task assembly 0x401FA0 signature mismatch; InitializeCityStateTurnTasks disabled");
        g_turn_task_assembly_fn = nullptr;
    } else {
        c6fw_log("lua_bridge: turn-task assembly 0x401FA0 verified @ %p",
                 g_turn_task_assembly_fn);
    }
    if (!g_activate_player_fn) {
        g_activate_player_fn = rva(kActivatePlayerRva);
        c6fw_log("lua_bridge: ActivatePlayer resolved @ %p", g_activate_player_fn);
    }
    // ⑥⑦ 收尾两步（漏了会让 InitUnit 崩）
    if (!g_ctx_default_fn)    g_ctx_default_fn    = rva(kCtxDefaultRva);
    if (!g_subsys_set_fn)     g_subsys_set_fn     = rva(kSubsysSetRva);
    if (!g_check_a_fn)        g_check_a_fn        = rva(kCheckARva);
    if (!g_list_a_get_fn)     g_list_a_get_fn     = rva(kPlayerListAGetRva);
    if (!g_list_a_add_fn)     g_list_a_add_fn     = rva(kListAAddRva);
    if (!g_check_b_fn)        g_check_b_fn        = rva(kCheckBRva);
    if (!g_list_b_get_fn)     g_list_b_get_fn     = rva(kListBGetRva);
    if (!g_list_b_add_fn)     g_list_b_add_fn     = rva(kListBAddRva);
    if (!g_handicap_type_fn)        g_handicap_type_fn        = rva(kHandicapTypeRva);
    if (!g_handicap_table_fn)      g_handicap_table_fn      = rva(kHandicapTableRva);
    if (!g_civ_level_fn)      g_civ_level_fn      = rva(kCivLevelRva);
    if (!g_set_leader_type_fn)       g_set_leader_type_fn       = rva(kSetLeaderTypeRva);
    if (!g_set_civilization_type_fn) g_set_civilization_type_fn = rva(kSetCivilizationTypeRva);
    if (!g_refresh_identity_fn)      g_refresh_identity_fn      = rva(kRefreshIdentityRva);
    if (!g_set_civ_level_fn)         g_set_civ_level_fn          = rva(kSetCivLevelRva);
    if (!g_set_civ_short_text_fn)    g_set_civ_short_text_fn     = rva(kSetCivShortTextRva);
    if (!g_set_civ_long_text_fn)     g_set_civ_long_text_fn      = rva(kSetCivLongTextRva);
    if (!g_set_civ_adjective_fn)     g_set_civ_adjective_fn      = rva(kSetCivAdjectiveRva);
    if (!g_clans_manager_getter_fn)  g_clans_manager_getter_fn  = rva(kClansManagerGetterRva);
    if (!g_clans_tribe_at_index_fn)  g_clans_tribe_at_index_fn  = rva(kClansTribeAtIndexRva);
    if (!g_clans_convert_fn)         g_clans_convert_fn         = rva(kClansConvertRva);

    // These three new calls are guarded by byte signatures from the pinned
    // XP2 disassembly. A changed game build fails closed instead of invoking
    // a nearby function with a compatible-looking address.
    static const unsigned char kSetAliveSignature[] = {
        0x48, 0x89, 0x5C, 0x24, 0x10, 0x48, 0x89, 0x74,
        0x24, 0x18, 0x57, 0x48, 0x83, 0xEC};
    static const unsigned char kClanIndexSignature[] = {
        0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x8B, 0x1D,
        0x74, 0xE7, 0x97, 0x00, 0xE8, 0xDF};
    static const unsigned char kDefaultTypeIndexSignature[] = {
        0x48, 0x89, 0x5C, 0x24, 0x08, 0x57, 0x48, 0x83,
        0xEC, 0x20, 0x83, 0xCF, 0xFF, 0xBB};
    static const unsigned char kSlotStatusSignature[] = {
        0x48, 0x83, 0xEC, 0x28, 0x48, 0x8B, 0x49, 0x10,
        0x8B, 0x15, 0xAA, 0x33, 0xA2, 0x00};
    static const unsigned char kSetSlotStatusSignature[] = {
        0x48, 0x89, 0x5C, 0x24, 0x08, 0x57, 0x48, 0x83,
        0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x8B, 0xFA};
    static const unsigned char kInitializedSignature[] = {
        0x0F, 0xB6, 0x81, 0x3A, 0x08, 0x00, 0x00, 0xC3};
    static const unsigned char kStartPositionSignature[] = {
        0x40, 0x53, 0x56, 0x41, 0x56, 0x48, 0x83, 0xEC,
        0x20, 0x48, 0x8B, 0xDA, 0x4C, 0x8B};
    // FUN_1802649F0(cityManager,args,xy,flag).  The relative call target
    // is intentionally excluded; the prologue and argument moves are stable.
    static const unsigned char kNativeCityCreateSignature[] = {
        0x48, 0x89, 0x5C, 0x24, 0x10, 0x48, 0x89, 0x74,
        0x24, 0x18, 0x57, 0x41, 0x56, 0x41, 0x57, 0x48,
        0x83, 0xEC, 0x40, 0x45, 0x0F, 0xB6, 0xF9, 0x49,
        0x8B, 0xF0, 0x4C, 0x8B, 0xF2, 0x48, 0x8B, 0xF9};
    static const unsigned char kEmptyBasicStringSignature[] = {
        0x48, 0x83, 0xEC, 0x28, 0x65, 0x48, 0x8B, 0x04,
        0x25, 0x58, 0x00, 0x00, 0x00};
    static const unsigned char kBasicStringAssignSignature[] = {
        0x48, 0x89, 0x5C, 0x24, 0x18, 0x48, 0x89, 0x74,
        0x24, 0x20, 0x57, 0x48, 0x83, 0xEC, 0x20, 0x48,
        0x8B, 0xF2, 0x48, 0x8B, 0xF9, 0x48, 0x85, 0xD2};
    static const unsigned char kIdentitySetterSignature[] = {
        0x48, 0x89, 0x74, 0x24, 0x10, 0x57, 0x48, 0x83,
        0xEC, 0x20, 0x48, 0x8B, 0xFA, 0x48, 0x8B, 0xF1};
    static const unsigned char kIdentityRefreshSignature[] = {
        0x48, 0x89, 0x5C, 0x24, 0x18, 0x48, 0x89, 0x74,
        0x24, 0x20, 0x57, 0x41, 0x54, 0x41, 0x55, 0x41,
        0x56, 0x41, 0x57, 0x48};
    // FUN_18061FDD0 (official clan conversion worker).  The first conditional
    // branch is stable in the pinned XP2 build; relative calls are excluded.
    static const unsigned char kClansConvertSignature[] = {
        0x48, 0x85, 0xD2, 0x0F, 0x84, 0xBA, 0x05, 0x00,
        0x00, 0x48, 0x89};
    // The getter and indexed-tribe accessor are also version-gated.  They
    // are read-only lookups, but invoking a nearby function on a reissued
    // GameCore would still make the diagnostic bridge unsafe.
    static const unsigned char kClansManagerGetterSignature[] = {
        0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x8B, 0x1D,
        0x14, 0xF9, 0xA7, 0x00, 0xE8, 0x9F, 0xE3, 0x86,
        0x00, 0x4C, 0x8B, 0x40, 0x08};
    static const unsigned char kClansTribeAtIndexSignature[] = {
        0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x63,
        0xDA, 0x85, 0xD2, 0x78, 0x27, 0x3B, 0x99, 0x88,
        0x01, 0x00, 0x00, 0x7D, 0x1F, 0x48, 0x81, 0xC1,
        0x68, 0x01, 0x00, 0x00, 0xE8, 0xFF, 0x76, 0x64};
    if (!native_signature_matches(g_set_alive_rebuild_fn, kSetAliveSignature,
                                  sizeof(kSetAliveSignature))) {
        c6fw_log("lua_bridge: SetAliveAndRebuild signature mismatch; disabling native clans path");
        g_set_alive_rebuild_fn = nullptr;
    }
    if (!native_signature_matches(g_clan_index_source_fn, kClanIndexSignature,
                                  sizeof(kClanIndexSignature))) {
        c6fw_log("lua_bridge: ClanIndexSource signature mismatch; disabling native clans path");
        g_clan_index_source_fn = nullptr;
    }
    if (!native_signature_matches(g_default_type_index_fn, kDefaultTypeIndexSignature,
                                  sizeof(kDefaultTypeIndexSignature))) {
        c6fw_log("lua_bridge: DefaultTypeIndex signature mismatch; disabling native clans path");
        g_default_type_index_fn = nullptr;
    }
    if (!native_signature_matches(g_slot_status_fn, kSlotStatusSignature,
                                  sizeof(kSlotStatusSignature))) {
        c6fw_log("lua_bridge: SlotStatus signature mismatch; disabling native clans path");
        g_slot_status_fn = nullptr;
    }
    if (!native_signature_matches(g_set_slot_status_fn, kSetSlotStatusSignature,
                                  sizeof(kSetSlotStatusSignature))) {
        c6fw_log("lua_bridge: SetSlotStatus signature mismatch; disabling native clans path");
        g_set_slot_status_fn = nullptr;
    }
    if (!native_signature_matches(g_initialized_fn, kInitializedSignature,
                                  sizeof(kInitializedSignature))) {
        c6fw_log("lua_bridge: InitializedGate signature mismatch; disabling native clans path");
        g_initialized_fn = nullptr;
    }
    if (!native_signature_matches(g_set_start_position_fn, kStartPositionSignature,
                                  sizeof(kStartPositionSignature))) {
        c6fw_log("lua_bridge: SetStartPosition signature mismatch; optional position helper disabled");
        g_set_start_position_fn = nullptr;
    }
    if (!native_signature_matches(g_native_city_create_fn,
                                  kNativeCityCreateSignature,
                                  sizeof(kNativeCityCreateSignature))) {
        c6fw_log("lua_bridge: NativeCityCreate signature mismatch; native copy-city path disabled");
        g_native_city_create_fn = nullptr;
    } else {
        c6fw_log("lua_bridge: NativeCityCreate resolved @ %p", g_native_city_create_fn);
    }
    if (!native_signature_matches(g_empty_basic_string_fn,
                                  kEmptyBasicStringSignature,
                                  sizeof(kEmptyBasicStringSignature))) {
        c6fw_log("lua_bridge: EmptyBasicString signature mismatch; native city path disabled");
        g_empty_basic_string_fn = nullptr;
    } else {
        c6fw_log("lua_bridge: EmptyBasicString resolved @ %p", g_empty_basic_string_fn);
    }
    if (!native_signature_matches(g_basic_string_assign_fn,
                                  kBasicStringAssignSignature,
                                  sizeof(kBasicStringAssignSignature))) {
        c6fw_log("lua_bridge: BasicStringAssign signature mismatch; native city path disabled");
        g_basic_string_assign_fn = nullptr;
    } else {
        c6fw_log("lua_bridge: BasicStringAssign resolved @ %p", g_basic_string_assign_fn);
    }
    if (!native_signature_matches(g_set_leader_type_fn, kIdentitySetterSignature,
                                  sizeof(kIdentitySetterSignature))) {
        c6fw_log("lua_bridge: LeaderType setter signature mismatch; identity preparation disabled");
        g_set_leader_type_fn = nullptr;
    }
    if (!native_signature_matches(g_set_civilization_type_fn, kIdentitySetterSignature,
                                  sizeof(kIdentitySetterSignature))) {
        c6fw_log("lua_bridge: CivilizationType setter signature mismatch; identity preparation disabled");
        g_set_civilization_type_fn = nullptr;
    }
    if (!native_signature_matches(g_refresh_identity_fn, kIdentityRefreshSignature,
                                  sizeof(kIdentityRefreshSignature))) {
        c6fw_log("lua_bridge: identity refresh signature mismatch; identity preparation disabled");
        g_refresh_identity_fn = nullptr;
    }
    if (!native_signature_matches(g_set_civ_level_fn, kIdentitySetterSignature,
                                  sizeof(kIdentitySetterSignature))) {
        c6fw_log("lua_bridge: civilization level setter signature mismatch; closed-slot preparation disabled");
        g_set_civ_level_fn = nullptr;
    }
    static const unsigned char shortTextSig[] = {
        0x48,0x8B,0x49,0x10,0x4C,0x8B,0xC2,0x8B,0x15,0xA3,0x23,0xA2,0x00,0x48,0x8B,0x01};
    static const unsigned char longTextSig[] = {
        0x48,0x8B,0x49,0x10,0x4C,0x8B,0xC2,0x8B,0x15,0x6F,0x24,0xA2,0x00,0x48,0x8B,0x01};
    static const unsigned char adjectiveSig[] = {
        0x48,0x8B,0x49,0x10,0x4C,0x8B,0xC2,0x8B,0x15,0x67,0x2A,0xA2,0x00,0x48,0x8B,0x01};
    if (!native_signature_matches(g_set_civ_short_text_fn, shortTextSig, sizeof(shortTextSig))) g_set_civ_short_text_fn = nullptr;
    if (!native_signature_matches(g_set_civ_long_text_fn, longTextSig, sizeof(longTextSig))) g_set_civ_long_text_fn = nullptr;
    if (!native_signature_matches(g_set_civ_adjective_fn, adjectiveSig, sizeof(adjectiveSig))) g_set_civ_adjective_fn = nullptr;
    if (!native_signature_matches(g_clans_convert_fn, kClansConvertSignature,
                                  sizeof(kClansConvertSignature))) {
        c6fw_log("lua_bridge: official clans conversion signature mismatch; chain disabled");
        g_clans_convert_fn = nullptr;
    } else {
        c6fw_log("lua_bridge: official clans conversion resolved @ %p", g_clans_convert_fn);
    }
    if (!native_signature_matches(g_clans_manager_getter_fn,
                                  kClansManagerGetterSignature,
                                  sizeof(kClansManagerGetterSignature))) {
        c6fw_log("lua_bridge: clans manager getter signature mismatch; diagnostic chain disabled");
        g_clans_manager_getter_fn = nullptr;
    }
    if (!native_signature_matches(g_clans_tribe_at_index_fn,
                                  kClansTribeAtIndexSignature,
                                  sizeof(kClansTribeAtIndexSignature))) {
        c6fw_log("lua_bridge: clans tribe lookup signature mismatch; diagnostic chain disabled");
        g_clans_tribe_at_index_fn = nullptr;
    }
    g_clans_diagnostic_ready =
        g_clans_manager_getter_fn && g_clans_tribe_at_index_fn && g_clans_convert_fn;
    c6fw_log("lua_bridge: official clans diagnostic bridge %s",
             g_clans_diagnostic_ready ? "READY" : "DISABLED");
    c6fw_log("lua_bridge: activation tail resolved (clanIdx=%p defaultIdx=%p subsys=%p listA=%p/%p listB=%p/%p handicapCfg=%p)",
             g_clan_index_source_fn, g_default_type_index_fn, g_subsys_set_fn,
             g_check_a_fn, g_list_a_add_fn,
             g_check_b_fn, g_list_b_add_fn, g_handicap_type_fn);
}

// 按槽位取【游戏侧】玩家对象：*(游戏对象 + 0x20)[slot]
//   逆向依据：FUN_180228580 里 uVar5 = *(*(FUN_180306b80() + 0x20) + playerID * 8)
void* game_player_from_slot(int slot) {
    if (!g_game_obj_getter_fn) return nullptr;
    if (slot < 0 || slot > 63) return nullptr;
    using GetObjFn = void* (*)();
    void* gameObj = reinterpret_cast<GetObjFn>(g_game_obj_getter_fn)();
    if (!gameObj) return nullptr;
    auto base = *reinterpret_cast<std::uintptr_t*>(
        reinterpret_cast<std::uintptr_t>(gameObj) + 0x20);
    if (!base) return nullptr;
    return *reinterpret_cast<void**>(base + static_cast<std::size_t>(slot) * 8);
}

// Push one integer diagnostic field into the table currently at the top of
// the Lua stack. Keeping all values numeric makes the API usable from both
// HavokScript and the small offline acceptance scripts without relying on a
// boolean export that is not present in this bridge.
void lua_snapshot_field(void* L, const char* name, int value) {
    g_pushint(L, value);
    g_setfield(L, -2, name);
}

int lua_snapshot_bad_pointer_count(const CsfSnapshotGroup& group) {
    return static_cast<int>(group.pointers[0].badMemberPointers +
                            group.pointers[1].badMemberPointers);
}

int lua_snapshot_bad_id_count(const CsfSnapshotGroup& group) {
    return static_cast<int>(group.pointers[0].badMemberIds +
                            group.pointers[1].badMemberIds + group.ids.badMemberIds);
}

int lua_snapshot_target_pointer_hits(const CsfSnapshotGroup& group) {
    return static_cast<int>(group.pointers[0].targetAddressHits +
                            group.pointers[1].targetAddressHits);
}

int lua_snapshot_target_slot_hits(const CsfSnapshotGroup& group) {
    return static_cast<int>(group.pointers[0].targetSlotHits +
                            group.pointers[1].targetSlotHits +
                            group.ids.targetSlotHits);
}

// ---------------------------------------------------------------------------
// Player+0x6B0 回合任务/事件装配对象的只读观察
//
// FUN_180401FA0(param_1) 的 param_1 就是 *(Player+0x6B0)。该对象在
// +0x1B8 / +0x1D0 / +0x1E8 维护三组事件订阅 vector，每个元素 0x40 字节：
//   vector+0x00 = 数据指针
//   vector+0x08 = u32 容量
//   vector+0x10 = u32 元素数
// 对象 +0x90 是所属 Player*。0x401FA0 只在 size==capacity 时扩容，从不清空
// 已有元素；因此本模块只读，且实验入口必须保留空队列闸门。
// 读回标志语义与 target_slot_id_read 一致：1 = 三组头与 owner 全部读到，
// 0 = 指针为空或任一解引用触发 SEH。绝不能让空指针看起来像“正常空队列”。
// ---------------------------------------------------------------------------
constexpr std::uintptr_t kPlayerTurnTaskObjectOffset = 0x6B0;
constexpr std::uintptr_t kTurnTaskOwnerOffset = 0x90;
constexpr std::uintptr_t kTurnTaskVectorOffsets[3] = {0x1B8, 0x1D0, 0x1E8};
constexpr std::uintptr_t kTurnTaskVectorCapacityOffset = 0x8;
constexpr std::uintptr_t kTurnTaskVectorSizeOffset = 0x10;
constexpr unsigned int kTurnTaskMaxCapacity = 256;

struct TurnTaskVectorView {
    const void* data;
    unsigned int capacity;
    unsigned int size;
};

struct TurnTaskView {
    TurnTaskVectorView vectors[3];
    int ownerMatches;
    int read;
};

bool read_player_turn_tasks(void* player, TurnTaskView* out) {
    if (!player || !out) return false;
    TurnTaskView view{};
    __try {
        const std::uintptr_t playerAddress = reinterpret_cast<std::uintptr_t>(player);
        void* taskObject = *reinterpret_cast<void**>(
            playerAddress + kPlayerTurnTaskObjectOffset);
        if (!taskObject) return false;
        const std::uintptr_t taskAddress = reinterpret_cast<std::uintptr_t>(taskObject);
        view.ownerMatches = (*reinterpret_cast<void**>(
            taskAddress + kTurnTaskOwnerOffset) == player) ? 1 : 0;
        for (int i = 0; i < 3; ++i) {
            const std::uintptr_t vectorAddress = taskAddress + kTurnTaskVectorOffsets[i];
            view.vectors[i].data = *reinterpret_cast<void**>(vectorAddress);
            view.vectors[i].capacity = *reinterpret_cast<unsigned int*>(
                vectorAddress + kTurnTaskVectorCapacityOffset);
            view.vectors[i].size = *reinterpret_cast<unsigned int*>(
                vectorAddress + kTurnTaskVectorSizeOffset);
        }
        view.read = 1;
        *out = view;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

// 只用于空队列入口的形状判断：size 必须为 0，容量不得超过安全阈值，
// 且非零容量必须伴随非空数据指针。零容量 + 空指针是合法空 vector。
bool turn_task_vector_empty_shape_ok(const TurnTaskVectorView& vector) {
    if (vector.size != 0) return false;
    if (vector.capacity > kTurnTaskMaxCapacity) return false;
    if (vector.size > vector.capacity) return false;
    if (vector.capacity != 0 && !vector.data) return false;
    return true;
}

int lua_snapshot_unsigned(unsigned int value) {
    return value > 0x7fffffffu ? 0x7fffffff : static_cast<int>(value);
}

// C6FW.GetPlayerSnapshot([slot]) -> diagnostic table / nil
//
// With no slot it snapshots the six inspected player-list vectors from the
// current Game object. With a slot it additionally resolves that game's
// Player* and reads only the target's slot/alive/initialized bytes plus target
// membership hits. It never calls the activation path or mutates memory. A
// non-zero read_status means the result is not suitable for a business-pass
// assertion; list_state is only a structural consistency observation.
int lua_get_player_snapshot(void* L) {
    if (!g_pushint || !g_setfield || !g_createtable || !g_game_obj_getter_fn) return 0;

    int targetSlot = -1;
    if (g_gettop && g_gettop(L) >= 1) {
        if (!g_tonumber) return 0;
        targetSlot = static_cast<int>(g_tonumber(L, 1));
    }

    void* gameObj = nullptr;
    __try {
        using GetObjFn = void* (*)();
        gameObj = reinterpret_cast<GetObjFn>(g_game_obj_getter_fn)();
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.GetPlayerSnapshot: GameObjGetter faulted");
    }

    void* targetPlayer = nullptr;
    if (targetSlot >= 0 && targetSlot < 64) {
        __try {
            targetPlayer = game_player_from_slot(targetSlot);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            c6fw_log("C6FW.GetPlayerSnapshot: target slot %d lookup faulted", targetSlot);
        }
    }

    const auto snapshot = csf_take_player_snapshot(
        reinterpret_cast<std::uintptr_t>(gameObj), targetSlot,
        reinterpret_cast<std::uintptr_t>(targetPlayer), csf_snapshot_reader);
    TurnTaskView turnTasks{};
    const bool turnTasksRead = kTurnTaskAssemblyRva != 0 &&
        read_player_turn_tasks(targetPlayer, &turnTasks);
    g_createtable(L, 0, 44);

    lua_snapshot_field(L, "read_status", static_cast<int>(snapshot.readStatus));
    lua_snapshot_field(L, "global_read_status", static_cast<int>(snapshot.global.readStatus));
    lua_snapshot_field(L, "global_list_state", static_cast<int>(snapshot.global.listState));
    lua_snapshot_field(L, "global_pointer_a_count",
                       static_cast<int>(snapshot.global.pointers[0].count));
    lua_snapshot_field(L, "global_pointer_b_count",
                       static_cast<int>(snapshot.global.pointers[1].count));
    lua_snapshot_field(L, "global_id_count", static_cast<int>(snapshot.global.ids.count));
    lua_snapshot_field(L, "global_pointer_a_shape",
                       static_cast<int>(snapshot.global.pointers[0].shape));
    lua_snapshot_field(L, "global_pointer_b_shape",
                       static_cast<int>(snapshot.global.pointers[1].shape));
    lua_snapshot_field(L, "global_id_shape", static_cast<int>(snapshot.global.ids.shape));
    lua_snapshot_field(L, "global_bad_member_pointer_count",
                       lua_snapshot_bad_pointer_count(snapshot.global));
    lua_snapshot_field(L, "global_bad_member_id_count",
                       lua_snapshot_bad_id_count(snapshot.global));
    lua_snapshot_field(L, "city_state_read_status",
                       static_cast<int>(snapshot.cityState.readStatus));
    lua_snapshot_field(L, "city_state_list_state",
                       static_cast<int>(snapshot.cityState.listState));
    lua_snapshot_field(L, "city_state_pointer_a_count",
                       static_cast<int>(snapshot.cityState.pointers[0].count));
    lua_snapshot_field(L, "city_state_pointer_b_count",
                       static_cast<int>(snapshot.cityState.pointers[1].count));
    lua_snapshot_field(L, "city_state_id_count",
                       static_cast<int>(snapshot.cityState.ids.count));
    lua_snapshot_field(L, "city_state_pointer_a_shape",
                       static_cast<int>(snapshot.cityState.pointers[0].shape));
    lua_snapshot_field(L, "city_state_pointer_b_shape",
                       static_cast<int>(snapshot.cityState.pointers[1].shape));
    lua_snapshot_field(L, "city_state_id_shape",
                       static_cast<int>(snapshot.cityState.ids.shape));
    lua_snapshot_field(L, "city_state_bad_member_pointer_count",
                       lua_snapshot_bad_pointer_count(snapshot.cityState));
    lua_snapshot_field(L, "city_state_bad_member_id_count",
                       lua_snapshot_bad_id_count(snapshot.cityState));
    lua_snapshot_field(L, "target_slot", snapshot.targetSlot);
    lua_snapshot_field(L, "target_slot_valid", snapshot.targetSlotValid ? 1 : 0);
    lua_snapshot_field(L, "target_pointer_found", snapshot.targetPointerFound ? 1 : 0);
    lua_snapshot_field(L, "global_target_pointer_hits",
                       lua_snapshot_target_pointer_hits(snapshot.global));
    lua_snapshot_field(L, "global_target_slot_hits",
                       lua_snapshot_target_slot_hits(snapshot.global));
    lua_snapshot_field(L, "city_state_target_pointer_hits",
                       lua_snapshot_target_pointer_hits(snapshot.cityState));
    lua_snapshot_field(L, "city_state_target_slot_hits",
                       lua_snapshot_target_slot_hits(snapshot.cityState));
    lua_snapshot_field(L, "target_slot_id_read", snapshot.targetSlotIdRead);
    lua_snapshot_field(L, "target_slot_id", snapshot.targetSlotId);
    lua_snapshot_field(L, "target_alive_read", snapshot.targetAliveRead);
    lua_snapshot_field(L, "target_alive", snapshot.targetAlive);
    lua_snapshot_field(L, "target_initialized_read", snapshot.targetInitializedRead);
    lua_snapshot_field(L, "target_initialized", snapshot.targetInitialized);
    // 0x401FA0 turn-task/event assembly head (Player+0x6B0). read=1 only when
    // the task object, its owner and all three vector headers were readable;
    // a null/faulting pointer therefore cannot masquerade as an empty queue.
    lua_snapshot_field(L, "target_turn_tasks_read", turnTasksRead ? 1 : 0);
    lua_snapshot_field(L, "owner_matches", turnTasksRead ? turnTasks.ownerMatches : 0);
    lua_snapshot_field(L, "target_turn_tasks_a_size",
                       turnTasksRead ? lua_snapshot_unsigned(turnTasks.vectors[0].size) : 0);
    lua_snapshot_field(L, "target_turn_tasks_a_capacity",
                       turnTasksRead ? lua_snapshot_unsigned(turnTasks.vectors[0].capacity) : 0);
    lua_snapshot_field(L, "target_turn_tasks_b_size",
                       turnTasksRead ? lua_snapshot_unsigned(turnTasks.vectors[1].size) : 0);
    lua_snapshot_field(L, "target_turn_tasks_b_capacity",
                       turnTasksRead ? lua_snapshot_unsigned(turnTasks.vectors[1].capacity) : 0);
    lua_snapshot_field(L, "target_turn_tasks_c_size",
                       turnTasksRead ? lua_snapshot_unsigned(turnTasks.vectors[2].size) : 0);
    lua_snapshot_field(L, "target_turn_tasks_c_capacity",
                       turnTasksRead ? lua_snapshot_unsigned(turnTasks.vectors[2].capacity) : 0);
    lua_snapshot_field(L, "game_available", gameObj ? 1 : 0);
    c6fw_log("C6FW.GetPlayerSnapshot: game=%p targetSlot=%d target=%p read=%d global=(%d,%d) city=(%d,%d)",
             gameObj, targetSlot, targetPlayer,
             static_cast<int>(snapshot.readStatus),
             static_cast<int>(snapshot.global.readStatus),
             static_cast<int>(snapshot.global.listState),
             static_cast<int>(snapshot.cityState.readStatus),
             static_cast<int>(snapshot.cityState.listState));
    if (targetPlayer) {
        c6fw_log("C6FW.GetPlayerSnapshot: turnTasks read=%d ownerMatch=%d A=%u/%u B=%u/%u C=%u/%u",
                 turnTasksRead ? 1 : 0, turnTasks.ownerMatches,
                 turnTasksRead ? turnTasks.vectors[0].size : 0,
                 turnTasksRead ? turnTasks.vectors[0].capacity : 0,
                 turnTasksRead ? turnTasks.vectors[1].size : 0,
                 turnTasksRead ? turnTasks.vectors[1].capacity : 0,
                 turnTasksRead ? turnTasks.vectors[2].size : 0,
                 turnTasksRead ? turnTasks.vectors[2].capacity : 0);
    }
    return 1;
}

// C6FW.HasGamePlayer(slot) -> 1/nil
// 只报"该槽有没有游戏侧玩家对象"，不把裸指针交给 Lua（避免 lightuserdata 依赖）。
int lua_has_game_player(void* L) {
    if (!g_pushint || !g_tonumber) return 0;
    int slot = static_cast<int>(g_tonumber(L, 1));
    void* p = game_player_from_slot(slot);
    if (!p) {
        c6fw_log("C6FW.HasGamePlayer: slot %d -> null", slot);
        return 0;
    }
    g_pushint(L, 1);
    return 1;
}

// C6FW.ActivatePlayer(slot [, startX, startY]) -> 1 (nil on error)
//
// ★ 本桥的核心：按官方氏族中途转换顺序激活一个预注册玩家槽。
//
//   逆向依据（FUN_180228580，见 CityStateFounder/docs/DLL对局中新增城邦_完整方案.md）：
//     ① 组装结构体 { playerID, native type value, 1, 0 }；官方氏族路径
//          flags 固定为 1，不走开局路径的 bit24 分支。
//     ② FUN_1803077c0(游戏对象, &结构体)   ★ 创建 + 初始化【游戏侧】玩家对象
//          （内部：FUN_180306320 若 *(gameObj+0x20)[slot] 为 null 就创建）
//     ③ uVar5 = *(游戏对象+0x20)[slot]
//     ④ FUN_1802FA9A0(player,1)             官方 alive 发布并重建列表
//     ⑤ FUN_1802FAB60(player+0x778,player,xy)（若提供坐标）
//     ⑥ FUN_1802F9500(player)               连接 Player+0x790 的引擎事件订阅
//     ⑦ FUN_1802F9350(player): conditional subsystem callback
//
//   实测（2026-10-04）：不调 ② 时 *(gameObj+0x20)[slot] 是 null → 无法激活。
//   所以 ② 是必需的，不是可选。
// Experimental explicit notification for an already initialized city state.
// Both startup 0x229940 and official clans conversion 0x61FDD0 dispatch this
// engine event after registration. Returning only certifies dispatch; the Lua
// caller must verify actual modifier owners/IDs before claiming abilities.
// Do not replay automatically: subscribers may attach persistent effects.
int lua_publish_city_state_ready(void* L) {
    if (!g_tonumber || !g_pushint || !g_publish_player_ready_fn ||
        !g_game_context_pointer || !g_initialized_fn || !g_civ_level_fn) return 0;
    const int slot=static_cast<int>(g_tonumber(L,1));
    if (slot<0 || slot>=62) return 0;
    void* player=game_player_from_slot(slot);
    void* cfg=player_config_by_slot(slot);
    if (!player || !cfg) return 0;
    __try {
        if (!reinterpret_cast<int(*)(void*)>(g_initialized_fn)(player) ||
            reinterpret_cast<unsigned(*)(void*)>(g_civ_level_fn)(cfg)!=0xC2577075u ||
            !*(reinterpret_cast<unsigned char*>(player)+0x258)) return 0;
        auto* context=*reinterpret_cast<unsigned char**>(g_game_context_pointer);
        if (!context) return 0;
        auto* events=*reinterpret_cast<unsigned char**>(context+0x280);
        if (!events) return 0;
        reinterpret_cast<void(*)(void*,void*)>(g_publish_player_ready_fn)(events+0x8E8,player);
        c6fw_log("C6FW.PublishCityStateReady: official notification returned for slot %d",slot);
    } __except(EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.PublishCityStateReady: notification faulted for slot %d",slot);
        return 0;
    }
    g_pushint(L,1); return 1;
}

// Experimental, separate from activation/publication. The official clans
// chain calls 0x401FA0(*(Player+0x6B0)) AFTER city creation; the load path also
// assembles these transient task vectors. The worker appends, so never replay
// over existing or partially assembled vectors. Return 1 certifies assembly
// readback only; real production and later turns require separate acceptance.
int lua_initialize_city_state_turn_tasks(void* L) {
    if (!g_tonumber || !g_pushint || !g_turn_task_assembly_fn ||
        !g_initialized_fn || !g_civ_level_fn || !g_slot_status_fn) return 0;
    const double requested = g_tonumber(L, 1);
    if (!(requested >= 0 && requested < 62)) return 0;
    const int slot = static_cast<int>(requested);
    if (requested != slot) return 0;
    void* player = game_player_from_slot(slot);
    void* cfg = player_config_by_slot(slot);
    if (!player || !cfg) return 0;
    TurnTaskView before{}, after{};
    __try {
        auto* bytes = static_cast<unsigned char*>(player);
        if (!reinterpret_cast<int(*)(void*)>(g_initialized_fn)(player) ||
            reinterpret_cast<unsigned(*)(void*)>(g_civ_level_fn)(cfg) != 0xC2577075u ||
            reinterpret_cast<unsigned(*)(void*)>(g_slot_status_fn)(cfg) != 1u ||
            !bytes[0x258] || *reinterpret_cast<int*>(bytes + 0xD8) != slot) return 0;
        auto* cities = *reinterpret_cast<unsigned char**>(bytes + 0x6D0);
        if (!cities || !*reinterpret_cast<void**>(cities + 0xD0)) return 0;
        if (!read_player_turn_tasks(player, &before) || !before.ownerMatches) return 0;
        for (int i = 0; i < 3; ++i) {
            if (!turn_task_vector_empty_shape_ok(before.vectors[i])) {
                c6fw_log("C6FW.InitializeCityStateTurnTasks: slot %d rejected nonempty/invalid group %d size=%u cap=%u",
                    slot, i, before.vectors[i].size, before.vectors[i].capacity);
                return 0;
            }
        }
        auto* taskObject = *reinterpret_cast<void**>(bytes + kPlayerTurnTaskObjectOffset);
        c6fw_log("C6FW.InitializeCityStateTurnTasks: slot %d before A=0 B=0 C=0", slot);
        reinterpret_cast<void(*)(void*)>(g_turn_task_assembly_fn)(taskObject);
        if (!read_player_turn_tasks(player, &after) || !after.ownerMatches) return 0;
        c6fw_log("C6FW.InitializeCityStateTurnTasks: slot %d after A=%u/%u B=%u/%u C=%u/%u",
            slot, after.vectors[0].size, after.vectors[0].capacity,
            after.vectors[1].size, after.vectors[1].capacity,
            after.vectors[2].size, after.vectors[2].capacity);
        for (int i = 0; i < 3; ++i) {
            const auto& v = after.vectors[i];
            if (!v.data || v.size == 0 || v.size > v.capacity ||
                v.capacity > kTurnTaskMaxCapacity) return 0;
        }
    } __except(EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.InitializeCityStateTurnTasks: slot %d faulted; no automatic retry", slot);
        return 0;
    }
    g_pushint(L, 1);
    return 1;
}

int lua_activate_player(void* L) {
    if (!g_pushint || !g_tonumber) return 0;
    int slot = static_cast<int>(g_tonumber(L, 1));
    if (slot < 0 || slot > 63) {
        c6fw_log("C6FW.ActivatePlayer: slot %d out of range", slot);
        return 0;
    }
    struct StartPosition { int x; int y; };
    StartPosition startPosition{};
    bool hasStartPosition = false;
    bool alivePublished = false;
    if (g_gettop && g_gettop(L) >= 3) {
        startPosition.x = static_cast<int>(g_tonumber(L, 2));
        startPosition.y = static_cast<int>(g_tonumber(L, 3));
        hasStartPosition = true;
    }
    if (!g_game_obj_getter_fn || !g_register_player_fn || !g_set_alive_rebuild_fn ||
        !g_slot_status_fn || !g_set_slot_status_fn || !g_clan_index_source_fn ||
        !g_default_type_index_fn ||
         !g_initialized_fn || !g_activate_player_fn ||
         !g_subsys_set_fn || !g_handicap_type_fn) {
        c6fw_log("C6FW.ActivatePlayer: not resolved (XP2 only?)");
        return 0;
    }

    using GetObjFn = void* (*)();
    void* gameObj = reinterpret_cast<GetObjFn>(g_game_obj_getter_fn)();
    if (!gameObj) {
        c6fw_log("C6FW.ActivatePlayer: no game object");
        return 0;
    }

    // ① 组装官方氏族转换结构体（不是开局路径的归一化记录）。
    //    uint slot; uint nativeTypeValue; uint flags; byte flag2;
    struct PlayerRecord {
        unsigned    id;
        unsigned    nativeTypeValue; // raw 0x169EE0 value used by the clans path
        unsigned    flags;
        unsigned char flag2;
        unsigned char pad[3];
    } rec;
    rec.id    = static_cast<unsigned>(slot);
    rec.nativeTypeValue = 0xffffffffu;
    rec.flags = 1u;
    rec.flag2 = 0;

    void* cfg = player_config_by_slot(slot);
    if (!cfg) return 0;
    unsigned nativeTypeValue = 0xffffffffu;
    unsigned dormantStatus = 0xffffffffu;
    __try {
        dormantStatus = reinterpret_cast<unsigned (*)(void*)>(g_slot_status_fn)(cfg);
        nativeTypeValue = reinterpret_cast<unsigned (*)(void*)>(g_handicap_type_fn)(cfg);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.ActivatePlayer: slot %d native config read faulted", slot);
        return 0;
    }
    if (dormantStatus != 5u) {
        c6fw_log("C6FW.ActivatePlayer: slot %d rejected: native slot status=%u (need 5)",
                 slot, dormantStatus);
        return 0;
    }
    __try {
        using SetSlotStatusFn = void (*)(void*, int);
        reinterpret_cast<SetSlotStatusFn>(g_set_slot_status_fn)(cfg, 1);
        const unsigned afterStatus = reinterpret_cast<unsigned (*)(void*)>(g_slot_status_fn)(cfg);
        if (afterStatus != 1u) {
            c6fw_log("C6FW.ActivatePlayer: slot %d native status setter readback=%u",
                     slot, afterStatus);
            return fail_activate_after_stage(cfg, slot, alivePublished);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.ActivatePlayer: slot %d native status setter faulted", slot);
        return fail_activate_after_stage(cfg, slot, alivePublished);
    }
    rec.nativeTypeValue = nativeTypeValue;
    c6fw_log("C6FW.ActivatePlayer: slot %d cfg=%p nativeTypeValue=%u status=%u",
             slot, cfg, nativeTypeValue, dormantStatus);

    // Resolve the official clans-path subsystem index before registering or
    // initializing a player. This is deliberately not the startup path's
    // 0x16A300(cfg) key: clans reads FUN_1801E5460()->entry+0xB8 and uses
    // 0x64E6C0 only when that small index is 0/-1.
    unsigned subsystemTypeKey = 0xffffffffu;
    __try {
        using ClanSourceFn = void* (*)();
        void* entry = reinterpret_cast<ClanSourceFn>(g_clan_index_source_fn)();
        if (!entry) return fail_activate_after_stage(cfg, slot, alivePublished);
        subsystemTypeKey = *reinterpret_cast<unsigned*>(
            reinterpret_cast<char*>(entry) + 0xB8);
        c6fw_log("C6FW.ActivatePlayer: slot %d clan index entry=%p primary=%u",
                 slot, entry, subsystemTypeKey);
        if (subsystemTypeKey == 0u || subsystemTypeKey == 0xffffffffu) {
            using DefaultTypeIndexFn = unsigned (*)(void*);
            subsystemTypeKey = reinterpret_cast<DefaultTypeIndexFn>(
                g_default_type_index_fn)(nullptr);
            c6fw_log("C6FW.ActivatePlayer: slot %d clan default type index=%u",
                     slot, subsystemTypeKey);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.ActivatePlayer: slot %d config index lookup faulted", slot);
        return fail_activate_after_stage(cfg, slot, alivePublished);
    }
    if (subsystemTypeKey == 0xffffffffu) {
        c6fw_log("C6FW.ActivatePlayer: slot %d invalid configuration index", slot);
        return fail_activate_after_stage(cfg, slot, alivePublished);
    }

    if (game_player_from_slot(slot)) {
        c6fw_log("C6FW.ActivatePlayer: slot %d already has a game-side player; refusing re-registration",
                 slot);
        return fail_activate_after_stage(cfg, slot, alivePublished);
    }

    // ② ★ 创建 + 初始化游戏侧玩家对象
    using RegisterFn = void* (*)(void*, void*);
    void* created = nullptr;
    __try {
        created = reinterpret_cast<RegisterFn>(g_register_player_fn)(gameObj, &rec);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.ActivatePlayer: slot %d player registration faulted", slot);
        return fail_activate_after_stage(cfg, slot, alivePublished);
    }
    c6fw_log("C6FW.ActivatePlayer: slot %d register -> %p (flags=0x%x)",
             slot, created, rec.flags);

    // ③ 取游戏侧玩家对象
    void* player = game_player_from_slot(slot);
    if (!player || !created || created != player) {
        c6fw_log("C6FW.ActivatePlayer: slot %d register result does not match the game-side player", slot);
        return fail_activate_after_stage(cfg, slot, alivePublished);
    }

    // Register invokes the constructor (slot @ +0xd8) and initializer (+0x83a).
    // Verify their postconditions BEFORE further callbacks; never repair them
    // by writing the expected values into a partially initialized object.
    __try {
        const auto* bytes = reinterpret_cast<const unsigned char*>(player);
        const unsigned registeredSlot = *reinterpret_cast<const unsigned*>(bytes + 0xd8);
        const bool initializedByField = bytes[0x83a] != 0;
        const bool initializedByGate = reinterpret_cast<int (*)(void*)>(g_initialized_fn)(player) != 0;
        if (!initializedByField || !initializedByGate || registeredSlot != static_cast<unsigned>(slot)) {
            c6fw_log("C6FW.ActivatePlayer: slot %d registration incomplete (initialized=%u actualSlot=%u)",
                     slot, static_cast<unsigned>(bytes[0x83a]), registeredSlot);
            return fail_activate_after_stage(cfg, slot, alivePublished);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.ActivatePlayer: slot %d registration readback faulted", slot);
        return fail_activate_after_stage(cfg, slot, alivePublished);
    }

    // Official clans order: set alive through the engine primitive before the
    // subsystem setup. FUN_1802FA9A0 calls FUN_180307250, which clears and
    // rebuilds all 23 classification vectors, including +0x1650/+0x1878 and
    // +0x1AA0. This replaces the old capacity-limited hand append.
    if (!g_set_alive_rebuild_fn) {
        c6fw_log("C6FW.ActivatePlayer: SetAliveAndRebuild is not resolved");
        return fail_activate_after_stage(cfg, slot, alivePublished);
    }

    if (hasStartPosition && !g_set_start_position_fn) {
        c6fw_log("C6FW.ActivatePlayer: start-position helper is not resolved");
        return fail_activate_after_stage(cfg, slot, alivePublished);
    }
    __try {
        using SetAliveFn = void (*)(void*, unsigned char);
        reinterpret_cast<SetAliveFn>(g_set_alive_rebuild_fn)(player, 1);
        const auto* bytes = reinterpret_cast<const unsigned char*>(player);
        if (bytes[0x258] == 0) {
            c6fw_log("C6FW.ActivatePlayer: slot %d native SetAlive did not set +0x258", slot);
            return fail_activate_after_stage(cfg, slot, alivePublished);
        }
        alivePublished = true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.ActivatePlayer: slot %d native SetAlive/rebuild faulted", slot);
        bool publishedDuringFault = false;
        __try {
            publishedDuringFault = *reinterpret_cast<const unsigned char*>(
                reinterpret_cast<const char*>(player) + 0x258) != 0;
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            publishedDuringFault = false;
        }
        return fail_activate_after_stage(cfg, slot, publishedDuringFault);
    }

    if (hasStartPosition) {
        __try {
            using SetStartPositionFn = void (*)(void*, void*, const StartPosition*);
            reinterpret_cast<SetStartPositionFn>(g_set_start_position_fn)(
                reinterpret_cast<char*>(player) + 0x778, player, &startPosition);
            c6fw_log("C6FW.ActivatePlayer: slot %d native start position=(%d,%d)",
                     slot, startPosition.x, startPosition.y);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            c6fw_log("C6FW.ActivatePlayer: slot %d native start-position write faulted", slot);
            return fail_activate_after_stage(cfg, slot, alivePublished);
        }
    }

    // ④ 字段设置
    if (g_set_player_field_fn) {
        using SetFieldFn = void (*)(void*);
        __try {
            reinterpret_cast<SetFieldFn>(g_set_player_field_fn)(player);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            c6fw_log("C6FW.ActivatePlayer: slot %d player field setup faulted", slot);
            return fail_activate_after_stage(cfg, slot, alivePublished);
        }
    }

    // The configuration value below is used by the +0x738 subsystem setter.
    // It is not a proven argument to 0x2F9350; see its conditional body.
    // subsystemTypeKey was validated before any player registration.

    // Preserve the legacy subsystem setter while its clans-path value source
    // is being compared. Do not equate this setter with full activation.
    if (g_subsys_set_fn) {
        __try {
            using SubsysSetFn = void (*)(void*, unsigned);
            void* subsys = *reinterpret_cast<void**>(
                reinterpret_cast<std::uintptr_t>(player) + 0x738);
            c6fw_log("C6FW.ActivatePlayer: slot %d subsys=%p idx=%u", slot, subsys, subsystemTypeKey);
            if (!subsys) return fail_activate_after_stage(cfg, slot, alivePublished);
            reinterpret_cast<SubsysSetFn>(g_subsys_set_fn)(subsys, subsystemTypeKey);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            c6fw_log("C6FW.ActivatePlayer: slot %d subsys write faulted", slot);
            return fail_activate_after_stage(cfg, slot, alivePublished);
        }
    }

    // The inspected body consumes Player* only and has two early-return gates.
    // A normal return from it is not a complete activation success predicate.
    using ActivateFn = void (*)(void*);
    __try {
        reinterpret_cast<ActivateFn>(g_activate_player_fn)(player);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.ActivatePlayer: slot %d native activation faulted", slot);
        return fail_activate_after_stage(cfg, slot, alivePublished);
    }
    c6fw_log("C6FW.ActivatePlayer: slot %d player=%p conditional callback returned (subsystemValue=%u)",
             slot, player, subsystemTypeKey);

    g_pushint(L, 1);
    return 1;
}

// C6FW.CreateCityNative(slot, x, y, cityName) -> 1/nil
//
// This is deliberately an experimental, XP2-only bridge.  The official
// Barbarian Clans conversion calls FUN_1802649F0 directly on player+0x6D0;
// Lua Players[id]:GetCities():Create reaches a different wrapper and was
// observed to return true while creating zero cities for same-civ copies.
// The argument layout below mirrors the official conversion call: three -1
// sentinels, an engine resident/count-prefixed string pointer at +0x10,
// 0x101 at +0x18, and -1 at +0x1c.  A Lua TString is never passed through:
// FUN_1802649F0 reads [name-4] as its byte length.  The official path first
// runs FUN_180993700(&nameStorage, "") so the pointer and its length prefix
// are an engine-owned BasicString pair; using only EXP_GetEmptyBasicString()
// leaves that contract dependent on the current TLS singleton state.  The
// function is signature-gated during resolution and every native call is SEH
// protected.  A non-null City* is the only success claim.
int lua_create_city_native(void* L) {
    if (!g_pushint || !g_tonumber || !g_gettop || !g_native_city_create_fn ||
        !g_empty_basic_string_fn || !g_basic_string_assign_fn ||
        g_gettop(L) < 4) return 0;
    const int slot = static_cast<int>(g_tonumber(L, 1));
    const int x = static_cast<int>(g_tonumber(L, 2));
    const int y = static_cast<int>(g_tonumber(L, 3));
    std::uint64_t requestedNameLen = 0;
    const char* requestedName = (g_tolstring && g_gettop(L) >= 4)
        ? g_tolstring(L, 4, &requestedNameLen) : nullptr;
    // The bridge accepts only nil/empty as a deliberate safety boundary. A
    // future custom-name path must first implement the engine's resident
    // string constructor and lifetime release; Lua memory is not compatible.
    if (slot < 0 || slot > 63 || !requestedName || requestedNameLen > 0) {
        c6fw_log("C6FW.CreateCityNative: bad arguments slot=%d xy=(%d,%d)",
                 slot, x, y);
        return 0;
    }
    void* player = game_player_from_slot(slot);
    if (!player) {
        c6fw_log("C6FW.CreateCityNative: slot %d has no game-side player", slot);
        return 0;
    }
    void* cityManager = nullptr;
    __try {
        cityManager = *reinterpret_cast<void**>(
            reinterpret_cast<std::uintptr_t>(player) + 0x6D0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.CreateCityNative: slot %d city-manager read faulted", slot);
        return 0;
    }
    if (!cityManager) {
        c6fw_log("C6FW.CreateCityNative: slot %d city manager is null", slot);
        return 0;
    }

    const char* emptyBasicString = nullptr;
    __try {
        using EmptyBasicStringFn = const char* (*)();
        emptyBasicString = reinterpret_cast<EmptyBasicStringFn>(g_empty_basic_string_fn)();
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.CreateCityNative: EmptyBasicString fault code=0x%08X",
                 static_cast<unsigned>(GetExceptionCode()));
        return 0;
    }
    if (!emptyBasicString) {
        c6fw_log("C6FW.CreateCityNative: EmptyBasicString returned null");
        return 0;
    }

    // This is the exact string preparation used by the official clan
    // conversion.  The bridge currently accepts only an empty Lua name, but
    // still performs the engine assignment so [name-4] is a valid zero length
    // field when FUN_1802649F0 inspects it.
    const char* residentName = emptyBasicString;
    __try {
        using BasicStringAssignFn = std::uint64_t (*)(const char**, const char*);
        const std::uint64_t assignResult =
            reinterpret_cast<BasicStringAssignFn>(g_basic_string_assign_fn)(
                &residentName, requestedName);
        if (!assignResult || !residentName) {
            c6fw_log("C6FW.CreateCityNative: BasicStringAssign returned failure");
            return 0;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.CreateCityNative: BasicStringAssign fault code=0x%08X",
                 static_cast<unsigned>(GetExceptionCode()));
        return 0;
    }

    struct NativeCityArgs {
        std::int32_t unknown0 = -1;
        std::int32_t unknown4 = -1;
        std::int32_t unknown8 = -1;
        std::int32_t unknownC = 0;
        const char* name = nullptr; // +0x10, engine resident/count-prefixed
        std::uint8_t nameMode = 1;  // +0x18
        std::uint8_t copyField = 1; // +0x19
        std::uint16_t reserved = 0;
        std::int32_t reserved2 = -1; // +0x1c, official conversion sentinel
    } args{};
    args.unknown0 = -1;
    args.unknown4 = -1;
    args.unknown8 = -1;
    args.unknownC = 0;
    args.name = residentName;
    args.nameMode = 1;
    args.copyField = 1;
    static_assert(offsetof(NativeCityArgs, name) == 0x10);
    static_assert(offsetof(NativeCityArgs, nameMode) == 0x18);
    static_assert(offsetof(NativeCityArgs, copyField) == 0x19);
    const int xy[2] = {x, y};
    void* city = nullptr;
    __try {
        using CreateCityFn = void* (*)(void*, NativeCityArgs*, const int*,
                                       unsigned char);
        city = reinterpret_cast<CreateCityFn>(g_native_city_create_fn)(
            cityManager, &args, xy, 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.CreateCityNative: slot %d native call fault code=0x%08X",
                 slot, static_cast<unsigned>(GetExceptionCode()));
        return 0;
    }
    c6fw_log("C6FW.CreateCityNative: slot %d xy=(%d,%d) city=%p", slot, x, y, city);
    if (!city) return 0;
    g_pushint(L, 1);
    return 1;
}

// C6FW.ConvertBarbarianTribeNative(tribeIndex) -> 1/nil
//
// This deliberately exposes the *destructive* official XP2 conversion worker
// as an experiment-only entry point.  It is not wired into CSF gameplay: the
// worker chooses a dormant slot, consumes/destroys the source tribe, updates
// player/context state and creates the tribe city.  Calling it is therefore
// only safe in a dedicated test save where the caller has first captured the
// tribe index and all post-state facts.  A return value only means the native
// call returned; it never certifies the complete conversion transaction.
int lua_convert_barbarian_tribe_native(void* L) {
    if (!g_pushint || !g_tonumber || !g_gettop ||
        !g_clans_manager_getter_fn || !g_clans_tribe_at_index_fn ||
        !g_clans_convert_fn || g_gettop(L) < 1) return 0;
    const int tribeIndex = static_cast<int>(g_tonumber(L, 1));
    if (tribeIndex < 0 || tribeIndex >= 256) return 0;
    void* manager = nullptr;
    void* tribe = nullptr;
    __try {
        using ManagerGetterFn = void* (*)();
        using TribeAtIndexFn = void* (*)(void*, int);
        manager = reinterpret_cast<ManagerGetterFn>(g_clans_manager_getter_fn)();
        if (!manager) {
            c6fw_log("C6FW.ConvertBarbarianTribeNative: manager is null");
            return 0;
        }
        tribe = reinterpret_cast<TribeAtIndexFn>(g_clans_tribe_at_index_fn)(manager, tribeIndex);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.ConvertBarbarianTribeNative: manager/tribe lookup threw");
        return 0;
    }
    if (!tribe) {
        c6fw_log("C6FW.ConvertBarbarianTribeNative: tribe %d is null", tribeIndex);
        return 0;
    }
    __try {
        using ConvertFn = void (*)(void*, void*, const void*, std::uint64_t);
        // DoTurnActivate passes an auxiliary candidate array here.  The
        // conversion worker does not dereference it; zero candidates selects
        // the same engine transaction while avoiding a fabricated vector.
        reinterpret_cast<ConvertFn>(g_clans_convert_fn)(manager, tribe, nullptr, 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.ConvertBarbarianTribeNative: tribe %d fault code=0x%08X",
                 tribeIndex, static_cast<unsigned>(GetExceptionCode()));
        return 0;
    }
    c6fw_log("C6FW.ConvertBarbarianTribeNative: tribe %d worker returned; post-state required",
             tribeIndex);
    g_pushint(L, 1);
    return 1;
}

// C6FW.SetAlive(slot, value) -> 1/nil
//
// Use the official FUN_1802FA9A0 primitive. Besides updating player+0x258 it
// rebuilds the engine's classification vectors and emits the native alive
// transition event when the value changes. Directly writing +0x258 would leave
// those derived structures stale and is therefore no longer permitted here.
int lua_set_alive(void* L) {
    if (!g_pushint || !g_tonumber || !g_set_alive_rebuild_fn) return 0;
    int slot = static_cast<int>(g_tonumber(L, 1));
    int value = static_cast<int>(g_tonumber(L, 2));
    void* player = game_player_from_slot(slot);
    if (!player) {
        c6fw_log("C6FW.SetAlive: slot %d has no game-side player", slot);
        return 0;
    }
    __try {
        using SetAliveFn = void (*)(void*, unsigned char);
        const unsigned char requested = (value != 0) ? 1 : 0;
        const unsigned char before = *(reinterpret_cast<const unsigned char*>(player) + 0x258);
        reinterpret_cast<SetAliveFn>(g_set_alive_rebuild_fn)(player, requested);
        const unsigned char after = *(reinterpret_cast<const unsigned char*>(player) + 0x258);
        if (after != requested) return 0;
        c6fw_log("C6FW.SetAlive: slot %d player=%p native +0x258 %u -> %u (lists rebuilt)",
                 slot, player, static_cast<unsigned>(before), static_cast<unsigned>(after));
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        c6fw_log("C6FW.SetAlive: slot %d native SetAlive/rebuild faulted", slot);
        return 0;
    }
    g_pushint(L, 1);
    return 1;
}

// C6FW.GetAlive(slot) -> 1/nil（读同一个字节，用于验证）
int lua_get_alive(void* L) {
    if (!g_pushint || !g_tonumber) return 0;
    int slot = static_cast<int>(g_tonumber(L, 1));
    void* player = game_player_from_slot(slot);
    if (!player) return 0;
    char v = *(reinterpret_cast<char*>(player) + 0x258);
    g_pushint(L, (v != 0) ? 1 : 0);
    return 1;
}

void resolve_hks_api(HMODULE core) {
    HMODULE hks = GetModuleHandleW(L"HavokScript_FinalRelease.dll");
    if (hks) {
        c6fw_log("lua_bridge: HavokScript module found @ %p", hks);
    } else {
        c6fw_log("lua_bridge: HavokScript module NOT loaded, falling back to GameCore exports");
    }

    auto get = [&](const char* name) -> void* {
        if (hks) {
            void* p = GetProcAddress(hks, name);
            if (p) return p;
        }
        return GetProcAddress(core, name);
    };

    g_pushcclosure = reinterpret_cast<FnPushCclosure>(
        get("?hks_pushnamedcclosure@@YAXPEAUlua_State@@P6AH0@ZHPEBDH@Z"));
    g_createtable = reinterpret_cast<FnCreateTable>(
        get("?lua_createtable@@YAXPEAUlua_State@@HH@Z"));
    g_pushfstring = reinterpret_cast<FnPushFstring>(
        get("?hksi_lua_pushfstring@@YAPEBDPEAUlua_State@@PEBDZZ"));
    g_setfield = reinterpret_cast<FnSetField>(get(kSetFieldExport));
    g_pushint = reinterpret_cast<FnPushInt>(
        get("?hksi_lua_pushinteger@@YAXPEAUlua_State@@H@Z"));
    g_gettop = reinterpret_cast<FnGetTop>(
        get("?hksi_lua_gettop@@YAHPEAUlua_State@@@Z"));
    g_tolstring = reinterpret_cast<FnToLstring>(
        get("?hksi_lua_tolstring@@YAPEBDPEAUlua_State@@HPEA_K@Z"));
    g_pushnil = reinterpret_cast<FnPushNil>(
        get("?hksi_lua_pushnil@@YAXPEAUlua_State@@@Z"));
    g_touserdata = reinterpret_cast<FnToUserdata>(
        get("?hksi_lua_touserdata@@YAPEAXPEAUlua_State@@H@Z"));
    g_tonumber = reinterpret_cast<FnToNumber>(
        get("?hksi_lua_tonumber@@YANPEAUlua_State@@H@Z"));
    g_pushnumber = reinterpret_cast<FnPushNumber>(
        get("?hksi_lua_pushnumber@@YAXPEAUlua_State@@N@Z"));
    g_get_instance_fn = reinterpret_cast<void*>(reinterpret_cast<uintptr_t>(core) + 0x15D60);
    resolve_player_color_helpers(core);
    resolve_csf_activate_helpers(core);
    if (!g_setfield || !g_pushint || !g_pushcclosure || !g_createtable) {
        c6fw_log("lua_bridge: hks exports missing (closure=%p table=%p setfield=%p pushint=%p pushfstring=%p)",
                 reinterpret_cast<void*>(g_pushcclosure),
                 reinterpret_cast<void*>(g_createtable),
                 reinterpret_cast<void*>(g_setfield),
                 reinterpret_cast<void*>(g_pushint),
                 reinterpret_cast<void*>(g_pushfstring));
    }
}

void register_csf(void* L, const char* env_tag) {
    if (!L || !g_setfield || !g_pushcclosure || !g_createtable) return;
    g_createtable(L, 0, 24);
    // C6FW.GetPlayerColor / C6FW.SetPlayerColor (CSF 城邦属性桥; XP2 only)
    // 颜色 setter 无 Lua 包装 —— 实时激活的城邦靠这两个函数补颜色、避免交互崩溃。
    g_pushcclosure(L, lua_get_player_color, 0, "GetPlayerColor", 0);
    g_setfield(L, -2, "GetPlayerColor");
    g_pushcclosure(L, lua_set_player_color, 0, "SetPlayerColor", 0);
    g_setfield(L, -2, "SetPlayerColor");
    // ★ 2026-10-06 新增：按槽位补色（旧的 SetPlayerColor 拿不到配置对象，永远失败）
    g_pushcclosure(L, lua_set_player_color_by_slot, 0, "SetPlayerColorBySlot", 0);
    g_setfield(L, -2, "SetPlayerColorBySlot");
    // ★ 2026-10-07 新增：只读取色 / 抄色 / 色名转索引（修正配置对象取法后）
    g_pushcclosure(L, lua_get_player_color_by_slot, 0, "GetPlayerColorBySlot", 0);
    g_setfield(L, -2, "GetPlayerColorBySlot");
    g_pushcclosure(L, lua_copy_player_color, 0, "CopyPlayerColor", 0);
    g_setfield(L, -2, "CopyPlayerColor");
    g_pushcclosure(L, lua_color_type_index, 0, "ColorTypeIndex", 0);
    g_setfield(L, -2, "ColorTypeIndex");
    // ★ 2026-10-07 诊断：直接读引擎判定城邦用的那两个值
    g_pushcclosure(L, lua_get_civ_level_value, 0, "GetCivLevelValue", 0);
    g_setfield(L, -2, "GetCivLevelValue");
    g_pushcclosure(L, lua_get_player_field, 0, "GetPlayerField", 0);
    g_setfield(L, -2, "GetPlayerField");
    g_pushcclosure(L, lua_get_player_high_water, 0, "GetPlayerHighWater", 0);
    g_setfield(L, -2, "GetPlayerHighWater");
    g_pushcclosure(L, lua_get_native_slot_status, 0, "GetNativeSlotStatus", 0);
    g_setfield(L, -2, "GetNativeSlotStatus");
    // C6FW.PreparePlayerIdentity: dormant-only official identity setter
    // sequence; this does not register a player or publish alive.
    g_pushcclosure(L, lua_prepare_player_identity, 0, "PreparePlayerIdentity", 0);
    g_setfield(L, -2, "PreparePlayerIdentity");
    g_pushcclosure(L, lua_prepare_closed_city_state, 0, "PrepareClosedCityState", 0);
    g_setfield(L, -2, "PrepareClosedCityState");
    g_pushcclosure(L, lua_set_city_state_identity_text, 0, "SetCityStateIdentityText", 0);
    g_setfield(L, -2, "SetCityStateIdentityText");
    g_pushcclosure(L, lua_publish_city_state_ready, 0, "PublishCityStateReady", 0);
    g_setfield(L, -2, "PublishCityStateReady");
    if (g_turn_task_assembly_fn) {
        g_pushcclosure(L, lua_initialize_city_state_turn_tasks, 0, "InitializeCityStateTurnTasks", 0);
        g_setfield(L, -2, "InitializeCityStateTurnTasks");
    }
    // C6FW.GetPlayerSnapshot (CSF diagnostics only; pure read, no lifecycle
    // or activation claim). It is registered before the mutating legacy
    // helpers so acceptance scripts can collect a baseline independently.
    g_pushcclosure(L, lua_get_player_snapshot, 0, "GetPlayerSnapshot", 0);
    g_setfield(L, -2, "GetPlayerSnapshot");
    // C6FW.HasGamePlayer / C6FW.ActivatePlayer（CSF 玩家激活桥; XP2 only）
    // Legacy bridge; return 1 does not certify the complete native lifecycle.
    g_pushcclosure(L, lua_has_game_player, 0, "HasGamePlayer", 0);
    g_setfield(L, -2, "HasGamePlayer");
    g_pushcclosure(L, lua_activate_player, 0, "ActivatePlayer", 0);
    g_setfield(L, -2, "ActivatePlayer");
    // C6FW.SetAlive / C6FW.GetAlive（写/读 player+0x258，即 IsAlive 的来源）
    g_pushcclosure(L, lua_set_alive, 0, "SetAlive", 0);
    g_setfield(L, -2, "SetAlive");
    g_pushcclosure(L, lua_get_alive, 0, "GetAlive", 0);
    g_setfield(L, -2, "GetAlive");
    // Experimental official city-construction primitive used only by the
    // same-civilization copy path after identity/list gates pass.
    g_pushcclosure(L, lua_create_city_native, 0, "CreateCityNative", 0);
    g_setfield(L, -2, "CreateCityNative");

    g_setfield(L, kLuaGlobalsIndex, "C6FW");
    c6fw_log("CSF shared bridge registered (%s, L=%p)", env_tag, L);
}
} // anonymous namespace
bool csf_bridge_prepare(HMODULE core) {
    resolve_hks_api(core);
    return g_setfield && g_pushint && g_pushcclosure && g_createtable &&
           g_pushfstring && g_gettop && g_tolstring && g_pushnil &&
           g_tonumber && g_pushnumber && g_turn_task_assembly_fn &&
           g_publish_player_ready_fn && g_register_player_fn && g_set_alive_rebuild_fn;
}
void csf_bridge_gameplay(void* L) { register_csf(L, "gameplay"); }
void csf_bridge_ui(void* L) { register_csf(L, "ui"); }
} // namespace c6fw
