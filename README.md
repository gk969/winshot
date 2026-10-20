# WinShot

Windows 屏幕截图工具，MFC C++ / Win32，x64，单个 exe。

**本项目的功能与交互借鉴了 QQ 截图。** 呼出热键、"整屏先冻结再框选"的操作顺序、选区下方那条横向工具栏、矩形 / 椭圆 / 箭头 / 画笔 / 马赛克 / 文字 / 序号这七种标注、长截图滚动自动拼接、钉在桌面、OCR 识字——这套用法都取自 QQ 截图。仓库里 `参考UI图/` 的 28 张图就是 QQ 截图的实际界面，本项目按它们逐张对齐实现：图标位置、工具栏高度与按钮间距、属性条的色块尺寸与间距、字号列表的行高，都是从那些图上一个像素一个像素量出来的，文件名即它对应的功能与状态（例如 `工具栏-矩形-点击后.png`、`文字-点击位置-输入时红色文本框.png`）。与 QQ 截图的差异只有一处：**屏幕录制**按钮按原位置画出但本期未实现，不可点。

---

## 下载

Release 版是单个可执行文件，没有安装程序，也不需要额外运行时（MFC 静态链接）：

| 文件 | 架构 | 大小 | 说明 |
| --- | --- | --- | --- |
| `winshot.exe` | x64 | 3.0 MB | 双击即运行，只在任务栏放一个图标 |

仓库：[github.com/gk969/winshot](https://github.com/gk969/winshot)（公开，默认分支 `master`）。

**下载：** [winshot.exe](https://github.com/gk969/winshot/releases/latest/download/winshot.exe)

> 仓库已经推到 GitHub 了，但**release 还没建**——现在 `releases/latest` 返回 404，仓库里也没有任何 tag，所以上面这个地址暂时点不开。在 GitHub 上建一个 release、把 Release 构建产物以 `winshot.exe` 这个名字作为资源传上去，链接就通了：`releases/latest/download/<名字>` 里的 `<名字>` 必须和资源文件名一字不差。在那之前，本机自己构建的 Release 产物在 `x64\Release\winshot.exe`。

运行环境：Windows 10 / 11 x64。OCR 需要系统装了对应的 `Windows.Media.Ocr` 语言包（中文识别需要中文 OCR 组件）。

---

## 功能

* **热键呼出**：`Ctrl+Shift+A`。按下的一瞬间整个虚拟桌面被冻结成一张位图，所以正在播放的视频、正在滚动的页面都会被当成静止画面截下来，不会截糊。
* **框选**：默认选中全屏，四周有蓝框。左键拖动新建选区，拖选区内部整体移动，拖 8 个手柄缩放，方向键 1px 微调（按住 `Shift` 变 10px）。
* **悬停预选**：还没选区时，鼠标停在哪个程序窗口上，那个窗口的可见边界就被选区同款蓝框描出来，跟着光标在窗口之间走；点一下就成了选区。框只是提示——点下去之前那个窗口仍然是暗的。
* **放大镜**：未选区时跟着光标的 5× 放大镜，带十字线和四行读数：选区尺寸、光标下的 `RGB:(r,g,b)`、`按c复制色号`、`鼠标右键自由截图`。按 `C` 把 `r,g,b` 复制进剪贴板并结束截图。
* **七种标注**：矩形、椭圆、箭头、画笔、马赛克、文字、序号。每种都有粗细三档 + 16 色色板的属性条；文字另有 8–32 号字号，马赛克另有模糊度滑块。已画好的元素可以点选、拖动、缩手柄、改粗细改颜色、`Delete` 删除。
* **撤销**：`Ctrl+Z` 或工具栏撤销，逐步回退每一次增删改。
* **四种输出**：复制到剪贴板（`✓`）、存 PNG 或 JPG（`Ctrl+S`）、钉在桌面、OCR 识字。
* **长截图**：选区变成实时画面的"洞"，滚动目标窗口，程序每 150ms 抓一帧自动拼接，结果可以远高于屏幕。停止滚动后可以编辑拼接结果，也可以直接存 PNG 或 JPG。
* **钉在桌面**：把选区贴回桌面成为独立窗口，截图退出后仍然存活，可拖动、滚轮缩放、复制、另存。
* **OCR**：用系统自带的 `Windows.Media.Ocr` 识别选区文字，结果开在一个非模态窗口里，可以全选复制。
* **托盘菜单**：截图、开机启动开关、关于、退出。

---

## 使用方法

### 呼出与退出

1. 双击 `winshot.exe`。没有窗口出现，只在任务栏右下角放一个图标（悬停提示 `WinShot  (Ctrl+Shift+A)`）。
2. 按 `Ctrl+Shift+A`，或者右键托盘图标点"开始截图"。整个桌面立刻变暗，全屏被选中，四周是蓝框。
3. 做完任意一次输出（`✓` / `Ctrl+S` / 钉图 / OCR）或按 `Esc` 就退出截图，回到托盘常驻。

热键被别的程序占用时不会静默失败：会弹气泡提示，托盘 tooltip 改文案，菜单项去掉快捷键标注，此时仍可用菜单里的"开始截图"。

### 选区

| 操作 | 结果 |
| --- | --- |
| 在暗处左键拖动 | 新建一个选区 |
| 在选区内部拖动 | 移动整个选区 |
| 拖 8 个手柄之一 | 缩放 |
| 方向键 | 移动 1px；按住 `Shift` 移动 10px |
| 悬停在某个窗口上（还没选区时） | 蓝框描出那个窗口的边界，点一下即为选区 |
| 右键（选区还是全屏且没画任何东西） | 复制整个屏幕并退出 |
| 右键点在选区外 | 全部重置：撤销所有绘制、清空撤销栈、收回已装的工具、选区回到全屏 |

选区不能缩到比已经画在上面的元素小，也不能把元素甩到框外——拖动和绘制都停在最后一次按住的点，而不是沿边滑动。

### 标注

工具栏从左到右：**矩形 / 椭圆 / 箭头 / 画笔 / 马赛克 / 文字 / 序号** ‖ **撤销 / 长截图 / OCR / 钉在桌面 / 屏幕录制（置灰）/ 保存** ‖ **✕ / 完成**。前七个是工具，装上一个之后它下方会再出一条属性条：

* **粗细**：三个点，分别是 2 / 4 / 8 px，默认中间那档。点画得比实际笔画大一半，否则 2px 的点在 37px 高的条里像个灰。矩形是唯一把最细那档读成 1px 的工具（发丝线），椭圆、画笔、箭头仍是 2px。
* **颜色**：16 色两行，默认红色。
* **文字属性条**：字号框。下拉列表是 8–32 的偶数共 13 行，框本身可以直接输入，奇数号就这么到。
* **马赛克属性条**：模糊度滑块，方块 4–24 px。

文字工具点击位置后直接在框里打字：

| 键 | 结果 |
| --- | --- |
| `Enter` | 插入换行 |
| `Ctrl+Enter` | 立即提交 |
| 点到别处（失焦） | 提交 |
| `Esc` | 撤销本次编辑 |

编辑中的标签就是它自己那个红框：红框和 8 个方形手柄是标签的几何，输入控件坐在框里，拖手柄就是在改正在输入的框。中文输入法直接在框内显示组合串和候选窗。

已画好的元素点一下即选中（红框 + 方形手柄），此时属性条改的是这个元素而不是工具默认值。手柄尺寸按元素种类给：矩形和箭头的手柄跟着它们抓的笔画一起长，椭圆和文本框取一半，画笔、马赛克、序号没有手柄（没有可标的角）。

### 长截图

1. 先框出要滚的区域，点工具栏的**长截图**。
2. 选区变成实时画面（一个洞），洞旁边显示已经拼了多少。滚动那个窗口，程序自动往下（或往上）拼。
3. 停止滚动后点 **编辑** 把拼接结果送回编辑器继续框选、标注，或点 **↓** 直接存 PNG / JPG，**✓ 完成** 复制到剪贴板，**✕** 放弃。

拼接结果可以高于屏幕：选区会跟着长到屏幕外，此时工具栏自动翻到选区上方。滚轮能落到洞下面的窗口上，快滚也不会把会话打断。上限 30000 px 高、256 MB 像素缓冲；画面跳变过大时停止自动拼接并提示，不会瞎猜偏移。

### 快捷键一览

| 键 | 作用 |
| --- | --- |
| `Ctrl+Shift+A` | 呼出截图（全局热键） |
| `Esc` | 退出截图；编辑文字时撤销本次编辑 |
| `Ctrl+Z` | 撤销 |
| `Ctrl+S` | 存 PNG / JPG |
| `Ctrl+Enter` | 提交文字 |
| `Enter` | 完成截图（复制到剪贴板并退出）；焦点在文字框里时是插换行 |
| `C` | 复制光标下的色号（放大镜在的时候），并结束截图 |
| `Delete` | 删除选中的元素 |
| 方向键 / `Shift`+方向键 | 选区移动 1px / 10px |

---

## 技术架构

### 进程与窗口

单实例：启动时抢 `Global\winshot.single.instance` 互斥体，抢不到就退出（全局名拿不到时退回会话内同名，非管理员会话也能挡住重复启动）。

常驻一个隐藏顶层窗 `WinShotSink`（`CHiddenWnd`），**故意不是 message-only 窗口**：`HWND_MESSAGE` 窗收不到广播消息，`TaskbarCreated`（Explorer 重启）就会丢，托盘图标从此永久消失。这个窗同时承担四件事：全局热键宿主、托盘回调宿主、`m_pMainWnd`（`CWinApp::Run()` 在 `m_pMainWnd` 为空时立刻返回 0，所以必须有个常驻窗占住这个槽，覆盖层和钉图才能来了又走而不结束消息循环）、以及开机启动注册表的读写方。

一次截图的窗口层次：

```
WinShotSink            隐藏顶层窗，全程存在
 └ WinShotOverlay      WS_POPUP | WS_VISIBLE | WS_CLIPCHILDREN, WS_EX_TOPMOST
    ├ WinShotToolbar   工具栏（WS_CHILD）
    ├ WinShotPropBar   属性条（WS_CHILD）
    └ WinShotTextEditor 文字输入面（WS_CHILD，里面是真正的 EDIT）

WinShotTipCard         顶层弹窗：WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW
WinShotPin             钉图，顶层：WS_EX_TOPMOST | WS_EX_TOOLWINDOW
长截图的 bar 与 tip     顶层弹窗
OCR 结果窗             普通顶层窗，非模态
```

覆盖层必须在抓屏之后创建，顺序反了它就会出现自己的背景里。钉图和 OCR 结果窗由 `CWinshotApp` 持有而不是由截图会话持有，所以截图退出后它们还活着。

工具栏和属性条是覆盖层的子窗，所以它们继承覆盖层的 topmost 槽位、随会话一起销毁；但也因为是子窗，`EnumWindows` 看不见它们（测试脚本要用 `EnumChildWindows`），而且它们的鼠标消息到不了覆盖层，得自己回调过去。tooltip 卡片反过来必须是顶层弹窗：只有这样才能浮在属性条上方而不被挤到下面去。

### 一帧是怎么画出来的

覆盖层不用 `WS_EX_LAYERED`，而是三个 32bpp DIB section（`DibCanvas`：一块 `CreateDIBSection` 的内存位图 + 一个 GDI+ face），最后 `BitBlt` 上屏：

| 缓冲 | 内容 | 重画时机 |
| --- | --- | --- |
| `m_base` | 冻结的 still + 已提交的标注。**故意不含选区**，所以拖动选区只需重绘它扫过的那条带 | 只在底下真的变了的地方重建 |
| `m_chrome` | dim 之上的一切：选区框、尺寸标签、放大镜、字号下拉、编辑框 | 每帧清空重画 |
| `m_out` | 装配处：`m_base` → dim → `m_chrome` → 拖动中的墨 | 每帧一次 |

三个缓冲而不是直接画到窗口，有两个各自独立的原因：

1. **原子性。** DWM 在 vsync 落下的任意时刻读 GDI 窗口的重定向表面，包括 paint 只画到一半的时候。早期版本 `OnPaint` 分六步把 still、dim、框、卡片交给窗口，就会看到 still 已经贴上、dim 还没上的半帧——表现是点一个形状或者拖选区时整屏闪一下。现在从 `m_out` 一次 `BitBlt` 上屏，半帧在结构上不可能出现。
2. **成本。** GDI+ 往窗口 DC 上画，不管画什么每次固定收约 0.35ms，一帧二十来次调用就是 7ms；往内存 DIB 上画低一个数量级。`m_chrome` 每帧只把上帧真正上墨的矩形（`m_chromeInk`）清掉并 `AlphaBlend` 回窗口，而不是整个更新区。

dim 也不走 `AlphaBlend`：GDI 加速的是 blend 到窗口 DC，而不是 blend 到 DIB section，同一张全屏 blend 前者 0.1ms、后者 40ms。改成 SSE2 逐字节缩放颜色分量（`_mm_unpacklo_epi8` + `_mm_mulhi_epu16` + `_mm_packus_epi16`）之后整帧 4.9ms。dim 色是 `0x99000000`，即 60% 不透明的黑，框外保留 40% 亮度。

**拖动中的墨画在 `m_out` 而不是 `m_chrome`。** GDI+ 解析抗锯齿边缘时按目标颜色混合并写出预乘结果；`m_chrome` 是透明黑，于是本该是"墨的一半叠在背景上"的边缘像素变成"墨的一半叠在黑上"再预乘一次，出现提交后的形状根本没有的暗边。编辑框和拖动方块标记仍留在 chrome 里，因为 chrome 缓冲在透明处的 `AlphaBlend` 就是恒等，照样盖得住。

### 坐标与 DPI

**全部几何都是物理像素**，只有字号和文本度量走 `Dpi::S()` / `Dpi::FontHeightForPoint()`。这样选区、标注、导出共用一套坐标，合成只是 clip 加 translate，缩放不会引入误差。

`app.manifest` 声明 `PerMonitorV2`，但**不重复声明 `dpiAware`**：MFC 的静态库已经合并进一个 `dpiAware` 元素，再写一遍会让合并后的 manifest 无效，exe 直接起不来。

### 各功能的实现方案

**抓屏**（`DesktopCapture`）—— `GetDC(NULL)` 把 `Dpi::VirtualScreen()` 整块 `BitBlt` 成一张 GDI+ 位图，坐标原点记下来。`Adopt()` 用于"编辑"交回一张拼接图（它锚在屏幕内而不是角上，覆盖层和合成器需要知道起点），`Detach()` 把被替换掉的 still 交还给"编辑"当框外的地面。

**热键与托盘**（`WinshotApp` / `HiddenWnd` / `TrayIcon`）—— `RegisterHotKey(MOD_CONTROL | MOD_SHIFT, 'A')`。托盘用 `Shell_NotifyIconW`，`NIM_ADD` 之后必须再发 `NIM_SETVERSION` 且 `uVersion` 要带在结构里（`NIM_SETVERSION` 从那里读，留 0 就把图标退回旧的消息布局）。一次真实右键会同时送 `NIN_KEYSELECT` 和 `WM_CONTEXTMENU`，只处理一个，否则菜单被关掉之后第二个会立刻把它顶回来。开机启动写 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 的 `WinShot` 值。

**选区**（`SelectionModel`）—— 8 个手柄 + 内部移动 + 方向键微调。`m_default` 表示"用户还没碰过选区"，`BeginCreate()` 在按下那一刻就清它，所以"有了选区才显示工具栏"这条规则不能只看 `IsDefault()`，还要看 `m_mode != Creating`，否则拖动途中工具栏就冒出来了。`SetKeepIn()` 传入已画元素的包围盒，缩放时把框顶回去，于是框永远不小于里面的东西。

**工具栏与属性条**（`ToolbarWnd` / `PropertyBarWnd` / `Toolbar.h` / `Glyphs`）—— 全部自绘。槽位由一张 `kSlots` 表定义（含分隔符位置），度量是从参考图量的逻辑像素常量。图标是矢量画的而不是位图：16px 位图在 133% 缩放下会糊。只有"完成"带文字标签，其余靠 tooltip。`Place(belowHeight)` 按"工具栏 + 属性条"整块的高度决定放选区下方还是翻到选区上方。可见性由 `COverlayWnd::LayoutChrome()` 统一管：只有选区被真正定下来之后才出现，用 `SW_SHOWNA` 显示（不激活子窗，焦点留在覆盖层）。

**标注模型与撤销**（`annot/`）—— `Annotation` 抽象基类 + 七个 shape，几何存 overlay client 像素。两个包围盒要分清：`BBox()` 是手柄所在的几何（对轮廓线来说就是中心线），`InkBBox()` 是落下墨之后真正覆盖的盒子（矩形描边居中于盒，半个笔宽挂在外面，它是唯一一个绘制盒不等于手柄盒的形状）。撤销栈存的是逆操作（Add / Remove / Replace）而不是列表快照——马赛克笔画列表的每次快照都会非常大。属性条的改动不进撤销栈：它们是 live 控件，没人指望"撤销"能一步步退回最后点过的那个色块。

**文字与输入法**（`TextEditor`）—— 用的是一个真正的 `EDIT` 控件（`ES_WANTRETURN`），透明地贴在标签自己的盒子里，而不是自绘光标。理由只有一个：真控件会让 IME 自己在框内画组合串、把候选窗停在光标处，这正是 `文字-点击位置-输入时红色文本框.png` 画的样子。`Enter` 插换行、`Ctrl+Enter` 提交、失焦提交、`Esc` 撤销本次编辑——`ES_WANTRETURN` 只挡得住 dialog manager 吃键，做不到后面这些，得自己拦 `WM_CHAR`。编辑期间这条标签被从 `m_base` 里摘出去：编辑器用 base 画自己的背景，留在里面的已提交字形会当成旧字透出来，变成双影；摘出去同时也让"取消"能把标签原样放回来而不是永久擦掉。字号和颜色对已选中的标签、对正在编辑的标签都立即生效——编辑器每次 paint 重读 ink，所以换色在光标还在字里的时候就看得见。

**马赛克**（`MosaicCache`）—— 把选区下的 still 加上已经画在纸上的墨，按 block 平均成方块，缓存成一张位图。只在 block 尺寸、选区或标注列表变化时重建，**绝不在拖动笔画期间重建**，这是 60Hz 重绘便宜的前提。带宽是粗细点的 4 倍：2 倍时最宽只有 16px 的条，盖不住 18px 的一行字。

**放大镜与取色**（`Loupe`）—— 只在未选区时画。117×85 的卡片 + 62px 的四行读数，5× 的 still 加十字线，卡片在光标右下 30px（它是用来看像素的，不能盖住那个像素），靠边时镜像到有空间的一侧。字体对象从外面传进来，因为卡片每帧都要画，每帧建一个 `Gdiplus::Font` 会计入成本。

**悬停预选窗口**（`WindowPick`）—— 从 `GetTopWindow(GetDesktopWindow())` 起步，用 `GetWindow(GW_HWNDNEXT)` 走真实的自上而下 z-order。这里踩过一个坑：`GW_HWNDPREV` 是往上爬而不是往下走，从最顶层开始它一次就返回 null，整趟遍历只有一个窗口长。用 `DWMWA_CLOAKED` 剔除被 DWM 藏起来的窗口——本机就有两个在 `IsWindowVisible` 眼里"可见"、却盖住每一个像素的窗口。边界取 `DWMWA_EXTENDED_FRAME_BOUNDS`（可见边界，不含不可见的阴影边距）。

**长截图拼接**（`longshot/`）—— 核心是一个刻意不带 MFC 和 GDI+ 依赖的纯 C++ 模块，好让它能单独编译单测：

1. 每行 BGRA 取样（每 4 个像素取一个，把 4K 一行压到几百次读）后哈希成 `uint64_t`，每个通道量化到 6 位，用来吸收滚动留下的亚像素抖动。
2. 拿已累积图末尾 B 行的签名带和新帧的签名对齐，**取最小的可用位移**：一份有重复模式的文档会在 `rows` 和 `rows+period` 都匹配，少拼一点还能救，多拼就是重复内容。
3. 向上滚走 `FindUpShift`（帧的头 B 行是未知内容）。
4. `FindInside` 判断"这一帧本来就已经在文档里"。两端的搜索只跟一端的带比，滚回已经拼过的地面时两边都对不上，会被读成一次翻页；这条判断把它和真的翻页分开，顺带消掉了每次超过一屏的长截图底部约 140 行重复内容。
5. 位移超过容忍行数就是 `jump`：停止自动拼接并提示，不猜。

**长截图的洞与滚轮**（`OverlayWnd::SetHole` / `LongShot`）—— 洞是靠**窗口区域**挖出来的，不用 layered 窗：不属于窗口的区域既透出桌面，也透入鼠标。代价是洞内本窗口 hit-test 透明，滚轮按光标位置直达下面那个页面，**永远进不了我们自己的消息处理**——所以节流闸门只能挂在 `WH_MOUSE_LL` 低级鼠标钩子上（只在长截图会话期间存在），那是 notch 唯一可达的地方。另外覆盖层还是会把 `WM_MOUSEWHEEL` 转发给 `WindowFromPoint` 找到的窗口，因为 Windows 是按焦点而不是按光标位置投递滚轮的。额度按拼接器的真实余量算，超出的一次直接丢弃：两次采样之间移动得比可匹配带还远的页面不是长截图，是两张不相干的截图。抓帧时隐藏光标——它就待在洞里，会被拼进去。

**钉图**（`PinWnd`）—— 无边框 topmost 顶层窗。client 区返回 `HTCAPTION` 所以能拖，只有角上的 ✕ 是 `HTCLIENT`（顺带要拦掉双击最大化）。尺寸只由滚轮决定：拖一个无边框矩形的边，误触比命中更容易。位图按自然尺寸存着，窗口是它的 `m_scale` 倍，所以放大回去不会重采样。中键、`Esc`、右键菜单（复制 / 保存 / 关闭）都能关掉它。

**OCR**（`OcrService`）—— C++/WinRT 调 `Windows.Media.Ocr`。引擎优先 `zh-CN`，其次 `en-US`，都没有就退回用户配置文件语言。BGRA 字节序和 `LockBits` 的 `Format32bppARGB` 一致，所以直接 `SoftwareBitmap::CreateCopyFromBuffer`，没有转换也没有 PNG 往返。识别从不在 UI 线程上跑：`StartAsync` 自己起线程、`winrt::init_apartment(multi_threaded)`（MFC 不为它没创建的线程初始化套间），完了把结果 `PostMessage` 回 `WM_APP_OCR_DONE`，位图是 move 进去的，所以截图可以先关掉而工作继续。结果窗非模态，而且要能设成 topmost——覆盖层是 topmost，压在它下面就等于看不见。

**输出**（`out/`）—— `RenderSelection` = 从 still 裁出选区 + 标注 clip 到同一个矩形。剪贴板同时写 `CF_DIB` 和 `CF_BITMAP`：`CF_DIB` 谁都收，但 .NET 的 `Clipboard.GetImage()` 之类按名字要 `CF_BITMAP`，只给前者它们渲染不出东西。PNG 和 JPEG 都走 GDI+ 编码器（按 MIME 找 CLSID），写哪一种**只看最终扩展名**：`.jpg`/`.jpeg` 走 JPEG，其余走 PNG。JPEG 要显式带质量参数（90），`EncoderParameter` 的 `Type` 必须是 `EncoderParameterValueTypeLong`、指针指向一个 `LONG`，类型不对 GDI+ 会静默忽略它并用编码器自己的默认 75，对截图里那种实色边框和文字有可见振铃。格式有两个地方能选——对话框的"保存类型"下拉，和自己敲的扩展名——两者必须给出同一个答案，所以规则只有一条：**名字里有扩展名就听名字的，没有就补下拉选中那一条的**。这里有个坑：`OPENFILENAMEW::lpstrDefExt` 是**单个**值、不跟随过滤器，写死 `L"png"` 的话 Windows 会在用户选了 JPEG 之后照样补 `.png`，下拉等于白选；所以它置空，默认名 `截图YYYYMMDDHHMMSS` 也去掉扩展名，扩展名按返回的 `nFilterIndex` 自己补。JPEG 没有 alpha 通道，这里不成问题：`RenderSelection` 裁到的每个像素都是不透明的桌面，盖不住的情况 `LockBits` 直接失败返回 nullptr，不会留下半透明像素，所以丢 alpha 是无损的。弹保存对话框之前必须先把 topmost 覆盖层降级，否则对话框开在它下面。

**图标**（`res/` + `winshot.rc` + `make_icon.ps1`）—— 一个 `res\winshot.ico`（16/24/32/48/64/128/256 七档）同时喂两处：`winshot.rc` 让它成为 exe 的文件图标，`TrayIcon.cpp` 用 `LoadImage(..., LR_SHARED)` 取同一个资源当托盘图标，所以两者不可能长得不一样。`LR_SHARED` 的句柄不属于我们，正好配合 `TaskbarCreated` 上的 Remove + Install（自己销毁一个共享句柄会把别人手里的也抽走）。`.ico` 是手写出来的（本机没有 ImageMagick，.NET 的 `Icon.Save` 只能写单尺寸）：`ICONDIR` + `ICONDIRENTRY[]` + 每档一个 32bpp BGRA DIB（`biHeight = 2*size`，尾部 AND mask 全 0）。形状取自 `res\截图.png`，只把描边染成产品蓝 `0xFF1E9FD4`——原描边 (51,51,51) 对这台机器的深色任务栏 (38,32,38) 只有 1.24:1 的对比度，换成产品蓝是 5.2:1。染色只在源图是消色差时才做，否则将来换成真彩色图标会被无声压平。

---

## 源码目录结构

```
winshot/
├── src/                    全部 C++ 源码
│   ├── annot/              标注模型（与窗口无关）
│   ├── session/            一次截图的会话与全部界面
│   ├── out/                输出：合成、PNG/JPG、剪贴板
│   ├── pin/                钉在桌面
│   ├── ocr/                OCR 引擎与结果窗
│   ├── longshot/           长截图：拼接算法、抓帧、控制器
├── res/                    图标源图与生成的 .ico
├── tests/                  拼接算法的单元测试
├── tools/                  端到端验收脚本与调试探针（PowerShell）
├── 参考UI图/               28 张 QQ 截图参考图，界面按它们实现
├── winshot.vcxproj         工程文件（VS2022 v143，x64，静态 MFC，Unicode，C++20）
├── winshot.rc              只有一条 ICON 语句（不含 manifest，见下）
├── resource.h              IDI_APP_ICON
├── app.manifest            PerMonitorV2 DPI + asInvoker
└── README.md
```

### 根目录

| 文件 | 作用 |
| --- | --- |
| `winshot.vcxproj` | 唯一的工程文件。`/permissive-`、`/W4`、`/bigobj /source-charset:utf-8`、预编译头 `stdafx.h`、多进程编译。`Stitcher.cpp` 单独设 `PrecompiledHeader=NotUsing`，好让单测能脱离 MFC 编译它。manifest 通过 Manifest 工具的 `AdditionalManifestFiles` 进来，所以 `winshot.rc` 里**不能**再写一份 RT_MANIFEST，那是重复 manifest 的合并错误。 |
| `winshot.rc` | 只声明 `IDI_APP_ICON ICON "res\winshot.ico"`。纯 ASCII（源 PNG 保留中文名，`.rc` 里只写 ASCII 路径，免得 rc.exe 在编码上找麻烦）。 |
| `resource.h` | 只有 `IDI_APP_ICON 101` 一个 ID。 |
| `app.manifest` | `PerMonitorV2` + `asInvoker`。 |
| `.gitignore` | `obj/ x64/ Debug/ Release/ .vs/` 和构建产物。`res/`、`*.ico`、`*.rc` 都不忽略——`.ico` 是构建输入，必须入库，不能构建时现生成。 |

### `src/` 顶层

| 文件 | 作用 |
| --- | --- |
| `stdafx.h` / `.cpp` | 预编译头。MFC + `windowsx.h` + `imm.h`（IME）+ `shellapi.h` + `dwmapi.h` + GDI+，以及 `gdiplus` / `msimg32`（`AlphaBlend`）/ `shcore` / `shlwapi` / `imm32` / `dwmapi` 的 `#pragma comment(lib, ...)`。 |
| `AppMessages.h` | 应用内消息 ID（`WM_APP_TRAY` / `_STARTCAPTURE` / `_OCR_DONE` / `_ENDCAPTURE` / `_EDITDONE` / `_LSEDIT`）、热键 ID、托盘菜单 ID。 |
| `Dpi.h` / `.cpp` | 物理像素与逻辑像素之间唯一的换算口：`ForWindow` / `ForMonitorOfPoint` / `S` / `FontHeightForPoint` / `VirtualScreen`。 |
| `WinshotApp.h` / `.cpp` | `CWinApp`。单实例互斥体、注册热键、启动/结束截图会话；**持有钉图窗和 OCR 结果窗**（不是会话持有，所以它们能活过截图），并顺手回收已经自毁的那些。刚钉下的那个在覆盖层消失后被聚焦，好让 `Esc` 能到它。 |
| `HiddenWnd.h` / `.cpp` | 常驻隐藏窗 `WinShotSink`。托盘回调、热键、`TaskbarCreated` 时重装托盘图标、托盘右键菜单、开机启动注册表。 |
| `TrayIcon.h` / `.cpp` | `Shell_NotifyIconW` 的薄封装：装 / 卸 / 改 tooltip / 弹气泡。图标从 `IDI_APP_ICON` 加载。 |
| `DesktopCapture.h` / `.cpp` | 冻结的整虚拟桌面 still，加 `Adopt` / `Detach` / `SetOrigin`，用来支持"编辑"把拼接图换进来、又把 still 还回去当框外的地面。 |

### `src/session/` —— 一次截图的会话与界面

| 文件 | 作用 |
| --- | --- |
| `CaptureSession.h` / `.cpp` | 一次会话的全部状态：still、选区、标注列表、撤销栈、装着的工具、属性条样式、文字编辑器、字号下拉、马赛克缓存。**所有标注改动都必须走 `Push*` / `Record*` 这一对**，撤销栈才不会和列表走散。`OnToolbar` 是工具栏槽位点击的唯一入口。`ResetCanvas` 实现框外右键的全量重置。 |
| `SelectionModel.h` / `.cpp` | 选区几何：8 手柄命中测试、内部移动、缩放、方向键微调、`IsDefault`（还没碰过）、`SetKeepIn`（不能缩到比已画元素小）。 |
| `OverlayWnd.h` / `.cpp` | 最大的一个文件（约 2200 行）：全屏覆盖层、三缓冲绘制、dim 的 SSE2 实现、全部鼠标键盘手势、光标形状、选区框与元素框、悬停预选框、尺寸标签、字号下拉、长截图的洞与 topmost 守卫。`DibCanvas` 结构也在这里。 |
| `Toolbar.h` | 界面共享词汇表：槽位枚举、从参考图量的全部度量、16 色色板、粗细三档、字号列表的换算、马赛克滑块的度量、默认样式（红色 + 中间那档粗细 + 18 号 + block 12）。 |
| `ToolbarWnd.h` / `.cpp` | 工具栏窗：槽位表、自绘按钮、命中测试、hover 高亮、tooltip 定时器、`Place(belowHeight)` 的翻边判断。 |
| `PropertyBarWnd.h` / `.cpp` | 属性条窗：三种布局（形状 / 文字 / 马赛克）、粗细点、色块、字号框（拆成 ▼ 条和可输入区两段）、模糊度滑块。字号输入框 `CFontEdit` 只收数字。 |
| `Glyphs.h` / `.cpp` | 工具栏图标的矢量绘制。 |
| `TextEditor.h` / `.cpp` | 文字输入面 `CTextEditor`（透明窗，自己用 `BltBase` 要背景）+ 里面的 `CTEditBox`（`Enter` 插换行、`Ctrl+Enter` 提交、双击打开时把光标放文末）。 |
| `Loupe.h` / `.cpp` | 放大镜卡片：`CardRect`（含靠边镜像）、`Sampled`、`Draw`、`CopyColor`。 |
| `WindowPick.h` / `.cpp` | `TopWindowUnder`：按真实 z-order 找光标下最顶的合格窗口，返回它的可见边界。 |
| `MosaicCache.h` / `.cpp` | 马赛克笔画采样的方块化位图缓存。 |

### `src/annot/` —— 标注模型

| 文件 | 作用 |
| --- | --- |
| `Annotation.h` | 抽象基类：`Draw` / `BBox` / `InkBBox` / `HitTest` / 手柄三件套 / `Translate` / `UpdateDrag` / `Commit` / `SetStyle` / `NeedsBBoxGuide` / `PenWidth`。 |
| `Shapes.h` / `.cpp` | 七个 shape 的实现，加上按粗细换算的映射函数：`BadgeRadiusForPen`、`MosaicBandForPen`、`RectPen`（唯一把最细档读成 1px 的那个）。文字换行、箭头锥形头、抗锯齿路径都在这里。 |
| `AnnotationList.h` / `.cpp` | 按 z 序（底→顶）持有全部标注；`TopAt` 命中测试、`DrawAll(skip)`；`HandleSize`（按种类给手柄半宽）和 `DrawSelection`（选中框 + 白心红方块）也在这里。 |
| `Commands.h` / `.cpp` | 撤销：`Edit{Add,Remove,Replace}` 的栈 + `ApplyUndo`。 |
| `HandleGeom.h` / `.cpp` | 8 手柄盒的通用几何：`BoxHandleAt`、`BoxResize`（跨过对边就翻转而不是求反）。 |
| `MosaicSource.h` | 马赛克采样的抽象接口，让 shape 不依赖会话。 |

### `src/out/`、`src/pin/`、`src/ocr/`、`src/longshot/`

| 文件 | 作用 |
| --- | --- |
| `out/Compositor.h` / `.cpp` | `RenderSelection`：裁出选区 + 标注 clip 到同一矩形。`off` 参数处理"编辑"交回的拼接图只覆盖那块空间一部分的情况。 |
| `out/Export.h` / `.cpp` | 按 MIME 找 GDI+ 编码器 CLSID、按最终扩展名写 PNG 或 JPEG（JPEG 质量 90）、`GetSaveFileName` 封装（两条过滤器、`lpstrDefExt` 置空、按 `nFilterIndex` 补扩展名）、`截图YYYYMMDDHHMMSS` 默认名。 |
| `out/ClipboardImage.h` / `.cpp` | 写 `CF_DIB` + `CF_BITMAP`。 |
| `out/ClipboardText.h` / `.cpp` | 写文本（`C` 复制色号、OCR 复制用）。 |
| `pin/PinWnd.h` / `.cpp` | 钉图窗：`HTCAPTION` 拖动、滚轮缩放、✕ 徽标、中键、右键菜单。 |
| `ocr/OcrService.h` / `.cpp` | C++/WinRT OCR：`Run`（同步）与 `StartAsync`（自己起线程 + `PostMessage`）。 |
| `ocr/OcrResultWnd.h` / `.cpp` | 非模态结果窗：只读编辑框 + 复制 + 关闭，可切 topmost。 |
| `longshot/Stitcher.h` / `.cpp` | 纯 C++ 拼接算法：`RowSignature` / `RowSignatures` / `FindShift` / `FindUpShift` / `FindInside` / `Tolerance`。不含 MFC 和 GDI+，所以能单独编译测试。 |
| `longshot/FrameGrab.h` / `.cpp` | 抓一帧洞内画面并顺手算好每行签名；抓时隐藏光标。 |
| `longshot/LongShot.h` / `.cpp` | 长截图控制器：挖洞、150ms 轮询、追加/前插行、缓冲扩容、`WH_MOUSE_LL` 滚轮闸门 `AllowWheel`、bar 与 tip 两个顶层弹窗、预览带绘制、`TakeResult`。上限 30000 行 / 256 MB。 |

### `res/`、`tests/`、`tools/`、`参考UI图/`

| 路径 | 作用 |
| --- | --- |
| `res\截图.png` | 图标源图（200×200 RGBA，四角裁切框）。 |
| `res\winshot.ico` | 由 `make_icon.ps1` 生成的七档 .ico，构建输入。 |
| `tools\make_icon.ps1` | 生成上面那个 .ico：读 PNG、染描边、重采样、手写 ICO 容器，然后把文件读回来逐条目校验，最后让 .NET 自己的图标读取器挑一档作为独立检查。 |
| `tests\stitcher_test.cpp` | 拼接算法的单元测试，独立编译，退出码即结论。 |
| `参考UI图\*.png` | 28 张 QQ 截图参考图，文件名即它对应的功能与状态。 |
| `tools\*.ps1` | 90 个 PowerShell 脚本，分两类：**53 条端到端验收脚本**（下表），和 **37 条一次性调试探针**（`*_probe.ps1`、`scan_*`、`crop*`、`kill_menu*`、`menu_owner*`、`tray_*` 等）。探针是当时怎么定位某个 bug 的记录，故意留着不删。 |

53 条验收脚本按它们盯的行为分组：

| 组 | 脚本 | 盯的行为 |
| --- | --- | --- |
| 抓屏与选区 | `smoke` `dim_check` `stage2_test` `stage2_drag` `click_full` `outside_click` `rclick_full` `drag_clamp` `mid_drag` `sel_flicker` `draw_freeze` | 选区与桌面逐像素对齐、dim 只盖框外、拖动被框硬停、框外右键的两种语义、按下不松手期间的画面 |
| 工具栏与属性条 | `stage3_tb` `stage3_flip` `toolbar_gated` `prop_default` `prop_dots` `font_size` `tip_layer` | 槽位与翻边、有了选区才出现、默认样式、粗细点位置与墨宽、字号列表、tooltip 层级 |
| 标注 | `stage4_test` `stage5_test` `stage5b_test` `stage5c_test` `anno_select` `anno_style` `arrow_head` `arrow_taper` `badge_size` `handle_shape` `mosaic_band` `rect_hairline` `pen_clean` `sel_keep_anno` `drag_ghost` `live_aa` `draw_probe` | 标注 + 撤销 + 输出、箭头/画笔/序号、文字与 IME、马赛克、选中改样式、手柄形状、1px 矩形、拖动中的抗锯齿 |
| 文字编辑 | `text_wrap` `text_wrap_fit` `text_edit_box` `text_ghost` `text_live_color` | 换行时机、编辑框就是标签的盒子、重编辑不出双影、编辑中改色即时生效 |
| 放大镜与光标 | `loupe_once` `cursor_shape` `hover_pick` `hover_flicker` | 放大镜只画一次、每种意图一个光标、悬停预选窗口 |
| 长截图 | `stage8_test` `ls_reverse` `ls_edit` `ls_throttle` | 拼接、反向拼接、编辑器、滚轮节流 |
| 输出与常驻 | `stage6_test` `stage7_test` `save_format` `pin_close` `tray_rclick` | 放大镜与钉图与 OCR、保存对话框两种格式（断言落盘文件的魔数）、钉图关闭、真实右键点托盘图标 |

---

## 开发调试迭代经过

项目从 2026-10-15 起，六天，七次提交。下面按实际经过记，包括走过的弯路。

### 10-15：一次把整条链路搭起来

第一版就把骨架走通：抓屏 → 覆盖层 → 选区 → 工具栏 → 七种标注 → 撤销 → 四种输出（剪贴板 / PNG / 钉图 / OCR）→ 长截图拼接。界面按 `参考UI图/` 逐张对，度量从图上量。同一批写下 17 条脚本和拼接算法的单元测试，其中 12 条（`smoke` 和 `stage2`–`stage8` 系列）到今天还在回归套件里——"每个阶段一条端到端脚本"从第一天就是做法，后面所有轮次都受它约束。屏幕录制按当时的决定本期不做，按钮画在原位置置灰。

### 10-17：整屏闪烁，根因不是画错

报上来的现象是"点一个形状或者拖选区时整屏闪一下"。第一反应是画错了，实际是**画得不够原子**：DWM 在 vsync 落下的任意时刻读 GDI 窗口的重定向表面，包括 paint 只画到一半的时候，而 `OnPaint` 分六步把 still、dim、框、卡片交给窗口，于是真的能看到 still 已贴、dim 未上的半帧。改成先在第三个缓冲里装配、再一次 `BitBlt` 上屏，这类 bug 从此在结构上不可能出现。

改成内存装配之后，dim 立刻变成瓶颈：GDI 加速的是 `AlphaBlend` 到窗口 DC，不是到 DIB section，同一张全屏 blend 前者 0.1ms、后者 40ms。换成 SSE2 逐字节缩放颜色分量，整帧 4.9ms。

同一轮还修掉一族症状各异、根因同一个的问题：拖动中的形状会消失、松手才出现；椭圆原地留下残影；箭头没有头；画笔笔画断在半路。全都是 damage rect 只算了新框没算旧框——受损矩形取前后两个盒子的并集才对。

这一轮写下 `sel_flicker` 和 `mid_drag`：**在手还没松开的时候采样**，而不是等动作落定。这一族 bug 只有在按住的过程中才看得见，落定之后屏幕上是正确的画面，脚本会一路绿灯。这个手法后来成为整套脚本的默认姿势。

### 10-18 上午：交互细化

一批小修，其中三处值得记：

* **tooltip 改成顶层弹窗。** 它原本是覆盖层自己画的，位置被压在属性条下面；改成顶层弹窗才能保持原来的位置、并且浮在宽度/颜色条上面。
* **框成为硬边界。** 原来是沿边滑动，改成停在最后一次按住的点。同时"在框外松手"要结束拖动。
* **右键和 `C` 都要挪到 button up 并吞掉点击。** 放在 button down 时，桌面会替这次点击回一个自己的右键菜单，看起来像是我们的菜单闪了一下就没了。

长截图这一轮变化最大：把"这一帧已经在文档里"识别出来（`FindInside`），于是拼接变成双向可用，而且顺带消掉了每次超过一屏的长截图底部约 140 行重复内容——之前每次都在底部重复一屏。预览按屏幕缩放显示但不改导出尺寸；编辑器锁框、裁剪文档、加可拖滚动条，滚轮方向和 Windows 一致。

### 10-18 晚：文字重编辑、手柄、滚轮节流

* **重编辑一个标签会显示两遍文字。** 编辑器用覆盖层缓存的 base 画自己的背景，而那块缓存里一直留着这条标签已提交的字形。改成整段编辑期间都把这条标签从 base 里摘出去——这同时也让"取消"能把标签原样放回来，而不是永久擦掉。
* **手柄从统一圆点改成按种类的方形。** 矩形和箭头的手柄跟着它们抓的笔画一起长（粗线配细标记抓不准），椭圆和文本框取一半（它们的手柄坐在用户本来就能看见的盒子上），画笔、马赛克、序号干脆没有手柄（没有可标的角）。抓取范围和绘制尺寸解耦，小标记仍然抓得住，大标记整体都能抓。
* **快滚一次就把会话判死，提示"画面变化过大"。** 根因是滚轮 notch 根本没进我们的处理：洞是靠窗口区域挖的，洞内本窗口 hit-test 透明，Windows 按光标位置而不是按焦点投递滚轮，于是它直达页面。闸门只能挂在 `WH_MOUSE_LL` 低级钩子上。额度也从常量改成跟拼接器的真实余量走——短选区以前会给两次装不下的 notch。

`ls_throttle` 这一轮改成**注入真实滚轮**而不是 post 一个到覆盖层：post 恰好是唯一绕过闸门的路径，测的是没有手会走的路，真的滚轮才测到用户实际走的那条。

### 10-19：编辑框与标签合一

现象是"重新编辑一个已经换行的标签，文字被摊平；缩放时留下旧框的残影"。原因是编辑时会另开一个按文本内容算出来的框，和标签自己的盒子是两个几何。改成**标签的盒子就是编辑框**：红框和 8 个方形手柄是标签携带的几何，透明 multiline edit 坐在里面，拖手柄就是在改正在输入的框。三个状态明确分开——未选中 / 选中（只有框，整框可拖）/ 编辑（框 + 手柄，里面是 I 型光标，`Enter` 插换行）。一个几何，从此不会互相跟不上。

同一轮：箭头尾从 2px 收到 1px 起；粗细点画大 50% 但不改它代表的笔宽（2px 的点在 37px 高的条里像个灰）；序号圆盘抗锯齿并分三档；文字只在右边缘离墨迹一个左margin 之内才换行；打开编辑时光标落在已有文末；马赛克带宽从粗细点的 2 倍改成 4 倍——2 倍时最宽只有 16px 的条，盖不住 18px 的一行字。

也是这一轮开始把调试证据截图（`出错截图/`）随 bug 一起提交，后来又判定它们不如脚本：那五张十字光标对比图删掉了，因为它们描述的行为已经由 `cursor_shape` 在活程序上盯住，参考图目录不再需要靠图片守规格。

### 10-20：拖动抗锯齿、字号、悬停预选

* **拖动中的形状有一圈提交后并不存在的暗边。** 拖动中的墨画在 `m_chrome` 里，而那块缓冲是透明黑；GDI+ 解析抗锯齿边缘时按目标颜色混合并写出预乘结果，于是本该是"墨的一半叠在背景上"的像素变成"墨的一半叠在黑上"再预乘一次。改成画到已经装配好的 `m_out` 上（still 和 dim 之后），拖动和提交就一致了。
* **字号列表只有六档，而且它和色板都改不了已经在纸上的标签。** 列表改成 8–32 的偶数共 13 行，框本身可以输入奇数号；两者对已选中的标签、对正在编辑的标签都立即生效（编辑器每次 paint 重读 ink，所以换色在光标还在字里的时候就看得见）。
* **呼出之后整屏选中，除了放大镜没有任何依据可选。** 加悬停预选窗口。走 z-order 时踩到 `GW_HWNDPREV` 是往上爬而不是往下走，从最顶层开始它一次就返回 null，整趟遍历只有一个窗口长——要用 `GetTopWindow` 起步配 `GW_HWNDNEXT`。还要用 `DWMWA_CLOAKED` 剔除被 DWM 藏起来的窗口：这台机器上就有两个在 `IsWindowVisible` 眼里"可见"、却盖住每一个像素的窗口。

`click_full` 这一轮改成把它点击点上盖住的窗口最小化、并在每条退出路径上恢复——因为悬停一个窗口不再等于悬停整屏。

### 10-20：图标、1px 矩形、工具栏门槛

* **exe 从来没有过文件图标**，托盘图标是代码画的（白底 + 四角蓝框 + 红点）。改成用 `res\截图.png` 生成一个 .ico 同时喂两处。动手前先测：原描边 (51,51,51) 对这台机器的任务栏底色 (38,32,38) 只有 **1.24:1** 的对比度，几乎看不见；换成产品一直在用的选区蓝 (30,159,212) 是 **5.2:1**。本机没有 ImageMagick（`convert` 是 FAT 转 NTFS 那个），.NET 的 `Icon.Save` 只能写单尺寸，所以 .ico 是手写容器。写完不能只看构建通过——`ICONDIR` 写错 Explorer 不报错，只显示默认图标——所以脚本把文件读回来逐条目校验，再让 .NET 自己的图标读取器挑一档做独立检查，最后从两个编好的 exe 上 `ExtractAssociatedIcon` 数蓝色像素（217 个，和 .ico 里 32px 那档完全一致，这才区分得开"资源在里面"和"那是 Windows 默认图标"）。
* **矩形最细档改成 1px，而且只有矩形。** 走 AA 的椭圆、画笔、箭头、序号保持 2px。这条改动天然干净：矩形的描边路径里没有任何 `SetSmoothingMode` 调用，继承的是 aliased 输出，1px 笔会被二值化成一根清晰的列，不会摊成两个半亮像素。验证用的是精确断言而不是 ±1 容差：同一个粗细点下矩形左边缘正好 1 列、椭圆至少 2 列。这里有个坑值得记：AA 的 2px 笔画会跨 2–3 列按 50/100/50 分布，**只有一列是全实**，所以"数实墨列"这个判据分不清 2px AA 和 1px，对照组必须换成含羽化的红占优判据。
* **工具栏从"一直显示"改成"有了选区才显示。** 可见性收归 `LayoutChrome()` 一处，判据是"选区已定且不在拖动中"——只看 `IsDefault()` 会在拖动途中就把工具栏放出来，因为 `BeginCreate` 在按下那一刻就清了它。副作用是放大镜（只在未选区时画）和工具栏从此互斥，`stage6_test` 里两条断言因此失去意义：一条反转，一条删掉。另外 `LoupeCursor` 必须一起加可见性守卫：`GetWindowRect` 对隐藏窗口照样返回真矩形，不加守卫放大镜会在一块什么都没画的空白处莫名其妙消失。

### 10-20：保存支持 JPG 与 PNG

* **只有 PNG 一条出路。** 加 JPG。唯一的设计问题是格式由谁决定——对话框的"保存类型"下拉，和用户自己敲的扩展名，两处都能选，必须给出同一个答案。定成一条规则：敲了扩展名听名字的，没敲就补下拉那一条的，写文件时按最终扩展名分派。连带两个坑：`lpstrDefExt` 是单个值、不跟随过滤器，写死 `L"png"` 会让下拉白选，所以置空；默认名 `截图YYYYMMDDHHMMSS.png` 里的 `.png` 也必须去掉，否则只动下拉不动名字的人永远拿到 PNG。JPEG 的质量参数要显式给全（`Type` 必须是 `EncoderParameterValueTypeLong`），类型不对 GDI+ 静默忽略并用默认 75。这条用一个一次性小程序量过：同一张图质量 75/90/99 分别是 37920/40417/42643 字节，参数确实被吃。
* **验收脚本第一次跑就暴露：保存对话框不是经典那个。** `GetSaveFileNameW` 在没有 `OFN_ENABLEHOOK`/`OFN_ENABLETEMPLATE` 时走 `IFileSaveDialog`，经典控件 id `cmb1`(0x47) 和 `cmb3`(0x4B) 根本不在窗口里，`GetDlgItem` 返回 0——而旧脚本能找到那些 Edit，靠的是 `EnumChildWindows`，它会递归，`GetDlgItem` 只看直接子窗口。文件名框是那个 control id 1001 的 `Edit`（地址栏 toolbar 共用同一个 id，所以类名必须一起判）；"保存类型"是个 control id 为 0 的 `ComboBox`，id 当不了定位依据，只能按形状找：和名字框同列、在它下面、且不在 `ComboBoxEx32` 里的那一个。两条都再拿布局交叉检查，认错了就在原地失败，而不是把路径敲进地址栏。
* **程序化改下拉不生效。** `CB_SETCURSEL` 加补发的 `WM_COMMAND`/`CBN_SELCHANGE` 会让 `CB_GETCURSEL` 报出新行，写出来却还是 PNG——对话框只认自己那个 combo 发的通知。改成真鼠标点开、方向键走一行、`{TAB}` 提交。`{ENTER}` 不行：它是对话框的默认按钮，当场就保存了，实测写出的是默认名。
* **改过格式之后连 `WM_SETTEXT` 写名字都不生效。** 换过滤器时对话框会自己改名字的扩展名并留一份自己的副本，`WM_SETTEXT` 只改了 Edit 的文本、没通知对话框，实测写出 `截图…jpg`。改成真键盘敲进去。这一条底下还埋着更阴的一点：对话框关掉之后 Edit 的句柄被回收，`WM_SETTEXT`/`WM_GETTEXT` 在一块废句柄上照样一进一出对得上，所以"名字回读一致"这个检查必须配一句 `IsWindow` 才作数。三轮断言的都是落盘文件的**魔数**，所以上面这些"看起来改了其实没改"的失败一个都逃不掉。

### 几条一直沿用的做法

* **每条被报出来的行为都要有一条端到端脚本盯着。** 脚本自己启动程序、驱动真实鼠标键盘（`mouse_event`）、抓屏断言像素，退出码就是结论。它们驱动的是全局鼠标、抓的是全屏，所以只能一条一条跑，不能并行。
* **在手还没松开的时候采样。** 这一族 bug（闪烁、残影、断笔、半帧）落定之后屏幕上都是正确的画面。
* **注入真实输入，而不是 post 消息。** post 出来的滚轮和 posted 的托盘通知都绕过过真实路径，把 bug 藏起来。
* **调试探针留着不删。** 37 条 `*_probe.ps1` / `scan_*` / `crop*` 是当时怎么定位的记录，不参与回归。
* **改行为要连测试一起改，并且让断言真的断言新行为**，而不是靠 ±1 容差蒙对过去（`prop_dots` 的 `$want` 从 `@(2,4,8)` 明确改成 `@(1,4,8)` 就是这个意思）。

---

## 构建

需要 VS2022（v143 工具集）+ Windows SDK 10.0.26100.0，静态 MFC。

```bash
msbuild winshot.vcxproj /p:Configuration=Release /p:Platform=x64
```

产物 `x64\Release\winshot.exe`（Debug 版在 `x64\Debug\`）。命令行构建要先 `call vcvars64.bat`。链接前先关掉正在运行的 winshot，否则 `LNK1168`。

拼接算法的单元测试独立编译，不需要 MFC：

```bash
cl /EHsc /std:c++20 /W4 /source-charset:utf-8 /Fe:obj\stitcher_test.exe /Fo:obj\ tests\stitcher_test.cpp src\longshot\Stitcher.cpp
```

跑验收脚本（一次一条，`$?` 是结论）：

```bash
powershell -NoProfile -File tools\stage2_test.ps1
```

脚本假设显示器是 3840×2160 @ 96 DPI（此时 `Dpi::S(hwnd,n) == n`，覆盖层 client 空间等于屏幕空间），每条像素断言都建立在这上面。有两条历史上比较飘：`tray_rclick` 在任务栏条里按像素形状找图标（托盘布局每次不同，而且选区蓝并不是它独有的颜色——同一条里蓝牙和手机互传的图标也过同一个判据，真正认出我们那个的是四行菜单），`font_size` 在"字体列表按完之后紧接着双击"那一步偶尔失败。单条失败重跑一次即可。锁屏会让一整批脚本同时失败（屏幕全黑、合成输入送不进去），别把它读成八条回归。

---

## 已知限制

* **DRM 保护的内容**（部分播放器、宽屏保护的视频）用 `BitBlt` 抓回来是纯黑。这是系统行为，无法绕过。
* **屏幕录制未实现**，按钮按参考图位置画出但不可点。
* **多显示器混合 DPI**：跨屏的覆盖层只拿到主屏 DPI。因为全部几何都用物理像素，覆盖层本身每屏都对；只有内联文字编辑框在异 DPI 屏上字号会略偏。
* **长截图会把吸顶表头、固定页脚这类内容重复拼进去**，需要事后手动裁剪。
* **1px 矩形在拖动过程中可能左右跳一列**：形状盒是浮点，aliased 输出会吸附而不是羽化。提交之后坐标固定，不会抖。
