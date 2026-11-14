extends RefCounted
class_name PostcardSystem

## 明信片纯逻辑:寄信 → 在途 → 次日投递 → 收藏。
##
## 时间用"绝对游戏日"记录((year-1)*360 + day_of_year),
## 这样跨年、读档、跳日期都能稳定判断是否到信。

static func abs_day(calendar: GameCalendar) -> int:
	return (calendar.year - 1) * GameCalendar.DAYS_PER_YEAR + calendar.day_of_year

static func date_from_abs(value: int) -> Dictionary:
	var year := int(floor(float(value) / GameCalendar.DAYS_PER_YEAR)) + 1
	var day_of_year := posmod(value, GameCalendar.DAYS_PER_YEAR)
	var calendar := GameCalendar.new()
	calendar.year = year
	calendar.day_of_year = day_of_year
	return {
		"year": year,
		"day_of_year": day_of_year,
		"month": calendar.get_real_month(),
		"day": calendar.get_day_of_month(),
		"label": "%d月%d日" % [calendar.get_real_month(), calendar.get_day_of_month()],
	}

static func pending_count(state: GameState) -> int:
	return state.postcards_pending.size()

static func is_collected(state: GameState, postcard_id: String) -> bool:
	return state.postcards_collected.has(postcard_id)

static func received_count(state: GameState, recipient_id: String) -> int:
	var count := 0
	for postcard_id in PostcardData.reply_ids(recipient_id):
		if is_collected(state, String(postcard_id)):
			count += 1
	return count

## 某位联系人下一张会寄来的明信片。全部收齐时返回空字典。
static func next_postcard_for(state: GameState, recipient_id: String) -> Dictionary:
	for postcard_id in PostcardData.reply_ids(recipient_id):
		if not is_collected(state, String(postcard_id)):
			return PostcardData.get_postcard(String(postcard_id))
	return {}

## 寄信。邮差一天只走一趟:有在途信件时,等回信到了再寄下一封。
static func send(state: GameState, calendar: GameCalendar, recipient_id: String) -> Dictionary:
	var recipient := PostcardData.get_recipient(recipient_id)
	if recipient.is_empty():
		return {"ok": false, "message": "信封上的地址看不清,寄不出去。"}
	if pending_count(state) > 0:
		var pending: Dictionary = state.postcards_pending[0]
		var pending_date := date_from_abs(int(pending.get("deliver_abs_day", 0)))
		return {
			"ok": false,
			"message": "邮车已经走了,上一封信要等 %s 才有回音。" % pending_date.get("label", ""),
		}
	var postcard := next_postcard_for(state, recipient_id)
	if postcard.is_empty():
		return {
			"ok": false,
			"message": "%s那边能讲的故事都听全了,换个人写写看吧。" % recipient.get("name", ""),
		}
	var sent_abs := abs_day(calendar)
	var deliver_abs := sent_abs + PostcardData.delivery_days()
	state.postcards_pending.append({
		"recipient_id": recipient_id,
		"postcard_id": String(postcard.get("id", "")),
		"sent_abs_day": sent_abs,
		"deliver_abs_day": deliver_abs,
		"sent_date": calendar.date_string(),
	})
	var deliver_date := date_from_abs(deliver_abs)
	return {
		"ok": true,
		"recipient_id": recipient_id,
		"card_id": String(postcard.get("id", "")),
		"deliver_abs_day": deliver_abs,
		"message": "信交给邮差了。等 %s 邮差到 %s 那边,回信就来了。" % [
			deliver_date.get("label", ""), recipient.get("name", "")],
	}

## 投递所有到期信件。返回本次新收到的明信片(可能为空)。
static func deliver_due(state: GameState, calendar: GameCalendar) -> Array:
	var today := abs_day(calendar)
	var remaining: Array = []
	var delivered: Array = []
	for pending in state.postcards_pending:
		if not pending is Dictionary:
			continue
		if today < int(pending.get("deliver_abs_day", 0)):
			remaining.append(pending)
			continue
		var postcard_id := String(pending.get("postcard_id", ""))
		if postcard_id == "" or is_collected(state, postcard_id):
			continue
		var postcard := PostcardData.get_postcard(postcard_id)
		if postcard.is_empty():
			continue
		state.postcards_collected.append(postcard_id)
		delivered.append(postcard)
	state.postcards_pending = remaining
	return delivered

## 收藏册按数据表顺序展示,读档后不会因数组顺序变化而乱。
static func collected_postcards(state: GameState) -> Array:
	var out: Array = []
	for postcard in PostcardData.all_postcards():
		var postcard_id := String(postcard.get("id", ""))
		if is_collected(state, postcard_id):
			out.append(postcard)
	return out

## 面板顶部状态行
static func status_text(state: GameState, calendar: GameCalendar) -> String:
	if state.postcards_pending.is_empty():
		return "邮车停在门口,今天可以寄一封。"
	var pending: Dictionary = state.postcards_pending[0]
	var recipient := PostcardData.get_recipient(String(pending.get("recipient_id", "")))
	var deliver_date := date_from_abs(int(pending.get("deliver_abs_day", 0)))
	return "在途:寄往%s · %s 前后到信。" % [
		recipient.get("name", "远方"), deliver_date.get("label", "明天")]
