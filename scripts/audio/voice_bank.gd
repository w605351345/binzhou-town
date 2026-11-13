extends RefCounted
class_name VoiceBank

## 语音包索引:按 key 找对应的 wav。
##
## 命名规则(必须与 tools/gen_voice.py 一致):
##     <npc_id>__<line_id>__<variant>.wav
## 例:zhang_xiaofang__greet__0.wav —— 张晓芳开场白的第一个季节变体。
##
## 音频文件入库,CI 不重录(录音依赖系统 TTS,各机器嗓音不同)。

const VOICE_DIR := "res://assets/audio/dialogue/"

static var _cache: Dictionary = {}
static var _missing: Dictionary = {}

## 语音键
static func key_for(npc_id: String, line_id: String, variant: int) -> String:
	return "%s__%s__%d" % [npc_id, line_id, variant]

## 取音频流;没有就返回 null(不报错,安静跳过)
static func stream_for(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	if _missing.has(key):
		return null
	var path := VOICE_DIR + key + ".wav"
	if not ResourceLoader.exists(path):
		_missing[key] = true
		return null
	var stream: AudioStream = load(path)
	_cache[key] = stream
	return stream

## 库里共有多少条语音(自测/调试用)
static func cached_count() -> int:
	return _cache.size()
