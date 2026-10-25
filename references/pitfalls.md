# 踩过的坑（按发现顺序）

这些不是理论风险，全部是实际让任务返工的问题。

## 1. 最小化窗口唤不醒

`ShowWindow(h, SW_RESTORE)` 对 RStudio 无效，`IsIconic` 仍为 True，rect 停在 `(-25600,-25600)`、尺寸 159×27。

**解法**：先 `SendMessage(h, 0x0112 /*WM_SYSCOMMAND*/, 0xF120 /*SC_RESTORE*/, 0)`，再 `ShowWindow` + `SetWindowPos(SWP_SHOWWINDOW)`。

## 2. 假 rect 骗过所有检查

最小化窗口的 `GetWindowRect` 返回 159×27 这类"合法但无意义"的值，`CopyFromScreen` 会截到一块黑。

**解法**：L0 尺寸门（宽 < 400 直接判废）。

## 3. 前台锁

`SetForegroundWindow` 返回 False，`GetForegroundWindow()` 不是目标窗口，随之而来的 `SendKeys` 会把内容打进别的窗口。

**解法**：`SendKeys("%")`（Alt）释放前台锁 → `SetForegroundWindow` → 仍失败则 `SwitchToThisWindow(h, true)`；最后再校验一次，不一致就退出，绝不盲发按键。

## 4. DPI 缩放

同一窗口在 `SetProcessDPIAware` 之前是 1550×926，之后是 1938×1158，按比例裁的常量会全部失效。

**解法**：进程内先 `SetProcessDPIAware()`；裁剪用比例，不用像素。

## 5. 剪贴板被抢

夸克云盘之类的同步工具会短时占用剪贴板，`Set-Clipboard` 抛 `Requested Clipboard operation did not succeed`，整个脚本中断。

**解法**：重试 25 次 × 250ms，仍失败则返回专用错误码，不中断后续 item。

## 6. OCR 丢提示符

控制台里 `> library(VIM)` 有时被识别成 `library(VIM)`（`>` 消失）。

**解法**：不要按 `>` 过滤代码行；改成"前 N 行任一行命中锚点"。

## 7. OCR 把下划线读成破折号

`find_words` → `find—words`，导致严格比较失败、连续两轮误判 SPLIT。

**解法**：包含式匹配用"宽松归一化"（只保留字母、数字、汉字）。

## 8. 锚点选词不当

`Bora`（Maserati Bora）被读成 `80ra`，于是"顶部丢了"被判成"抓错图"，动作从 SPLIT 变成 FAIL。

**解法**：锚点优先纯字母或纯数字、避开大小写混排；tail 锚点最好来自自己生成的稳定输出（如 `row 60`）。

## 9. 无 BOM 的 .ps1 含中文 → 静默语义错误

`$forbid = @("Error","错误",...)` 在 PowerShell 5.1 按 ANSI 解码后数组被截断，**L3 校验直接失效但仍返回 ACT=OK**。不报错、不崩溃，只是悄悄不检查。

**解法**：脚本纯 ASCII；中文进 UTF-8 数据文件；改完必须回归。

## 10. `Add-Type -AssemblyName System.Security.Cryptography` 不存在

`Get-FileHash` 是内置 cmdlet，不需要加载程序集；照抄某个片段会导致整个 hook 起不来。

## 11. `Where-Object` 单条结果没有 `.Count`

`($list | Where-Object {...}).Count` 在只命中一条时返回空，汇总行出现 `ok=13 split= fail=`——明细对、汇总错。

**解法**：一律写 `@(...).Count`。

## 12. 固定 sleep 不可靠

执行时间从 0.2 秒到 40 秒不等（多重插补、随机森林），拍短了截到半截，拍长了浪费。

**解法**：帧稳定检测（连续两帧 PNG 的 MD5 相同）；但仍需 tail 断言兜底——帧稳定分不清"跑完了"和"卡住了"。
