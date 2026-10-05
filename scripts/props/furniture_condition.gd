class_name FurnitureCondition
extends RefCounted
## 家具「條件觸發」狀態要不要啟用的純函式(不管畫面,方便測試):
##   always      一直啟用(等同沒有條件,通常用不到,備用)
##   time_range  一天裡的某個時段(可跨午夜),例如檯燈只在晚上亮
##   pet_action  場上有任何一隻桌寵正在做某個動作時啟用,例如有人跳舞就亮迪斯可燈
##   in_use      2026-10-04 新增:有桌寵正在使用(坐/躺)這件家具本身時啟用
##   full        2026-10-04 新增:這件家具所有坐/躺錨點都被佔滿時啟用
## in_use/full 是「這件家具自己當下的使用狀況」,不是純函式算得出來的(跟時間/場上動作不一樣,需要呼叫端
## 傳進這件家具自己的即時佔用狀態),見下面 evaluate() 的 in_use/is_full 參數,呼叫端是 FurnitureItem.evaluate()。
## 以後要加更多種類(積木能用的其他條件)在這裡加一個 case 就好,呼叫端(FurnitureItem)不用跟著改。

const TYPES: Array[String] = ["always", "time_range", "pet_action", "in_use", "full"]
const DEFAULTS := {"type": "always", "start": 1080, "end": 360, "action": "dance"}


## 驗證一筆條件設定,壞的欄位用預設值;type 不認得就退回 "always"。
static func clean(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var kind := str(source.get("type", "always"))
	if not TYPES.has(kind):
		kind = "always"
	var result := {"type": kind}
	if kind == "time_range":
		result["start"] = _minute(source.get("start"), int(DEFAULTS["start"]))
		result["end"] = _minute(source.get("end"), int(DEFAULTS["end"]))
	elif kind == "pet_action":
		var action := str(source.get("action", DEFAULTS["action"])).strip_edges()
		result["action"] = action if action != "" and action.length() <= 40 else str(DEFAULTS["action"])
	return result


static func _minute(value: Variant, fallback: int) -> int:
	return clampi(int(value), 0, 24 * 60 - 1) if (value is float or value is int) else fallback


## 這個條件現在成不成立。minute_of_day 是純函式測試用(0~1439);actions 是場上每隻桌寵目前動作名稱的清單
## (pet_action 用);in_use/is_full 是這件家具自己當下的佔用狀況(呼叫端先查好傳進來,這裡只負責比對)。
static func evaluate(condition: Dictionary, minute_of_day: int, actions: Array, in_use := false, is_full := false) -> bool:
	match str(condition.get("type", "always")):
		"time_range":
			var start: int = int(condition.get("start", 0))
			var end: int = int(condition.get("end", 0))
			if start == end:
				return true
			return (minute_of_day >= start and minute_of_day < end) if start < end else (minute_of_day >= start or minute_of_day < end)
		"pet_action":
			var wanted := str(condition.get("action", ""))
			return actions.any(func(name: Variant) -> bool: return str(name) == wanted)
		"in_use":
			return in_use
		"full":
			return is_full
		_:
			return true


## 給精靈圖編輯器下拉選單用的白話說明。
static func label_of(kind: String) -> String:
	match kind:
		"time_range":
			return "指定時間段"
		"pet_action":
			return "有桌寵正在做某個動作"
		"in_use":
			return "有桌寵正在使用這件家具"
		"full":
			return "這件家具所有座位都被佔滿"
		_:
			return "一直啟用"
