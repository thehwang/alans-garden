# Alan's Garden — MVP 原型

验证 [`../DESIGN.md`](../DESIGN.md) §12 的核心玩法：**方格细胞自动机 + 精确目标匹配**。

> 你给花设定「生长规则」（往哪些方向蔓延），点日出让花园按规则生长，
> 目标是让花朵**恰好长成目标图案**——不多（不能溢出 `!`）、不少（不能留空 `_`）。
> 这是把图灵的形态发生学包装成园艺解谜的最小可玩内核（纯逻辑 + 终端可视化）。

## 结构

```
Sources/GardenCore/      可复用核心库（代码/注释英文）
  Grid.swift             网格 / 单元格 / 方向 / 坐标
  GrowthEngine.swift     确定性 CA：同步生长一步、跑多帧、与目标比对
  Level.swift            关卡模型 + 2 个内置谜题 + 规则解析
  Renderer.swift         ASCII 渲染（带目标叠加，匹配状态一眼可读）
Sources/garden/          命令行演示（逐帧打印生长过程）
Sources/GardenApp/       macOS 图形界面（SpriteKit）
  main.swift             纯代码 AppKit 宿主（窗口 + SKView，无 .xcodeproj）
  GardenScene.swift      棋盘/目标虚影/花朵渲染 + 规则开关 + 生长动画 + 绽放反馈
Tests/                   确定性 / 单调生长 / 关卡可解 / 错误规则失败
```

## 关卡（机制爬升）

| 关 | 名称 | 教什么 |
|---|---|---|
| 1 | First Bloom | 四向绽放 → 菱形 |
| 2 | Garden Path | 方向控制（只向东 → 直线，绽放会溢出） |
| 3 | Around the Stone | 石头塑形（碎石碾出 L 形走廊，蔓延即填满） |
| 4 | Two Beds | 多色：A/B 对冲，精确二分花床 |
| 5 | Keep Your Distance | **抑制**：B 铺满花床但避开 A，留出十字空隙（形态发生的离散版） |
| 6 | Climbing Rose | **激活**：B 只在 A 旁边才长（`+A`），沿静止花架攀爬而非泛滥 |
| 7 | Tide Pools | **抑制成斑**：B 泛滥整床但避开每个 A，留出十字水洼（图灵斑点的负空间） |
| 8 | Sunrise Corner | **预算约束**：只填东北角，最多用 2 个方向——选对那两个 |

> 激活 `+X`（只在 X 旁长）+ 抑制 `~X`（避开 X）= 图灵反应-扩散系统的离散一对，能涌现镶边/斑点/条纹。

## 运行（图形界面 · macOS）

```bash
swift run GardenApp
```

> ⚠️ 需要从**真正的 Terminal.app**（或 Xcode）启动才能弹出窗口——从非 GUI 会话
> （如某些自动化/SSH 环境）启动时进程会运行但窗口不显示。

界面操作：
- 棋盘上**浅色虚影格**就是目标图案（带颜色的虚影表示该格要的花色）；`#` 是石头。
- 右侧每种花有方向开关（↑→↓←）和「avoid X」抑制开关——点亮即生效。
- **☀︎ Sunrise** 让花园按当前规则逐帧生长；顶部太阳条表示日照（步数预算）。
- 长成目标会**绽放**并提示成功；没长好会用大白话说"还差几格 / 溢出几格"。
- **Hint** 一键填入参考解，**Reset** 清回种子，**Next** 切换下一关。

## 运行（命令行 · 逐帧 ASCII）

```bash
swift run garden --level 1            # 菱形
swift run garden --level 4            # 双色对冲二分
swift run garden --level 5            # 抑制：B 避开 A 留出空隙
swift run garden --level 6            # 激活：B 沿 A 花架攀爬
swift run garden --level 7            # 抑制成斑：十字水洼图案
swift run garden --level 8            # 预算：只填东北角

# 自己试规则
swift run garden --level 2 --rule A=E --steps 6     # 只向东
swift run garden --level 2 --rule A=NSEW --steps 3  # 故意绽放 → 满屏 ! 溢出
swift run garden --level 5 --rule B=NSEW~A          # ~A = 避开 A
swift run garden --level 6 --rule B=NSEW+A          # +A = 只在 A 旁长

swift run garden --list   # 列出关卡
swift run garden --help
```

规则语法：`A=NSEW`（四向）/ `A=E`（只向东）/ `B=NSEW~A`（避开 A）/ `B=NSEW+A`（只在 A 旁长）
读图例：`字母` = 正确的花　`x` = 颜色错　`!` = 溢出　`_` = 还没长到　`.` = 空地　`#` = 石头

## 测试

```bash
swift test
```

## 设计对应

| 设计文档 | 原型实现 |
|---|---|
| §3 核心循环（设规则→生长→匹配） | `GrowthEngine.grow` + `evaluate` |
| §4 生长规则卡（方向蔓延） | `RuleSet` + `GrowthEngine.step` |
| §11 因果可读、目标驱动 | 逐帧 ASCII + 精确匹配胜负 |

> 下一步：把这套内核接上 macOS/iPad 的图形界面（反应-扩散着色器的美术 + 拖拽规则卡 + 绽放反馈）。
> 当前先用终端验证"拖规则养图案"的解谜手感是否成立——已成立。
