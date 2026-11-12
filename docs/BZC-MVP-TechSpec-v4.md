# 《宾州小镇》MVP 技术需求清单 v4.0(黑龙江版)

> **文档版本**:v4.0(2026-11-12)
> **配套文档**:`docs/宾州小镇_完整游戏企划_v4.md` §8 / §10
> **代码仓库**:`github.com/w605351345/binzhou-town`
> **已落地状态**:Week 0 核心系统已实装,**92 项 headless 测试全部通过**

---

## 1. MVP 总览

**MVP 目标**:8 周内产出 **3-5 小时可玩 Demo**,证明三大支柱核心循环成立。

| 支柱 | MVP 占比 | 验证假设 |
|------|---------|----------|
| 种田 | 75% | "玩家愿意为一年一熟的深度农艺循环留存" |
| 通讯 | 5% | "明信片系统能带来情感钩子" |
| 历史剧 | 20% | "闯关东题材的季节性活动能撑起长期留存" |

---

## 2. 技术栈(已锁定)

```
Godot 4.3(.3 LTS 后即可,4.4/5.x 不进 MVP)
主语言 GDScript 90% + C++ 10%(性能关键)
静态数据 JSON(data/*.json) + Python 校验脚本
本地存档 JSON(v1.0 迁 SQLite)
云存档 Steamworks SDK 1.60+ / Steam Cloud
账号中心 Supabase(MVP 用本地账号,EA 上云)
CI/CD GitHub Actions(数据校验 + headless 自测 + 导出)
版本控制 Git / GitHub
```

**已验证环境**:Godot 4.3-stable.official.77dcf97d8 (headless),Linux x86_64

---

## 3. 已实装模块(Week 0 交付,含实测结果)

### 3.1 目录树(当前实际状态)

```
BinzhouTown/
├── project.godot                  # Godot 4.3 项目配置
├── data/
│   └── crops.json                 # 9 种作物 + 6 项冬季产出 + 农时元数据
├── docs/                          # 企划书 5 份
├── scenes/
│   ├── main_menu.tscn             # 主菜单(含性别切换)
│   └── game.tscn                  # 游戏根场景 + HUD
├── scripts/
│   ├── core/
│   │   ├── game_calendar.gd       # 四季农时(真实月份驱动)
│   │   ├── game_state.gd          # 全局状态(可序列化)
│   │   └── game_manager.gd        # autoload:日推进 + 存读档
│   ├── farming/
│   │   ├── crop.gd                # 作物模型(月份窗口/早收晚收/储藏)
│   │   ├── crop_database.gd       # 作物库 + 季节查询
│   │   ├── farm_plot.gd           # 地块状态机(8 态 + 秋翻地)
│   │   └── farm_system.gd         # 3×3 农场闭环
│   ├── player/
│   │   └── player_profile.gd      # 主角档案(双主角 D10)
│   ├── ui/
│   │   ├── main_menu.gd
│   │   └── game_hud.gd
│   └── tests/
│       └── test_core.gd           # headless 自测(10 组 92 项)
├── tools/
│   └── validate_data.py           # 静态数据校验(CI 必跑)
├── .github/workflows/ci.yml       # CI
├── README.md / LICENSE / .gitignore
```

### 3.2 四大差异化机制的代码落点

| 机制 | 实现位置 | 实现要点 |
|------|---------|---------|
| **一年一熟 / 冬季禁播** | `game_calendar.gd` + `farm_system.plant_crop()` | 冬季 `is_winter()` 直接拒绝播种;播种窗口按真实月份 |
| **早收腾茬 → 复种秋菜** | `crop.gd.can_sow_in_month()` + `farm_plot.gd` | 马铃薯/春小麦/亚麻 7-8 月早收 → 7 月可复种 `autumn_vegetable` |
| **秋霜冻死** | `farm_plot.advance_day()` | `month >= FROST_MONTH(10)` 且作物不在收获窗 → DEAD("秋霜冻死") |
| **秋翻地 +15%** | `farm_plot.autumn_plough()` + `crop.roll_yield()` | 秋季/冬季深翻标记 `autumn_plowed`,收获时产量 ×1.15 |

### 3.3 时间系统(GameCalendar)

```gdscript
# 真实月份驱动的四季(黑龙江物候)
const MONTH_SEASON := ["winter","winter","winter",  # 1-3月
                       "spring","spring",            # 4-5月
                       "summer","summer","summer",    # 6-8月
                       "autumn","autumn",            # 9-10月
                       "winter","winter"]            # 11-12月
const SEASON_LENGTH := {"winter":150, "spring":60, "summer":90, "autumn":60}
const DAYS_PER_YEAR := 360   # 12 月 × 30 天
```

**公开 API**:`get_season()` / `get_real_month()` / `is_winter()` / `is_sowing_season()` / `sowing_window_open()` / `advance_day()` / `advance_to_month()` / `advance_to_season()` / `season_cn()` / `season_desc()`

**信号**(GameManager):`day_started(day)` / `season_changed(season)` / `game_saved(slot)`

### 3.4 作物数据格式(data/crops.json)

```json
{
  "id": "corn",
  "name": "玉米",
  "category": "grain",
  "sowing_season": "spring",
  "harvest_season": "autumn",
  "plant_days": ["spring"],
  "plant_window": [4, 5],          // 连续区间 [起始月, 结束月]
  "harvest_window": [9, 10],       // 连续区间
  "growth_days": [150, 170],       // 对齐真实农时
  "yield_min": 3, "yield_max": 6,
  "buy_price": 12, "sell_price": 26, "seed_price": 30,
  "water_per_day": 1,
  "storage": "晾晒",                 // 窖藏 / 晾晒
  "storage_note": "收后在场院挂干，编成玉米辫子挂房梁",
  "early_harvest": false, "late_harvest": true,
  "origin": "松嫩平原主产玉米带，黑龙江是全国玉米产量第一大省",
  "flavor": "秋收后在场院上堆成金黄的玉米楼子",
  "mvp": true
}
```

### 3.5 地块状态机(FarmPlot)

```
UNTILLED ──till──> TILLED ──plant──> PLANTED ──advance──> GROWING ──成熟──> READY
   │                  ↑                  │                    │              │
   │                  │            缺水枯死 │              缺水枯死 │        harvest
   │                  │            秋霜冻死 │              秋霜冻死 │            ↓
   └──────────────────┴────clear_dead─────┴────────────────────┴──────> FALLOW
                                                                          │
                                                          till ──────────┘
```

**字段**:`index / state / crop_id / days_grown / days_watered / last_watered_day / dead_reason / sown_month / autumn_plowed`

### 3.6 主角档案(D10 双主角)

```gdscript
enum Gender { MALE, FEMALE }
# 数值零差异;仅以下项不同:
#   display_name()  → 林砚舟 / 林晚舟(可自定义)
#   honorific()     → 他 / 她
#   立绘与对白称呼
#   主菜单 ← → 切换,存档序列化保留
```

---

## 4. MVP 期间待实现(Week 1-8)

| # | 模块 | 目标文件 | 优先级 |
|---|------|---------|--------|
| 1 | 玩家控制器(4 方向 8 帧) | `scripts/player/player.gd` | P0 |
| 2 | 黑土地场景 + 瓦片地图 | `scenes/farm.tscn` | P0 |
| 3 | 工具栏(翻土/浇水/播种/收获 4 键) | `scripts/farming/tool_bar.gd` | P0 |
| 4 | 体力与每日结算 | `scripts/core/game_manager.gd` | P0 |
| 5 | NPC 基类 + 张婶 | `scripts/npc/npc_base.gd` | P1 |
| 6 | 对话系统 + 商店 | `scripts/dialogue/` | P1 |
| 7 | 邮局 + 明信片 | `scripts/postcard/` | P1 |
| 8 | 古戏台 + H01 剧本运行时 | `scripts/drama/` | P1 |
| 9 | Steam Cloud 接入 | `scripts/core/save_manager.gd` | P2 |
| 10 | 数值表 | `data/items.json` / `data/npcs.json` | P2 |

---

## 5. 测试矩阵

### 5.1 自动化(已落地)

| 测试 | 工具 | 覆盖 | 状态 |
|------|------|------|------|
| 静态数据校验 | `tools/validate_data.py` | 字段完整 / 一年一熟规则 / 农时窗口区间 / 生长天数不超农时 | ✅ 通过 |
| 核心逻辑自测 | `scripts/tests/test_core.gd` | 10 组 92 项 | ✅ 全通过 |
| CI 集成 | `.github/workflows/ci.yml` | 校验 → 导入 → 自测 → 导出 | ✅ 已配置 |

### 5.2 自测覆盖明细(test_core.gd)

```
[1]  时间与季节系统(真实月份驱动)      10 项
[2]  作物数据库                          7 项
[3]  播种窗口(黑龙江一年一熟)            8 项
[3b] 农时月份窗口                        11 项
[3c] 秋霜冻死机制                        3 项
[3d] 越冬储藏与冬季产出                   8 项
[4]  完整生长循环 T01                    12 项
[5]  秋翻地增产                          6 项
[6]  早收腾茬 → 复种秋菜                7 项
[7]  冬季休耕校验                        3 项
[8]  缺水枯死判定                        2 项
[9]  男女双主角支持(D10)                 4 项
[10] 存档序列化往返                      7 项
────────────────────────────────────
合计 88 项断言 + 4 项汇总 = 92 项
```

### 5.3 MVP 必测用例(手动/集成)

```
T01  进入农场 → 翻土 → 浇水 → 播玉米 → 收获 → 卖出 → 金币增加
T02  进入邮局 → 寄信 → 等 1 日 → 收到明信片 → 收藏册显示
T03  进入古戏台 → H01 → 5 决策点 → 完成 → 存档标记 H01_done
T04  存档 → 重启 → 读档 → 状态不丢
T05  走 4 个场景 FPS 均 ≥ 55
T06  【D14 新增】秋收季不收割 → 推进到 11 月 → 作物显示"秋霜冻死"
T07  【D14 新增】冬季尝试播种 → 被拒绝并提示"冬歇"
T08  【D14 新增】早收作物 7 月腾茬 → 复种秋菜 → 秋收成功
```

---

## 6. CI 配置(.github/workflows/ci.yml)

```yaml
jobs:
  test:                    # 核心逻辑自测
    - checkout
    - setup-godot (4.3.0)
    - python3 tools/validate_data.py data/
    - godot --headless --import --quit
    - godot --headless --script res://scripts/tests/test_core.gd
  export:                  # Linux 构建
    needs: test
    - checkout / setup-godot / import
    - godot --headless --export-release "Linux" ./build/binzhoutown.x86_64
    - upload-artifact
```

---

## 7. 风险与对策

| # | 风险 | 影响 | 概率 | 对策 |
|---|------|------|------|------|
| R1 | Godot 5.x 上线带来迁移风险 | 高 | 中 | 锁 4.3,封装兼容层 |
| R2 | 美术产能不足 | 高 | 高 | **AI 辅助 + 主美把关**(B+A) |
| R3 | 8 周时间不够 | 高 | 中 | Week 4 检查点,砍非核心 |
| R4 | Steam 审核退回 | 中 | 低 | 提前 1 月申请预审 |
| R5 | **一年一熟导致玩家挫败** | 中 | **高** | **前 2 季做"农时提示"教学**(日历高亮播种窗/秋霜倒计时) |
| R6 | **黑土地题材与暖区种田认知冲突** | 中 | 中 | 主菜单与 HUD 常驻"当前可播种作物"提示 |
| R7 | AI 版权风险 | 中 | 中 | Stable Diffusion 自部署 + AI 仅作参考手修 |

### Week 4 检查点(Go/No-Go)

```
✅ Go 条件:
  - 主角能在 4 个场景间流畅移动
  - 3 种作物能完整生长(含早收复种与秋霜冻死两条分支)
  - NPC 张婶能交互触发对话
  - 92 项自测保持全绿

❌ No-Go 触发(任一):
  - 任何场景 FPS < 30
  - 秋收/秋霜机制无法在 2 分钟内被玩家理解
  - 自动化测试持续红
```

---

**文档结束。** *v4.0 · 2026-11-12 · 配套《宾州小镇_完整游戏企划_v4.md》*
