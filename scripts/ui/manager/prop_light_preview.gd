class_name PropLightPreview
extends Control
## 道具光源的即時預覽(道具管理視窗用):深色底上畫道具的圖(沒有圖就是替代方塊)和光暈,在圖上按一下或拖曳就是設定光源錨點;
## 參數(半徑、強度、顏色)改了馬上看得到效果。座標和 PropDef.light 一致:x = 圖寬比例(−0.5~0.5)、y = 從腳底往上的比例(−1~0)。

signal anchor_picked(x: float, y: float)

const VIEW_SIZE := Vector2(220.0, 190.0)
## 預覽把道具本體(PropItem.SIZE)放大這麼多倍。
const ZOOM := 2.6

var _light: Dictionary = PropDef.default_light()
var _texture: Texture2D
var _dragging := false


func _init() -> void:
	custom_minimum_size = VIEW_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = tr("在圖上按一下或拖曳,設定光源的位置(十字標記)。")


func set_state(light: Dictionary, texture: Texture2D) -> void:
	_light = PropDef.clean_light(light)
	_texture = texture
	queue_redraw()


## 腳底線中心在控制項裡的位置。
func _feet() -> Vector2:
	return Vector2(size.x * 0.5, size.y - 22.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.11))
	var feet := _feet()
	var box := PropItem.SIZE * ZOOM
	draw_line(feet + Vector2(-size.x * 0.5, 0.0), feet + Vector2(size.x * 0.5, 0.0), Color(1, 1, 1, 0.12), 1.0)
	var body := Rect2(feet + Vector2(-box * 0.5, -box), Vector2(box, box))
	if _texture != null:
		var texture_size := _texture.get_size()
		var factor := box / maxf(maxf(texture_size.x, texture_size.y), 1.0)
		var draw_size := texture_size * factor
		draw_texture_rect(_texture, Rect2(feet + Vector2(-draw_size.x * 0.5, -draw_size.y), draw_size), false)
	else:
		draw_rect(body, Color(0.55, 0.6, 0.7, 0.6))
		draw_rect(body, Color(1, 1, 1, 0.35), false, 1.0)
	var anchor := feet + Vector2(float(_light["x"]), float(_light["y"])) * box
	if bool(_light["enabled"]):
		var radius := float(_light["radius"]) * ZOOM * 0.5   # 預覽縮小一點,不然大光暈整個蓋住視窗
		var color := Color(str(_light["color"]))
		color.a = clampf(float(_light["energy"]) * 0.6, 0.0, 1.0)
		draw_texture_rect(PetLights.glow_texture(), Rect2(anchor - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)
	draw_line(anchor + Vector2(-7.0, 0.0), anchor + Vector2(7.0, 0.0), Color(1, 0.3, 0.3, 0.95), 1.5)
	draw_line(anchor + Vector2(0.0, -7.0), anchor + Vector2(0.0, 7.0), Color(1, 0.3, 0.3, 0.95), 1.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		if _dragging:
			_pick((event as InputEventMouseButton).position)
	elif event is InputEventMouseMotion and _dragging:
		_pick((event as InputEventMouseMotion).position)


func _pick(point: Vector2) -> void:
	var box := PropItem.SIZE * ZOOM
	var relative := (point - _feet()) / box
	anchor_picked.emit(clampf(relative.x, -0.5, 0.5), clampf(relative.y, -1.0, 0.0))
