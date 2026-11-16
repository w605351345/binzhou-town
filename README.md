# 《麦溪镇》Meadowbrook

> 明亮西式田园生活 RPG · Godot 4.3 + GDScript
> 工程版本 `0.1.2` · 设计口径 **75% 种田 / 5% 旅行青蛙 / 20% 古代戏剧本**

## 一句话

主角继承了外祖父留下的旧农场，在麦溪镇从一小片荒地重新开始。白天翻土、播种、浇水、收获与卖货，傍晚去镇上认识人、寄信，或到月桂剧场排一段没唱完的古戏。

## 核心设计

| 支柱 | 占比 | 玩家行为 |
|---|---:|---|
| 农庄经营 | **75%** | 翻土、播种、浇水、收获、扩建、出货、采集、钓鱼、畜牧、制造 |
| 旅行青蛙 | **5%** | 在邮局给远方联系人寄明信片，次日收到回信，不设强制日常 |
| 古代戏剧本 | **20%** | 收获作物解锁戏页，在月桂剧场选择分支、排练三幕并得到公演结局 |

第一天的目标必须在一局内闭环：

```text
翻地 → 播种 → 浇水 → 回农舍睡觉 → 次日看见作物生长
```

首个可收获作物约 4–5 个游戏日；完整游戏日约 18 分钟现实时间。积累 3 份作物后，指引会把玩家带到月桂剧场排练第一幕。

## 当前内容

| 内容 | 实装量 | 说明 |
|---|---:|---|
| 可进入场景 | 14 | 农场、农舍、镇中心、商铺、河湾、林地、剧场、矿洞、牧场、镇史馆 |
| NPC | 11 | 每人有日程、喜恶、生日、季节对白与好感故事 |
| 好感事件 | 33 | 每人三段，按好感阈值递进 |
| 作物 | 9 种 | 春播秋收、初霜、早收与秋翻 |
| 农田 | 9 → 24 块 | 木工房扩建，旧档坐标与地块状态保留 |
| 古戏 | 3 幕 × 3 场 | 剧情节点、分支选择、公演评价与结局 |
| 明信片 | 3 位联系人 / 6 张回信 | 次日投递、收藏、旅行见闻 |
| 生活系统 | 7 项技能 | 农耕、畜牧、采矿、制造、垂钓、采集、人情 |
| 经营系统 | 运输 / 牧场 / 矿洞 / 镇史馆 / 公共工程 / 农具升级 | 均有面板与存档状态 |
| 节日 | 4 个 | 春耕、河灯、秋收、冬歇 |
| AI 美术 | 4 张四季板、14 张地点概念图、11 张 NPC 立绘 | 主菜单、立绘与美术方向已接入；运行时地图仍由数据驱动 |

## 操作

| 键鼠 | 手柄 | 作用 |
|---|---|---|
| `WASD` | 左摇杆 / 方向键 | 移动 |
| `E` | A | 交互、对话、开门、调查、地块上下文农作 |
| `J` / `K` / `L` / `I` | X / Y / LB / RB | 翻土 / 浇水 / 播种 / 收获 |
| `R` | 右摇杆按下 | 秋翻地 |
| `TAB` | BACK | 背包 |
| `T` | 左摇杆按下 | 在农舍木床旁睡觉 |
| `ESC` | START | 暂停菜单（存档 / 读档 / 回主菜单） |

靠近 NPC、门、地块或互动物时，底部才显示对应提示；离开范围后自动收起。

## 场景

| ID | 场景 | 主要用途 |
|---|---|---|
| L01 | 柳溪农场 | 种田、扩建、出货、畜棚、南门去镇上 |
| L02 | 农舍 | 木床睡觉、铸铁灶做饭、储物、天气预报 |
| L03 | 麦溪镇中心 | 集市、公告板、公共工程、社交 |
| L04 | 杂货店 | 种子、工具、礼物与卖粮 |
| L05 | 老邮局 | 明信片、回信收藏与邮差日程 |
| L06 | 玉梅旅店 | 吃饭回体力、打听消息 |
| L07 | 麦溪诊所 | 恢复状态、医生日程 |
| L08 | 赵氏木工坊 | 农场扩建、制造、铁匠服务 |
| L09 | 河湾 | 钓鱼、采集、河岸散步 |
| L10 | 柳溪林 | 采集、矿洞入口 |
| L11 | 月桂剧场 | 古戏排练、分支选择与公演 |
| L12 | 北岭矿洞 | 矿层、矿石、战斗风险 |
| L13 | 牧云牧场 | 牲畜购买、喂养与产出 |
| L14 | 麦溪镇史馆 | 藏品捐赠与镇史里程碑 |

## 本地开发

```bash
godot --headless --import --quit

# 确定性美术：只补缺，不覆盖 AI 成品立绘/四季板
python3 tools/gen_art.py assets

python3 tools/validate_data.py data/
python3 tools/validate_ai_assets.py
```

测试组位于 `scripts/tests/`，使用 headless 逐组运行。发布前必须跑完整数据校验、Godot 导入与全部测试。

## 构建

```bash
# macOS universal
godot --headless --export-release macOS build/macos/BinzhouTown.zip

# Windows x86_64
godot --headless --export-release "Windows Desktop" build/windows/BinzhouTown.exe
```

最终安装包输出在仓库外：

- `/Users/chu/localspace/BinzhouTown-macOS-universal.dmg`
- `/Users/chu/localspace/BinzhouTown-Windows-x86_64.zip`

macOS 包会实际挂载并启动验收；Windows 包进行结构与资源完整性验收。

## 美术与音频管线

- `assets/art/concept/season_*.png`：主菜单四季板，来自 AI 母版并保留最终版本。
- `assets/art/ai/portraits/*.png`：MiniMax `image-01` 重绘的 NPC 头像母版。
- `assets/art/portraits/*.png`：对话立绘，运行时统一裁切为 256×256。
- `assets/art/ai/backgrounds/*.png`：地点概念图与旅行视觉参考。
- `assets/art/generated/*`：确定性运行时地形、道具与背景层。
- `assets/sprites/*`：角色、NPC、作物与物品。
- `assets/audio/music/*.wav`：14 首确定性循环配乐，按地图 `ambience` 切换并淡入淡出。

NPC 语音默认关闭，对话只保留字幕；场景音乐覆盖农场、镇上、河湾、林间、剧场、矿洞等全部地点。

```bash
# 使用 MiniMax image-01 重绘 NPC 头像，配置读取 ~/.codex/minimax.config.toml
python3 tools/generate_ai_assets.py --only portraits --force

# 重新生成全部场景循环配乐
python3 tools/gen_music.py --force
```

如后续需要重新生成其它概念图，也可使用 `tools/ai_imagegen.py` 或 `tools/generate_ai_assets.py`。

## 当前状态

- 已优化八方向移动与加减速手感、建筑落地碰撞、提示去黑边、NPC 辨识度、场景配乐、MiniMax 对话头像、画面亮度与时间流速。
- 已修复南门碰撞、农场出口、近距离提示、NPC 可见性、E 交互、ESC 模态叠加与体力/农时反馈。
- 全量 20 组 Godot headless 测试：**1993 通过 / 0 失败**；数据校验、控件校验与 AI 资产校验通过。
- macOS universal 包已在 DMG 中实际启动并跑通：新农庄、移动、E 翻土/播种、NPC 对话、暂停菜单、睡觉进入第 2 天。
- Windows x86_64 包已完成 PE/PCK 与 ZIP 完整性校验；当前机器无 Wine，未做 Windows 实机启动。

详细状态与设计口径见 `docs/麦溪镇-当前进度.md`。
