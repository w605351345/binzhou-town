extends RefCounted
class_name ModalStack

## 模态栈:对话、商店、背包、邮册、事件等界面统一登记。
## input_locked 由栈深度派生,避免多个布尔锁互相覆盖或遗漏归还。

var _tokens: Array[String] = []

func push(token: String) -> void:
	if token == "":
		return
	if _tokens.has(token):
		return
	_tokens.append(token)

func pop(token: String) -> void:
	var idx := _tokens.rfind(token)
	if idx >= 0:
		_tokens.remove_at(idx)

func has(token: String) -> bool:
	return _tokens.has(token)

func depth() -> int:
	return _tokens.size()

func is_locked() -> bool:
	return not _tokens.is_empty()

func clear() -> void:
	_tokens.clear()

func tokens() -> Array[String]:
	return _tokens.duplicate()
