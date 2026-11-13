extends SceneTree
## headless 商店自测:道具库 + 买卖结算(纯逻辑)
##
## 运行: godot --headless --script res://scripts/tests/test_shop.gd
##
## 这组测试守住一条底线:**张晓芳的收购账必须算得清**。
## 黑龙江一年一熟,一季的收成全靠卖给张晓芳换成钱,钱算错了整个循环就断了。

var _passed := 0
var _failed := 0

func _init() -> void:
	print("=== 《宾州小镇》商店自测 (shop test) ===")
	print("设定:张晓芳是收购商,收购价 = 作物售价 × buy_ratio,好感度还能加成")
	print("--------------------------------------------------")

	test_item_database()
	test_buy_item()
	test_sell_crop()
	test_price_consistency()
	test_shop_summary()

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

# --- 道具库 ---
func test_item_database() -> void:
	print("\n[1] 道具库(items.json)")
	check("items.json 可读", not ItemDatabase.load_all().is_empty())
	check("12 件道具", ItemDatabase.all_items().size() == 12,
		"→ %d 件" % ItemDatabase.all_items().size())
	var seeds := ItemDatabase.seed_items()
	check("3 件种子", seeds.size() == 3, "→ %d 件" % seeds.size())
	var corn_seed := ItemDatabase.get_item("seed_corn")
	check("玉米种存在", not corn_seed.is_empty())
	check("玉米种指向玉米", String(corn_seed.get("crop_id", "")) == "corn")
	check("按作物找种子", ItemDatabase.seed_for_crop("corn") == "seed_corn",
		"→ " + ItemDatabase.seed_for_crop("corn"))
	check("没有的作物找种子返回空", ItemDatabase.seed_for_crop("不存在的作物") == "")
	check("按分类取道具", ItemDatabase.items_of_category("tool").size() == 3,
		"→ %d 件" % ItemDatabase.items_of_category("tool").size())
	# 种子的进价必须跟 crops.json 的 seed_price 对得上,否则播种成本会前后不一
	var crop := CropDatabase.get_crop("corn")
	var seed := ItemDatabase.get_item("seed_corn")
	check("种子进价与作物表一致",
		int(seed.get("buy_price", 0)) == int(crop.seed_price),
		"→ %s vs %s" % [seed.get("buy_price", "?"), crop.seed_price])

# --- 买 ---
func test_buy_item() -> void:
	print("\n[2] 买东西(买种子/工具)")
	var player := PlayerProfile.new()
	player.gold = 100
	var res := Shop.buy_item(player, "seed_corn", 1)
	check("买种子成功", bool(res.get("ok", false)), "→ " + String(res.get("message", "")))
	check("金币扣了", player.gold == 70, "→ %d" % player.gold)
	check("背包里有种子了", int(player.inventory.get("seed_corn", 0)) == 1)

	# 买两个
	var res2 := Shop.buy_item(player, "seed_corn", 2)
	check("买两个也成功", bool(res2.get("ok", false)))
	check("金币扣了 60", player.gold == 10, "→ %d" % player.gold)
	check("背包里有 3 个种子", int(player.inventory.get("seed_corn", 0)) == 3)

	# 钱不够
	var res3 := Shop.buy_item(player, "seed_corn", 1)
	check("钱不够买不了", not bool(res3.get("ok", false)), "→ " + String(res3.get("message", "")))
	check("钱不够时金币没动", player.gold == 10, "→ %d" % player.gold)
	check("钱不够时背包没多", int(player.inventory.get("seed_corn", 0)) == 3)

	# 买不存在的东西
	var res4 := Shop.buy_item(player, "不存在的道具", 1)
	check("买不存在的道具被拒", not bool(res4.get("ok", false)))
	# 数量非法
	var res5 := Shop.buy_item(player, "seed_corn", 0)
	check("买 0 个被拒", not bool(res5.get("ok", false)))
	var res6 := Shop.buy_item(player, "seed_corn", -1)
	check("买负数个被拒", not bool(res6.get("ok", false)))
	check("非法数量没扣钱", player.gold == 10, "→ %d" % player.gold)

# --- 卖 ---
func test_sell_crop() -> void:
	print("\n[3] 卖粮(张晓芳收购)")
	var player := PlayerProfile.new()
	player.gold = 500
	player.inventory["corn"] = 4
	var npc := ZhangXiaofang.new()
	var res := Shop.sell_crop(player, npc, "corn", 4)
	check("卖 4 个玉米成功", bool(res.get("ok", false)), "→ " + String(res.get("message", "")))
	check("背包清空", int(player.inventory.get("corn", 0)) == 0)
	# 收购价 = 26(售价) × 0.9(收购比) = 23 → 4 个 = 92
	check("金币到账 92", player.gold == 592, "→ %d" % player.gold)

	# 没有的作物
	var res2 := Shop.sell_crop(player, npc, "corn", 4)
	check("卖没货的作物被拒", not bool(res2.get("ok", false)), "→ " + String(res2.get("message", "")))

	# 不存在的作物 id
	player.inventory["corn"] = 2
	var res3 := Shop.sell_crop(player, npc, "不存在的作物", 1)
	check("卖不存在的作物被拒", not bool(res3.get("ok", false)))
	check("金币没变", player.gold == 592, "→ %d" % player.gold)

	# 数量非法
	var res4 := Shop.sell_crop(player, npc, "corn", 0)
	check("卖 0 个被拒", not bool(res4.get("ok", false)))
	var res5 := Shop.sell_crop(player, npc, "corn", 99)
	check("卖超量被拒", not bool(res5.get("ok", false)))
	check("超量后金币没变", player.gold == 592, "→ %d" % player.gold)
	check("超量后背包没少", int(player.inventory.get("corn", 0)) == 2)

# --- 价格一致性 ---
func test_price_consistency() -> void:
	print("\n[4] 收购价与好感度加成")
	var player := PlayerProfile.new()
	player.gold = 0
	player.inventory["corn"] = 4
	var npc := ZhangXiaofang.new()
	# 好感度 0:ratio = 0.9 → 26 × 0.9 = 23.4 → 23
	Shop.sell_crop(player, npc, "corn", 4)
	check("零好感度按 0.9 收购", player.gold == 92, "→ %d 文" % player.gold)

	# 好感度 30:ratio = 0.9 + 30×0.01 = 1.0 → 26 → 4 个 = 104
	player.gold = 0
	player.inventory["corn"] = 4
	npc.affection = 30
	Shop.sell_crop(player, npc, "corn", 4)
	check("好感度 30 收购价上浮到 1.0", player.gold == 104, "→ %d 文" % player.gold)

	# 好感度封顶:最多加 0.1 → ratio = 1.0
	player.gold = 0
	player.inventory["corn"] = 4
	npc.affection = 999
	Shop.sell_crop(player, npc, "corn", 4)
	check("好感度加成有上限(最多 1.0)", player.gold == 104, "→ %d 文" % player.gold)

	# 收购价必须低于市价(收购商压价),不然玩家不如直接卖给市场
	check("收购价不高于市价", npc.buy_ratio <= 1.0, "→ %.2f" % npc.buy_ratio)

# --- 商店清单 ---
func test_shop_summary() -> void:
	print("\n[5] 商店清单(给 UI 用)")
	var player := PlayerProfile.new()
	player.gold = 100
	player.inventory["corn"] = 4
	player.inventory["potato"] = 2
	var npc := ZhangXiaofang.new()

	var sellable := Shop.sellable_crops(player)
	check("背包里两种作物可卖", sellable.size() == 2, "→ %d 种" % sellable.size())
	var corn_entry: Dictionary = {}
	for entry in sellable:
		if String(entry.get("crop_id", "")) == "corn":
			corn_entry = entry
	check("玉米条目有数量", int(corn_entry.get("amount", 0)) == 4)
	check("玉米条目有单价", int(corn_entry.get("unit_price", 0)) == 23,
		"→ %d 文" % int(corn_entry.get("unit_price", 0)))
	check("玉米条目有总价", int(corn_entry.get("total", 0)) == 92,
		"→ %d 文" % int(corn_entry.get("total", 0)))

	var purchasable := Shop.purchasable_items(player)
	check("商店有货可买", purchasable.size() > 0, "→ %d 件" % purchasable.size())
	var affordable := 0
	for entry in purchasable:
		if bool(entry.get("affordable", false)):
			affordable += 1
	check("100 钱能买下部分道具", affordable > 0, "→ %d 件买得起" % affordable)
	# 买得起的那件,单价必须不超过手里的钱
	for entry in purchasable:
		if bool(entry.get("affordable", false)):
			check("买得起的单价不超余额",
				int(entry.get("price", 0)) <= player.gold,
				"→ %s %d 文" % [entry.get("name", "?"), int(entry.get("price", 0))])
			break
