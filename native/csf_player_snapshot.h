#pragma once

// CSF 实机验收用【只读】玩家快照器（诊断组件，不参与激活决策）
// 约束：无 Windows 依赖（不 include windows.h、不用 __try/SEH），内存读取全交给调用者的 reader
// 回调；不调用任何引擎函数（P-025）、不新增 RVA；不含写游戏内存的语句，也不追加 vector（满容量
// 不算错）；不推导 game+8 / game+0x20 之类访问链，目标玩家地址由调用者传入；固定数组、无动态
// 分配，单次快照的回调次数有上界。
// 只观察已核对的 6 个 vector（不塞未核实偏移，也不塞全部 23 张分类表）：全局组 game+0x50 /
// game+0x278（vector<Player*>）、game+0x4A0（vector<int>）；城邦组 game+0x1650 / game+0x1878
// （vector<Player*>）、game+0x1AA0（vector<int>）。
// 每次访问（向量头、成员、成员+0xD8、目标三字段）都先做 checked 加法：base+offset 连同读尾巴
// 都不得越过 kCsfSnapshotAddressLimit，更不得回绕；被拦下的访问一律算读取失败，绝不把回绕后的
// 低地址交给 reader。
// 回调次数上界：6 次 vector 头 + 4 张指针表 × 64 项 × 2 次 + 2 张 id 表 × 64 项 × 1 次 + 目标 3 次
// = 649。任一头读取失败时会读完 6 个头再短路（不再读成员）；目标三字段与列表相互独立，仍会尝试。
// 状态语义：readStatus 只说"6 张表是否都读到"，listState 只说"这 6 张表内部与彼此是否自洽"；
// 二者都不表示玩家已初始化、也不表示可激活。targetSlotId / targetAlive / targetInitialized 只是
// 原样读回的对照值（+0xD8 是玩家槽位 id / PLAYER SLOT ID，不是文明索引），是否可激活交主 GPT 判断。

#include <algorithm>
#include <cstddef>
#include <cstdint>

namespace c6fw {

static_assert(sizeof(std::uintptr_t) == 8, "The inspected XP2 layout requires 64-bit addresses");

// 调用者提供的读取原语：成功读满 size 字节写入 output 时返回 true。本文件绝不自己
// 解引用地址，因此测试可用人工内存、框架侧可用 SEH 包装。
using CsfSnapshotReader = bool (*)(std::uintptr_t address, void* output, std::size_t size);

constexpr std::size_t kCsfSnapshotMaxCount = 64;      // 引擎玩家槽位上限，也是本快照上限
constexpr std::size_t kCsfSnapshotPointerTables = 2;  // 每组两张 vector<Player*>
constexpr std::uintptr_t kCsfSnapshotAddressLimit =
    ~static_cast<std::uintptr_t>(0) - 0x1000;         // 高位垃圾地址防线（防回绕靠 checked 加法）

// 全局组（game + offset）
constexpr std::uintptr_t kCsfGlobalPointerOffsets[kCsfSnapshotPointerTables] = { 0x50, 0x278 };
constexpr std::uintptr_t kCsfGlobalIdOffset = 0x4A0;
// 城邦组（game + offset）
constexpr std::uintptr_t kCsfCityStatePointerOffsets[kCsfSnapshotPointerTables] = { 0x1650, 0x1878 };
constexpr std::uintptr_t kCsfCityStateIdOffset = 0x1AA0;

// 目标玩家字段（调用者给出目标玩家地址后按这三个偏移读取，仅供对照）
constexpr std::uintptr_t kCsfPlayerSlotOffset = 0xD8;          // 玩家槽位 id（PLAYER SLOT ID）
constexpr std::uintptr_t kCsfPlayerAliveOffset = 0x258;        // IsAlive 的来源字节
constexpr std::uintptr_t kCsfPlayerInitializedOffset = 0x83A;  // 引擎激活闸门字节

struct CsfRawVector {
    std::uintptr_t begin;
    std::uintptr_t end;
    std::uintptr_t capacity;
};

// empty = {0,0,0}（零容量空表，合法且读空）；usable = 形状合法；malformed = 形状非法。
enum class CsfVectorShape { empty = 0, usable, malformed };
// 轴一：6 张表本身的读取是否全部成功（回调失败、地址被 checked 加法拦下=该地址当前不可读）。
enum class CsfSnapshotReadStatus { ok = 0, readFailed };
// 轴二：列表是否自洽。优先级 unknown > malformed > duplicate > mismatch > empty > consistent，
// 各级含义见 csf_evaluate_group()。
enum class CsfListState { unknown = 0, malformed, duplicate, mismatch, empty, consistent };

struct CsfSnapshotTable {
    std::uintptr_t vectorOffset;      // 该 vector 头相对 game 的偏移（便于日志对照）
    CsfRawVector raw;                 // begin / end / capacity 原样记录
    CsfVectorShape shape;
    std::size_t count;                // (end-begin)/stride；形状非法时为 0
    std::size_t targetAddressHits;    // 指针表：成员 == 目标地址；id 表恒为 0
    std::size_t targetSlotHits;       // 指针表：成员+0xD8 == 目标槽位；id 表：成员 == 槽位
    std::size_t badMemberPointers;    // 空指针或超地址上限的成员指针
    std::size_t badMemberIds;         // 不在 0..63 的成员 id（id 表成员或 +0xD8 读回值）
    std::uintptr_t pointerMember[kCsfSnapshotMaxCount];  // 指针表：成员 Player* 原值；id 表恒 0
    std::int32_t member[kCsfSnapshotMaxCount];           // 指针表：成员 +0xD8；id 表：成员原值
    std::uint8_t memberIdValid[kCsfSnapshotMaxCount];    // 1 = 指针与 id 都可用（可用于集合比较）
};

struct CsfSnapshotGroup {
    CsfSnapshotTable pointers[kCsfSnapshotPointerTables];
    CsfSnapshotTable ids;
    CsfSnapshotReadStatus readStatus;
    CsfListState listState;
};

struct CsfPlayerSnapshot {
    std::uintptr_t game;
    std::int32_t targetSlot;
    std::uintptr_t targetPlayer;      // 由调用者输入，本组件不推导
    bool targetSlotValid;             // 目标槽位是否落在 0..63
    bool targetPointerFound;          // 目标地址是否出现在任一指针表
    CsfSnapshotReadStatus readStatus; // 两组聚合读取状态；目标缺失/不在表内不算失败
    CsfSnapshotGroup global;          // 全局组
    CsfSnapshotGroup cityState;       // 城邦组
    std::int32_t targetSlotId;        // 目标玩家 +0xD8（槽位 id）
    std::uint8_t targetAlive;         // 目标玩家 +0x258
    std::uint8_t targetInitialized;   // 目标玩家 +0x83A
    std::uint8_t targetSlotIdRead;    // 三个字段各自的读回标志
    std::uint8_t targetAliveRead;
    std::uint8_t targetInitializedRead;
};

// 严格 checked 地址计算：base + offset 连同读尾巴 +size 都不得越过 kCsfSnapshotAddressLimit，
// 更不得回绕。返回 false 时调用者必须直接判读取失败，绝不把算出的地址交给 reader。
inline bool csf_checked_access(std::uintptr_t base, std::uintptr_t offset, std::size_t size,
                               std::uintptr_t& address) {
    if (base > kCsfSnapshotAddressLimit) return false;
    if (offset > kCsfSnapshotAddressLimit - base) return false;
    address = base + offset;
    return static_cast<std::uintptr_t>(size) <= kCsfSnapshotAddressLimit - address;
}

// 统一受检读取：reader 为空、地址被 checked 加法拦下、reader 失败，三者都算读取失败
// （failed 只置位，不重置）。
inline bool csf_checked_read(CsfSnapshotReader reader, std::uintptr_t base, std::uintptr_t offset,
                             void* output, std::size_t size, bool& failed) {
    std::uintptr_t address = 0;
    if (!reader || !csf_checked_access(base, offset, size, address) ||
        !reader(address, output, size)) {
        failed = true;
        return false;
    }
    return true;
}

// 纯算术形状校验，不解引用任何地址：步长只接受明确支持的 4/8 字节（先挡下，杜绝除零）；
// 回绕/溢出由 end<begin、capacity<end、begin 超上限挡住，对齐与步长倍数由 % elementSize 挡住，
// 条数由 count <= 64 挡住。
inline CsfVectorShape csf_classify_vector(const CsfRawVector& raw, std::size_t elementSize,
                                          std::size_t& count) {
    count = 0;
    if (elementSize != sizeof(std::uintptr_t) && elementSize != sizeof(std::int32_t))
        return CsfVectorShape::malformed;
    if (!raw.begin && !raw.end && !raw.capacity) return CsfVectorShape::empty;
    if (!raw.begin || !raw.end || !raw.capacity) return CsfVectorShape::malformed;
    if (raw.end < raw.begin || raw.capacity < raw.end) return CsfVectorShape::malformed;
    if (raw.begin > kCsfSnapshotAddressLimit) return CsfVectorShape::malformed;
    if (raw.begin % elementSize || raw.end % elementSize ||
        raw.capacity % elementSize) return CsfVectorShape::malformed;
    const std::uintptr_t bytes = raw.end - raw.begin;
    if (bytes % elementSize) return CsfVectorShape::malformed;
    const std::size_t entries = static_cast<std::size_t>(bytes / elementSize);
    if (entries > kCsfSnapshotMaxCount) return CsfVectorShape::malformed;
    count = entries;
    return CsfVectorShape::usable;
}

// 逐成员读取；遇第一个读失败即停该表并置 readFailed（避免级联垃圾读取）。
inline void csf_read_table_members(CsfSnapshotTable& table, bool pointerTable,
                                   std::uintptr_t targetPlayer, std::int32_t targetSlot,
                                   bool targetSlotValid, CsfSnapshotReader reader,
                                   CsfSnapshotReadStatus& readStatus) {
    // 只会是 4/8：调用方仅在 shape == usable 时进来，而 usable 已排除其它步长。
    const std::size_t elementSize = pointerTable ? sizeof(std::uintptr_t) : sizeof(std::int32_t);
    bool failed = false;
    for (std::size_t i = 0; i < table.count; ++i) {
        std::int32_t id = 0;
        if (pointerTable) {
            std::uintptr_t member = 0;
            if (!csf_checked_read(reader, table.raw.begin, i * elementSize, &member,
                                  sizeof(member), failed)) break;
            if (!member || member > kCsfSnapshotAddressLimit) {
                ++table.badMemberPointers;  // 空指针或超上限：不算身份，但不中止整表
                continue;
            }
            table.pointerMember[i] = member;
            if (member == targetPlayer) ++table.targetAddressHits;
            if (!csf_checked_read(reader, member, kCsfPlayerSlotOffset, &id, sizeof(id), failed))
                break;
        } else if (!csf_checked_read(reader, table.raw.begin, i * elementSize, &id, sizeof(id),
                                     failed)) {
            break;
        }
        table.member[i] = id;
        if (id < 0 || id >= static_cast<std::int32_t>(kCsfSnapshotMaxCount)) {
            ++table.badMemberIds;
            continue;
        }
        table.memberIdValid[i] = 1;
        if (targetSlotValid && id == targetSlot) ++table.targetSlotHits;
    }
    if (failed) readStatus = CsfSnapshotReadStatus::readFailed;
}

inline std::size_t csf_collect_member_ids(const CsfSnapshotTable& table, std::int32_t* out) {
    std::size_t n = 0;
    for (std::size_t i = 0; i < table.count; ++i)
        if (table.memberIdValid[i]) out[n++] = table.member[i];
    std::sort(out, out + n);
    return n;
}

// 指针表里真实存在的 Player* 地址集合（同样只取指针与 id 都读回的项）。
inline std::size_t csf_collect_member_pointers(const CsfSnapshotTable& table,
                                               std::uintptr_t* out) {
    std::size_t n = 0;
    for (std::size_t i = 0; i < table.count; ++i)
        if (table.memberIdValid[i]) out[n++] = table.pointerMember[i];
    std::sort(out, out + n);
    return n;
}

// 三表一致性判定（不读内存，只看已采集成员）。读取不全 => unknown（不可判定）。
inline void csf_evaluate_group(CsfSnapshotGroup& group) {
    if (group.readStatus == CsfSnapshotReadStatus::readFailed) {
        group.listState = CsfListState::unknown;
        return;
    }
    bool structureOk = true;
    for (std::size_t t = 0; t < kCsfSnapshotPointerTables; ++t) {
        const CsfSnapshotTable& table = group.pointers[t];
        if (table.shape != CsfVectorShape::usable && table.shape != CsfVectorShape::empty)
            structureOk = false;
        if (table.badMemberPointers || table.badMemberIds ||
            table.count > kCsfSnapshotMaxCount) structureOk = false;
    }
    if (group.ids.shape != CsfVectorShape::usable && group.ids.shape != CsfVectorShape::empty)
        structureOk = false;
    if (group.ids.badMemberIds || group.ids.count > kCsfSnapshotMaxCount) structureOk = false;
    if (!structureOk) {
        group.listState = CsfListState::malformed;
        return;
    }

    std::uintptr_t pointerSets[kCsfSnapshotPointerTables][kCsfSnapshotMaxCount];
    std::size_t pointerSizes[kCsfSnapshotPointerTables] = {};
    for (std::size_t t = 0; t < kCsfSnapshotPointerTables; ++t)
        pointerSizes[t] = csf_collect_member_pointers(group.pointers[t], pointerSets[t]);

    std::int32_t idSets[kCsfSnapshotPointerTables + 1][kCsfSnapshotMaxCount] = {};
    std::size_t idSizes[kCsfSnapshotPointerTables + 1] = {};
    idSizes[0] = csf_collect_member_ids(group.ids, idSets[0]);
    for (std::size_t t = 0; t < kCsfSnapshotPointerTables; ++t)
        idSizes[t + 1] = csf_collect_member_ids(group.pointers[t], idSets[t + 1]);

    // 重复检测（每张表内）：同一槽位 id 出现两次即身份重复——重复 Player* 必然如此，两个不同
    // Player* 携带同一槽位 id 同样如此。
    for (std::size_t s = 0; s < kCsfSnapshotPointerTables + 1; ++s)
        for (std::size_t i = 1; i < idSizes[s]; ++i)
            if (idSets[s][i] == idSets[s][i - 1]) {
                group.listState = CsfListState::duplicate;
                return;
            }

    // 两张指针表必须持有同一批真实 Player* 地址（先比指针集合，才能发现"不同地址却同槽位 id"），
    // 再要求两张指针表与 id 表的读回身份集合一一对应。
    bool agrees = group.ids.count == group.pointers[0].count &&
                  group.ids.count == group.pointers[1].count &&
                  pointerSizes[0] == pointerSizes[1] &&
                  std::equal(pointerSets[0], pointerSets[0] + pointerSizes[0], pointerSets[1]);
    for (std::size_t s = 1; s <= kCsfSnapshotPointerTables && agrees; ++s)
        agrees = idSizes[s] == idSizes[0] && std::equal(idSets[0], idSets[0] + idSizes[0], idSets[s]);
    if (!agrees) {
        group.listState = CsfListState::mismatch;
        return;
    }
    group.listState = (group.ids.count == 0) ? CsfListState::empty : CsfListState::consistent;
}

inline void csf_read_group(CsfSnapshotGroup& group, const std::uintptr_t* pointerOffsets,
                           std::uintptr_t idOffset, std::uintptr_t gameAddress,
                           std::uintptr_t targetPlayer, std::int32_t targetSlot,
                           bool targetSlotValid, CsfSnapshotReader reader) {
    group.readStatus = CsfSnapshotReadStatus::ok;
    bool headersOk = true;
    bool failed = false;
    for (std::size_t t = 0; t < kCsfSnapshotPointerTables; ++t) {
        CsfSnapshotTable& table = group.pointers[t];
        table.vectorOffset = pointerOffsets[t];
        if (!csf_checked_read(reader, gameAddress, pointerOffsets[t], &table.raw,
                              sizeof(table.raw), failed)) {
            headersOk = false;  // 仍把 6 个头都读一遍，日志里能看清哪几张读不到
            continue;
        }
        table.shape = csf_classify_vector(table.raw, sizeof(std::uintptr_t), table.count);
    }
    group.ids.vectorOffset = idOffset;
    if (!csf_checked_read(reader, gameAddress, idOffset, &group.ids.raw, sizeof(group.ids.raw),
                          failed)) {
        headersOk = false;
    } else {
        group.ids.shape = csf_classify_vector(group.ids.raw, sizeof(std::int32_t), group.ids.count);
    }
    if (failed) group.readStatus = CsfSnapshotReadStatus::readFailed;
    if (!headersOk) {
        group.listState = CsfListState::unknown;  // 头都没读全：短路，不读成员
        return;
    }
    for (std::size_t t = 0; t < kCsfSnapshotPointerTables; ++t)
        if (group.pointers[t].shape == CsfVectorShape::usable)
            csf_read_table_members(group.pointers[t], true, targetPlayer, targetSlot,
                                   targetSlotValid, reader, group.readStatus);
    if (group.ids.shape == CsfVectorShape::usable)
        csf_read_table_members(group.ids, false, targetPlayer, targetSlot, targetSlotValid,
                               reader, group.readStatus);
    csf_evaluate_group(group);
}

// 取一次只读快照。回调次数上界见文件头。targetPlayer == 0 表示本轮不提供目标对象：不读那三个
// 字段，也不算读取失败；目标玩家不在任何表里同样不算读取失败（只记零命中）。targetPlayer 非 0
// 时任何一次字段读取失败（含地址越上限/回绕被 checked 加法拦下）都算读取失败，但列表状态照旧
// 独立给出。
inline CsfPlayerSnapshot csf_take_player_snapshot(std::uintptr_t gameAddress,
                                                  std::int32_t targetSlot,
                                                  std::uintptr_t targetPlayer,
                                                  CsfSnapshotReader reader) {
    CsfPlayerSnapshot snapshot{};
    snapshot.game = gameAddress;
    snapshot.targetSlot = targetSlot;
    snapshot.targetPlayer = targetPlayer;
    snapshot.targetSlotValid = targetSlot >= 0 &&
        targetSlot < static_cast<std::int32_t>(kCsfSnapshotMaxCount);

    if (!reader || !gameAddress || gameAddress > kCsfSnapshotAddressLimit) {
        snapshot.readStatus = CsfSnapshotReadStatus::readFailed;
        snapshot.global.readStatus = CsfSnapshotReadStatus::readFailed;
        snapshot.cityState.readStatus = CsfSnapshotReadStatus::readFailed;
        snapshot.global.listState = CsfListState::unknown;
        snapshot.cityState.listState = CsfListState::unknown;
        return snapshot;
    }

    csf_read_group(snapshot.global, kCsfGlobalPointerOffsets, kCsfGlobalIdOffset, gameAddress,
                   targetPlayer, targetSlot, snapshot.targetSlotValid, reader);
    csf_read_group(snapshot.cityState, kCsfCityStatePointerOffsets, kCsfCityStateIdOffset,
                   gameAddress, targetPlayer, targetSlot, snapshot.targetSlotValid, reader);

    snapshot.readStatus = (snapshot.global.readStatus == CsfSnapshotReadStatus::readFailed ||
                           snapshot.cityState.readStatus == CsfSnapshotReadStatus::readFailed)
        ? CsfSnapshotReadStatus::readFailed : CsfSnapshotReadStatus::ok;

    snapshot.targetPointerFound = false;
    for (std::size_t t = 0; t < kCsfSnapshotPointerTables; ++t)
        if (snapshot.global.pointers[t].targetAddressHits ||
            snapshot.cityState.pointers[t].targetAddressHits) snapshot.targetPointerFound = true;

    // 三个对照字段各自独立读（与列表状态无关）；失败者保持 0 且降级聚合 readStatus。
    if (targetPlayer) {
        bool failed = false;
        snapshot.targetSlotIdRead = csf_checked_read(reader, targetPlayer, kCsfPlayerSlotOffset,
                                                     &snapshot.targetSlotId,
                                                     sizeof(snapshot.targetSlotId), failed) ? 1 : 0;
        snapshot.targetAliveRead = csf_checked_read(reader, targetPlayer, kCsfPlayerAliveOffset,
                                                    &snapshot.targetAlive,
                                                    sizeof(snapshot.targetAlive), failed) ? 1 : 0;
        snapshot.targetInitializedRead =
            csf_checked_read(reader, targetPlayer, kCsfPlayerInitializedOffset,
                             &snapshot.targetInitialized, sizeof(snapshot.targetInitialized),
                             failed) ? 1 : 0;
        if (failed) snapshot.readStatus = CsfSnapshotReadStatus::readFailed;
    }
    return snapshot;
}

} // namespace c6fw
