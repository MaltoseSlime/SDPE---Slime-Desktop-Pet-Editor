class_name PropDef
extends RefCounted
## 小道具的定義(企劃書第五章「物品欄與小道具資源定義」):顯示名稱、縮圖與桌面貼圖(存在道具資料夾裡的檔名)、兩種互動模式(丟入拾取/吃掉、貼身摩擦)、
## 預設交互反應(沒有事件積木也沒有數值綁定時的保底行為)、直接數值綁定、狀態切換綁定、拖曳中吸引、可持有、逾時自動消失、摩擦後是否消耗。
## 存成 user://props/<id>/prop.json(見 PropLibrary);所有欄位讀進來都會驗證與夾範圍,壞的欄位用預設值。

const MAX_NAME := 40
const MAX_BINDINGS := 12
const MAX_KEY := 40
const MAX_TIMEOUT := 3600.0
## 預設交互反應:none = 單純消失(仍算一次互動),pickup = 播放 gather 動作後移除。
const REACTIONS: Array[String] = ["none", "pickup"]
const SCOPES: Array[String] = ["local", "global"]
const LENS_OPS: Array[String] = ["enable", "disable"]
## 被使用(拾取或摩擦消耗)時的表現:none 立刻消失、shake 左右搖晃幾次(晃一下、停頓、再晃一下,只晃不縮小)後消失(適合食物)、shake_v 同樣但上下晃、float_up 向上飄後淡出(適合金幣)、fade 原地淡出。
const USE_ANIMS: Array[String] = ["none", "shake", "shake_v", "float_up", "fade"]
## 進階貼圖(精靈圖編輯器的道具區,存在道具資料夾的 sprite/)的狀態動畫播放方式:trigger = 進入這個狀態時播 count 次就回預設;loop = 這個狀態持續期間一直循環。
const STATE_MODES: Array[String] = ["trigger", "loop"]
const MAX_STATE_COUNT := 20
## 碰撞形狀:box 一般方形道具;ball 圓球(會滾動旋轉、彈跳,桌寵會追著玩、拋、頂在頭上;沒有桌寵在玩時才計自動消失)。被持有時放在哪:hand 手上(持有錨點)、head 頭頂(判定框頭頂位置)。
const SHAPES: Array[String] = ["box", "ball"]
const HOLD_PLACES: Array[String] = ["hand", "head"]
const MIN_SHAKES := 2
const MAX_SHAKES := 8

## 資料夾名稱(由顯示名稱轉成檔案安全的字串),同一個物品欄裡不重複。
var id := ""
var display_name := ""
## 圖片檔名(相對於道具資料夾),空字串 = 沒有,桌面上用程式畫的替代圖示。桌面貼圖空白時沿用縮圖。
var thumbnail := ""
var desktop_texture := ""
var toss := true
var rub := false
var default_reaction := "pickup"
## 每筆 {scope: local/global, key: 數值名稱, delta: 增減量}。
var value_bindings: Array[Dictionary] = []
## 每筆 {op: enable/disable, lens: 狀態鏡名稱}。
var lens_bindings: Array[Dictionary] = []
## 觸發時解除所有目前生效、被標記為「負面」的狀態鏡。
var disable_negative := false
## 觸發時解除所有目前生效、被標記為「正面」的狀態鏡。
var disable_positive := false
## 觸發時恢復多少精力(疲勞值);0 = 不恢復。疲憊狀態下拿到它,疲憊會更快結束。
var restore_energy := 0.0
var attract_while_dragging := false
var holdable := false
var shape := "box"
var hold_place := "hand"
## 落地後幾秒沒被拾取就自動消失;0 = 永久留存。預設 3 分鐘,避免測試用又沒人撿的道具佔滿桌面。
const DEFAULT_TIMEOUT := 180.0
var timeout_seconds := DEFAULT_TIMEOUT
## 貼身摩擦模式觸發後是否一次性消耗(預設回到物品欄可重複使用)。
var consume_on_rub := false
## 被使用時的表現動畫與搖晃次數(shake 才用)。
var use_anim := "fade"
var use_shakes := 3
## 觸發時連帶在桌寵身上播的特效(PetEffects 的名稱,空白 = 不播);例如洗滌用品 → 泡沫。
var effect := ""
## 進階貼圖的兩個狀態動畫(預設狀態一直循環):used = 被使用(和桌寵交互時播),drag = 拖曳中(被滑鼠抓著移動時才播)。
var used_mode := "trigger"
var used_count := 1
var drag_mode := "loop"
var drag_count := 1
## 使用結束後才播的第二個特效(空白 = 不播):丟入式在使用動畫播完後,貼身摩擦在桌寵不再被這個道具擦(道具離開、放開或用完)之後;例如洗滌用品擦完接著閃閃發光。
var effect_after := ""
## 這個道具是從哪個內建模板做的(只是標記,不影響行為)。
var template := ""
## 道具 / 家具專屬光源(燈具、蠟燭…,企劃書第八章):{enabled, x, y, radius, energy, color}。x 是圖片寬度的比例(−0.5 ~ 0.5,0 = 正中間),y 是從腳底往上的圖片高度比例(−1 ~ 0,−1 = 頂端),
## radius 是光暈半徑(像素)、energy 強度 0.1~2。沒開就不發光。畫法見 PropLight。
var light: Dictionary = default_light()
const LIGHT_LIMITS := {"x": Vector2(-0.5, 0.5), "y": Vector2(-1.0, 0.0), "radius": Vector2(20.0, 300.0), "energy": Vector2(0.1, 2.0)}


static func default_light() -> Dictionary:
	return {"enabled": false, "x": 0.0, "y": -0.75, "radius": 70.0, "energy": 0.9, "color": "#ffe4a0"}


## 逐欄驗證光源設定,壞的欄位用預設、數字夾在範圍內。
static func clean_light(raw: Variant) -> Dictionary:
	var result := default_light()
	if not raw is Dictionary:
		return result
	if raw.get("enabled") is bool:
		result["enabled"] = raw["enabled"]
	for key: String in LIGHT_LIMITS:
		var value: Variant = raw.get(key)
		if (value is float or value is int) and is_finite(float(value)):
			var limits: Vector2 = LIGHT_LIMITS[key]
			result[key] = clampf(float(value), limits.x, limits.y)
	var color := str(raw.get("color", ""))
	if color != "" and Color.html_is_valid(color):
		result["color"] = "#" + Color.html(color).to_html(false)
	return result


func has_light() -> bool:
	return bool(light.get("enabled", false))


## 顯示名稱 → 資料夾名稱:去掉檔案系統不能用的字元與前後空白、句點,太長截斷;空的用 "prop"。
static func safe_id(text: String) -> String:
	var result := ""
	for i in text.strip_edges().length():
		var c := text[i]
		if c in "\\/:*?\"<>|" or c.unicode_at(0) < 32:
			result += "_"
		else:
			result += c
	result = result.strip_edges().lstrip(".").rstrip(". ")
	if result.length() > MAX_NAME:
		result = result.left(MAX_NAME)
	return result if result != "" else "prop"


static func clean_name(text: String) -> String:
	var result := text.strip_edges().replace("\n", " ").replace("\t", " ")
	if result.length() > MAX_NAME:
		result = result.left(MAX_NAME)
	return result


func modes() -> Array[String]:
	var result: Array[String] = []
	if toss:
		result.append("toss")
	if rub:
		result.append("rub")
	return result


## Schema 匯出用(網頁的下拉選單與積木):{name, modes, holdable, attractWhileDragging}。
func schema_entry() -> Dictionary:
	return {"name": display_name, "modes": modes(), "holdable": holdable, "attractWhileDragging": attract_while_dragging}


## 觸發時有沒有任何「免寫積木」的效果(數值、狀態鏡、解除負面)。預設交互反應只在「沒有事件積木、也沒有這些」時才當保底。
func has_bindings() -> bool:
	return not value_bindings.is_empty() or not lens_bindings.is_empty() or disable_negative or disable_positive or restore_energy > 0.0


func to_dict() -> Dictionary:
	return {
		"name": display_name, "thumbnail": thumbnail, "desktopTexture": desktop_texture,
		"toss": toss, "rub": rub, "shape": shape, "holdPlace": hold_place, "defaultReaction": default_reaction,
		"valueBindings": value_bindings.duplicate(true), "lensBindings": lens_bindings.duplicate(true),
		"disableNegative": disable_negative, "disablePositive": disable_positive, "restoreEnergy": restore_energy, "attractWhileDragging": attract_while_dragging, "holdable": holdable,
		"timeoutSeconds": timeout_seconds, "consumeOnRub": consume_on_rub, "template": template, "light": light.duplicate(),
		"useAnim": use_anim, "useShakes": use_shakes, "effect": effect, "effectAfter": effect_after,
		"states": {"used": {"mode": used_mode, "count": used_count}, "drag": {"mode": drag_mode, "count": drag_count}},
	}


## 從字典還原(逐欄驗證);folder_id 是資料夾名稱。名稱空白回傳 null。
static func from_dict(data: Variant, folder_id: String) -> PropDef:
	if not data is Dictionary:
		return null
	var def := PropDef.new()
	def.id = folder_id
	def.display_name = clean_name(str(data.get("name", folder_id)))
	if def.display_name == "":
		return null
	def.thumbnail = _file_name(data.get("thumbnail", ""))
	def.desktop_texture = _file_name(data.get("desktopTexture", ""))
	def.toss = _flag(data.get("toss", true), true)
	def.rub = _flag(data.get("rub", false), false)
	var reaction := str(data.get("defaultReaction", "pickup"))
	def.default_reaction = reaction if REACTIONS.has(reaction) else "pickup"
	def.value_bindings = _clean_value_bindings(data.get("valueBindings", []))
	def.lens_bindings = _clean_lens_bindings(data.get("lensBindings", []))
	def.disable_negative = _flag(data.get("disableNegative", false), false)
	def.disable_positive = _flag(data.get("disablePositive", false), false)
	var restore: Variant = data.get("restoreEnergy", 0.0)
	def.restore_energy = clampf(float(restore), 0.0, 100.0) if (restore is float or restore is int) else 0.0
	def.attract_while_dragging = _flag(data.get("attractWhileDragging", false), false)
	def.holdable = _flag(data.get("holdable", false), false)
	def.shape = str(data.get("shape", "box")) if SHAPES.has(str(data.get("shape", "box"))) else "box"
	def.hold_place = str(data.get("holdPlace", "hand")) if HOLD_PLACES.has(str(data.get("holdPlace", "hand"))) else "hand"
	var timeout: Variant = data.get("timeoutSeconds", DEFAULT_TIMEOUT)
	def.timeout_seconds = clampf(float(timeout), 0.0, MAX_TIMEOUT) if (timeout is float or timeout is int) else DEFAULT_TIMEOUT
	def.consume_on_rub = _flag(data.get("consumeOnRub", false), false)
	def.template = clean_name(str(data.get("template", "")))
	def.light = clean_light(data.get("light"))
	var anim := str(data.get("useAnim", "fade"))
	def.use_anim = anim if USE_ANIMS.has(anim) else "fade"
	var shakes: Variant = data.get("useShakes", 3)
	def.use_shakes = clampi(int(shakes), MIN_SHAKES, MAX_SHAKES) if (shakes is float or shakes is int) else 3
	var effect_name := str(data.get("effect", "")).strip_edges()
	def.effect = PetEffects.resolve(effect_name)   # 存英文代號(不隨語系變;舊檔的中文名稱讀進來會轉成代號)
	var states: Variant = data.get("states")
	if states is Dictionary:
		var used: Variant = states.get("used")
		if used is Dictionary:
			def.used_mode = _state_mode(used.get("mode"), "trigger")
			def.used_count = _state_count(used.get("count"))
		var drag: Variant = states.get("drag")
		if drag is Dictionary:
			def.drag_mode = _state_mode(drag.get("mode"), "loop")
			def.drag_count = _state_count(drag.get("count"))
	var after_name := str(data.get("effectAfter", "")).strip_edges()
	def.effect_after = PetEffects.resolve(after_name)
	return def


static func _state_mode(value: Variant, fallback: String) -> String:
	return str(value) if STATE_MODES.has(str(value)) else fallback


static func _state_count(value: Variant) -> int:
	return clampi(int(value), 1, MAX_STATE_COUNT) if (value is float or value is int) else 1


## 布林欄位:只認 true/false 或 0/1,其他型別(字串、陣列…)用預設值。
static func _flag(value: Variant, fallback: bool) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	return fallback


## 圖片檔名只能是道具資料夾裡的單純檔名(不含路徑),擋掉 ../ 之類。
static func _file_name(value: Variant) -> String:
	var text := str(value).strip_edges()
	if text == "" or text != text.get_file() or text.begins_with("."):
		return ""
	return text


static func _clean_value_bindings(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if result.size() >= MAX_BINDINGS or not entry is Dictionary:
			continue
		var key := str(entry.get("key", "")).strip_edges()
		var delta: Variant = entry.get("delta", 0.0)
		if key == "" or key.length() > MAX_KEY or not (delta is float or delta is int):
			continue
		var scope := str(entry.get("scope", "local"))
		result.append({"scope": scope if SCOPES.has(scope) else "local", "key": key, "delta": clampf(float(delta), -1000000.0, 1000000.0)})
	return result


static func _clean_lens_bindings(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if result.size() >= MAX_BINDINGS or not entry is Dictionary:
			continue
		var lens := str(entry.get("lens", "")).strip_edges()
		var op := str(entry.get("op", "enable"))
		if lens == "" or lens.length() > MAX_KEY:
			continue
		result.append({"op": op if LENS_OPS.has(op) else "enable", "lens": lens})
	return result
