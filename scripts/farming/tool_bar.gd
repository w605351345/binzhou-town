extends RefCounted
class_name ToolBar

## 工具栏(4 键:翻土/浇水/播种/收获 + 秋翻地)
##
## J = 翻土  K = 浇水  L = 播种  I = 收获
## 秋翻地走 R(收获后或冬季深翻积肥,黑土地保护核心农法)
##
## 本类只做"意图 → 结果"的判定与文案,真正的状态变更交给 FarmSystem。
## 这样 UI 层(HUD/场景)只管按键与提示,规则集中在一处。

enum Tool { TILL, WATER, SEED, HARVEST }

const TOOL_KEYS := {
	Tool.TILL: "J",
	Tool.WATER: "K",
	Tool.SEED: "L",
	Tool.HARVEST: "I",
}

## 每种工具的体力消耗
const TOOL_COST := {
	Tool.TILL: StaminaSystem.COST_TILL,
	Tool.WATER: StaminaSystem.COST_WATER,
	Tool.SEED: StaminaSystem.COST_PLANT,
	Tool.HARVEST: StaminaSystem.COST_HARVEST,
}

## 工具中文名
static func tool_cn(tool: int) -> String:
	match tool:
		Tool.TILL:
			return "翻土"
		Tool.WATER:
			return "浇水"
		Tool.SEED:
			return "播种"
		Tool.HARVEST:
			return "收获"
	return "?"

## 工具提示文案
static func tool_hint(tool: int) -> String:
	match tool:
		Tool.TILL:
			return "J · 翻土:把荒地翻松,准备好下种"
		Tool.WATER:
			return "K · 浇水:黑土地不缺水才出苗"
		Tool.SEED:
			return "L · 播种:4-5 月是唯一播种窗口"
		Tool.HARVEST:
			return "I · 收获:熟了才能收,过了秋霜就冻在地里"
	return ""

## 当前应选中的作物(优先选当前月份可播种的)
static func default_seed_crop(farm: FarmSystem) -> String:
	var ids: Array = farm.sowable_crop_ids()
	if ids.is_empty():
		return ""
	return String(ids[0])

## 执行一次工具操作。返回 {ok: bool, message: String, result: Dictionary}
##
## plot_index 为目标地块;seed_crop_id 仅在播种时有效。
static func apply_tool(tool: int, farm: FarmSystem, plot_index: int,
		player: PlayerProfile, seed_crop_id: String = "") -> Dictionary:
	var plot := farm.get_plot(plot_index)
	if plot == null:
		return _fail("这块地不在农场里")
	if player == null or player.stamina == null:
		return _fail("主角状态异常")

	var cost: int = TOOL_COST.get(tool, 0)
	if not player.stamina.has(cost):
		return _fail("体力不够了(%s),歇一晚再说" % player.stamina.status_cn())

	match tool:
		Tool.TILL:
			return _do_till(farm, plot, player, cost)
		Tool.WATER:
			return _do_water(farm, plot, player, cost)
		Tool.SEED:
			return _do_seed(farm, plot, player, cost, seed_crop_id)
		Tool.HARVEST:
			return _do_harvest(farm, plot, player, cost)
	return _fail("没这个工具")

static func _do_till(farm: FarmSystem, plot: FarmPlot, player: PlayerProfile, cost: int) -> Dictionary:
	# 死株(秋霜冻死 / 缺水旱死)也得能清 —— 黑龙江秋收后翻地就是要把死茬翻进土里沤肥。
	# 没有这条通路,玩家一旦错过收成,这块地就永久废了(9 块地少一块)。
	if plot.state == FarmPlot.State.DEAD:
		if not player.stamina.consume(cost):
			return _fail("体力不够了")
		if not plot.clear_dead():
			return _fail("清地失败")
		return _ok("把死茬翻进土里了,这地还能种", {"cleared_dead": true})
	if plot.state != FarmPlot.State.UNTILLED and plot.state != FarmPlot.State.FALLOW:
		return _fail("这块地已经翻过了")
	if not player.stamina.consume(cost):
		return _fail("体力不够了")
	var ok := farm.till_plot(plot.index)
	if not ok:
		return _fail("翻土失败")
	return _ok("翻好了,可以下种了", {})

static func _do_water(farm: FarmSystem, plot: FarmPlot, player: PlayerProfile, cost: int) -> Dictionary:
	if plot.state == FarmPlot.State.UNTILLED:
		return _fail("还没翻土呢,水浇不进荒地")
	if plot.last_watered_day == farm.calendar.day_of_year:
		return _fail("今天浇过了")
	if not player.stamina.consume(cost):
		return _fail("体力不够了")
	if not farm.water_plot(plot.index):
		return _fail("浇水失败")
	return _ok("浇过水了", {})

static func _do_seed(farm: FarmSystem, plot: FarmPlot, player: PlayerProfile, cost: int, crop_id: String) -> Dictionary:
	if plot.state != FarmPlot.State.TILLED:
		return _fail("得先翻土才能播种")
	if farm.calendar.is_winter():
		return _fail("冬歇呢,地里的庄稼在土里歇着,开春再说")
	if crop_id == "":
		crop_id = default_seed_crop(farm)
	if crop_id == "":
		return _fail("这个月没有能种的%s" % _month_window_cn(farm.calendar))
	var crop := CropDatabase.get_crop(crop_id)
	if crop == null:
		return _fail("没有这种种子")
	if not crop.can_sow_in_month(farm.calendar.get_real_month()):
		return _fail("%s不能种在%d月" % [crop.name, farm.calendar.get_real_month()])
	var seed_cost := crop.seed_price
	if player.gold < seed_cost:
		return _fail("买%s的种子要%d文钱,钱不够" % [crop.name, seed_cost])
	if not player.stamina.consume(cost):
		return _fail("体力不够了")
	if not farm.plant_crop(plot.index, crop_id):
		return _fail("播种失败")
	player.gold -= seed_cost
	return _ok("种下了%s" % crop.name, {"crop_id": crop_id, "cost": seed_cost})

static func _do_harvest(farm: FarmSystem, plot: FarmPlot, player: PlayerProfile, cost: int) -> Dictionary:
	if plot.state == FarmPlot.State.DEAD:
		return _fail("%s,翻进土里沤肥吧(J 翻土清地)" % _dead_reason_cn(plot))
	if plot.state != FarmPlot.State.READY:
		return _fail("还没熟呢")
	if not player.stamina.consume(cost):
		return _fail("体力不够了")
	var res := farm.harvest_plot(plot.index)
	if res.is_empty():
		return _fail("没收成")
	# 收获物进背包
	var crop_id := String(res.get("crop_id", ""))
	var amount := int(res.get("amount", 0))
	_add_to_inventory(player, crop_id, amount)
	return _ok("收了%s %d个(%s)" % [res.get("crop_name", ""), amount, res.get("storage", "")], res)

## 收获物入背包
static func _add_to_inventory(player: PlayerProfile, item_id: String, amount: int) -> void:
	if item_id == "" or amount <= 0:
		return
	var cur := int(player.inventory.get(item_id, 0))
	player.inventory[item_id] = cur + amount

## 死因中文(冻死 / 旱死)
static func _dead_reason_cn(plot: FarmPlot) -> String:
	if plot == null:
		return "死的庄稼"
	if plot.dead_reason == "缺水":
		return "旱死的庄稼"
	return "冻死的庄稼"

## 秋翻地(收获后或冬季深翻积肥,黑土地保护核心农法)
static func apply_autumn_plough(farm: FarmSystem, plot_index: int,
		player: PlayerProfile) -> Dictionary:
	var plot := farm.get_plot(plot_index)
	if plot == null:
		return _fail("这块地不在农场里")
	if player == null or player.stamina == null:
		return _fail("主角状态异常")
	if plot.crop_id != "":
		return _fail("地里还有庄稼,收了再翻")
	if not player.stamina.has(StaminaSystem.COST_AUTUMN_PLOUGH):
		return _fail("体力不够了,深翻最累")
	if not player.stamina.consume(StaminaSystem.COST_AUTUMN_PLOUGH):
		return _fail("体力不够了")
	if not farm.autumn_plough_plot(plot_index):
		return _fail("翻地失败")
	return _ok("深翻了一遍,开春这块地能多打一成粮", {"autumn_plowed": true})

static func _ok(message: String, result: Dictionary) -> Dictionary:
	return {"ok": true, "message": message, "result": result}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "result": {}}

## 当前月份的播种窗口中文描述
static func _month_window_cn(calendar: GameCalendar) -> String:
	var m := calendar.get_real_month()
	if calendar.is_winter():
		return "冬天(11-3 月)"
	return "%d月" % m
