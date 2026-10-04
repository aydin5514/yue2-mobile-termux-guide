# اجرای YuE2 روی گوشی اندروید (Termux، فقط CPU)

یادداشت‌ها، اسکریپت‌ها و دو پچ کوچک برای اجرای محلی مدل **YuE2-3B** (تولید آهنگ) روی گوشی اندروید با [yue2.cpp](https://github.com/ServeurpersoCom/yue2.cpp)، بدون کامپیوتر و بدون GPU.

> راهنمای غیررسمی. ارتباطی با سازندگان YuE2 (M-A-P) یا سازنده yue2.cpp ندارد و از طرف آن‌ها تأیید نشده. اعتبار مدل و runtime مال خودشان است.

نسخه انگلیسی (کامل‌تر): [README.md](README.md)

## نتیجه

- گوشی: Poco F7 Pro، ۱۲ گیگ رم، Termux، فقط CPU
- مدل: `YuE2-3B-Q6_K.gguf` و `YuE2-Vae-F32.gguf` (و اختیاری `SheetSage2-Q8_0.gguf` برای کاور)
- مصرف رم سرور: حدود ۱٫۷ تا ۲٫۷ گیگ
- یک آهنگ **۱۰ ثانیه‌ای با ۱۲ مرحله NAR و ۶ ترد**: حدود **۴ دقیقه**
- آهنگ‌های بلند خیلی کند هستند (۲۵۵ ثانیه با ۳۲ مرحله: هر مرحله NAR حدود ۴۱۵ ثانیه، یعنی چند ساعت)

## ۱. نصب Termux

Termux را از ریلیزهای رسمی گیت‌هاب (`github.com/termux/termux-app`) نصب کن، نه پلی‌استور. هشدار «ریسکی» Play Protect برای Termux عادی است.

```bash
pkg update
pkg install -y git cmake clang make python python-pip
termux-setup-storage
```

## ۲. بیلد

```bash
git clone --recurse-submodules https://github.com/ServeurpersoCom/yue2.cpp
cd yue2.cpp
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . -j6
cd ..
```

ریپوی اصلی خودش یک اسکریپت `buildtermux.sh` هم دارد. من با همان دستورهای بالا بیلد کردم و این دو را با هم مقایسه نکرده‌ام، پس آن را هم ببین.

## ۳. مدل‌ها

مدل‌ها از [Serveurperso/YuE2-GGUF](https://huggingface.co/Serveurperso/YuE2-GGUF) گرفته می‌شوند و اینجا بازنشر نشده‌اند. من با Chrome دانلود کردم (برای کنترل اینترنت) و کپی کردم:

```bash
mkdir -p models
cp ~/storage/downloads/YuE2-3B-Q6_K.gguf models/
cp ~/storage/downloads/YuE2-Vae-F32.gguf models/
cp ~/storage/downloads/SheetSage2-Q8_0.gguf models/   # اختیاری
```

### حتماً هش را چک کن

اولین فایل VAE من **حجم درست ولی محتوای خراب** داشت و همه خروجی‌ها نویز بود. بعد از دانلود دوباره درست شد:

```bash
sha256sum models/*.gguf
```

با SHA256 صفحه Hugging Face مقایسه کن. برای `YuE2-Vae-F32.gguf` هش درست من این بود: `93e49dfb1970e89ad64cacb17cf13b5d05f6bb30ef7ed3adae3050bcb728638a` (صفحه HF را هم ببین، ممکن است فایل آپدیت شده باشد).

## ۴. بهینه‌سازی سرعت

- **تعداد ترد:** پیش‌فرض پروژه `hardware_concurrency()/2` است (۴ ترد روی گوشی ۸ هسته‌ای). `scripts/apply-patches.sh` متغیر `YUE_THREADS` را اضافه می‌کند.
- **قفل روی هسته‌های قوی:** با `taskset -c 2-7` (روی گوشی من cpu0 و cpu1 کندترند).
- **استفاده دوباره از score و توکن‌ها:** فیلد `abc` مرحله score و فیلد `semantic_tokens` مرحله semantic را رد می‌کنند. این قابلیت را [README ریپوی اصلی](https://github.com/ServeurpersoCom/yue2.cpp) هم توضیح داده؛ من فقط یک روند کاری دورش ساختم.
- **ذخیره میانی:** پچ دوم هر ۱۰۰ توکن semantic را در `semantic_partial.csv` می‌نویسد، تا اگر اندروید Termux را بست، بشود بخش تولیدشده را رندر کرد.

### بنچمارک (فقط NAR، یک آهنگ، ۴ مرحله)

| ترد | میلی‌ثانیه برای هر مرحله |
|---|---|
| ۴ | ۲۲٬۰۲۹ |
| ۶ | ۱۷٬۷۳۲ |
| ۸ | ۲۰٬۴۰۱ |
| ۶ قفل‌شده روی cpu2 تا cpu7 | **۱۵٬۳۱۳** |

توجه: فقط یک گوشی و یک آهنگ، و گرما ±۱۰٪ نویز دارد. ۸ ترد فایده نداشت.

## ۵. پچ و اسکریپت

```bash
cd ~/yue2.cpp
bash /path/to/scripts/apply-patches.sh
cd build && cmake --build . -j6
cp /path/to/scripts/music $PREFIX/bin/music && chmod +x $PREFIX/bin/music
music
```

پچ برای کامیت `11c1ecb` نوشته شده. اگر نسخه فرق کند، متن پیدا نمی‌شود و هیچ تغییری اعمال نمی‌شود. برای گوشی خودت `YUE_CORES` را تنظیم کن (پیش‌فرض `2-7`).

## ۶. مشکلات

- **GPU:** Adreno 750 با OpenCL دیده شد ولی بیلد GPU به نتیجه نرسید، پس این راهنما فقط CPU است.
- **بسته‌شدن Termux:** باتری Termux را روی «بدون محدودیت» بگذار، wakelock را از نوتیفیکیشن بزن، گوشی را خنک نگه دار.
- **چسباندن چندخطی** در Termux گاهی خراب می‌شود؛ اسکریپت را یک‌جا یا دستورها را تک‌تک بزن.

## لایسنس

- اسکریپت‌ها و پچ‌های این ریپو: MIT
- yue2.cpp: MIT (Serveurperso)
- وزن‌های YuE2: از M-A-P، طبق صفحه GGUF با لایسنس **CC BY-NC 4.0**. بعضی پروژه‌ها از یک مجوز اضافه برای سازندگان فردی نام می‌برند. قبل از استفاده تجاری لایسنس رسمی وزن‌ها را خودت بخوان.
