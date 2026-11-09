#pragma once
#include <cstring>

// Exact official Windows XP2 images. Build26407122 was compared against the
// original image by tools/verify_game_build.py; native code, data, unwind,
// relocations and non-metadata read-only data are identical. Unknown images
// remain rejected before resolving or calling any fixed native address.
inline bool csf_supported_core(const char* sha256) {
    return sha256 && (
        std::strcmp(sha256, "324c51e9ea3531758842e16c69e6cddbefbb226c5b675c3d6e60111646c2e98c") == 0 ||
        std::strcmp(sha256, "092abfbb2176f8df04b5212f819dc269dd83aea866ff05aaf489904a1ff7c41f") == 0);
}
