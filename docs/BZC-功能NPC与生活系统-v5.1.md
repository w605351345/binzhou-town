# 《宾州小镇》功能 NPC 与生活系统 v5.1

> **历史归档：系统清单仍可追溯，地域与项目名称已被西式田园版取代。当前口径见 `docs/麦溪镇-当前进度.md`。**

> 状态:✅ 已实装并通过本地验收
> 日期:2026-11-14
> 范围:L12-L14、5 名功能 NPC、七项生活技能、制造/畜牧/矿洞/博物馆/公共工程/农具升级/运输箱

## 1. 功能 NPC

| NPC | 身份 | 服务 | 地点 | 专属委托 |
|---|---|---|---|---|
| 石铁山 | 北街铁匠 | 农具升级 | L03 镇中心 | `q_shi_copper` |
| 姜牧云 | 牧云牧场主 | 买牲畜、草料、喂食 | L13 牧云牧场 | `q_jiang_eggs` |
| 何水根 | 河湾渔具商 | 买鱼饵、收鱼 | L09 河岸 | `q_he_fish` |
| 苏文博 | 镇史馆管理员 | 藏品捐赠与里程碑 | L14 宾州镇史馆 | `q_su_donation` |
| 郎三顺 | 旅行货郎 | 每日轮换货单 | L03 镇中心 | `q_lang_purchase` |

5 人均具备:

- 春/夏/秋/冬四段日常对白。
- 服务面板内的“聊两句”和“送份礼”入口。
- 日程、喜恶、生日、独立立绘与冬装精灵。
- 3 段好感事件,使全镇好感事件总数由 18 增至 33。
- 可接取、可推进、可交付的委托。

## 2. 生活系统闭环

| 系统 | 入口 | 核心行为 | 存档状态 |
|---|---|---|---|
| 七项技能 | 面板/HUD | 农耕、畜牧、采矿、制造、垂钓、采集、人情;最高 10 级 | 等级与经验 |
| 运输箱 | 农舍/L01 | 投入作物或可售物,次日结算金币 | 待结算物、累计收入、最近报告 |
| 制造 | 工作台/熔炉/腌菜坛 | 9 条配方;铡草料、鱼饵、储物箱、喷灌器、熔炉、腌菜坛、铜锭、铁锭、酸菜 | 库存与设施 |
| 畜牧 | L13 牧场 | 购买芦花鸡/奶山羊/长毛兔,喂草料,跨日产蛋/奶/毛 | 牲畜列表与累计产出 |
| 矿洞 | L12 矿洞 | 8 层探索、矿脉、守洞野兽、体力、生命、倒下回洞口 | 当前/最深楼层与统计 |
| 镇史馆 | L14 镇史馆 | 12 件藏品捐赠、重复校验、3 档里程碑奖励 | 已捐藏品与已领奖励 |
| 公共工程 | L03 公告/服务面板 | 河桥 → 小学屋顶 → 卫生所火墙 → 戏台灯光,顺序捐料 | 每项材料进度与完成列表 |
| 农具升级 | 石铁山服务 | 铁锹/水桶/镐各 2 级,消耗金币、铜/铁锭、煤;矿石需先在熔炉炼成锭 | 工具等级 |
| 货郎轮换 | 郎三顺服务 | 每日按存档日确定性抽取 3 件商品 | 商品由日期推导,无需额外状态 |

## 3. 数据与校验

运行时数据:

- `data/skills.json`:7 项技能、10 级门槛与经验曲线。
- `data/crafting.json`:9 条配方及工位/技能门槛。
- `data/livestock.json`:3 种牲畜、饲料与产出。
- `data/mine.json`:8 层矿洞、矿脉权重与怪物数值。
- `data/museum.json`:12 件藏品与 3 档里程碑。
- `data/community.json`:4 项公共工程及依赖链。
- `data/tool_upgrades.json`:3 类农具升级。
- `data/services.json`:渔具商参数与货郎轮换池。

`tools/validate_data.py` 已校验:

- 所有道具、作物、技能、工位、藏品、奖励、材料与货郎商品引用存在。
- 矿洞楼层连续、矿脉权重与 min/max 合法、怪物属性为正。
- 里程碑严格递增且不超过藏品总数。
- 公共工程依赖无环、奖励合法。
- 农具等级从 2 连续递增。
- 功能 NPC 四季日常对白完整。

## 4. 验收

- `test_life_systems.gd`:165 项通过。
- 全量 18 组 Godot headless 测试:1893 项通过 / 0 失败。
- 19 个场景冒烟无 `SCRIPT ERROR` / `Parse Error`。
- 数据、手柄映射、AI 资产与 Python 工具单测全部通过。

## 5. 已知边界

- 仍不包含完整婚姻、无限矿洞、全 NPC 社交网络或 38 名 NPC。
- AI 图仅作概念母版,运行时不直接加载 AI 概念图。
- Steamworks SDK 与商店页仍依赖外部账号;本地安装包不包含 Steam 功能。

## 6. 发行包与本地验证

2026-11-14 已从当前工作区重新导出双平台发行包:

| 平台 | 最终文件 | 大小 | SHA-256 |
|---|---|---:|---|
| macOS Universal 2 | `/Users/chu/localspace/BinzhouTown-macOS-universal.dmg` | 64 MB | `0f3b47a814d09ddae141d0567641f4ffdd71dd378c5850ecf715e7fd63b540d7` |
| Windows x86_64 | `/Users/chu/localspace/BinzhouTown-Windows-x86_64.zip` | 37 MB | `ced5a8bb73c742f7bb69588036b66cea2b5128af6fff487f78d27727507c572a` |

验证记录:

- macOS 应用包含 `x86_64 + arm64` 两个切片,ad-hoc 签名通过 `codesign --verify --deep --strict`。
- DMG 通过 `hdiutil verify`;已实际挂载,应用包含 `/Applications` 快捷方式,并安装到 `/Applications/Binzhou Town.app` 与 `~/Applications/Binzhou Town.app`。
- 从最终 DMG 安装后的 `/Applications/Binzhou Town.app` 实机验证主菜单、新游戏春季农场、HUD、地块 E 翻土与体力 `100→96`、背包、杂货店购买、暂停、存档、立即读档、铁匠服务面板与聊两句、暂停菜单退出。
- Windows 包内包含 `BinzhouTown.exe`、`BinzhouTown.pck` 与 `README-Windows.txt`;ZIP 通过 `unzip -tq`,exe 为 PE32+ x86-64,PCK 头为 `GDPC`,导出过滤已排除 `build/docs/tools/scripts/tests` 资源。
- Windows 导出时的 `rcedit` 警告只影响可执行文件资源元数据,不阻断导出;本机没有 Windows/Wine 运行环境,因此 Windows 侧完成了包结构、架构与资源完整性校验,运行性由同一 Godot 工程的 1893 项测试、19 场景冒烟及 macOS 发行包启动测试共同覆盖。
- 发行包未做 Apple 公证或 Windows 代码签名,首次启动可能触发 Gatekeeper/SmartScreen 提示。
