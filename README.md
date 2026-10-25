# win-gui-shot-docx

把「某个 GUI 软件里真实跑出来的界面」截成图、自动校验、再插进 Word 文档的可复用流水线。

`仓库` https://github.com/baiyuexinxi/win-gui-shot-docx · `许可` MIT · `平台` Windows

为 Windows + DSH 设计，重点解决一个具体痛点：**没有图像输入能力时，怎么知道这张截图是不是废的。**

## 为什么不是"截个图而已"

一次真实任务（12 道 R 题的实验报告）里，首轮自动截的 10 张图只有 3 张能直接用：

- 5 张因为输出超过一屏，**顶部代码被滚出可视区**；
- 1 张截到了上一题的残留内容；
- 1 张只有表格尾巴，看不到表头。

全部靠人事后逐张看才发现。这个 skill 就是把"事后发现"变成"当场判定"：

```
        截                       验
┌──────────────────┐    ┌──────────────────────────┐
│ 唤醒窗口          │    │ OCR 读字                  │
│ 只截目标区域      │───▶│ 首行锚点 / 尾部锚点 / 禁用词 │───▶ OK / RETRY / SPLIT / FAIL
│ 帧稳定代替死等    │    │ 尺寸门 / 空图门            │
└──────────────────┘    └──────────────────────────┘
```

## 快速开始

```powershell
# 1. 入口判据（A1/A2/A3 强制）
powershell -ExecutionPolicy Bypass -File scripts\gate.ps1 `
  -GateFile scripts\gate.json -AnswersFile my-answers.json

# 2. 回归自检（不碰真实窗口，用 fixtures 里的图）
powershell -ExecutionPolicy Bypass -File scripts\capture.ps1 `
  -Manifest examples\manifest-regression.tsv `
  -OutDir out -LogPath out\regression.json -Hook scripts\hook_stub.ps1
# 期望：SUMMARY ok=3 split=1 fail=1

# 3. 真实采集（需要 RStudio 在前台）
powershell -ExecutionPolicy Bypass -File scripts\capture.ps1 `
  -Manifest my-manifest.tsv -OutDir imgs -LogPath imgs\log.json `
  -Hook scripts\hook_rstudio.ps1

# 4. 图 + 图注 → Word（自动打中文字体补丁）
powershell -ExecutionPolicy Bypass -File scripts\to-docx.ps1 `
  -Manifest examples\manifest-docx.tsv -Out out\demo.docx -Title "实验报告"
```

manifest 每行：`名字|代码文件|head锚点|tail锚点|模式(first|any)|等待秒数`

## 判定阶梯

| 级 | 判据 |
|:---|:---|
| L0 | 尺寸下限（挡最小化窗口的假 rect） |
| L1 | OCR 行数 ≥ 2 |
| L2 | 前 6 行命中 head 锚点（Dice ≥ 0.55 或宽松包含） |
| L3 | 未命中禁用词（Error / 错误 / cannot open …） |
| L4 | tail 锚点存在（软） |

## 分派

| head | tail | 动作 |
|:---|:---|:---|
| 命中 | 命中 | OK |
| 丢失 | 命中 | **SPLIT** —— 内容还在，只是顶部滚出，交回作者按语义拆块 |
| 命中 | 丢失 | RETRY —— 没跑完或被截断 |
| 丢失 | 丢失 | RETRY —— 抓错图 |
| 任何 | 任何 | 重试一次仍不行 → FAIL |

`SPLIT` 的拆块权归作者，驱动不自动拆。**不允许**用缩小字号、删减输出、拼接图片来"消除"溢出。

## 目录

```
SKILL.md                    工作流、硬规则、脚本契约
LICENSE                     MIT
references/gate.md          入口清单（5 条判据 + 否决码）
references/split-policy.md  溢出拆图策略（R1–R6）
references/pitfalls.md      12 个实际踩过的坑
scripts/verify2.ps1         判定器：ACT/WHY/证据
scripts/capture.ps1         薄驱动：状态机 + 钩子
scripts/to-docx.ps1         图 + 图注 → docx（含中文字体补丁）
scripts/hook_rstudio.ps1    RStudio 采集钩子
scripts/hook_stub.ps1       测试桩（从 fixtures 拷图）
scripts/gate.ps1            入口闸门评估
fixtures/                   回归素材（5 张）
examples/                   manifest、锚点与 docx 示例
```

## 适用 / 不适用

**适用**：实验报告、操作手册、缺陷报告等"要证明我真跑过"的图文交付。

**不适用**：
- 浏览器页面 → 用 CDP，别截屏；
- 命令行结果 → 直接重定向 stdout；
- 绘图 → 让绘图库自己导出 PNG；
- 锁屏 / RDP 断开 / 需要无人值守 / 需要与他人同时用同一软件。

## 已知限制

- `TopFrac` / `RightFrac` 是按当前机器与布局标定的比例，换机器需复核（失败会被判定器暴露，不会静默出错）；
- 帧稳定检测分不清"跑完了"和"卡住了"，必须靠 tail 断言兜底；
- 锚点选词要挑 OCR 读得稳的（纯字母 / 纯数字优先）。
