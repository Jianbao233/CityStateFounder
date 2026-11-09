#include <windows.h>
#include <bcrypt.h>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include "HookAPI.h"
#include "csf_log.h"
#include "csf_supported_cores.h"

namespace c6fw {
bool csf_bridge_prepare(HMODULE core);
void csf_bridge_gameplay(void* L);
void csf_bridge_ui(void* L);
}
namespace {
HMODULE self_module = nullptr;
wchar_t log_path[MAX_PATH] = {};
SRWLOCK log_lock = SRWLOCK_INIT;
bool loaded = false;

void init_log() {
    if (!GetModuleFileNameW(self_module, log_path, MAX_PATH)) return;
    if (!wcsstr(log_path, L"\\Binaries\\Win64\\Plugins\\GameCore\\")) {
        log_path[0] = 0;
        return;
    }
    // <mod>/Binaries/Win64/Plugins/GameCore/CityStateFounder.dll
    for (int i = 0; i < 5; ++i) {
        wchar_t* slash = wcsrchr(log_path, L'\\');
        if (!slash) { log_path[0] = 0; return; }
        *slash = 0;
    }
    wcscat_s(log_path, L"\\Logs");
    CreateDirectoryW(log_path, nullptr);
    wcscat_s(log_path, L"\\CSFNative.log");
}

bool pinned_core(HMODULE core) {
    wchar_t path[MAX_PATH] = {}, exe[MAX_PATH] = {}, expected[MAX_PATH] = {};
    if (!core || !GetModuleFileNameW(core, path, MAX_PATH) ||
        !GetModuleFileNameW(nullptr, exe, MAX_PATH)) return false;
    auto slash = wcsrchr(exe, L'\\');
    if (!slash) return false;
    *slash = 0;
    wcscat_s(exe, L"\\..\\..\\..\\DLC\\Expansion2\\Binaries\\Win64\\GameCore_XP2_FinalRelease.dll");
    if (!GetFullPathNameW(exe, MAX_PATH, expected, nullptr) ||
        CompareStringOrdinal(path, -1, expected, -1, TRUE) != CSTR_EQUAL) return false;
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr,
                              OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    unsigned char digest[32] = {}, buffer[65536];
    bool ok = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0;
    if (ok) ok = BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) >= 0;
    DWORD count = 0;
    while (ok) {
        if (!ReadFile(file, buffer, sizeof(buffer), &count, nullptr)) { ok = false; break; }
        if (!count) break;
        ok = BCryptHashData(hash, buffer, count, 0) >= 0;
    }
    if (ok) ok = BCryptFinishHash(hash, digest, sizeof(digest), 0) >= 0;
    if (hash) BCryptDestroyHash(hash);
    if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
    CloseHandle(file);
    char hex[65] = {};
    for (int i = 0; i < 32; ++i) sprintf_s(hex + i * 2, 3, "%02x", digest[i]);
    c6fw_log("official XP2 path=%ls sha256=%s pin=%s", path, hex,
              ok && csf_supported_core(hex) ? "PASS" : "FAIL");
    return ok && csf_supported_core(hex);
}
}

void c6fw_log(const char* format, ...) {
    if (!log_path[0]) return;
    va_list args;
    va_start(args, format);
    char text[1600] = {};
    vsnprintf_s(text, sizeof(text), _TRUNCATE, format, args);
    va_end(args);
    SYSTEMTIME now;
    GetLocalTime(&now);
    char line[1800] = {};
    int length = sprintf_s(line, "[%04u-%02u-%02u %02u:%02u:%02u.%03u] %s\r\n",
        now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond, now.wMilliseconds, text);
    AcquireSRWLockExclusive(&log_lock);
    HANDLE file = CreateFileW(log_path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                             nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        WriteFile(file, line, static_cast<DWORD>(length), &written, nullptr);
        CloseHandle(file);
    }
    ReleaseSRWLockExclusive(&log_lock);
}

extern "C" __declspec(dllexport) int OnLoad(const HookContext* context) {
    if (!HookContext_IsCompatible(context) || !context->Query || loaded) return 0;
    init_log();
    auto api = HookAPI_Resolve(context);
    if (!api->RegisterGameCoreScriptForGamePlay || !api->RegisterGameCoreScriptForUI) return 0;
    HMODULE core = GetModuleHandleW(L"GameCore_XP2_FinalRelease.dll");
    if (!pinned_core(core) || !c6fw::csf_bridge_prepare(core)) {
        c6fw_log("OnLoad rejected: unsupported official core or incomplete native bridge");
        return 0;
    }
    api->RegisterGameCoreScriptForGamePlay(c6fw::csf_bridge_gameplay);
    api->RegisterGameCoreScriptForUI(c6fw::csf_bridge_ui);
    loaded = true;
    c6fw_log("OnLoad ready v1.1.2; script hooks owned by shared Loader");
    return 1;
}

extern "C" __declspec(dllexport) void OnUnload() {
    // Loader removes the module's registrations before unloading it. No raw
    // patch, worker or borrowed official-core reference needs manual cleanup.
    c6fw_log("OnUnload; registrations owned by shared Loader");
    loaded = false;
}

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        self_module = module;
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}
