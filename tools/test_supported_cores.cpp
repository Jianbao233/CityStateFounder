#include "../native/csf_supported_cores.h"
#include <cstdio>
int main() {
    if (!csf_supported_core("324c51e9ea3531758842e16c69e6cddbefbb226c5b675c3d6e60111646c2e98c") ||
        !csf_supported_core("092abfbb2176f8df04b5212f819dc269dd83aea866ff05aaf489904a1ff7c41f") ||
        csf_supported_core(nullptr) || csf_supported_core("") ||
        csf_supported_core("092abfbb2176f8df04b5212f819dc269dd83aea866ff05aaf489904a1ff7c41e") ||
        csf_supported_core("092abfbb2176f8df04b5212f819dc269dd83aea866ff05aaf489904a1ff7c41f-extra")) return 1;
    std::puts("PASS: production core allowlist, old/new exact images and unknown/empty/prefix rejection");
}
