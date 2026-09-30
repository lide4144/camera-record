# camera-record

**摄像头无损录制 + 实时预览** —— 一个 100 行的 shell 脚本，用系统自带的 `ffmpeg` 做两件事：
把摄像头原始的 MJPEG 流**零重编码**写进 `.mkv`，同时开一个实时预览窗。CPU 占用几乎为零，画质等于摄像头原画质。

```bash
camera-record                # 录 1080p30 + 麦克风，按 q 结束并保存
```

---

## 为什么写这个

在 ASUS ROG Flow Z13（Linux Mint 22.3 / X11）上，GNOME Snapshot 51（Flatpak）的预览会在
**第一帧之后彻底死锁**：整段运行只从 PipeWire 取到 5 个 buffer、只为 `gtk4paintablesink` 生成 1 帧纹理，
全部挤在启动后 0.4 秒内，随后进程 0.5% CPU 空转、GStreamer 线程全部停在 futex 等待；
切到红外摄像头同样只出一两帧就黑屏。内核层实测摄像头本身完全正常
（MJPG 1080p30 ≈ 26fps、IR 720p15 ≈ 14fps），所以问题在播放/预览那条链路上。

既然摄像头本身没问题，最省事的方案就是**绕开渲染框架，直接用 ffmpeg 对接 V4L2**：
不重新编码就不需要编码器，不经过 GL 就不会卡死，帧到即落盘。

## 技术亮点

| 亮点 | 说明 |
|---|---|
| **MJPG 直通，零重编码** | `-c:v copy` 直接把摄像头吐出的 JPEG 帧写进 mkv。画质 1:1、无转码损失、CPU 占用≈0、不需要任何硬件编码器 |
| **单进程双路输出** | 同一个 ffmpeg 同时喂两条路：`-map 0:v -c:v copy` 落盘，`-map 0:v -vf format=yuv420p` 进预览窗。绝不二次打开设备（V4L2 独占，双开必然 `Device or resource busy`） |
| **音画同步** | `-f pulse -i default -c:a aac -af aresample=async=1:first_pts=0`：以视频时钟为准丢弃/补齐音频，避免 USB 摄像头时间戳抖动导致的漂移与 `Non-monotonic DTS` |
| **四级自动降级** | 带音频+预览 → 纯画面+预览 → 纯画面+xv 预览 → 纯画面无预览。任何一级失败自动换下一级，不会一黑到底 |
| **零依赖、零安装** | 只用 `bash` + `ffmpeg` +（可选）`pulseaudio`。没有编译、没有 Python、没有 pip |

## 原理

```
        /dev/video0  (V4L2, MJPEG 1920x1080@30)
             │
             │  同一个 ffmpeg 进程
             ├── -map 0:v -c:v copy ──────────────► ~/Videos/Camera/2026-09-29_23-10-05.mkv
             │                                       （原始 MJPG 帧，画质无损）
             └── -map 0:v -vf format=yuv420p ─────► 预览窗口 (sdl，失败退 xv)
                                                    ▲
        -f pulse -i default ─ -c:a aac ─────────────┘  （音轨写进同一个 mkv）
```

为什么预览必须写 `format=yuv420p`：MJPG 解码出来是 `yuvj422p`，而 `sdl`/`xv` 输出设备都不收这个格式，
不转换就会以 `Unsupported pixel format 'yuvj422p'` 整条命令退出（连录制一起挂掉）。

## 安装

```bash
git clone <你的仓库地址> ~/Projects/camera-record
cd ~/Projects/camera-record
./install.sh          # 建立 ~/.local/bin/camera-record 软链 + 桌面菜单项
camera-record --selftest
```

`install.sh` 只做两件事：把本目录的 `camera-record` 软链到 `~/.local/bin/`，并按本机路径生成一个
`~/.local/share/applications/camera-record.desktop`（菜单里显示为「相机录制」）。删除软链即卸载。

## 使用

```bash
camera-record                     # 默认 RGB 摄像头 1920x1080@30 + 内置麦克风
camera-record /dev/video2         # 红外摄像头（自动用 1280x720@15）
camera-record /dev/video0 &       # 后台录制
NO_AUDIO=1  camera-record         # 不录声音
PREVIEW=xv  camera-record         # 换预览后端（sdl 默认 / xv / none 关闭预览）
OUT_DIR=~/桌面 camera-record      # 换个保存目录
camera-record --selftest          # 检查 ffmpeg 后端 / 设备 / 麦克风
```

**结束录制**：在预览窗口上按 `q` 或 `Esc`，或直接关掉预览窗口 —— ffmpeg 正常退出即文件已写好
（mkv 可以随写随用，异常断电也不会丢已成簇的数据）。

产物：`~/Videos/Camera/2026-09-29_23-10-05.mkv`，`ffprobe` 显示 `codec_name=mjpeg`（原始 MKJP）+ `aac`。

## 实测数据（ASUS 5M webcam `0bda:636e`，USB2 480M）

| 场景 | 命令 | 结果 |
|---|---|---|
| 1080p30 纯画面 | `ffmpeg -f v4l2 -input_format mjpeg -video_size 1920x1080 -framerate 30 -i /dev/video0 -c:v copy out.mkv` | 6.025s / 176 帧 ≈ **29.2fps** / 72MB |
| 1080p30 + 麦克风 | 同上 + `-f pulse -i default -c:a aac -b:a 160k -af aresample=async=1:first_pts=0` | 5.021s / 60MB / `aac 48000Hz 2ch` |
| 本脚本（sdl 预览+录制） | `camera-record` | 478 帧 / 16.07s = **30.0fps**，`mjpeg 1920x1080 avg_frame_rate=30/1` |
| 红外摄像头 | `camera-record /dev/video2` | `1280x720@15`（该设备上限） |
| 直接读内核上限 | MJPG 640x480 / 720p / 1080p / 2592x1944 | 全部 ≈ **26fps**（USB2 带宽足够，MJPG 是压缩流） |
| 反面教材 | `YUY2 1280x720`（未压缩） | 只有 **4.8fps** —— USB2 带宽吃满 |

> 结论：**MJPG 是这条路唯一正确的格式**。选 YUY2 会被 USB2 带宽掐死在 5fps。

## 常见问题

**`Device or resource busy`** —— V4L2 设备独占，别的程序（浏览器、会议软件、另一个录制进程）占着摄像头。
```bash
fuser -k /dev/video0        # 杀掉占用者
```
注意：杀掉一个 ffmpeg 后，本脚本的"降级重试"会再拉起一个来抢设备；要停就停整个脚本
（`pkill -f 'camera[-]record'` —— 注意 `pkill -x camera-record` 匹配不到，脚本的进程名是 `bash`），
或直接 `fuser -k /dev/video0`。脚本启动前会先检查设备是否被占用，被占用时直接退出并打印占用者 PID，
不再徒劳地重试四种方案。

**预览窗口黑屏 / 不出现** —— 换后端：`PREVIEW=xv camera-record`；在 Xephyr、无 GPU 加速或远程桌面上
`sdl` 常失败（`Error submitting a packet to the muxer: Operation not permitted`），换成 `xv` 即可。
纯后台录制用 `PREVIEW=none`。

**预览窗口能看见画面但截图是黑的** —— 正常。`sdl` 预览走 GL/加速曲面，X 截图（`import`、`scrot`）抓不到；
人眼看得到就行。要能截图的那种，用 `PREVIEW=xv`。

**文件太大** —— MJPG 1080p30 ≈ 13MB/s ≈ 780MB/分钟，这是摄像头原始数据量，不是脚本的锅。
要更小：`camera-record /dev/video2`（720p15 ≈ 1.1MB/s），或自己接一段 `-c:v h264_vaapi` 重编码
（本机可用的 VAAPI 编码器：`h264_vaapi / hevc_vaapi / av1_vaapi / mjpeg_vaapi`）。

**没有声音** —— 摄像头本身没有麦克风，脚本用的是系统默认录音源（本机为内置 `ALC294`）。
`pactl get-default-source` 能列出时才会加音轨，否则自动只录画面。

**为什么是 .mkv 而不是 .mp4** —— mkv 支持随写随播、异常退出不易损坏；且 MJPG 直通写 mp4 需要
正确的索引，中断即废。

## 环境

* Linux + X11/Wayland（预览窗需要 X11 或 XWayland）
* `ffmpeg`（实测 6.1.1）、`bash`、可选 `pulseaudio`
* V4L2 摄像头，支持 `MJPG`（绝大多数 USB 摄像头都支持）

## 许可

MIT
