extends RefCounted
class_name FarmPlot

## 农场地块状态机
## 黑龙江设定:一年一熟。春播秋收,冬季休耕(冬季可做加工/休整,不能播种)。
## 秋霜(10月)后未收的作物冻死在地里 —— 这是本作秋收节奏压力的来源。

enum State {
	UNTILLED,   # 未开垦
	TILLED,      # 已翻土
	PLANTED,     # 已播种(未出苗)
	GROWING,     # 生长中
	READY,       # 可收获
	DEAD,        # 枯死
	FALLOW,      # 休耕(冬季/已收割待翻耕)
}

## 秋霜月(10月)之后,晚收作物若未收完将冻死
const FROST_MONTH := 10

var index: int = 0
var state: int = State.UNTILLED
var crop_id: String = ""
var days_grown: float = 0.0
var days_watered: int = 0
var last_watered_day: int = -1
var dead_reason: String = ""
## 播种时的真实月份(用于农时校验)
var sown_month: int = 0
## 是否已秋翻地(黑龙江黑土地保护核心技术:秋翻杀虫保墒,来年增产)
var autumn_plowed: bool = false

func _init(p_index: int = 0) -> void:
	index = p_index

## 翻土:UNTILLED/FALLOW -> TILLED
## autumn_plough=true 表示秋翻(秋收后/冬季进行),来年播种有肥力加成
func till(autumn_plough: bool = false) -> bool:
	if state == State.UNTILLED or state == State.FALLOW:
		state = State.TILLED
		dead_reason = ""
		if autumn_plough:
			self.autumn_plowed = true
		return true
	return false

## 秋翻地:收获后或冬季进行的深翻,积肥越冬,来年产量更高
func autumn_plough() -> bool:
	if state == State.UNTILLED or state == State.TILLED or state == State.FALLOW:
		autumn_plowed = true
		return true
	return false

## 浇水:今日已浇则失败
func water(current_day: int) -> bool:
	if state == State.UNTILLED:
		return false
	if last_watered_day == current_day:
		return false
	last_watered_day = current_day
	days_watered += 1
	return true

## 播种:仅 TILLED 可播种,且须在作物的播种月份窗口内
func plant(p_crop_id: String, season: String, month: int = 0) -> bool:
	if state != State.TILLED:
		return false
	var crop := CropDatabase.get_crop(p_crop_id)
	if crop == null:
		return false
	if not crop.can_sow_in(season):
		return false
	if month > 0 and not crop.can_sow_in_month(month):
		return false
	crop_id = p_crop_id
	days_grown = 0.0
	sown_month = month
	state = State.PLANTED
	dead_reason = ""
	return true

## 每日推进生长
func advance_day(current_day: int, month: int = 0) -> void:
	if state == State.PLANTED:
		state = State.GROWING
	if state != State.GROWING and state != State.READY:
		return
	var crop := CropDatabase.get_crop(crop_id)
	if crop == null:
		return
	# 缺水判定:连续 2 天没浇水 → 枯死
	if last_watered_day >= 0 and current_day - last_watered_day > 2:
		state = State.DEAD
		dead_reason = "缺水"
		return
	# 秋霜判定:过了 10 月仍未收 → 冻死在地里
	if month >= FROST_MONTH and not crop.can_harvest_in_month(month):
		state = State.DEAD
		dead_reason = "秋霜冻死"
		return
	days_grown += 1.0
	if crop.is_ready(days_grown):
		state = State.READY

## 收获:READY -> FALLOW,返回作物 id 与产量(含越冬储藏信息)
func harvest() -> Dictionary:
	if state != State.READY:
		return {}
	var crop := CropDatabase.get_crop(crop_id)
	if crop == null:
		return {}
	var amount := crop.roll_yield(days_grown, autumn_plowed)
	var result := {
		"crop_id": crop_id,
		"crop_name": crop.name,
		"amount": amount,
		"sell_price": crop.sell_price,
		"total_value": amount * crop.sell_price,
		"days_grown": days_grown,
		"early_harvest": crop.is_early_harvest(),
		"late_harvest": crop.is_late_harvest(),
		"storage": crop.storage,
		"storage_note": crop.storage_note,
		"autumn_plowed": autumn_plowed,
	}
	# 收获后进入休耕,需重新翻土(秋翻标记保留)
	state = State.FALLOW
	crop_id = ""
	days_grown = 0.0
	return result

## 清除死株
func clear_dead() -> bool:
	if state != State.DEAD:
		return false
	state = State.TILLED
	crop_id = ""
	days_grown = 0.0
	dead_reason = ""
	return true

func is_empty() -> bool:
	return state == State.UNTILLED or state == State.TILLED or state == State.FALLOW

func get_growth_stage() -> int:
	if crop_id == "":
		return -1
	var crop := CropDatabase.get_crop(crop_id)
	if crop == null:
		return -1
	return crop.growth_stage(days_grown)

func to_dict() -> Dictionary:
	return {
		"index": index, "state": state, "crop_id": crop_id,
		"days_grown": days_grown, "days_watered": days_watered,
		"last_watered_day": last_watered_day, "dead_reason": dead_reason,
		"sown_month": sown_month, "autumn_plowed": autumn_plowed,
	}

static func from_dict(d: Dictionary) -> FarmPlot:
	var p := FarmPlot.new(int(d.get("index", 0)))
	p.state = int(d.get("state", 0))
	p.crop_id = String(d.get("crop_id", ""))
	p.days_grown = float(d.get("days_grown", 0.0))
	p.days_watered = int(d.get("days_watered", 0))
	p.last_watered_day = int(d.get("last_watered_day", -1))
	p.dead_reason = String(d.get("dead_reason", ""))
	p.sown_month = int(d.get("sown_month", 0))
	p.autumn_plowed = bool(d.get("autumn_plowed", false))
	return p
