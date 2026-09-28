class_name FurnitureLight
extends Node2D
## 家具的光源(和道具的 PropLight 同一套畫法,程式畫、沒有陰影),多一種形狀:扇形(手電筒/聚光燈那種有方向、有張角的光)。
## 一件家具可以有好幾盞燈(FurnitureDef.lights,2026-09-23 從單一 Dictionary 改成清單),這個節點統一負責畫全部。
## 「一直啟用」以外的觸發方式(見 FurnitureCondition):每盞燈各自的 enabled 開著、且條件成立(item.active(),
## 即 conditional 狀態)才會亮,呼應「檯燈只在晚上亮」這種用法;「一直啟用」的家具只看每盞燈自己的 enabled。
## 全局設定的光源總開關關掉就整組不畫。
## z_index 依 FurnitureDef.above_light 決定疊在貼圖上面還是下面(見 FurnitureItem.setup),這是整件家具共用一個,
## 不是每盞燈分開設定(家具的貼圖只有一張,沒辦法讓某幾盞燈疊上面、某幾盞疊下面)。

const PULSE_SPEED := 1.1
const PULSE_AMOUNT := 0.07
const REDRAW_INTERVAL := 1.0 / 20.0
const FAN_SEGMENTS := 24

var _item: FurnitureItem
var _enabled := true
var _time := 0.0
var _redraw_left := 0.0


func setup(item: FurnitureItem) -> void:
	_item = item
	add_to_group("Cutout")
	add_to_group("pet_lights")   # 全局設定總開關改了要能立刻更新,沿用既有的群組廣播(見 AppSettings 呼叫端)。
	refresh_setting()


func refresh_setting() -> void:
	_enabled = AppSettings.lights_enabled()
	queue_redraw()


## 這盞燈現在是不是真的在發光:依家具目前播放的動作槽(normal_0/conditional_0/interacted_0)各自查 slots 設定——
## off 不亮、always 這個槽在播就亮、frames 只有目前幀落在 [start, end] 才亮(見 FurnitureDef.LIGHT_SLOT_NAMES)。
## 這一幀如果單獨調整過「是否亮著」(FurnitureDef.enabled_override,精靈圖編輯器的「單獨調整此幀」),
## 直接以那個為準,雙向覆蓋上面 slot 的判斷(可以讓平常暗的幀單獨打開,也可以讓平常亮的幀單獨關掉)。
func _lit(light: Dictionary) -> bool:
	if not _enabled or _item == null or _item.def == null:
		return false
	var slot_name := _item.current_animation()
	var frame := _item.current_frame()
	var override: Variant = FurnitureDef.enabled_override(light, slot_name, frame)
	if override is bool:
		return override
	var slots: Dictionary = light.get("slots", {})
	var slot: Dictionary = slots.get(slot_name, {})
	match str(slot.get("mode", "off")):
		"always":
			return true
		"frames":
			return frame >= int(slot.get("start", 0)) and frame <= int(slot.get("end", 0))
	return false


## 這件家具有沒有任何一盞燈現在亮著(給 _process 判斷要不要繼續重繪)。
func _any_lit() -> bool:
	if _item == null or _item.def == null:
		return false
	for light: Dictionary in _item.def.lights:
		if _lit(light):
			return true
	return false


## 光源座標是相對軸心存的(跟精靈圖編輯器的畫布預覽一致),要加上 item.pivot_offset() 才是這個節點畫圖用的原點相對座標
## (見 FurnitureItem.pivot_offset 檔頭;2026-09-23 修正:之前沒加這個偏移,光源在遊戲裡的位置會跟編輯器預覽對不起來)。
func anchor(light: Dictionary) -> Vector2:
	var offset := _item.pivot_offset() if _item != null else Vector2.ZERO
	return offset + Vector2(float(light.get("x", 0.0)), float(light.get("y", 0.0)))


func _process(delta: float) -> void:
	if not _any_lit():
		return
	_time += delta
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = REDRAW_INTERVAL
		queue_redraw()


func _draw() -> void:
	if _item == null or _item.def == null:
		return
	var slot_name := _item.current_animation()
	var frame := _item.current_frame()
	for light: Dictionary in _item.def.lights:
		if not _lit(light):
			continue
		var radius := FurnitureDef.radius_of(light, slot_name, frame)
		var color := Color(FurnitureDef.color_of(light, slot_name, frame))
		color.a = clampf(FurnitureDef.energy_of(light, slot_name, frame) * (1.0 + sin(_time * PULSE_SPEED) * PULSE_AMOUNT) * 0.6, 0.0, 1.0)
		var center := anchor(light)
		if str(light.get("shape", "radial")) == "fan":
			_draw_fan(center, radius, float(light.get("angle", 90.0)), float(light.get("spread", 60.0)), color)
		else:
			draw_texture_rect(PetLights.glow_texture(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)


## 扇形(三角扇):中心(頂點)最亮,往外緣淡出;角度邊緣是硬邊(沒有再另外做角度羽化)。
## angle_deg = 0 朝右、90 朝下、180 朝左、270 朝上(畫面座標 Y 向下);spread_deg = 扇形總張角。
func _draw_fan(center: Vector2, radius: float, angle_deg: float, spread_deg: float, color: Color) -> void:
	var base := deg_to_rad(angle_deg)
	var half := deg_to_rad(spread_deg) * 0.5
	var points := PackedVector2Array([center])
	var colors := PackedColorArray([color])
	var edge_color := color
	edge_color.a = 0.0
	for i in FAN_SEGMENTS + 1:
		var t := -half + (2.0 * half) * float(i) / float(FAN_SEGMENTS)
		points.append(center + Vector2(cos(base + t), sin(base + t)) * radius)
		colors.append(edge_color)
	draw_polygon(points, colors)


## 亮著的每盞燈各自的光暈範圍(全域座標的四邊形,扇形也用外接方框,跟 PropLight/PetLights 一致的簡化做法),給穿透多邊形用。
## 2026-09-28 效能優化:平時(非編輯模式)家具整個被搬到裝飾層(DecorOverlay,全螢幕滑鼠完全穿透的另一個視窗,
## 見 FurnitureManager._process),這盞燈是家具的子節點,跟著一起過去,畫面照樣正確顯示——但裝飾層本來就完全
## 穿透,不需要再讓這盞燈額外貢獻一份穿透形狀給主視窗(那樣只是白白增加 _collect_cutout_polygon 要比對的
## 形狀數量,對「看得到/點得到」什麼都沒有幫助)。用 get_window() 跟主視窗比較,判斷自己現在是不是在裝飾層底下
## (裝飾層是另一個 Window,不是主視窗);編輯模式時家具搬回主視窗,這裡自動恢復正常貢獻穿透形狀。
func get_cutout_polygons() -> Array:
	if _item == null or _item.def == null:
		return []
	if is_inside_tree() and get_window() != get_tree().root:
		return []
	var slot_name := _item.current_animation()
	var frame := _item.current_frame()
	var polygons: Array = []
	for light: Dictionary in _item.def.lights:
		if not _lit(light):
			continue
		var radius := FurnitureDef.radius_of(light, slot_name, frame)
		var center := anchor(light)
		polygons.append(PackedVector2Array([
			to_global(center + Vector2(-radius, -radius)), to_global(center + Vector2(radius, -radius)),
			to_global(center + Vector2(radius, radius)), to_global(center + Vector2(-radius, radius))]))
	return polygons
