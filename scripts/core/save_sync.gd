extends RefCounted
class_name SaveSync

## 云存档适配层。
##
## Steam Cloud 需要 Steamworks SDK 与发行方 AppID,当前账号条件不具备;
## 这里先定义一个可外部同步的镜像目录(BZC_CLOUD_DIR)。接入 Steamworks 时
## 只需把 push_slot / pull_slot 换成 RemoteStorage 调用,游戏存档格式不变。

const CLOUD_DIR_ENV := "BZC_CLOUD_DIR"

static func cloud_dir() -> String:
	return OS.get_environment(CLOUD_DIR_ENV).strip_edges()

static func is_configured() -> bool:
	return cloud_dir() != ""

static func slot_path(slot: int) -> String:
	var dir := cloud_dir()
	if dir == "":
		return ""
	return "%s/slot_%d.json" % [dir, slot]

## 把存档正文推到云目录。未配置时静默跳过(本地存档仍然可用)。
static func push_slot(slot: int, payload: String) -> bool:
	var path := slot_path(slot)
	if path == "":
		return false
	if DirAccess.make_dir_recursive_absolute(cloud_dir()) != OK:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSync: 云目录写入失败 %s" % path)
		return false
	f.store_string(payload)
	f.close()
	return true

## 读取云目录里的存档正文;没有配置或文件不存在时返回空串。
static func pull_slot(slot: int) -> String:
	var path := slot_path(slot)
	if path == "" or not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var payload := f.get_as_text()
	f.close()
	return payload

static func has_slot(slot: int) -> bool:
	var path := slot_path(slot)
	return path != "" and FileAccess.file_exists(path)
