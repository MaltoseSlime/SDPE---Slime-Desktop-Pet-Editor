class_name FurnitureDef
extends RefCounted
## 家具的定義(企劃書第九章家具/背景物,第一批只做「純裝飾」:滑鼠可穿透的貼圖,可以動畫化、可以依條件切換要不要啟用)。
## 存成 user://furniture/<id>/furniture.json(見 FurnitureLibrary)。
## 進階貼圖(精靈圖編輯器的家具區,存在家具資料夾的 sprite/)有三個狀態槽:
##   normal      平時的樣子(trigger 沒成立,或設成「一直啟用」時的一般狀態),一直循環播放
##   conditional 條件成立時切過去的樣子(例如檯燈的燈是亮的、迪斯可燈在轉),一直循環播放
##   interacted  桌寵在使用這件家具時播的樣子(坐下、開箱子…);這批還沒有讓桌寵真的去用家具,這個狀態槽先留著給素材,之後接上
## 桌寵坐下/躺下(可坐/可躺的「錨點」,見下面 anchors)第二批已經做;交互(判定框、容量以外的細節)、
## 積木(加入使用/取消使用/邀請/觸發開關…)、家具標籤、網頁端同步還沒做,見記憶 project_furniture_phase2_spec。
## 圖層+光源(第三批):光源設定見下面 lights(一件家具可以有好幾盞,例如吊燈好幾顆燈泡;畫法見 FurnitureLight,
## 和道具的 PropLight 同一套,多了扇形遮罩可以選);「一直啟用」以外的觸發方式時,燈只有條件成立(conditional 狀態)
## 才會亮,呼應「檯燈只在晚上亮」這種用法(2026-09-23:精靈圖編輯器的預覽也照這個規則,不是條件成立的時段就會變暗)。
## above_light:這件家具的貼圖要不要蓋在自己的光暈「之上」(預設 false = 貼圖在下面、光暈疊上去,跟道具/桌寵一致)。
## 家具標籤(第四批,見下面 tags):網頁端積木編輯器很難讓使用者「指定某一件特定的家具」,改用標籤篩選事件判定;
## 標籤是固定清單(TAGS_CATALOG,不能自訂),一件家具可以掛好幾個標籤。

const MAX_NAME := 40
const SCALE_RANGE := Vector2(0.3, 3.0)
## 錨點座標(相對家具原點的偏移)夾在這個範圍內,避免存進毀損的極端值。
const ANCHOR_RANGE := 4000.0
## "lay"(不是 "lie")故意跟桌寵素材包既有的系統動作同名(見 pet.gd chat_context()/_start_animation 已經有的
## sit/lay 動作與「缺 lay 就退回 sit」的降級邏輯),錨點類型直接對應要播哪個動作,不用另外轉換名稱。
const ANCHOR_TYPES: Array[String] = ["sit", "lay"]
## 使用這個錨點時桌寵要面向哪邊:"both"(預設,使用時隨機擇一方向)/"left"/"right"。
const ANCHOR_FACINGS: Array[String] = ["both", "left", "right"]
## 光源形狀:radial 一般圓形光暈(跟道具/桌寵同款貼圖);fan 扇形(手電筒/聚光燈那種有方向、有張角的光,見 FurnitureLight)。
const LIGHT_SHAPES: Array[String] = ["radial", "fan"]
const LIGHT_LIMITS := {"radius": Vector2(20.0, 500.0), "energy": Vector2(0.1, 2.0), "angle": Vector2(0.0, 360.0), "spread": Vector2(10.0, 180.0)}
## 每盞燈依三個動作槽(見檔頭)各自決定要不要亮:off 不啟用、always 這個槽播放中就一直亮、frames 只有目前幀落在
## [start, end] 才亮(例如蠟燭動畫只有中間幾幀火苗最亮時才發光)。interacted_0 目前還沒真的播放(見 FurnitureItem
## 檔頭),先讓資料模型支援,之後接上播放邏輯就會生效。
const LIGHT_SLOT_NAMES: Array[String] = ["normal_0", "conditional_0", "interacted_0"]
const LIGHT_SLOT_MODES: Array[String] = ["off", "always", "frames"]
## 幀數範圍上限(跟精靈圖動作幀數上限同量級,寬鬆給,不夠再調)。
const LIGHT_FRAME_MAX := 999
## 一件家具最多幾盞光(跟角色的 PackLights.MAX_LIGHTS 同一個量級,家具通常比角色簡單一點)。
const MAX_LIGHTS := 6
## 家具標籤:固定清單,只是名字,方便使用者在網頁端積木編輯器篩選事件判定用(不能自訂,寬一點方便涵蓋各種家具)。
const TAGS_CATALOG: Array[String] = [
	"燈具", "椅子", "沙發", "床", "桌子", "櫃子", "書架", "容器", "廚具", "電器",
	"裝飾品", "植物", "地毯", "窗簾", "鏡子", "樂器", "遊樂設施", "運動器材",
	"衛浴", "壁爐", "時鐘", "掛畫", "遊戲機", "其他",
]
const MAX_TAGS := 6
## 容器(第五批):存放哪些道具種類、各自補滿的數量上限(見下面 container_items)。一件家具的容器內容物在家具庫的
## 浮動視窗設定(見 PackEditorWindow.open_furniture());最多能設 MAX_CONTAINER_ITEMS 種道具,每種數量上限在
## CONTAINER_CAPACITY_RANGE 之間。桌寵被觸發使用容器,或使用者雙擊容器打開查看時,家具播第三個動作動畫
## (interacted_0,見 FurnitureItem.play_interacted());實際「目前還剩幾個」是每一件放上桌面的實例各自的即時狀態
## (見 FurnitureItem.container_remaining),不是存在這份定義裡(定義只有補滿用的上限)。
const MAX_CONTAINER_ITEMS := 8
const CONTAINER_CAPACITY_RANGE := Vector2(1, 99)
## 效果(第六批,2026-10-04,使用者回饋):家具「條件成立」(conditional,即 FurnitureItem.active())期間,
## 對行動區裡所有桌寵套用的持續效果,例如小夜燈讓低精力的桌寵更容易入睡。做法是「覆蓋成指定值,效果消失
## 時還原回原來的值」(不是每秒累加,累加容易讓目標值無限飄走、也更難保證还原乾淨)。
## 每筆 {target_kind, target_key, scope, value, filter_kind, filter_key, filter_scope, filter_op, filter_value}:
## - target_kind:"value"(使用者自訂的局部/全域數值,ValueGateway)或 "stat"(桌寵內建、性格會調整的參數,
##   只能挑 AURA_STAT_KEYS 裡列的,不開放任意屬性名稱,避免改到不該被外部覆寫的欄位)。
## - target_key:value 模式是數值的 key(使用者自訂字串);stat 模式是 AURA_STAT_KEYS 其中一個。
## - scope:"local"/"global",只有 target_kind="value" 才有意義(跟 ValueGateway.set_value 的 scope_hint 一致)。
## - value:套用期間要覆蓋成的數值。
## - filter_kind:""(不篩選,家具一啟用就對所有桌寵生效)/"value"/"stat"——篩選用哪一種數值判斷「這隻桌寵
##   現在要不要套用」,例如「精力 < 30」才讓小夜燈生效。
## - filter_key/filter_scope:跟 target 同一套規則,挑要比較的那個數值。
## - filter_op:">"/">="/"="/"<="/"<"。
## - filter_value:篩選的門檻值。
## 實際套用/還原由 FurnitureItem 負責(見 FurnitureItem._apply_aura),每 CHECK_INTERVAL 重新算一次「現在
## 哪些桌寵該套用哪些效果」,跟上次的套用狀態做差集:新符合的套用(先記住桌寵原本的值)、不再符合的還原。
## 防呆(使用者 2026-10-04 明確要求的四種情境):① 桌寵被收起來——套用紀錄用 instance_from_id 查,查無效
## 桌寵就直接丟掉紀錄(桌寵都被刪了,沒有「還原」的對象,不算洩漏);② 遊戲關閉再打開——套用紀錄只存在
## FurnitureItem 的記憶體裡,不存檔,重開自然從頭乾淨判定;③ 家具被刪除或編輯模式收起來——FurnitureItem
## 新增 _exit_tree() 離場前把目前套用中的效果全部還原;④ 家具效果設定被改掉(拿掉某筆效果)——
## FurnitureManager.refresh_def → FurnitureItem.apply_def() 先把目前全部套用中的效果還原,再用新的
## aura_effects 重新判定套用,不會留下舊效果的殘留。
const AURA_STAT_KEYS: Array[String] = [
	"vitality.energy", "vitality.mood", "vitality.fatigue_rate", "vitality.rest_recovery_rate",
	"vitality.tired_threshold", "vitality.exhausted_threshold",
	"vitality.mood_happy_threshold", "vitality.mood_angry_threshold", "vitality.mood_sad_threshold",
	"sociability", "game_refuse_base",
]
const AURA_FILTER_OPS: Array[String] = [">", ">=", "=", "<=", "<"]
const AURA_TARGET_KINDS: Array[String] = ["value", "stat"]
const AURA_FILTER_KINDS: Array[String] = ["", "value", "stat"]
const AURA_SCOPES: Array[String] = ["local", "global"]
const MAX_AURA_EFFECTS := 6
const AURA_VALUE_RANGE := Vector2(-999999.0, 999999.0)

var id := ""
var display_name := ""
var thumbnail := ""
## 條件觸發設定,見 FurnitureCondition;type = "always" 時 conditional 狀態沒有意義(一直顯示 normal)。
var condition: Dictionary = FurnitureCondition.clean({})
## 放上桌面時的縮放倍率。
var scale_multiplier := 1.0
## 這個家具是從哪個內建模板做的(只是標記,不影響行為)。
var template := ""
## 可坐/可躺的位置:每筆 {type:"sit"/"lie", x, y, action, facing}(相對家具原點的偏移,未縮放,實際位置會再乘上
## scale_multiplier)。桌寵想用時自己挑一個當下沒人在的錨點過去(見 FurnitureItem.claim_anchor),不會湊人數也
## 不會中途換位置。
## action(行為重綁,選填):素材包作者如果準備了不同於預設 sit/lay 的坐躺姿勢動作(自訂名稱),可以在這裡指定這個
## 錨點改播哪個動作;那隻桌寵的素材包真的有這個動作才會用,沒有就自動退回 type 本身對應的預設動作(見
## FurnitureItem.anchor_action)。type 欄位本身永遠是 claim_anchor/邀請共用等配對邏輯認的「基本類型」,不受這個影響。
## facing(見 ANCHOR_FACINGS,預設 "both"):桌寵坐/躺到這個錨點時要面向哪邊;"both" = 每次使用時隨機擇一方向
## (不是左右來回切換),"left"/"right" = 固定面向。
var anchors: Array[Dictionary] = []
## 光源清單(2026-09-23 從單一 Dictionary 改成清單,可以放好幾盞;2026-09-27 enabled 布林改成 slots 依動作槽分開設定,
## 見 LIGHT_SLOT_NAMES):每筆 {slots, x, y, radius, energy, color, shape, angle, spread}(x/y 跟錨點一樣是相對家具
## 原點的像素偏移,angle/spread 只有 shape="fan" 才用,單位是度:angle = 朝哪個方向(0=右、90=下、180=左、270=上),
## spread = 扇形張角)。最多 MAX_LIGHTS 盞。
var lights: Array[Dictionary] = []
## 這件家具的貼圖是不是蓋在自己的光暈之上(見檔頭)。
var above_light := false
## 這件家具要不要畫在桌寵與對話氣泡之上(2026-09-30 使用者要求:協助使用者自製 UI 用,例如當成一塊
## 「相框」貼在畫面最上層)。預設 false(跟平時一樣,在裝飾層裡、被桌寵/氣泡蓋住);開啟後改由
## DesktopShell 一個更高的 CanvasLayer 畫(見 FurnitureManager._home_parent_for()),編輯模式拖曳、
## 光源、坐躺、容器這些既有功能都不受影響,純粹只是換一個畫面圖層。
var render_above_ui := false
## 家具標籤(見檔頭),TAGS_CATALOG 的子集合。
var tags: Array[String] = []
## 容器內容物(見檔頭):每筆 {id: 道具的 PropDef.id, capacity: 補滿時的數量}。空陣列 = 不是容器。
var container_items: Array[Dictionary] = []
## 效果(見檔頭 AURA_STAT_KEYS 的說明):家具啟用期間對行動區桌寵套用的覆蓋效果。空陣列 = 沒有效果,
## 單純裝飾/光源用的家具不受影響。
var aura_effects: Array[Dictionary] = []


func is_container() -> bool:
	return not container_items.is_empty()


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
	return result if result != "" else "furniture"


static func clean_name(text: String) -> String:
	var result := text.strip_edges().replace("\n", " ").replace("\t", " ")
	if result.length() > MAX_NAME:
		result = result.left(MAX_NAME)
	return result


static func default_light_slot() -> Dictionary:
	return {"mode": "off", "start": 0, "end": 0}


## 逐欄驗證單一動作槽的設定;start/end 夾在 [0, LIGHT_FRAME_MAX],end 補到不小於 start。
static func clean_light_slot(raw: Variant) -> Dictionary:
	var result := default_light_slot()
	if not raw is Dictionary:
		return result
	var mode := str(raw.get("mode", "off"))
	if LIGHT_SLOT_MODES.has(mode):
		result["mode"] = mode
	var start_value: Variant = raw.get("start")
	var end_value: Variant = raw.get("end")
	var start := clampi(int(start_value), 0, LIGHT_FRAME_MAX) if (start_value is int or start_value is float) else 0
	var end := clampi(int(end_value), 0, LIGHT_FRAME_MAX) if (end_value is int or end_value is float) else 0
	result["start"] = start
	result["end"] = maxi(end, start)
	return result


static func default_light() -> Dictionary:
	var slots := {}
	for slot_name: String in LIGHT_SLOT_NAMES:
		slots[slot_name] = default_light_slot()
	return {"slots": slots, "x": 0.0, "y": 0.0, "radius": 90.0, "energy": 0.9, "color": "#ffe4a0", "shape": "radial", "angle": 90.0, "spread": 60.0}


## 逐欄驗證光源設定,壞的欄位用預設、數字夾在範圍內(跟 PropDef.clean_light 同一套邏輯,多了 shape/angle/spread)。
## family_condition:這件家具本身的觸發條件(FurnitureDef.condition),只在相容舊資料(單一 enabled 布林)時用來
## 判斷该還原成哪種畫面才不會變成不同的效果——見下面 elif 分支的說明。
static func clean_light(raw: Variant, family_condition: Dictionary = {}) -> Dictionary:
	var result := default_light()
	if not raw is Dictionary:
		return result
	var slots_raw: Variant = raw.get("slots")
	if slots_raw is Dictionary:
		for slot_name: String in LIGHT_SLOT_NAMES:
			result["slots"][slot_name] = clean_light_slot((slots_raw as Dictionary).get(slot_name))
	elif raw.get("enabled") is bool:
		# 相容舊資料(2026-09-27 之前是單一 enabled 布林,沒有分動作槽):舊規則是「家具條件一直成立(type=always,
		# 也就是一直播 normal_0)就跟著 normal_0 一起亮;條件不是一直成立(有 time_range 之類)就只有條件成立、
		# 播 conditional_0 的時候才亮」,這裡照這個規則轉成對應的動作槽,行為才不會因為這次改資料模型而變掉。
		if bool(raw["enabled"]):
			if str(family_condition.get("type", "always")) == "always":
				for slot_name: String in LIGHT_SLOT_NAMES:
					result["slots"][slot_name] = {"mode": "always", "start": 0, "end": 0}
			else:
				result["slots"]["conditional_0"] = {"mode": "always", "start": 0, "end": 0}
	for key in ["x", "y"]:
		var value: Variant = raw.get(key)
		if (value is float or value is int) and is_finite(float(value)):
			result[key] = clampf(float(value), -ANCHOR_RANGE, ANCHOR_RANGE)
	for key: String in LIGHT_LIMITS:
		var value: Variant = raw.get(key)
		if (value is float or value is int) and is_finite(float(value)):
			var limits: Vector2 = LIGHT_LIMITS[key]
			result[key] = clampf(float(value), limits.x, limits.y)
	var color := str(raw.get("color", ""))
	if color != "" and Color.html_is_valid(color):
		result["color"] = "#" + Color.html(color).to_html(false)
	var shape := str(raw.get("shape", "radial"))
	if LIGHT_SHAPES.has(shape):
		result["shape"] = shape
	ScopedProperty.write_cleaned(result, "radius", ScopedProperty.clean_float_by_frame(raw.get("radius_by_frame"), LIGHT_LIMITS["radius"]))
	ScopedProperty.write_cleaned(result, "energy", ScopedProperty.clean_float_by_frame(raw.get("energy_by_frame"), LIGHT_LIMITS["energy"]))
	ScopedProperty.write_cleaned(result, "color", ScopedProperty.clean_color_by_frame(raw.get("color_by_frame")))
	ScopedProperty.write_cleaned(result, "enabled", ScopedProperty.clean_bool_by_frame(raw.get("enabled_by_frame")))
	return result


## 分幀單獨調整(2026-09-28,見 ScopedProperty):半徑/亮度/顏色比照 PackLights 那套,「這一幀」= slot_name
## (LIGHT_SLOT_NAMES 其中之一)+ frame 組合,沒單獨調整就跟著這盞燈的預設值走(包括預設值之後又被改動的情況)。
## 「是否亮著」不太一樣:家具原本就有 slots[slot].mode(off/always/frames)這套更複雜的判斷,不是單純一個布林,
## 所以 enabled_of() 回傳的是「這一幀有沒有被單獨調整過」的 Variant(null = 沒調整,交給 slot 判斷;true/false =
## 單獨調整過,直接以它為準,可以雙向覆蓋 slot 原本的判斷——這是使用者明確要求的:「即使第一幀關燈了也能藉此
## 打開」,跟 PackLights 的「總開關優先於逐幀覆蓋」不同,因為家具沒有那種簡單的總開關概念)。
static func radius_of(light: Dictionary, slot: String, frame: int) -> float:
	return float(ScopedProperty.effective(light, "radius", light.get("radius", 90.0), slot, frame))


static func energy_of(light: Dictionary, slot: String, frame: int) -> float:
	return float(ScopedProperty.effective(light, "energy", light.get("energy", 0.9), slot, frame))


static func color_of(light: Dictionary, slot: String, frame: int) -> String:
	return str(ScopedProperty.effective(light, "color", light.get("color", "#ffe4a0"), slot, frame))


## 這一幀有沒有單獨調整「是否亮著」:null = 沒有,交給 slot 的 mode/frames 範圍判斷;true/false = 單獨調整過,
## 不管 slot 怎麼判斷都以這個為準。
static func enabled_override(light: Dictionary, slot: String, frame: int) -> Variant:
	return ScopedProperty.effective(light, "enabled", null, slot, frame)


static func set_radius(light: Dictionary, scope: int, slot: String, frame: int, frame_count: int, value: float) -> void:
	ScopedProperty.set_value(light, "radius", "radius", scope, slot, frame, frame_count, clampf(value, LIGHT_LIMITS["radius"].x, LIGHT_LIMITS["radius"].y))


static func set_energy(light: Dictionary, scope: int, slot: String, frame: int, frame_count: int, value: float) -> void:
	ScopedProperty.set_value(light, "energy", "energy", scope, slot, frame, frame_count, clampf(value, LIGHT_LIMITS["energy"].x, LIGHT_LIMITS["energy"].y))


static func set_color(light: Dictionary, scope: int, slot: String, frame: int, frame_count: int, value: String) -> void:
	ScopedProperty.set_value(light, "color", "color", scope, slot, frame, frame_count, value if Color.html_is_valid(value) and value.begins_with("#") else "#ffe4a0")


static func set_enabled_override(light: Dictionary, scope: int, slot: String, frame: int, frame_count: int, value: bool) -> void:
	ScopedProperty.set_value(light, "enabled", "enabled", scope, slot, frame, frame_count, value)


static func radius_source_of(light: Dictionary, slot: String, frame: int) -> int:
	return ScopedProperty.source_of(light, "radius", slot, frame)


static func energy_source_of(light: Dictionary, slot: String, frame: int) -> int:
	return ScopedProperty.source_of(light, "energy", slot, frame)


static func color_source_of(light: Dictionary, slot: String, frame: int) -> int:
	return ScopedProperty.source_of(light, "color", slot, frame)


static func enabled_source_of(light: Dictionary, slot: String, frame: int) -> int:
	return ScopedProperty.source_of(light, "enabled", slot, frame)


static func clear_radius_scope(light: Dictionary, scope: int, slot: String, frame: int) -> void:
	ScopedProperty.clear_scope(light, "radius", "radius", scope, slot, frame)


static func clear_energy_scope(light: Dictionary, scope: int, slot: String, frame: int) -> void:
	ScopedProperty.clear_scope(light, "energy", "energy", scope, slot, frame)


static func clear_color_scope(light: Dictionary, scope: int, slot: String, frame: int) -> void:
	ScopedProperty.clear_scope(light, "color", "color", scope, slot, frame)


static func clear_enabled_scope(light: Dictionary, scope: int, slot: String, frame: int) -> void:
	ScopedProperty.clear_scope(light, "enabled", "enabled", scope, slot, frame)


## 逐筆驗證光源清單,壞的整筆用 clean_light 補成合法值(不丟棄,理由跟單筆一致:避免存進中間值),最多 MAX_LIGHTS 筆。
## 相容舊資料(2026-09-23 之前只有單一 light 字典):傳進來是 Dictionary 就當成僅有一筆,且只有原本 enabled=true
## 才搬過來(避免每件從沒設定過光源的家具都平白多出一筆停用的預設光,只留真的有在用的)。
static func clean_lights(raw: Variant, family_condition: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw is Dictionary:
		if bool((raw as Dictionary).get("enabled", false)):
			result.append(clean_light(raw, family_condition))
		return result
	if not raw is Array:
		return result
	for entry: Variant in (raw as Array):
		if result.size() >= MAX_LIGHTS:
			break
		result.append(clean_light(entry, family_condition))
	return result


func has_light() -> bool:
	for entry: Dictionary in lights:
		var slots: Dictionary = entry.get("slots", {})
		for slot_name: String in LIGHT_SLOT_NAMES:
			if str((slots.get(slot_name, {}) as Dictionary).get("mode", "off")) != "off":
				return true
	return false


func to_dict() -> Dictionary:
	return {
		"name": display_name, "thumbnail": thumbnail, "condition": condition.duplicate(true),
		"scale": scale_multiplier, "template": template, "anchors": anchors.duplicate(true),
		"lights": lights.duplicate(true), "above_light": above_light, "tags": tags.duplicate(),
		"containerItems": container_items.duplicate(true), "render_above_ui": render_above_ui,
		"auraEffects": aura_effects.duplicate(true),
	}


## 驗證容器內容物清單:每筆要有非空的道具 id、capacity 夾在 CONTAINER_CAPACITY_RANGE;壞的整筆略過(理由同錨點,
## 不修正、直接丟掉,避免存進奇怪的中間值);同一個道具 id 只留第一筆(不能重複設定同一種),最多 MAX_CONTAINER_ITEMS 筆。
static func clean_container_items(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array:
		return result
	var seen: Dictionary = {}
	for entry: Variant in (raw as Array):
		if result.size() >= MAX_CONTAINER_ITEMS:
			break
		if not entry is Dictionary:
			continue
		var id := str((entry as Dictionary).get("id", "")).strip_edges()
		if id == "" or seen.has(id):
			continue
		var capacity_value: Variant = (entry as Dictionary).get("capacity", 1)
		if not (capacity_value is int or capacity_value is float):
			continue
		seen[id] = true
		result.append({"id": id, "capacity": clampi(int(capacity_value), int(CONTAINER_CAPACITY_RANGE.x), int(CONTAINER_CAPACITY_RANGE.y))})
	return result


## 驗證單一效果篩選條件(filter_kind/key/scope/op/value);filter_kind 不合法或 key 空白一律視為不篩選
## ("" / 保留欄位但不生效),不丟整筆效果(效果本身可能還是有效,只是沒有篩選條件,等同一啟用就對所有
## 桌寵生效)。
static func _clean_aura_filter(raw: Dictionary) -> Dictionary:
	var kind := str(raw.get("filter_kind", ""))
	if not AURA_FILTER_KINDS.has(kind):
		kind = ""
	var key := str(raw.get("filter_key", "")).strip_edges().left(MAX_NAME)
	if key == "" or (kind == "stat" and not AURA_STAT_KEYS.has(key)):
		kind = ""
		key = ""
	var scope := str(raw.get("filter_scope", "local"))
	if not AURA_SCOPES.has(scope):
		scope = "local"
	var op := str(raw.get("filter_op", "<"))
	if not AURA_FILTER_OPS.has(op):
		op = "<"
	var value_raw: Variant = raw.get("filter_value", 0.0)
	var value := clampf(float(value_raw), AURA_VALUE_RANGE.x, AURA_VALUE_RANGE.y) if (value_raw is float or value_raw is int) else 0.0
	return {"filter_kind": kind, "filter_key": key, "filter_scope": scope, "filter_op": op, "filter_value": value}


## 驗證效果清單(見檔頭 AURA_STAT_KEYS 說明):壞的整筆丟掉(target_kind 不合法、target_key 空白,或
## stat 模式選了不在允許清單裡的 key),最多 MAX_AURA_EFFECTS 筆。
static func clean_aura_effects(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array:
		return result
	for entry: Variant in (raw as Array):
		if result.size() >= MAX_AURA_EFFECTS or not entry is Dictionary:
			continue
		var target_kind := str((entry as Dictionary).get("target_kind", "value"))
		if not AURA_TARGET_KINDS.has(target_kind):
			continue
		var target_key := str((entry as Dictionary).get("target_key", "")).strip_edges().left(MAX_NAME)
		if target_key == "" or (target_kind == "stat" and not AURA_STAT_KEYS.has(target_key)):
			continue
		var scope := str((entry as Dictionary).get("scope", "local"))
		if not AURA_SCOPES.has(scope):
			scope = "local"
		var value_raw: Variant = (entry as Dictionary).get("value", 0.0)
		if not (value_raw is float or value_raw is int):
			continue
		var cleaned := {
			"target_kind": target_kind, "target_key": target_key, "scope": scope,
			"value": clampf(float(value_raw), AURA_VALUE_RANGE.x, AURA_VALUE_RANGE.y),
		}
		cleaned.merge(_clean_aura_filter(entry as Dictionary))
		result.append(cleaned)
	return result


## 讀「stat」模式 key(AURA_STAT_KEYS 其中一個,"vitality.xxx" 或桌寵本體屬性)目前的值;物件不存在或不是
## 數字回 0.0。
static func read_stat(pet: Node, key: String) -> float:
	var target: Object = pet
	var prop := key
	if key.begins_with("vitality."):
		if pet.vitality == null:
			return 0.0
		target = pet.vitality
		prop = key.substr(9)
	var value: Variant = target.get(prop)
	return float(value) if (value is float or value is int) else 0.0


static func write_stat(pet: Node, key: String, value: float) -> void:
	var target: Object = pet
	var prop := key
	if key.begins_with("vitality."):
		if pet.vitality == null:
			return
		target = pet.vitality
		prop = key.substr(9)
	target.set(prop, value)


## 效果的 target 或 filter 共用:kind = "value"(ValueGateway)/"stat"(read_stat/write_stat)。
static func read_effect_value(pet: Node, kind: String, key: String, scope: String) -> float:
	if kind == "stat":
		return read_stat(pet, key)
	return ValueGateway.get_value(pet, key, scope)


static func write_effect_value(pet: Node, kind: String, key: String, scope: String, value: float) -> void:
	if kind == "stat":
		write_stat(pet, key, value)
	else:
		ValueGateway.set_value(pet, key, value, scope)


## 這隻桌寵現在符不符合這筆效果的篩選條件;filter_kind 空白(沒設篩選)一律符合。
static func aura_filter_passes(pet: Node, effect: Dictionary) -> bool:
	var kind := str(effect.get("filter_kind", ""))
	if kind == "":
		return true
	var current := read_effect_value(pet, kind, str(effect.get("filter_key", "")), str(effect.get("filter_scope", "local")))
	var threshold := float(effect.get("filter_value", 0.0))
	match str(effect.get("filter_op", "<")):
		">":
			return current > threshold
		">=":
			return current >= threshold
		"=":
			return is_equal_approx(current, threshold)
		"<=":
			return current <= threshold
		_:
			return current < threshold


## 驗證標籤清單:只留在 TAGS_CATALOG 裡的、去重、最多 MAX_TAGS 個。
static func clean_tags(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw is Array:
		return result
	for entry: Variant in (raw as Array):
		var tag := str(entry)
		if TAGS_CATALOG.has(tag) and not result.has(tag) and result.size() < MAX_TAGS:
			result.append(tag)
	return result


## 從字典還原(逐欄驗證);folder_id 是資料夾名稱。名稱空白回傳 null。
static func from_dict(data: Variant, folder_id: String) -> FurnitureDef:
	if not data is Dictionary:
		return null
	var def := FurnitureDef.new()
	def.id = folder_id
	def.display_name = clean_name(str(data.get("name", folder_id)))
	if def.display_name == "":
		return null
	def.thumbnail = _file_name(data.get("thumbnail", ""))
	def.condition = FurnitureCondition.clean(data.get("condition"))
	var scale_value: Variant = data.get("scale", 1.0)
	def.scale_multiplier = clampf(float(scale_value), SCALE_RANGE.x, SCALE_RANGE.y) if (scale_value is float or scale_value is int) else 1.0
	def.template = clean_name(str(data.get("template", "")))
	def.anchors = _clean_anchors(data.get("anchors"))
	# "lights"(新格式)優先;沒有就退回舊格式的單一 "light" 字典(clean_lights 會處理相容轉換)。
	def.lights = clean_lights(data.get("lights", data.get("light")), def.condition)
	def.above_light = bool(data.get("above_light", false)) if data.get("above_light", false) is bool else false
	def.render_above_ui = bool(data.get("render_above_ui", false)) if data.get("render_above_ui", false) is bool else false
	def.tags = clean_tags(data.get("tags"))
	def.container_items = clean_container_items(data.get("containerItems"))
	def.aura_effects = clean_aura_effects(data.get("auraEffects"))
	return def


## 驗證錨點清單:每筆要有合法的 type(sit/lie)與數字座標,壞的整筆略過(不是修正,直接丟掉,避免存進奇怪的中間值)。
static func _clean_anchors(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array:
		return result
	for entry: Variant in (raw as Array):
		if not entry is Dictionary:
			continue
		var kind := str((entry as Dictionary).get("type", ""))
		if not ANCHOR_TYPES.has(kind):
			continue
		var x: Variant = (entry as Dictionary).get("x", 0.0)
		var y: Variant = (entry as Dictionary).get("y", 0.0)
		if not ((x is float or x is int) and (y is float or y is int)):
			continue
		var action := str((entry as Dictionary).get("action", "")).strip_edges().left(MAX_NAME)
		var facing := str((entry as Dictionary).get("facing", "both"))
		if not ANCHOR_FACINGS.has(facing):
			facing = "both"
		result.append({"type": kind, "x": clampf(float(x), -ANCHOR_RANGE, ANCHOR_RANGE), "y": clampf(float(y), -ANCHOR_RANGE, ANCHOR_RANGE), "action": action, "facing": facing})
	return result


static func _file_name(value: Variant) -> String:
	var text := str(value).strip_edges()
	if text == "" or text != text.get_file() or text.begins_with("."):
		return ""
	return text
