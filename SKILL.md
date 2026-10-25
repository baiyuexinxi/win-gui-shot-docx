---
name: win-gui-shot-docx
description: Windows 上将"某个 GUI 软件的真实运行界面"截成图、自动校验、再插入 Word/文档的可复用流水线。适用于实验报告、操作手册、缺陷报告等"必须证明我在这个软件里真的跑过"的图文交付。核心能力：按窗口标题定位并唤醒窗口、只截目标区域、用 Windows 内置 OCR 读出文字并按「首行锚点 + 尾部锚点 + 禁用词」自动判定截图是否有效（OK / RETRY / SPLIT / FAIL），裁剪成控制台条带，最后用 pandoc 生成 docx。当用户要求"截图"、"把运行结果放进 word"、"仿照某份报告的格式配图"、或需要在无图像输入的情况下判断界面内容时使用。
version: 1.0.0
tags:
  - screenshot
  - windows
  - ocr
  - docx
  - rstudio
  - lab-report
  - automation
  - 截图
  - 实验报告
related_skills:
  - office-docx
disable-model-invocation: false
---

# Windows GUI 截图 → 校验 → 入库

## 它解决什么问题

把"软件界面里的运行结果"变成"文档里一张可信的图"，并且**在没有图像输入的情况下也能判断这张图是不是废的**。

两件事缺一不可：

1. **截**：定位窗口、唤醒、只截目标区域；
2. **验**：用 OCR 读出文字，按锚点判定，废图不许静默存盘。

只做第一件，等于闭着眼睛交付。历史教训：12 张图里首轮只有 3 张能用，其余全靠人眼事后发现——本 skill 的价值就是把这个"事后发现"变成"当场判定"。

## 入口判据（不满足就别用）

| 项 | 要求 | 否决码 |
|:---|:---|:---|
| A1 | 能写出一句 `claim_it_proves`，且不能用数值/表格等价表达 | `DENY_TEXT` |
| A2 | 目标不在更优通道内（浏览器→CDP；命令行→stdout；绘图库→导出图片） | `DENY_CHANNEL` |
| A3 | 能给出 ≥8 字符的 ASCII 锚点，且能说明大致在第几行 | `DENY_NO_ORACLE` |

A4（会话 Active）、A5（n≥3）目前**只记录不阻断**。清单见 `references/gate.md`，可用 `scripts/gate.ps1` 机检。

## 五步工作流

```
1. 过闸门          → scripts/gate.ps1（A1/A2/A3 强制）
2. 写块 + 锚点     → examples/manifest.tsv 格式，每条 item 给出 head / tail 锚点
3. 采集 + 判定     → scripts/capture.ps1 调 hook，逐条调 verify2
4. 处置            → OK 收；RETRY 重采一次；SPLIT 交回作者拆块（见 split-policy）
5. 入库            → scripts/to-docx.ps1：图 + 图注成对进 docx（图不可单独存在）
```

## 脚本契约

| 脚本 | 入参 | 输出 |
|:---|:---|:---|
| `scripts/capture.ps1` | `-Manifest -OutDir -LogPath -Hook [-Verifier -MaxRetry]` | 逐行 `name ACT try head tail why`；`-LogPath` 写 JSON；末行 `SUMMARY ok= split= fail=` |
| `scripts/verify2.ps1` | `-Image -Head -Tail -Mode first\|any [-ScanLines -MinScore -RetryUsed -MaxHeight]` | `ACT=OK\|RETRY\|SPLIT\|FAIL`、`WHY=`、`SIZE=`、`LINES=`、`HEAD=分值@行号`、`TAIL=0/1`、`FORBIDN=` |
| `scripts/hook_rstudio.ps1` | `-CodeFile -OutPng -Wait -Attempt [-TopFrac -RightFrac]` | 截图到 OutPng；打印 `HOOK_OK/HOOK_NO_WINDOW/HOOK_NOT_FOREGROUND/...` |
| `scripts/hook_stub.ps1` | 同上 | 从 `fixtures/` 拷图，用于回归测试，不碰真实窗口 |
| `scripts/to-docx.ps1` | `-Manifest -Out [-Title -Pandoc -WidthIn -NoCaption]` | `DOCX_OK name images=N size=KB`；自动找 pandoc（PATH → RStudio 内置），并给 theme1.xml 打中文字体补丁 |
| `scripts/gate.ps1` | `-GateFile -AnswersFile` | `VERDICT=ALLOW` 或 `VERDICT=DENY A2:DENY_CHANNEL`，附 `PASS=` `WARN=` |

## 硬性规则

### 判定阶梯（verify2 内部）

| 级 | 性质 | 判据 |
|:---|:---|:---|
| L0 | 硬 | 400≤w、40≤h；条带模式另加 h≤MaxHeight（整窗用 `-Mode any` 不受限） |
| L1 | 硬 | OCR 行数 ≥ 2 |
| L2 | 硬 | 前 6 行任一行与 head 锚点 Dice ≥ 0.55，或宽松包含命中 |
| L3 | 硬 | 未命中 `forbid.txt` 中的词（Error / 错误 / cannot open …） |
| L4 | 软 | tail 锚点存在（决定 retry 还是 split 的关键） |

### 分派

| head | tail | 动作 |
|:---|:---|:---|
| 命中 | 命中 | OK |
| 丢失 | 命中 | **SPLIT**（顶部滚出，内容还在） |
| 命中 | 丢失 | RETRY（没跑完/被截断） |
| 丢失 | 丢失 | RETRY（抓错图） |
| — | — | 重试一次仍不行 → FAIL+BUDGET |

### 溢出（SPLIT）不许自动拆

驱动只上报 `NEEDS_BLOCK_SPLIT`，拆块必须由作者在**语义边界**完成（定义块 / 调用块）。
禁止用缩小字号、删减输出、拼接图片来"消除"溢出——那是拿可读性换通过率。详见 `references/split-policy.md`。

### 编码（血的教训）

- `.ps1` 脚本**只写 ASCII**。中文放 `forbid.txt` / `gate.json` / manifest 等 UTF-8 数据文件。
  无 BOM 的脚本含中文时，PowerShell 5.1 会按 ANSI 读，**可能不报错但让判断失效**（L3 曾因此静默关闭）。
- 需要写中文的命令，用 `powershell.exe -File` 跑脚本，而不是 `-Command` 拼接。

## 环境前提

- Windows + 交互式桌面（`quser` 显示 Active）；锁屏/RDP 断开时不可用；
- 目标软件在前台运行；同一时刻只驱动一个应用（键鼠注入不能并发）；
- 浏览器内页面请改用 `dsh_browser_*`，不要走本流程。

## 已知坑（详见 references/pitfalls.md）

1. `ShowWindow(SW_RESTORE)` 对某些最小化窗口无效 → 用 `SendMessage(WM_SYSCOMMAND, 0xF120)`；
2. `SetForegroundWindow` 被前台锁挡住 → 先 `SendKeys("%")` 释放，再 `SwitchToThisWindow`；
3. 最小化窗口的 rect 是假的（159×27）→ 必须做尺寸下限检查；
4. 剪贴板可能被同步工具抢占 → 重试 25 次；
5. OCR 会丢提示符 `>`，也会把 `_` 读成破折号 → 锚点匹配要宽松归一化；
6. 锚点选词要挑 OCR 能读稳的（`Bora` 被读成 `80ra`）；
7. 目标区域不要写死像素，用窗口比例；比例也是本机标定值，换机器要复核。

## 回归测试

```powershell
powershell -ExecutionPolicy Bypass -File scripts/capture.ps1 `
  -Manifest examples/manifest-regression.tsv `
  -OutDir out -LogPath out/log.json -Hook scripts/hook_stub.ps1
```

期望：`SUMMARY ok=3 split=1 fail=1`（覆盖 OK / SPLIT / FAIL 三条分支）。
改动 `verify2.ps1` 或锚点规则后**必须**重跑，否则视为未验证。
