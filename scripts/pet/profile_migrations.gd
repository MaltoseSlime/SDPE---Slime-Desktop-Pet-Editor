class_name ProfileMigrations
extends RefCounted
## 存檔(桌寵設定檔 profile、執行狀態 state、全域數值 globals)的格式版本與「舊資料轉新格式」的升級表。
## 開發守則(新版本不可以讓舊存檔故障):
##  1. 新增欄位:讀的時候一律用預設值(`.get(key, 預設)`),舊檔沒有這欄照樣能讀;不用升級步驟。
##  2. 改了既有欄位的意思或結構(改名、拆開、換單位):CURRENT 加一,並在 steps 登記「從舊版升到新版」的函式;讀檔時自動一版一版升上來。
##  3. 內建預設內容(性格、狀態鏡…)有更新:不用動這裡,改內建性格檔即可,簽章會變,開機時詢問使用者是否追加(見 DefaultsUpdater)。
##  4. 存檔比程式新(版本號比 CURRENT 大):不動它、盡量讀得懂的部分。
## 升級函式只拿到字典(已是深拷貝),回傳升級後的字典;不要做 IO。

## 目前的格式版本(測試會暫時改它,所以是 static var)。
static var CURRENT := {"profile": 1, "state": 1, "globals": 1}

## kind → {從哪個版本: Callable(data: Dictionary) -> Dictionary(升到「該版本 + 1」)}。目前還沒有需要升級的格式。
static var steps := {"profile": {}, "state": {}, "globals": {}}


## 把讀進來的資料升到目前的格式版本。沒有登記升級步驟的版本視為相容(只更新版號)。
static func migrate(kind: String, data: Dictionary) -> Dictionary:
	var raw: Variant = data.get("version", 1)
	var version := int(raw) if (raw is int or raw is float) else 1
	var target := int(CURRENT.get(kind, 1))
	if version >= target:
		return data
	var result := data
	while version < target:
		var step: Variant = (steps.get(kind, {}) as Dictionary).get(version)
		if step is Callable:
			var upgraded: Variant = (step as Callable).call(result.duplicate(true))
			if upgraded is Dictionary:
				result = upgraded
		version += 1
		result["version"] = version
	return result
