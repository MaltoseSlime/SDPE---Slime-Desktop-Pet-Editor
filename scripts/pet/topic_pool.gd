class_name TopicPool
extends RefCounted
## 預設話題文本(2026-10-06):content/topic_pool.json,由 docs/關鍵詞閒聊文本池範本.md 轉換而來。
## 每句 {condition, text};所有性格先共用這一組,之後會依性格另外做版本。

const PATH := "res://content/topic_pool.json"
static var _cache: Array = []


## 依語系取話題句要說的文字:英文語系且這句有英文版(en)就用英文,否則用原文(text)。
static func text_for(entry: Dictionary, locale: String) -> String:
	var en := str(entry.get("en", ""))
	if en != "" and is_english(locale):
		return en
	return str(entry.get("text", ""))


static func is_english(locale: String) -> bool:
	return locale.replace("_", "-").split("-")[0].to_lower() == "en"


static func defaults() -> Array:
	if _cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Array:
			_cache = parsed
	return _cache.duplicate(true)
