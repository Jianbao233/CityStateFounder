#pragma once

#include <cstddef>
#include <cstdint>

namespace c6fw {

// The verified XP2 vector layout, not a C++ library vector or allocator.
template <typename T> struct CsfEngineVector {
    T* begin;
    T* end;
    T* capacity;
};

enum class CsfListStatus { ready, registered, invalid, inconsistent, full };

template <typename T>
inline bool csf_vector_count(const CsfEngineVector<T>& v, std::size_t& count) {
    const auto begin = reinterpret_cast<std::uintptr_t>(v.begin);
    const auto end = reinterpret_cast<std::uintptr_t>(v.end);
    const auto capacity = reinterpret_cast<std::uintptr_t>(v.capacity);
    if (!begin && !end && !capacity) { count = 0; return true; }
    if (!begin || end < begin || capacity < end ||
        begin % alignof(T) || (end - begin) % sizeof(T) ||
        (capacity - begin) % sizeof(T)) return false;
    count = (end - begin) / sizeof(T);
    return count <= 64;
}

// Check BOTH lists before any write. Never repair a pre-existing one-sided
// registration by guessing which engine bookkeeping has already happened.
inline CsfListStatus csf_inspect_alive_lists(
    const CsfEngineVector<void*>& players, const CsfEngineVector<int>& ids,
    void* player, int slot) {
    std::size_t playerCount = 0, idCount = 0;
    if (slot < 0 || slot >= 64 || !csf_vector_count(players, playerCount) ||
        !csf_vector_count(ids, idCount)) return CsfListStatus::invalid;
    if (playerCount != idCount) return CsfListStatus::inconsistent;
    std::size_t matchingPlayers = 0, matchingIds = 0;
    for (std::size_t i = 0; i < playerCount; ++i) {
        if (!players.begin[i]) return CsfListStatus::invalid;
        if (player && players.begin[i] == player) ++matchingPlayers;
    }
    for (std::size_t i = 0; i < idCount; ++i) {
        if (ids.begin[i] < 0 || ids.begin[i] >= 64) return CsfListStatus::invalid;
        if (ids.begin[i] == slot) ++matchingIds;
    }
    if (matchingPlayers > 1 || matchingIds > 1) return CsfListStatus::inconsistent;
    if ((matchingPlayers != 0) != (matchingIds != 0)) return CsfListStatus::inconsistent;
    if (matchingPlayers) return CsfListStatus::registered;
    if (playerCount >= 64 || !players.end || !ids.end ||
        players.end == players.capacity || ids.end == ids.capacity) return CsfListStatus::full;
    return CsfListStatus::ready;
}

// Caller runs this only at the gameplay mutation point and catches native
// access faults. This is not a lock or a complete player activation transaction.
inline CsfListStatus csf_append_alive_lists(
    CsfEngineVector<void*>& players, CsfEngineVector<int>& ids,
    void* player, int slot) {
    if (!player) return CsfListStatus::invalid;
    const auto status = csf_inspect_alive_lists(players, ids, player, slot);
    if (status != CsfListStatus::ready) return status;
    // Prepare both entries before publishing either end pointer.
    *players.end = player;
    *ids.end = slot;
    ++players.end;
    ++ids.end;
    return csf_inspect_alive_lists(players, ids, player, slot);
}

} // namespace c6fw
