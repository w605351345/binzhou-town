extends SceneTree
## v5.1 生活系统验收：技能、运输、制造、畜牧、矿洞、博物馆、社区工程、
## 工具升级、功能 NPC 服务、货郎轮换与存档 v3。
## 运行: godot --headless --script res://scripts/tests/test_life_systems.gd

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《麦溪镇》生活系统自测 (life systems test) ===")
	await process_frame
	_test_skills()
	_test_shipping()
	_test_crafting()
	_test_livestock()
	_test_mining()
	_test_museum()
	_test_community_projects()
	_test_functional_npc_quests()
	_test_tool_upgrades()
	_test_service_catalog()
	_test_save_v3_roundtrip()
	_test_service_panel()
	print("--------------------------------------------------")
	print("结果: %d 通过 / %d 失败" % [_passed, _failed])
	if _failed > 0:
		print("❌ TEST FAILED")
		quit(1)
	else:
		print("✅ ALL TESTS PASSED")
		quit(0)

func check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✅ %s %s" % [label, detail])
	else:
		_failed += 1
		print("  ❌ %s %s" % [label, detail])

func _inventory_total(state: GameState) -> int:
	var total := 0
	for count in state.player.inventory.values():
		total += int(count)
	return total

func _first_fish_id() -> String:
	for item in ItemDatabase.all_items():
		var item_id := String(item.get("id", ""))
		if item_id.begins_with("fish_"):
			return item_id
	return ""

# --- 技能 ---
func _test_skills() -> void:
	print("\n[1] 七项生活技能与升级")
	var player := PlayerProfile.new()
	SkillSystem.ensure_player(player)
	check("技能数为七项", SkillSystem.all_skills().size() == 7,
		"→ %d 项" % SkillSystem.all_skills().size())
	check("旧 handcraft 键保留", player.skills.has("handcraft"))
	for skill_id in ["farming", "ranching", "mining", "crafting", "fishing", "foraging", "social"]:
		check("%s 默认 1 级" % skill_id, SkillSystem.level(player, skill_id) == 1)

	var result := SkillSystem.add_xp(player, "farming", 100)
	check("农耕 100 经验升到 2 级", bool(result.get("level_up", false))
		and SkillSystem.level(player, "farming") == 2,
		"→ Lv.%d / %d XP" % [SkillSystem.level(player, "farming"), SkillSystem.xp(player, "farming")])
	check("升级提示含等级", String(result.get("message", "")).contains("2 级"),
		String(result.get("message", "")))
	check("2 级作物售价有加成", SkillSystem.crop_value_multiplier(player) > 1.0,
		"→ %.2f" % SkillSystem.crop_value_multiplier(player))

	player.skills["mining"] = SkillSystem.max_level()
	player.skill_xp["mining"] = SkillSystem.xp_for_level(SkillSystem.max_level())
	check("满级后无下一级经验门槛", SkillSystem.xp_to_next(player, "mining") == 0)
	var capped := SkillSystem.add_xp(player, "mining", 999)
	check("满级后不会继续升级", int(capped.get("level", 0)) == SkillSystem.max_level())

# --- 运输箱 ---
func _test_shipping() -> void:
	print("\n[2] 运输箱隔夜结算")
	var state := GameState.new()
	state.player.inventory["corn"] = 5
	var unit := ShippingSystem.unit_price(state, "corn")
	var gold_before := state.player.gold
	var xp_before := SkillSystem.xp(state.player, "farming")
	var added := ShippingSystem.add(state, "corn", 3)
	check("放入 3 个玉米成功", bool(added.get("ok", false)), String(added.get("message", "")))
	check("运输提示使用中文作物名", String(added.get("message", "")).contains("玉米"),
		String(added.get("message", "")))
	check("运输箱显示中文作物名", ShippingSystem.display_name("corn") == "玉米",
		ShippingSystem.display_name("corn"))
	check("背包立即扣 3 个", int(state.player.inventory.get("corn", 0)) == 2)
	check("箱内待结价值正确", ShippingSystem.pending_value(state) == unit * 3,
		"→ %d 文" % ShippingSystem.pending_value(state))
	var settled := ShippingSystem.settle(state)
	check("隔夜结算成功", bool(settled.get("ok", false)), String(settled.get("message", "")))
	check("金币按单价到账", state.player.gold == gold_before + unit * 3,
		"→ %d 文" % state.player.gold)
	check("箱内已清空", Dictionary(state.shipping.get("items", {})).is_empty())
	check("累计收入记录", int(state.shipping.get("lifetime", 0)) == unit * 3)
	check("结算报告可回放", Array(state.shipping.get("last_report", [])).size() == 1)
	check("运输结算给农耕经验", SkillSystem.xp(state.player, "farming") > xp_before)
	check("收不了的东西被拒", not bool(ShippingSystem.add(state, "material_stone", 1).get("ok", false)))

# --- 制造 ---
func _test_crafting() -> void:
	print("\n[3] 制造、技能门槛与喷灌器")
	var state := GameState.new()
	state.player.inventory["forage_wood"] = 2
	state.player.inventory["food_dried_corn"] = 1
	var xp_before := SkillSystem.xp(state.player, "crafting")
	var crafted := CraftingSystem.craft(state, "craft_feed")
	check("铡草料成功", bool(crafted.get("ok", false)), String(crafted.get("message", "")))
	check("消耗干柴", not state.player.inventory.has("forage_wood"))
	check("消耗干玉米", not state.player.inventory.has("food_dried_corn"))
	check("产出 3 捆草料", int(state.player.inventory.get("feed_hay", 0)) == 3,
		"→ %d 捆" % int(state.player.inventory.get("feed_hay", 0)))
	check("制造给经验", SkillSystem.xp(state.player, "crafting") > xp_before)
	check("配方不存在时拒绝", not bool(CraftingSystem.craft(state, "no_such_recipe").get("ok", false)))

	state.player.inventory["forage_wood"] = 12
	state.player.inventory["material_stone"] = 3
	check("1 级做不了 2 级木箱", not CraftingSystem.can_craft(state, "craft_chest"))
	state.player.skills["crafting"] = 2
	check("2 级后木箱解锁", CraftingSystem.can_craft(state, "craft_chest"))
	check("制造木箱成功", bool(CraftingSystem.craft(state, "craft_chest").get("ok", false)))

	state.calendar.advance_to_month(4, 20)
	for i in 4:
		state.farm.till_plot(i)
		state.farm.plant_crop(i, "corn")
	state.player.inventory["sprinkler_basic"] = 1
	var watered := CraftingSystem.apply_sprinklers(state)
	check("1 个喷灌器浇 3 块地", watered == 3, "→ %d 块" % watered)
	check("第 4 块地没被浇", state.farm.get_plot(3).last_watered_abs_day != state.calendar.abs_day())

	state.player.inventory["ore_copper"] = 5
	state.player.inventory["material_coal"] = 1
	check("没有熔炉不能炼铜", not CraftingSystem.station_available(state, "furnace_basic"))
	state.player.inventory["furnace_basic"] = 1
	check("拥有熔炉后可炼铜", CraftingSystem.station_available(state, "furnace_basic"))
	check("炼出铜锭", bool(CraftingSystem.craft(state, "smelt_copper").get("ok", false)))
	check("铜锭入包", int(state.player.inventory.get("material_copper_bar", 0)) >= 1)
	check("炼铜消耗矿石与煤", not state.player.inventory.has("ore_copper")
		and not state.player.inventory.has("material_coal"))

	state.player.inventory["preserve_jar"] = 1
	state.player.inventory["autumn_vegetable"] = 3
	state.player.inventory["material_salt"] = 2
	check("拥有腌菜坛后可腌菜", CraftingSystem.station_available(state, "preserve_jar"))
	var pickled := CraftingSystem.craft(state, "preserve_sour_cabbage")
	check("腌出腌菜", bool(pickled.get("ok", false)), String(pickled.get("message", "")))
	check("腌菜入包", int(state.player.inventory.get("food_sour_cabbage", 0)) >= 3)

# --- 畜牧 ---
func _test_livestock() -> void:
	print("\n[4] 畜牧购买、喂食与跨日产出")
	var state := GameState.new()
	var gold_before := state.player.gold
	var bought := LivestockSystem.buy_animal(state, "chicken")
	check("买芦花鸡成功", bool(bought.get("ok", false)), String(bought.get("message", "")))
	check("买牲口扣钱", state.player.gold == gold_before - 180,
		"→ %d 文" % state.player.gold)
	check("棚内数量为 1", LivestockSystem.animal_count(state) == 1)
	check("没有草料时喂食失败", not bool(LivestockSystem.feed_all(state).get("ok", false)))
	var no_feed := LivestockSystem.advance_day(state)
	check("没喂食不产出", not bool(no_feed.get("ok", false)))

	state.player.inventory["feed_hay"] = 1
	var fed := LivestockSystem.feed_all(state)
	check("有草料时喂食成功", bool(fed.get("ok", false)), String(fed.get("message", "")))
	check("喂食消耗草料", not state.player.inventory.has("feed_hay"))
	check("重复喂食被拒", not bool(LivestockSystem.feed_all(state).get("ok", false)))
	var produced := LivestockSystem.advance_day(state)
	check("跨日产出鸡蛋", bool(produced.get("ok", false)), String(produced.get("message", "")))
	check("鸡蛋进背包", int(state.player.inventory.get("animal_egg", 0)) == 1)
	check("产出写入累计", int(state.livestock.get("lifetime_products", 0)) == 1)
	check("跨日后喂食状态重置", not bool(Dictionary(state.livestock["animals"][0]).get("fed_today", true)))

# --- 矿洞 ---
func _test_mining() -> void:
	print("\n[5] 矿洞探索、战斗、降层与倒下")
	var state := GameState.new()
	check("进洞成功", bool(MiningSystem.enter(state).get("ok", false)))
	check("矿洞 active", bool(state.mine.get("active", false)))
	var inventory_before := _inventory_total(state)
	var explored := MiningSystem.explore(state)
	check("凿矿成功", bool(explored.get("ok", false)), String(explored.get("message", "")))
	check("矿石进背包", _inventory_total(state) > inventory_before)
	check("矿石计数增加", int(state.mine.get("ore_mined", 0)) > 0)
	check("探索消耗体力", state.player.energy < StaminaSystem.OVERFLOW_MAX)

	state.mine["monster"] = {"name": "测试石兽", "hp": 1, "max_hp": 1, "damage": 5}
	check("有怪时不能下层", not bool(MiningSystem.descend(state).get("ok", false)))
	var defeated := MiningSystem.attack(state)
	check("攻击击败怪物", bool(defeated.get("defeated", false)), String(defeated.get("message", "")))
	check("击败计数增加", int(state.mine.get("monsters_defeated", 0)) == 1)
	var descended := MiningSystem.descend(state)
	check("清怪后降到第 2 层", bool(descended.get("ok", false)), String(descended.get("message", "")))
	check("最深记录同步", int(state.mine.get("deepest", 0)) == 2)

	state.mine["monster"] = {"name": "塌方石灵", "hp": 999, "max_hp": 999, "damage": 99}
	state.mine["health"] = 5
	var collapsed := MiningSystem.attack(state)
	check("生命耗尽会倒下", bool(collapsed.get("collapsed", false)), String(collapsed.get("message", "")))
	check("倒下回第 1 层", int(state.mine.get("floor", 0)) == 1)
	check("倒下只损失体力不丢档", int(state.mine.get("health", 0)) == 30
		and state.player.energy <= 35 and not bool(state.mine.get("active", true)))
	MiningSystem.enter(state)
	check("回洞口后能再次进洞", bool(state.mine.get("active", false)))
	MiningSystem.retreat(state)
	check("收灯后 active 关闭", not bool(state.mine.get("active", true)))

# --- 博物馆 ---
func _test_museum() -> void:
	print("\n[6] 镇史馆捐赠与里程碑")
	var state := GameState.new()
	state.player.gold = 0
	var all := MuseumSystem.all_collectibles()
	check("藏品表至少 12 件", all.size() >= 12, "→ %d 件" % all.size())
	var ids: Array = []
	for i in 4:
		ids.append(String(all[i].get("item_id", "")))
		state.player.inventory[ids[i]] = 1
	var first := MuseumSystem.donate(state, ids[0])
	check("第一件捐赠成功", bool(first.get("ok", false)), String(first.get("message", "")))
	check("捐赠后背包扣除", int(state.player.inventory.get(ids[0], 0)) == 0)
	check("仓库记录藏品", MuseumSystem.donated_ids(state).has(ids[0]))
	check("重复捐赠被拒", not bool(MuseumSystem.donate(state, ids[0]).get("ok", false)))
	check("非藏品被拒", not bool(MuseumSystem.donate(state, "material_stone").get("ok", false)))
	check("1 件未达里程碑", Array(state.museum.get("rewards", [])).is_empty())
	for i in range(1, 4):
		MuseumSystem.donate(state, ids[i])
	check("4 件触发第一档里程碑", Array(state.museum.get("rewards", [])).has("milestone_4"))
	check("里程碑奖励金币到账", state.player.gold == 120, "→ %d 文" % state.player.gold)
	check("里程碑奖励物品到账", int(state.player.inventory.get("material_fertilizer", 0)) == 4)
	check("进度文案含 4/12", MuseumSystem.progress_text(state).contains("4/12"),
		MuseumSystem.progress_text(state))

# --- 社区工程 ---
func _donate_project(state: GameState, project_id: String) -> void:
	var project := CommunityProjectSystem.get_project(project_id)
	for raw_id in Dictionary(project.get("requirements", {})).keys():
		var item_id := String(raw_id)
		var need := int(project["requirements"][raw_id])
		state.player.inventory[item_id] = need
		for _i in need:
			CommunityProjectSystem.donate(state, project_id, item_id)

func _test_community_projects() -> void:
	print("\n[7] 公共工程顺序解锁与奖励")
	var state := GameState.new()
	check("河桥一开始可交材料", CommunityProjectSystem.is_available(state, "repair_bridge"))
	check("小学屋顶一开始锁着", not CommunityProjectSystem.is_available(state, "repair_school_roof"))
	state.player.inventory["forage_wood"] = 1
	var part := CommunityProjectSystem.donate(state, "repair_bridge", "forage_wood")
	check("单项材料可分批交", bool(part.get("ok", false)) and not bool(part.get("completed", true)))
	check("工程进度记录 1", int(CommunityProjectSystem.progress_for(
		state, "repair_bridge").get("forage_wood", 0)) == 1)

	_donate_project(state, "repair_bridge")
	check("河桥完工", CommunityProjectSystem.is_completed(state, "repair_bridge"))
	check("河桥奖励金币", state.player.gold >= 180, "→ %d 文" % state.player.gold)
	check("河桥奖励鱼饵", int(state.player.inventory.get("bait_worm", 0)) >= 8)
	check("河桥写世界 flag", bool(state.flags.get("community_bridge_fixed", false)))
	check("小学屋顶随后解锁", CommunityProjectSystem.is_available(state, "repair_school_roof"))
	check("已完成工程不能重复交", not CommunityProjectSystem.is_available(state, "repair_bridge"))

	for project_id in ["repair_school_roof", "repair_clinic_stove", "restore_stage_lights"]:
		_donate_project(state, project_id)
		check("%s 完工" % project_id, CommunityProjectSystem.is_completed(state, project_id))
	check("四项公共工程全部完成", Array(state.community.get("completed", [])).size() == 4)
	check("四项 flag 全部写入", bool(state.flags.get("community_school_roof_fixed", false))
		and bool(state.flags.get("community_clinic_warm", false))
		and bool(state.flags.get("community_stage_lit", false)))
	check("工程进度文案 4/4", CommunityProjectSystem.progress_text(state).contains("4/4"),
		CommunityProjectSystem.progress_text(state))

# --- 功能 NPC 委托 ---
func _test_functional_npc_quests() -> void:
	print("\n[7b] 功能 NPC 委托与系统动作联动")
	var quests := QuestSystem.all_quests()
	check("任务总数至少 23", quests.size() >= 23, "→ %d 条" % quests.size())
	var givers := {}
	for quest in quests:
		givers[String(quest.get("giver", ""))] = true
	for npc_id in ["shi_tieshan", "jiang_muyun", "he_shuigen", "su_wenbo", "lang_sanshun"]:
		check("%s 有可接委托" % npc_id, givers.has(npc_id))

	var state := GameState.new()
	state.player.gold = 1000
	state.player.inventory["ore_copper"] = 5
	state.player.inventory["animal_egg"] = 2
	QuestSystem.accept(state, "q_shi_copper")
	QuestSystem.accept(state, "q_jiang_eggs")
	check("铁匠交付委托可交", QuestSystem.can_turn_in(state, "q_shi_copper"))
	check("牧场交付委托可交", QuestSystem.can_turn_in(state, "q_jiang_eggs"))

	QuestSystem.accept(state, "q_he_fish")
	QuestSystem.progress(state, "fish", 3)
	check("钓鱼推进渔具商委托", QuestSystem.can_turn_in(state, "q_he_fish"))

	QuestSystem.accept(state, "q_su_donation")
	var first_collectible := String(MuseumSystem.all_collectibles()[0].get("item_id", ""))
	state.player.inventory[first_collectible] = 1
	MuseumSystem.donate(state, first_collectible)
	check("博物馆捐赠推进镇史馆委托", QuestSystem.can_turn_in(state, "q_su_donation"))

	QuestSystem.accept(state, "q_lang_purchase")
	var stock := ServiceCatalog.merchant_stock(state)
	for i in 2:
		var entry: Dictionary = stock[i]
		ServiceCatalog.buy_merchant_item(state, String(entry.get("item_id", "")))
	check("货郎购买推进货郎委托", QuestSystem.can_turn_in(state, "q_lang_purchase"))

# --- 工具升级 ---
func _test_tool_upgrades() -> void:
	print("\n[8] 铁匠工具升级")
	var player := PlayerProfile.new()
	player.gold = 220
	player.inventory["material_copper_bar"] = 2
	var xp_before := SkillSystem.xp(player, "crafting")
	var up1 := ToolUpgradeSystem.upgrade(player, "pickaxe")
	check("镐升到 2 级", bool(up1.get("ok", false)), String(up1.get("message", "")))
	check("铁匠扣金币", player.gold == 0, "→ %d 文" % player.gold)
	check("铁匠扣铜锭", not player.inventory.has("material_copper_bar"))
	check("工具等级写档", ToolUpgradeSystem.current_level(player, "pickaxe") == 2)
	check("升级给制造经验", SkillSystem.xp(player, "crafting") > xp_before)
	check("钱不够不能升 3 级", not ToolUpgradeSystem.can_upgrade(player, "pickaxe"))
	player.gold = 560
	player.inventory["material_iron_bar"] = 2
	player.inventory["material_coal"] = 3
	check("补齐材料后能升 3 级", ToolUpgradeSystem.can_upgrade(player, "pickaxe"))
	check("升到 3 级", bool(ToolUpgradeSystem.upgrade(player, "pickaxe").get("ok", false)))
	check("满级后下一级为空", ToolUpgradeSystem.next_upgrade(player, "pickaxe").is_empty())

# --- 货郎与渔具商 ---
func _test_service_catalog() -> void:
	print("\n[9] 旅行货郎轮换与渔具商")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 20)
	var stock_a := ServiceCatalog.merchant_stock(state)
	var stock_b := ServiceCatalog.merchant_stock(state)
	check("货郎每天 3 件货", stock_a.size() == 3, "→ %d 件" % stock_a.size())
	check("同一天货单稳定", stock_a == stock_b)
	var first_stock: Dictionary = stock_a[0]
	var first_id := String(first_stock.get("item_id", ""))
	var price := int(first_stock.get("price", 0))
	state.player.gold = price
	var bought := ServiceCatalog.buy_merchant_item(state, first_id)
	check("货郎可买当日货", bool(bought.get("ok", false)), String(bought.get("message", "")))
	check("买货扣钱", state.player.gold == 0, "→ %d 文" % state.player.gold)
	check("非当日货被拒", not bool(ServiceCatalog.buy_merchant_item(state, "gem_amber").get("ok", false)))
	state.calendar.advance_day()
	var stock_c := ServiceCatalog.merchant_stock(state)
	check("次日货单轮换", _stock_ids(stock_a) != _stock_ids(stock_c),
		"→ %s / %s" % [str(_stock_ids(stock_a)), str(_stock_ids(stock_c))])

	state.player.gold = 12
	var bait := ServiceCatalog.buy_bait(state)
	check("买一包鱼饵", bool(bait.get("ok", false)), String(bait.get("message", "")))
	check("鱼饵 5 个入包", int(state.player.inventory.get("bait_worm", 0)) == 5)
	var fish_id := _first_fish_id()
	check("鱼表存在可售鱼", fish_id != "")
	state.player.inventory[fish_id] = 2
	var gold_before := state.player.gold
	var sold := ServiceCatalog.sell_fish(state)
	check("收鱼成功", bool(sold.get("ok", false)), String(sold.get("message", "")))
	check("鱼从背包移除", not state.player.inventory.has(fish_id))
	check("卖鱼金币到账", state.player.gold > gold_before)

func _stock_ids(stock: Array) -> Array:
	var ids: Array = []
	for entry in stock:
		ids.append(String(entry.get("item_id", "")))
	ids.sort()
	return ids

# --- 存档 v3 ---
func _test_save_v3_roundtrip() -> void:
	print("\n[10] 存档 v3 新系统往返")
	var state := GameState.new()
	state.player.skills["farming"] = 4
	state.player.skill_xp["farming"] = 450
	state.player.tool_levels["hoe"] = 2
	state.shipping["items"] = {"corn": 3}
	state.livestock["animals"] = [{"uid": 1, "type": "chicken", "name": "芦花鸡",
		"days_left": 1, "fed_today": true, "lifetime": 4}]
	state.mine["floor"] = 3
	state.mine["deepest"] = 5
	state.museum["donated"] = ["ore_copper"]
	state.community["progress"] = {"repair_bridge": {"forage_wood": 2}}
	state.community["completed"] = ["repair_bridge"]
	var data := state.to_dict()
	check("存档版本为 3", int(data.get("schema_version", 0)) == 3)
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	check("技能等级保留", loaded.player.skills.get("farming", 0) == 4)
	check("技能经验保留", loaded.player.skill_xp.get("farming", 0) == 450)
	check("工具等级保留", loaded.player.tool_levels.get("hoe", 0) == 2)
	check("运输箱保留", int(loaded.shipping.get("items", {}).get("corn", 0)) == 3)
	check("畜棚保留", Array(loaded.livestock.get("animals", [])).size() == 1)
	check("矿洞深度保留", int(loaded.mine.get("deepest", 0)) == 5)
	check("博物馆藏品保留", Array(loaded.museum.get("donated", [])).has("ore_copper"))
	check("公共工程保留", Array(loaded.community.get("completed", [])).has("repair_bridge"))
	var old := GameState.from_dict({"schema_version": 2, "player": {"gold": 7}})
	check("v2 旧档补齐新系统", old.shipping.has("items") and old.livestock.has("animals")
		and old.mine.has("floor") and old.museum.has("donated") and old.community.has("progress"))

# --- 服务面板 ---
func _test_service_panel() -> void:
	print("\n[11] 功能 NPC 服务面板与社交入口")
	var mgr: Node = root.get_node("GameStateManager")
	var state := GameState.new()
	state.player.gold = 2000
	state.player.inventory["corn"] = 3
	state.player.inventory["animal_egg"] = 2
	state.player.inventory["ore_copper"] = 1
	state.player.inventory["forage_wood"] = 20
	state.player.inventory["material_stone"] = 10
	mgr.state = state
	var panel: Control = load("res://scripts/ui/service_panel.gd").new()
	root.add_child(panel)
	var services := ["crafting", "blacksmith", "livestock", "fishmonger", "museum",
		"merchant", "shipping", "mine", "community"]
	for service_type in services:
		panel.open_service(service_type)
		check("%s 面板能打开" % service_type, panel.is_open()
			and panel.service_type() == service_type)
		check("%s 面板有可操作按钮" % service_type, panel.action_buttons().size() > 0,
			"→ %d 个" % panel.action_buttons().size())
		panel.close_panel()

	var npc_data := NpcRegistry.get_npc("shi_tieshan")
	var npc := NpcBase.from_data(npc_data)
	var gifts: Array = []
	check("服务面板暴露送礼信号", panel.has_signal("gift_requested"))
	if panel.has_signal("gift_requested"):
		panel.connect("gift_requested", func(data: Dictionary): gifts.append(data))
	panel.open_service("blacksmith", npc)
	var talk_text := ""
	var gift_text := ""
	for button in panel.action_buttons():
		if String(button.text).contains("聊两句"):
			talk_text = String(button.text)
		if String(button.text).contains("送份礼"):
			gift_text = String(button.text)
	check("功能 NPC 有聊两句入口", talk_text != "")
	check("功能 NPC 有送份礼入口", gift_text != "")
	var affection_before := state.npc_affection("shi_tieshan")
	for button in panel.action_buttons():
		if String(button.text).contains("聊两句"):
			button.pressed.emit()
			break
	check("聊两句增加好感", state.npc_affection("shi_tieshan") > affection_before,
		"→ %d" % state.npc_affection("shi_tieshan"))
	for button in panel.action_buttons():
		if String(button.text).contains("送份礼"):
			button.pressed.emit()
			break
	check("送份礼请求发给 HUD", gifts.size() == 1 and String(gifts[0].get("id", "")) == "shi_tieshan",
		"→ %s" % str(gifts))
	panel.close_panel()
	panel.queue_free()
