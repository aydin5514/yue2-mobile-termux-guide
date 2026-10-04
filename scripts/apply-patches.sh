#!/data/data/com.termux/files/usr/bin/bash
# Patches yue2.cpp (tested on commit 11c1ecb):
#  1) src/backend.h : YUE_THREADS env var for CPU thread count
#  2) src/generate.h: write semantic_partial.csv every 100 tokens
# Usage: bash apply-patches.sh [path-to-yue2.cpp]   (default ~/yue2.cpp)
set -e
cd "${1:-$HOME/yue2.cpp}"
python3 - << 'PY'
import sys

def patch(path, old, new, marker):
    s = open(path).read()
    if marker in s:
        print(path, ": already patched, skipping")
        return
    if s.count(old) != 1:
        print(path, ": expected text not found (different yue2.cpp version?), NOT changed")
        sys.exit(1)
    open(path, "w").write(s.replace(old, new))
    print(path, ": OK")

patch("src/backend.h",
      "int n = (int) std::thread::hardware_concurrency() / 2;",
      'const char *e = getenv("YUE_THREADS"); int n = e ? atoi(e) : (int) std::thread::hardware_concurrency() / 2;',
      "YUE_THREADS")

old = '''        if ((step % 100) == 0) {
            fprintf(stderr, "[AR] %s %d/%d\\n", label, step, s.max_tokens);
'''
new = old + '''            if (phase != YUE2_PHASE_ABC && !out->empty()) {
                FILE * pf = fopen("semantic_partial.csv.tmp", "w");
                if (pf) {
                    const std::vector<int> & pt = (*out)[0].tokens;
                    for (size_t k = 0; k < pt.size(); k++) {
                        fprintf(pf, k ? ",%d" : "%d", pt[k] - 151853);
                    }
                    fclose(pf);
                    rename("semantic_partial.csv.tmp", "semantic_partial.csv");
                }
            }
'''
patch("src/generate.h", old, new, "semantic_partial.csv")
PY
echo "Now rebuild: cd build && cmake --build . -j6"
