class_name PropLight
extends Node2D
## 道具 / 家具專屬光源(企劃書第八章):掛在 PropItem 底下,在道具的光源錨點畫一團柔和的暖色光暈(程式畫,沒有陰影;和桌寵身上的光源用同一張放射漸層貼圖),
## 亮度只有很慢的呼吸起伏。全局設定的光源總開關關掉(AppSettings.lights_enabled)就不畫;道具被使用中(消失動畫)也不畫。
## 光暈超出道具本身的部分要在穿透形狀裡,否則會被視窗裁掉,所以是「Cutout」群組成員(方形範圍);「pet_lights」群組讓總開關改了能立刻更新。

const PULSE_SPEED := 1.1
const PULSE_AMOUNT := 0.07
const REDRAW_INTERVAL := 1.0 / 20.0

var _item: PropItem
var _enabled := true
var _time := 0.0
var _redraw_left := 0.0


func setup(item: PropItem) -> void:
	_item = item
	z_index = 1
	add_to_group("Cutout")
	add_to_group("pet_lights")
	refresh_setting()


func refresh_setting() -> void:
	_enabled = AppSettings.lights_enabled()
	queue_redraw()


func _lit() -> bool:
	return _enabled and _item != null and _item.def != null and _item.def.has_light() and not _item.consuming


## 光源錨點(道具本地座標;原點是腳底線中心)。
func anchor() -> Vector2:
	var light: Dictionary = _item.def.light
	return Vector2(float(light["x"]) * PropItem.SIZE, float(light["y"]) * PropItem.SIZE)


func _process(delta: float) -> void:
	if not _lit():
		return
	_time += delta
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = REDRAW_INTERVAL
		queue_redraw()


func _draw() -> void:
	if not _lit():
		return
	var light: Dictionary = _item.def.light
	var radius := float(light["radius"])
	var color := Color(str(light["color"]))
	color.a = clampf(float(light["energy"]) * (1.0 + sin(_time * PULSE_SPEED) * PULSE_AMOUNT) * 0.6, 0.0, 1.0)
	var center := anchor()
	draw_texture_rect(PetLights.glow_texture(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)


func get_cutout_polygons() -> Array:
	if not _lit():
		return []
	var radius := float(_item.def.light["radius"])
	var center := anchor()
	return [PackedVector2Array([
		to_global(center + Vector2(-radius, -radius)), to_global(center + Vector2(radius, -radius)),
		to_global(center + Vector2(radius, radius)), to_global(center + Vector2(-radius, radius))])]
