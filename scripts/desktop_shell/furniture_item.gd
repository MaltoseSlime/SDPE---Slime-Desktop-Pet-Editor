class_name FurnitureItem
extends Node2D
## 桌面上一件已經放好的家具(純裝飾:一開始畫在主視窗裡,裝飾層準備好之後會搬過去變成滑鼠完全穿透,見 FurnitureManager / DecorOverlay)。
## 定期依 FurnitureCondition 檢查要不要切到「條件成立」的樣子(normal ↔ conditional)。
## interacted 這個動畫狀態的素材已經能準備,但目前播放邏輯還沒接上(桌寵使用家具時播的是自己身上的 sit/lie 動作,不是家具的 interacted)。
## 錨點(可坐/可躺的位置,見 FurnitureDef.anchors):桌寵想用時呼叫 claim_anchor() 佔一個,見 Pet.use_furniture()。
## 光源(見 FurnitureDef.lights/FurnitureLight,一件家具可以有好幾盞):z_index 依 def.above_light 決定貼圖疊在光暈上面還是下面。
## 手動開關(積木「觸發家具」,見 try_toggle):蓋掉 FurnitureCondition 的自動判斷,直到再被觸發一次;
## 有冷卻時間防止好幾隻桌寵同時偵測到同一件家具、結果一起瘋狂開關。

const CHECK_INTERVAL := 1.0
## 光暈的 z_index;above_light 開了就把貼圖疊到比這個更高。
const LIGHT_Z := 1
## 「觸發家具」積木的冷卻秒數(同一件家具,不分是哪隻桌寵觸發的)。
const TOGGLE_COOLDOWN := 4.0
## 播 interacted_0(容器被使用/被打開查看)的秒數,沒有這個動畫槽就什麼都不做,直接退回 evaluate() 的自動判斷。
const INTERACTED_SECONDS := 1.2

var def: FurnitureDef
var _sprite: AnimatedSprite2D
var _light: FurnitureLight
var _check_left := 0.0
## 測試用:>= 0 時用這個當「現在是一天的第幾分鐘」(見 FurnitureCondition 的 time_range)。
var override_minute := -1
## 錨點索引 → 佔用的桌寵節點;claim_anchor/release_anchor 維護,失效的桌寵(被移除、queue_free)會自動清掉。
var _anchor_holders: Dictionary = {}
## null = 沒有手動覆蓋,交給 FurnitureCondition 自動判斷;true/false = 手動強制開/關,蓋掉自動判斷(見 try_toggle)。
var manual_state: Variant = null
var _toggle_cooldown_left := 0.0
## 容器(見 FurnitureDef.container_items):道具 id → 目前還剩幾個。放上桌面時從 def 的補滿上限初始化;之後只有
## 補滿(container_refill)或被拿走(container_take)會改,不會因為 def 重新載入(apply_def)就被重置,不然使用者剛
## 補滿或桌寵剛拿走的東西會無緣無故恢復/消失。
var container_remaining: Dictionary = {}
var _interacted_left := 0.0
## 效果套用紀錄(見 FurnitureDef.aura_effects 檔頭的防呆說明):鍵是 "<桌寵 instance id>:<效果索引>",
## 值是套用前的原始數值(還原用)。只存在記憶體裡,不存檔——重開程式/場景自然從頭乾淨判定,見防呆②。
var _aura_state: Dictionary = {}


func setup(new_def: FurnitureDef, frames: SpriteFrames) -> void:
	def = new_def
	scale = Vector2.ONE * def.scale_multiplier
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.centered = false
	_sprite.z_index = LIGHT_Z + 1 if def.above_light else 0
	add_child(_sprite)
	_light = FurnitureLight.new()
	_light.z_index = LIGHT_Z
	add_child(_light)
	_light.setup(self)
	_sync_container_items()
	add_to_group("furniture")
	evaluate()


## 讓容器的道具清單跟上目前的 def:新加的道具種類補滿、被移除的道具種類清掉,已經在追蹤的種類保留目前數量不動
## (不管是使用者手動改過家具設定,還是 apply_def() 重新套用同一份定義,現有庫存都不該被平白重置/清空)。
func _sync_container_items() -> void:
	if def == null:
		return
	var wanted: Dictionary = {}
	for entry: Dictionary in def.container_items:
		wanted[str(entry["id"])] = int(entry["capacity"])
	for id: String in wanted.keys():
		if not container_remaining.has(id):
			container_remaining[id] = wanted[id]
	for id: String in container_remaining.keys().duplicate():
		if not wanted.has(id):
			container_remaining.erase(id)


## 精靈圖編輯器改了這件家具的定義並存檔後呼叫(見 FurnitureManager.refresh_def):場上已經放置的實例手上抓的是
## 另一份獨立讀出來的舊 FurnitureDef,存檔不會自動同步過去(光源座標/大小/顏色、坐躺錨點都吃這份舊資料一直不會變),
## 這裡換掉整份定義;above_light 疊層順序只在 setup() 算一次,要另外重算,其餘欄位 _light/_sprite 每次都即時讀 def,不用另外處理。
func apply_def(new_def: FurnitureDef) -> void:
	# 防呆④(效果設定被改掉,見 FurnitureDef.aura_effects 檔頭):換定義前先把目前套用中的效果全部還原,
	# 不然換成新定義之後,_aura_state 裡記的效果索引會對不上新的 aura_effects,還原會還錯甚至還原失敗。
	_restore_all_aura()
	def = new_def
	if _sprite != null:
		_sprite.z_index = LIGHT_Z + 1 if def.above_light else 0
	if _light != null:
		_light.queue_redraw()
	_sync_container_items()
	evaluate()


func _process(delta: float) -> void:
	_toggle_cooldown_left = maxf(_toggle_cooldown_left - delta, 0.0)
	if _interacted_left > 0.0:
		_interacted_left = maxf(_interacted_left - delta, 0.0)
		_play(&"interacted_0")
		if _interacted_left > 0.0:
			return
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_INTERVAL
		evaluate()


## 現在是不是「條件成立」的狀態(給 UI/測試看目前播哪一段)。
func active() -> bool:
	return _sprite != null and str(_sprite.animation) == "conditional_0"


## 目前播的動作槽名稱(normal_0/conditional_0/interacted_0),給光源分槽判定用(見 FurnitureLight._lit)。
func current_animation() -> String:
	return str(_sprite.animation) if _sprite != null else "normal_0"


## 目前播到第幾幀,給光源「在指定幀範圍啟用」判定用。
func current_frame() -> int:
	return _sprite.frame if _sprite != null else 0


## 家具編輯模式用的點擊/拖曳判定範圍(全域座標,左上角對齊,見 setup() 的 centered=false)。
## 抓不到目前這幀的貼圖大小就退回一個夠抓的預設方塊(空 SpriteFrames 之類的極端情形)。
func touch_rect() -> Rect2:
	var size := Vector2(48.0, 48.0)
	if _sprite != null and _sprite.sprite_frames != null and str(_sprite.animation) != "":
		var texture := _sprite.sprite_frames.get_frame_texture(_sprite.animation, 0)
		if texture != null:
			size = texture.get_size()
	return Rect2(global_position, size * scale)


## 重新檢查條件、切換播放的狀態;獨立成函式方便測試立刻檢查,不用等 CHECK_INTERVAL。
func evaluate() -> void:
	if def == null or _sprite == null or _sprite.sprite_frames == null:
		return
	var has_conditional := _sprite.sprite_frames.has_animation(&"conditional_0")
	var wants_conditional: bool
	if manual_state is bool:
		wants_conditional = bool(manual_state) and has_conditional
	else:
		var actions: Array = []
		for pet: Node in get_tree().get_nodes_in_group("pets"):
			if is_instance_valid(pet) and pet.has_method("current_activity"):
				actions.append(str(pet.current_activity()))
		var minute := override_minute if override_minute >= 0 else AppSettings.minute_of_day_now()
		# in_use/full(2026-10-04):這件家具自己當下的佔用狀況,先清掉失效的持有者(桌寵被移除卻沒釋放
		# 錨點的情形)才查,不然會把已經不在場的桌寵也算進「有人在用」。
		_prune_anchor_holders()
		var in_use := not _anchor_holders.is_empty()
		var is_full := def.anchors.size() > 0 and _anchor_holders.size() >= def.anchors.size()
		wants_conditional = FurnitureCondition.evaluate(def.condition, minute, actions, in_use, is_full) and has_conditional
	_play(&"conditional_0" if wants_conditional else &"normal_0")
	_apply_aura(wants_conditional)


## 效果(見 FurnitureDef.aura_effects):is_active = 家具現在是不是「條件成立」的狀態。每次重新掃一遍場上
## 所有桌寵跟這件家具的每一筆效果,跟上次的套用紀錄(_aura_state)做差集──新符合的套用(先記住原始值),
## 不再符合的還原(桌寵離開篩選範圍、或家具本身不再啟用)。防呆①(桌寵被收起來):無效的桌寵直接丟掉紀錄,
## 不嘗試還原(桌寵都不在了,没有「還原」的對象,不算洩漏)。
func _apply_aura(is_active: bool) -> void:
	if def == null:
		return
	if not is_active or def.aura_effects.is_empty():
		_restore_all_aura()
		return
	for state_key: String in _aura_state.keys().duplicate():
		var pid := int(str(state_key).split(":")[0])
		var holder: Object = instance_from_id(pid)
		if holder == null or not (holder is Node) or not is_instance_valid(holder):
			_aura_state.erase(state_key)
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		if not is_instance_valid(pet):
			continue
		for i in def.aura_effects.size():
			var effect: Dictionary = def.aura_effects[i]
			var state_key := "%d:%d" % [pet.get_instance_id(), i]
			var should_apply := FurnitureDef.aura_filter_passes(pet, effect)
			var target_kind := str(effect.get("target_kind", "value"))
			var target_key := str(effect.get("target_key", ""))
			var scope := str(effect.get("scope", "local"))
			if should_apply and not _aura_state.has(state_key):
				_aura_state[state_key] = FurnitureDef.read_effect_value(pet, target_kind, target_key, scope)
				FurnitureDef.write_effect_value(pet, target_kind, target_key, scope, float(effect.get("value", 0.0)))
			elif not should_apply and _aura_state.has(state_key):
				FurnitureDef.write_effect_value(pet, target_kind, target_key, scope, float(_aura_state[state_key]))
				_aura_state.erase(state_key)


## 把目前所有套用中的效果還原成原始值,清空套用紀錄。防呆③(家具被刪除/編輯模式收起來)靠 _exit_tree()
## 呼叫這個;防呆④(效果設定被改掉)靠 apply_def() 呼叫這個。
func _restore_all_aura() -> void:
	if _aura_state.is_empty():
		return
	for state_key: String in _aura_state.keys().duplicate():
		var parts := str(state_key).split(":")
		var pid := int(parts[0])
		var effect_index := int(parts[1])
		var holder: Object = instance_from_id(pid)
		# is_instance_valid() 要先檢查:`is` 碰到已釋放的 Object 會直接噴執行期錯誤,不是安全失敗
		# (跟 manager_ui.gd 的事件管理視窗同一個坑,見那邊的詳細說明)。instance_from_id() 找到的物件
		# 隨時可能已經被釋放(例如桌寵/家具在套用殘留效果前就被移除)。
		if is_instance_valid(holder) and holder is Node and def != null and effect_index >= 0 and effect_index < def.aura_effects.size():
			var effect: Dictionary = def.aura_effects[effect_index]
			FurnitureDef.write_effect_value(holder as Node, str(effect.get("target_kind", "value")), str(effect.get("target_key", "")), str(effect.get("scope", "local")), float(_aura_state[state_key]))
	_aura_state.clear()


## 防呆③:家具被刪除(FurnitureManager.remove() → queue_free())或編輯模式收起來都會經過這裡,
## 離場前把目前套用中的效果全部還原,不會留著桌寵被覆蓋的數值回不去。
func _exit_tree() -> void:
	_restore_all_aura()


## 積木「觸發家具(開/關/與現況相反)」用:mode = "on"/"off"/"toggle"。冷卻中(見 TOGGLE_COOLDOWN)回傳 false、什麼都不做,
## 避免好幾隻桌寵同一時間偵測到同一件家具、結果一起瘋狂開關。
func try_toggle(mode: String) -> bool:
	if _toggle_cooldown_left > 0.0:
		return false
	match mode:
		"on":
			manual_state = true
		"off":
			manual_state = false
		_:
			manual_state = not active()
	_toggle_cooldown_left = TOGGLE_COOLDOWN
	evaluate()
	return true


# --- 容器(見 FurnitureDef.container_items):存放道具、桌寵觸發使用或使用者打開查看時播 interacted_0 ---

func is_container() -> bool:
	return def != null and def.is_container()


## 這種道具補滿的上限(定義裡設的);沒有這種道具回 0。
func container_capacity(prop_id: String) -> int:
	for entry: Dictionary in (def.container_items if def != null else []):
		if str(entry["id"]) == prop_id:
			return int(entry["capacity"])
	return 0


## 目前還剩幾個;不是容器內容物之一就是 0。
func container_remaining_of(prop_id: String) -> int:
	return int(container_remaining.get(prop_id, 0))


## 容器裡任何一種道具還有庫存。
func container_has_stock() -> bool:
	for count: int in container_remaining.values():
		if count > 0:
			return true
	return false


## 拿走一個(桌寵觸發使用時呼叫):庫存 >0 才成功、扣一個並回傳 true;沒庫存或不是這種道具回 false。
func container_take(prop_id: String) -> bool:
	if int(container_remaining.get(prop_id, 0)) <= 0:
		return false
	container_remaining[prop_id] = int(container_remaining[prop_id]) - 1
	return true


## 補滿全部(查看視窗的「補充」按鈕)。
func container_refill() -> void:
	for entry: Dictionary in (def.container_items if def != null else []):
		container_remaining[str(entry["id"])] = int(entry["capacity"])


## 播 interacted_0(容器被拿東西,或使用者雙擊打開查看):播完自動退回 evaluate() 的自動判斷,沒有這個動畫槽就
## 什麼都看不出來(素材沒準備,不強求)。
func play_interacted() -> void:
	_interacted_left = INTERACTED_SECONDS


func _play(animation: StringName) -> void:
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(animation):
		return
	if _sprite.animation != animation:
		_sprite.animation = animation
	if not _sprite.is_playing():
		_sprite.play()


# --- 錨點(可坐/可躺):不湊人數,桌寵各自挑一個當下沒人用的過去;中途有人離席不會讓已經在用的換位置 ---

## 找一個 wanted_type("sit"/"lie")類型、目前沒人用的錨點佔起來,回傳錨點索引;都滿了(或這個家具根本沒這個類型)回 -1。
## 2026-10-06:挑空位時優先選「離其他桌寵最遠」的那個(不是第一個空的),讓大家盡量分開坐/躺;
## 沒有任何空位回傳 -1(坐滿,呼叫端照原本的規則處理)。
func claim_anchor(pet: Node, wanted_type: String) -> int:
	_prune_anchor_holders()
	if def == null:
		return -1
	var best := -1
	var best_gap := -1.0
	for i in def.anchors.size():
		if str((def.anchors[i] as Dictionary).get("type")) != wanted_type:
			continue
		if _anchor_holders.has(i):
			continue
		var gap := _nearest_pet_distance(i, pet)
		if gap > best_gap:
			best_gap = gap
			best = i
	if best >= 0:
		_anchor_holders[best] = pet
	return best


## 目前也在用這件家具的其他桌寵(不含 pet 自己,已經不在場或已釋放的略過)。給好感度「一起使用家具」判定用。
func other_holders(pet: Node) -> Array:
	_prune_anchor_holders()
	var result: Array = []
	for holder: Node in _anchor_holders.values():
		if holder != pet and is_instance_valid(holder) and not result.has(holder):
			result.append(holder)
	return result


## 錨點到其他桌寵(不含自己)的最近距離;沒有其他桌寵時回傳很大的數,代表「很空」。
func _nearest_pet_distance(anchor: int, pet: Node) -> float:
	var spot := anchor_global_position(anchor)
	var nearest := 1.0e9
	for other: Node in pet.get_tree().get_nodes_in_group("pets"):
		if other == pet or not is_instance_valid(other):
			continue
		nearest = minf(nearest, spot.distance_to(other.global_position))
	return nearest


## 這隻桌寵目前佔用的錨點都讓出來(正常一次只會佔一個,保險起見清全部)。
func release_anchor(pet: Node) -> void:
	for key: int in _anchor_holders.keys().duplicate():
		if _anchor_holders[key] == pet:
			_anchor_holders.erase(key)


## 找目前沒人用、離 point 最近的錨點,回傳它的類型("sit"/"lay");沒有任何空位回傳 ""。
## 給「把桌寵拖到家具上放開就自動使用」判定用(拖曳結束時只知道放開的座標,不知道使用者想選哪個錨點,用最近的猜)。
func nearest_free_anchor_type(point: Vector2) -> String:
	_prune_anchor_holders()
	if def == null:
		return ""
	var best_type := ""
	var best_dist := INF
	for i in def.anchors.size():
		if _anchor_holders.has(i):
			continue
		var dist := anchor_global_position(i).distance_to(point)
		if dist < best_dist:
			best_dist = dist
			best_type = str((def.anchors[i] as Dictionary).get("type", "sit"))
	return best_type


func anchor_holder(index: int) -> Node:
	var holder: Variant = _anchor_holders.get(index)
	return holder if holder is Node else null


## 反查:這隻桌寵佔用的是哪個錨點索引(沒佔用回 -1)。給「邀請加入使用家具」積木查對方要用哪種類型(sit/lay)。
func anchor_index_of(pet: Node) -> int:
	for key: int in _anchor_holders:
		if _anchor_holders[key] == pet:
			return key
	return -1


func _prune_anchor_holders() -> void:
	for key: int in _anchor_holders.keys().duplicate():
		var holder: Variant = _anchor_holders[key]
		if not (holder is Node) or not is_instance_valid(holder):
			_anchor_holders.erase(key)


## 精靈圖編輯器的畫布是相對「軸心」(SpritePackLoader 烘進 SpriteFrames 的腳底/中心點,通常是圖片底邊中心)算光源、
## 坐/躺錨點的座標;但這個節點的貼圖是 centered=false、以「畫布(cell)左上角」當節點原點畫的(方便家具在桌面上的
## 點擊判定/拖曳範圍維持成一個從 global_position 起算的矩形,不用另外處理軸心)。這兩套原點不是同一個點,相差就是
## 軸心在 cell 裡的位置——水平置中、距頂 cell.y − ground_below(跟 Pet.set_sprite_frames 用的是同一份烘焙資料,
## ground_below 是幫名字標籤/影子留的裁切空間,家具通常是 0)。存在 def.anchors/def.lights 裡的座標是「軸心相對」,
## 要先加上這個偏移才是「節點原點相對」,不然錨點/光源在遊戲裡看起來會跟精靈圖編輯器預覽的位置對不起來
## (2026-09-23 修正:之前完全沒補這個偏移,家具貼圖越大、軸心離 cell 左上角越遠,跑掉得越明顯)。
func pivot_offset() -> Vector2:
	if _sprite == null or _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(&"normal_0"):
		return Vector2.ZERO
	var texture := _sprite.sprite_frames.get_frame_texture(&"normal_0", 0)
	if texture == null:
		return Vector2.ZERO
	var cell := Vector2(texture.get_size())
	var ground_below := float(_sprite.sprite_frames.get_meta("ground_below", 0.0))
	return Vector2(cell.x * 0.5, cell.y - ground_below)


## 這個錨點的全域座標(家具原點 + 軸心偏移 + 錨點本身的偏移,偏移跟著家具的縮放倍率走)。索引不合法就退回家具本身的位置。
func anchor_global_position(index: int) -> Vector2:
	if def == null or index < 0 or index >= def.anchors.size():
		return global_position
	var anchor: Dictionary = def.anchors[index]
	return global_position + (pivot_offset() + Vector2(float(anchor.get("x", 0.0)), float(anchor.get("y", 0.0)))) * scale


## 這個錨點的基本類型("sit"/"lay"):給 claim_anchor/邀請加入使用等「配對」邏輯用,永遠是這個原始值,
## 不受下面 anchor_action() 的行為重綁覆蓋影響(覆蓋只改「播哪個動畫」,不改「這個錨點算哪一種」)。
func anchor_type(index: int) -> String:
	if def == null or index < 0 or index >= def.anchors.size():
		return "sit"
	return str((def.anchors[index] as Dictionary).get("type", "sit"))


## 這個錨點設定的面向("both"/"left"/"right",見 FurnitureDef.ANCHOR_FACINGS)。
func anchor_facing(index: int) -> String:
	if def == null or index < 0 or index >= def.anchors.size():
		return "both"
	return str((def.anchors[index] as Dictionary).get("facing", "both"))


## 這個錨點實際要播的桌寵動作(行為重綁,見 FurnitureDef.anchors 的 action 欄位):這個錨點設定了覆蓋動作、
## 而且傳進來的 pet 的素材包真的有那個動作時,優先播覆蓋動作;否則播 anchor_type() 本身("sit"/"lay" 對應
## 桌寵自己素材包裡同名的系統動作,不是家具的動畫)。不傳 pet(或用不到 action_names())就不檢查存在性、
## 直接退回類型本身——Pet._start_animation 本身也有素材缺失時的降級邏輯,不會因為這裡沒檢查就播失敗。
func anchor_action(index: int, pet: Node = null) -> StringName:
	if def == null or index < 0 or index >= def.anchors.size():
		return &"idle"
	var override_name := str((def.anchors[index] as Dictionary).get("action", "")).strip_edges()
	if override_name != "" and pet != null and pet.has_method("action_names") and (pet.action_names() as Array).has(override_name):
		return StringName(override_name)
	return StringName(anchor_type(index))
