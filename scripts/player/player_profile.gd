extends RefCounted
class_name PlayerProfile

## 主角档案(支持男女双主角,D10 决策)
## 玩家在创建角色时选择性别,除立绘/文本称谓外不影响任何数值。

enum Gender { MALE, FEMALE }

var gender: int = Gender.MALE
var given_name: String = ""
var age: int = 32
var hometown: String = "哈尔滨"
var from_city: String = "北京"
var energy: int = 100
var max_energy: int = 100
var gold: int = 500
var inventory: Dictionary = {}
var skills: Dictionary = {"farming": 1, "handcraft": 1, "social": 1}

## 性别中文
static func gender_cn(g: int) -> String:
	return "男" if g == Gender.MALE else "女"

## 默认名:未自定义时按性别取名
func display_name() -> String:
	if given_name != "":
		return given_name
	return "林砚舟" if gender == Gender.MALE else "林晚舟"

## 称谓:NPC 对话中如何称呼玩家
func honorific() -> String:
	return "他" if gender == Gender.MALE else "她"

func to_dict() -> Dictionary:
	return {
		"gender": gender, "given_name": given_name, "age": age,
		"hometown": hometown, "from_city": from_city,
		"energy": energy, "max_energy": max_energy, "gold": gold,
		"inventory": inventory, "skills": skills,
	}

static func from_dict(d: Dictionary) -> PlayerProfile:
	var p := PlayerProfile.new()
	p.gender = int(d.get("gender", 0))
	p.given_name = String(d.get("given_name", ""))
	p.age = int(d.get("age", 32))
	p.hometown = String(d.get("hometown", "哈尔滨"))
	p.from_city = String(d.get("from_city", "北京"))
	p.energy = int(d.get("energy", 100))
	p.max_energy = int(d.get("max_energy", 100))
	p.gold = int(d.get("gold", 500))
	p.inventory = d.get("inventory", {})
	p.skills = d.get("skills", p.skills)
	return p
