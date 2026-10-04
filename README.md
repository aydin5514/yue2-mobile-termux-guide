# YuE2 on an Android phone (Termux, CPU only)

Notes, scripts and two small patches for running **YuE2-3B** song generation locally on an Android phone with [yue2.cpp](https://github.com/ServeurpersoCom/yue2.cpp), with no PC and no GPU.

> Unofficial community guide. Not affiliated with or endorsed by the authors of YuE2 (M-A-P) or the author of yue2.cpp. All credit for the model and the runtime goes to them.

Persian version: [README.fa.md](README.fa.md)

## What worked

- Device: Poco F7 Pro, 12 GB RAM, Snapdragon (Adreno 750), Termux, CPU only
- Model: `YuE2-3B-Q6_K.gguf` + `YuE2-Vae-F32.gguf` (+ optional `SheetSage2-Q8_0.gguf` for covers)
- Runtime: yue2.cpp, commit `11c1ecb` (2026-09-28)
- RAM use stays around 1.7 to 2.7 GB for the server process

Typical time for a **10 s song, 12 NAR steps, 6 threads**: about **4 minutes** (score ~50 s, semantic ~65 s, NAR ~190 s, VAE ~9 s). A very long generated score can push this to ~6 minutes.

Long songs are slow. A 255 s song with 32 NAR steps needed ~415 s per NAR step (before core pinning), i.e. hours in total, so I stopped it. Keep songs short, or lower the step count.

## 1. Install Termux

Install Termux from its official GitHub releases (`github.com/termux/termux-app`), not from the Play Store. Play Protect may flag it as risky; that is expected for Termux.

```bash
pkg update
pkg install -y git cmake clang make python python-pip
termux-setup-storage
```

## 2. Build (CPU)

```bash
git clone --recurse-submodules https://github.com/ServeurpersoCom/yue2.cpp
cd yue2.cpp
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . -j6
cd ..
```

## 3. Get the models

Models are hosted at [Serveurperso/YuE2-GGUF](https://huggingface.co/Serveurperso/YuE2-GGUF). They are **not** redistributed here.

I downloaded them in Chrome (to control mobile data) and copied them over:

```bash
mkdir -p models
cp ~/storage/downloads/YuE2-3B-Q6_K.gguf models/
cp ~/storage/downloads/YuE2-Vae-F32.gguf models/
cp ~/storage/downloads/SheetSage2-Q8_0.gguf models/   # optional, for covers
```

### Verify the hashes (important)

My first VAE download had the **correct file size but was corrupted**. Every song came out as pure noise (a constant buzz) until I re-downloaded it. Check each file:

```bash
sha256sum models/*.gguf
```

and compare with the SHA256 shown on the file's page on Hugging Face. For `YuE2-Vae-F32.gguf` mine matched `93e49dfb1970e89ad64cacb17cf13b5d05f6bb30ef7ed3adae3050bcb728638a` (check the HF page in case the file was updated).

Symptom of a bad VAE: output is noise regardless of input. Test: `neural-codec --encode` then `--decode` on a real clip; a healthy VAE returns something close to the input.

## 4. Speed tweaks

### 4.1 Thread count

yue2.cpp picks `hardware_concurrency() / 2` threads (a hyperthreading assumption), which gives 4 on an 8-core phone. `scripts/apply-patches.sh` adds a `YUE_THREADS` environment variable.

### 4.2 Pin threads to the fast cores

Check core speeds:

```bash
for i in 0 1 2 3 4 5 6 7; do echo -n "cpu$i: "; cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq; done
```

On my phone cpu0 and cpu1 are slower (2.27 GHz) and cpu2 to cpu7 are faster (2.96 to 3.30 GHz). Using 6 threads pinned to those:

```bash
YUE_THREADS=6 taskset -c 2-7 ./build/yue-synth ...
```

### Benchmark (NAR only, same song, 4 steps, run one after another)

| Threads | ms per NAR step |
|---|---|
| 4 | 22,029 |
| 6 | 17,732 |
| 8 | 20,401 (one step spiked to 26 s) |
| 6, pinned to cpu2 to cpu7 | **15,313** |

Caveats: single phone, single song, and the phone heats up during runs, so expect ±10% noise. 8 threads gave no benefit, probably because the slow cores hold back the fast ones.

### 4.3 Reuse the score and semantic tokens

The request JSON accepts two optional fields:

- `"abc"`: a score (ABC text). If set, the slow score stage is skipped.
- `"semantic_tokens"`: comma-separated integers. If set, the semantic stage is skipped (replay).

Workflow (this is what `scripts/music` automates):

```bash
./build/yue-plan  --model models/YuE2-3B-Q6_K.gguf --request req.json --out score.abc
# put score.abc into req2.json as "abc", then:
./build/yue-synth --model models/YuE2-3B-Q6_K.gguf --vae models/YuE2-Vae-F32.gguf \
                  --request req2.json --out song.mp3 --tokens tokens.csv
# put tokens.csv into req3.json as "semantic_tokens"; now re-render cheaply:
./build/yue-synth ... --request req3.json --steps 32 --seed 7 --out final.mp3
```

Tips from testing:
- Score length is mostly luck (same short prompt gave 656, 1205 and 1900 tokens with different seeds). A long score makes the semantic prefill and NAR slower. Re-roll the seed if it gets long.
- Draft with few NAR steps, then re-render the good ones with more steps from the saved tokens. I hear a clear quality difference between 12 and 32 steps.

### 4.4 Save semantic tokens while generating

Semantic generation is a single long step; if Android kills Termux, hours of work are lost. `scripts/apply-patches.sh` makes the semantic stage write `semantic_partial.csv` (in the working directory) every 100 tokens. An interrupted song can then be rendered from the partial tokens (option 4 in `scripts/music`). It renders what was generated so far; it does not resume generation.

## 5. Patches

```bash
cd ~/yue2.cpp
bash /path/to/scripts/apply-patches.sh
cd build && cmake --build . -j6
```

The script changes `src/backend.h` (`YUE_THREADS`) and `src/generate.h` (partial save), and refuses to run twice. It was written against commit `11c1ecb`; on a different version the text match may fail, in which case it changes nothing.

## 6. The `music` launcher

`scripts/music` is an interactive menu (WebUI server, new song, re-render, render from interrupted song). Install:

```bash
cp scripts/music $PREFIX/bin/music && chmod +x $PREFIX/bin/music
music
```

Set `YUE_CORES` for your own phone (default `2-7`), for example `YUE_CORES=0-7 music`.

Songs are rendered into `~/yue2.cpp/songs/<date>/` and copied to your Download folder as MP3.

## 7. Things that did not work or need care

- **GPU:** the Adreno 750 is visible through OpenCL (`clinfo`), but I could not get a working GPU build, so this guide is CPU only. Vulkan was not verified.
- **Termux gets killed:** set Android battery usage for Termux to unrestricted, enable the wakelock in the Termux notification, and keep the phone cool. Phones throttle under long loads.
- **Q4 quantization:** I did not use it; the model author advises that quality drops.
- **Multi-line paste in Termux** sometimes garbles commands. Paste scripts as one block, or run commands one at a time.

## License and credits

- Scripts and patches in this repo: MIT (see `LICENSE`).
- yue2.cpp: MIT, by Serveurperso.
- YuE2 model weights: by M-A-P, licensed under **CC BY-NC 4.0** according to the GGUF page. Some projects mention an additional permission for individual creators; read the official license of the weights yourself before using generated songs commercially.
- Links: [yue2.cpp](https://github.com/ServeurpersoCom/yue2.cpp), [YuE2-GGUF](https://huggingface.co/Serveurperso/YuE2-GGUF).
