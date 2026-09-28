class_name PackLoop
extends RefCounted
## 動作的「循環設定」(pack.json 的 loop_by_action,鍵是動畫基本名稱,例如 idle、sit):
##   {"mode": "loop", "start": 2, "end": 4}  一直循環,但只在 start~end 幀之間:第一次從第 0 幀播到 end 幀,之後每次都從 start 幀接回來循環(end 之後的幀不播;不寫 start / end = 整段循環)
##   {"mode": "once", "hold": 5}             不循環:播到 hold 幀就停住,直到這個動作被切換(不寫 hold = 停在最後一幀)
##   {"mode": "repeat", "times": 2}          整段動畫重複播 times+1 次(含第一次)後停在最後一幀;times = 0 等同只播一次、不循環
## 沒有設定 = 照舊(整段循環;enter / leave 這類一次性動作播一次停在最後一幀)。幀編號從 0 開始、都是這個動作自己的幀順序。
## 純函式,載入器、精靈圖編輯器(存讀與預覽)、桌寵執行時共用同一套規則。
## repeat 模式的「播 N 次就停」無法只靠 frame_range/next_frame 這種每次只看「目前第幾幀」的無狀態函式做到(分不出這是第幾輪循環),
## 所以載入器改用 repeat_frames() 直接把幀序重複串接、再當成不循環的長動畫播(引擎原生只有「一直循環」或「播一次」兩種,沒有「播 N 次」);
## 精靈圖編輯器的預覽為了保持無狀態,repeat 模式一律當成一直循環播放,只在下面的說明文字提醒「遊戲裡實際只會播 N 次」。

const MODES: Array[String] = ["loop", "once", "repeat"]
## repeat 模式「重複次數」欄位(times)的上限,避免動畫被撐成離譜長。
const MAX_TIMES := 20


## 驗證一筆設定(壞的欄位丟掉);沒有任何有效內容或等於預設(整段循環)就回空字典。
static func clean_entry(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var mode := str(raw.get("mode", "loop"))
	if not MODES.has(mode):
		return {}
	var entry := {"mode": mode}
	if mode == "once":
		if _is_number(raw.get("hold")):
			entry["hold"] = maxi(int(raw["hold"]), 0)
		return entry
	if mode == "repeat":
		entry["times"] = clampi(int(raw.get("times", 0)) if _is_number(raw.get("times")) else 0, 0, MAX_TIMES)
		return entry
	var has_start := _is_number(raw.get("start")) and int(raw["start"]) >= 0
	var has_end := _is_number(raw.get("end")) and int(raw["end"]) >= 0
	if has_start:
		entry["start"] = int(raw["start"])
	if has_end:
		entry["end"] = int(raw["end"])
	return entry if has_start or has_end else {}


## repeat 模式專用:把來源幀索引陣列(frames,例如 [0,1,2])依 times+1 次重複串接成播放清單(times=0 就是原封不動的一輪)。
## 串起來的每個元素仍是原本的來源幀索引,眨眼/說話差分照原本邏輯直接用就對。
static func repeat_frames(frames: Array, times: int) -> Array:
	var cycles := clampi(times, 0, MAX_TIMES) + 1
	var result: Array = []
	for i in cycles:
		result.append_array(frames)
	return result


static func clean(raw: Variant) -> Dictionary:
	var result := {}
	if raw is Dictionary:
		for key: Variant in (raw as Dictionary).keys():
			var entry := clean_entry(raw[key])
			if not entry.is_empty():
				result[str(key)] = entry
	return result


## 這個動作(count 幀)實際會播哪些幀:{kept: 保留前幾幀(0 ~ kept-1)、loop: true / false / null(null = 沒設定,照舊)、start: 循環時接回來的幀}。
## repeat 模式在這裡當成「整段一直循環」(kept=count、loop=true):真正「播 N 次就停」只有載入器用 repeat_frames() 另外處理,
## 這個函式是無狀態的(不知道已經播過幾輪),沒辦法自己數次數;精靈圖編輯器的預覽也因此會一直循環,不會自動停。
static func frame_range(count: int, entry: Dictionary) -> Dictionary:
	var total := maxi(count, 1)
	if entry.is_empty():
		return {"kept": total, "loop": null, "start": 0}
	var mode := str(entry.get("mode", "loop"))
	if mode == "once":
		var hold := clampi(int(entry.get("hold", total - 1)), 0, total - 1)
		return {"kept": hold + 1, "loop": false, "start": 0}
	if mode == "repeat":
		return {"kept": total, "loop": true, "start": 0}
	var last := clampi(int(entry.get("end", total - 1)), 0, total - 1)
	return {"kept": last + 1, "loop": true, "start": clampi(int(entry.get("start", 0)), 0, last)}


## 預覽用:目前在第 current 幀,下一格要顯示哪一幀(停住的動作會一直回傳同一幀)。
static func next_frame(count: int, entry: Dictionary, current: int) -> int:
	var span := frame_range(count, entry)
	var kept := int(span["kept"])
	if current + 1 < kept:
		return current + 1
	if span["loop"] == false:
		return kept - 1
	return int(span["start"])


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
