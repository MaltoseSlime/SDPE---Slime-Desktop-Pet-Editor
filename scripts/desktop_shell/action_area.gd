extends Node2D
## 行動區:管理桌寵可活動的矩形邊界、四邊縮放手把、底部實體地面,
## 以及右鍵暫時穿透的觸發判定(主企劃書第二章)。
##
## 以「Cutout」group 對外提供自己的可點擊形狀(get_cutout_polygon()),
## 由 DesktopShell 逐影格彙整成一份穿透多邊形——這個慣例沿用自參考實作 DesktopPet
## (作者 ASecondGuy,MIT License):https://github.com/ASecondGuy/DesktopPet

signal boundary_changed(rect: Rect2)
signal right_click_in_area

const SIDES: Array[String] = ["top", "bottom", "left", "right"]

const HANDLE_THICKNESS := 14.0
const HANDLE_LENGTH_RATIO := 0.28
const MIN_SIZE := Vector2(240.0, 160.0)
const FRAME_WIDTH := 2.0
const GROUND_THICKNESS := 6.0
const GROUND_INSET := 2.0
const CAPTURE_MARGIN := 20.0
const BOUNDARY_COLOR := Color(1.0, 0.82, 0.4, 0.9)
const HANDLE_COLOR := Color(1.0, 0.82, 0.4, 0.55)
const GROUND_COLOR := Color(0.53, 0.38, 0.25, 0.9)

const Layers := preload("res://scripts/common/physics_layers.gd")

## 四邊邊界牆往行動區外側延伸的厚度,夠厚才不會被高速的桌寵穿過去。
const WALL_THICKNESS := 200.0

## 開機預設尺寸與位置固定寫死,不依賴 get_window().size;使用者可用四邊把手自行拉大。
## 使用者調整過的位置與尺寸會存在 user://settings.cfg 的 [frame] 區段,下次開機還原(見 _load_saved_rect);
## 緊急召回(recenter)會重設回預設並覆寫存檔。
const DEFAULT_SIZE := Vector2(600.0, 600.0)
const DEFAULT_POSITION := Vector2(100.0, 100.0)
const SETTINGS_PATH := "user://settings.cfg"

var boundary_rect: Rect2 = Rect2()

## 邊框/把手/地面條是否顯示。隱藏時不畫、不收滑鼠事件、也不佔穿透多邊形,
## 桌面上只剩桌寵本身(對應「縮小至系統匣」後只保留桌寵的狀態)。
var frame_visible := true

var _dragging_side: String = ""
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_rect: Rect2 = Rect2()
var _walls: Dictionary = {}

@onready var _ground_body: StaticBody2D = $GroundBody
@onready var _ground_shape: CollisionShape2D = $GroundBody/CollisionShape2D


func _ready() -> void:
	add_to_group("Cutout")
	_init_default_rect()
	# 底部地面是「單向碰撞、layer 1」的站立平臺,規則與第二章雙來源平臺一致。
	_ground_body.collision_layer = Layers.PLATFORM
	_ground_body.collision_mask = 0
	_ground_shape.one_way_collision = true
	_create_walls()
	_notify_boundary_changed()


func _init_default_rect() -> void:
	boundary_rect = _load_saved_rect()


## 讀上次存的行動區(沒有、壞掉、數值不合理就用預設),並把它限制在目前視窗(螢幕)範圍內:
## 換了螢幕解析度、拔掉副螢幕之後,框也不會跑到看不見的地方。
func _load_saved_rect() -> Rect2:
	var default_rect := Rect2(DEFAULT_POSITION, DEFAULT_SIZE)
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK or not config.has_section("frame"):
		return default_rect
	var values: Array = []
	for key in ["x", "y", "w", "h"]:
		var value: Variant = config.get_value("frame", key)
		if not (value is float or value is int) or is_nan(float(value)) or is_inf(float(value)):
			return default_rect
		values.append(float(value))
	return fit_to_window(Rect2(values[0], values[1], values[2], values[3]), Vector2(get_window().size))


## 把矩形夾進 [0, bounds] 的範圍:尺寸不小於 MIN_SIZE、不大於視窗,位置不讓框跑出視窗外。
static func fit_to_window(rect: Rect2, bounds: Vector2) -> Rect2:
	var size := rect.size.clamp(MIN_SIZE, Vector2(maxf(bounds.x, MIN_SIZE.x), maxf(bounds.y, MIN_SIZE.y)))
	var position := rect.position.clamp(Vector2.ZERO, (bounds - size).max(Vector2.ZERO))
	return Rect2(position, size)


## 存目前的行動區位置與尺寸(只覆寫自己的 [frame] 區段)。
func save_rect() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("frame", "x", boundary_rect.position.x)
	config.set_value("frame", "y", boundary_rect.position.y)
	config.set_value("frame", "w", boundary_rect.size.x)
	config.set_value("frame", "h", boundary_rect.size.y)
	config.save(SETTINGS_PATH)


func set_frame_visible(value: bool) -> void:
	frame_visible = value
	_dragging_side = ""
	queue_redraw()


## 把行動區重設為預設大小,並置中於指定的視窗座標(緊急召回用)。
func recenter(window_center: Vector2) -> void:
	_dragging_side = ""
	boundary_rect = Rect2(window_center - DEFAULT_SIZE * 0.5, DEFAULT_SIZE)
	_notify_boundary_changed()
	save_rect()


## Cutout group 介面:回傳這個節點目前可被點到的形狀(全域座標),供 DesktopShell 彙整。
## 形狀是一圈中間鏤空的方框環帶,寬度為邊框線兩側各 CAPTURE_MARGIN,涵蓋邊框、四個把手與
## 底部地面條;行動區中間的空地不在形狀內,滑鼠可以直接穿透點到桌面。
## 環帶拆成互不重疊的四個矩形(上下兩條通長、左右兩條夾在中間),每個都是簡單多邊形,
## 方便 DesktopShell 跟桌寵等其他成員的形狀做重疊扣除。
## 邊框隱藏時(縮到系統匣後只剩桌寵那種狀態)還是要保留這圈穿透形狀,不然這個範圍內完全收不到滑鼠事件,
## 右鍵暫時穿透(見 _handle_mouse_button/DesktopShell._on_action_area_right_click)整個判定不到,形同壞掉
## (2026-09-27 修正:之前邊框隱藏就整組回傳空陣列,連右鍵這種不需要看到邊框才能用的功能也一起停用了)。
## 隱藏時左鍵拖曳把手仍然關閉(見 _handle_mouse_button),只差在滑鼠事件收得到、收不到而已。
func get_cutout_polygons() -> Array:
	var outer := boundary_rect.grow(CAPTURE_MARGIN)
	var inner := boundary_rect.grow(-CAPTURE_MARGIN)
	var bands: Array[Rect2] = [
		Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)),
		Rect2(outer.position.x, inner.end.y, outer.size.x, outer.end.y - inner.end.y),
		Rect2(outer.position.x, inner.position.y, inner.position.x - outer.position.x, inner.size.y),
		Rect2(inner.end.x, inner.position.y, outer.end.x - inner.end.x, inner.size.y),
	]
	var polygons: Array = []
	for band in bands:
		polygons.append(
			PackedVector2Array(
				[
					to_global(band.position),
					to_global(Vector2(band.end.x, band.position.y)),
					to_global(band.end),
					to_global(Vector2(band.position.x, band.end.y)),
				]
			)
		)
	return polygons


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging_side != "":
		_handle_drag_motion()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var mouse_pos := get_global_mouse_position()
	if event.button_index == MOUSE_BUTTON_LEFT:
		if not frame_visible:
			return   # 邊框隱藏時看不到把手,不能拖曳縮放(右鍵穿透不受這個限制,見 get_cutout_polygons 檔頭註解)。
		if event.pressed:
			var side := _side_at_point(mouse_pos)
			if side != "":
				_dragging_side = side
				_drag_start_mouse = mouse_pos
				_drag_start_rect = boundary_rect
				get_viewport().set_input_as_handled()
		elif _dragging_side != "":
			_dragging_side = ""
			save_rect()
			get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if boundary_rect.grow(CAPTURE_MARGIN).has_point(mouse_pos):
			right_click_in_area.emit()
			get_viewport().set_input_as_handled()


func _handle_drag_motion() -> void:
	var mouse_pos := get_global_mouse_position()
	var delta := mouse_pos - _drag_start_mouse
	var rect := _drag_start_rect
	match _dragging_side:
		"top":
			var new_y: float = min(rect.position.y + delta.y, rect.end.y - MIN_SIZE.y)
			rect.size.y = rect.end.y - new_y
			rect.position.y = new_y
		"bottom":
			rect.size.y = max(rect.size.y + delta.y, MIN_SIZE.y)
		"left":
			var new_x: float = min(rect.position.x + delta.x, rect.end.x - MIN_SIZE.x)
			rect.size.x = rect.end.x - new_x
			rect.position.x = new_x
		"right":
			rect.size.x = max(rect.size.x + delta.x, MIN_SIZE.x)
	boundary_rect = rect
	_notify_boundary_changed()


## 四個把手的矩形,繪製(_draw)與命中判定(_side_at_point)共用同一份,不會各算各的。
## 上/左/右把手跨在邊框線上;底部把手整條移到邊框與地面條的下方,不跟兩者重疊。
func _handle_rect(side: String) -> Rect2:
	var r := boundary_rect
	var length: float = min(r.size.x, r.size.y) * HANDLE_LENGTH_RATIO
	var x_start := r.position.x + (r.size.x - length) * 0.5
	var y_start := r.position.y + (r.size.y - length) * 0.5
	match side:
		"top":
			return Rect2(x_start, r.position.y - HANDLE_THICKNESS * 0.5, length, HANDLE_THICKNESS)
		"bottom":
			return Rect2(x_start, r.end.y + FRAME_WIDTH, length, HANDLE_THICKNESS)
		"left":
			return Rect2(r.position.x - HANDLE_THICKNESS * 0.5, y_start, HANDLE_THICKNESS, length)
		_:
			return Rect2(r.end.x - HANDLE_THICKNESS * 0.5, y_start, HANDLE_THICKNESS, length)


func _ground_rect() -> Rect2:
	var r := boundary_rect
	return Rect2(
		r.position.x + GROUND_INSET,
		r.end.y - GROUND_THICKNESS,
		r.size.x - GROUND_INSET * 2.0,
		GROUND_THICKNESS
	)


func _side_at_point(point: Vector2) -> String:
	for side in SIDES:
		if _handle_rect(side).has_point(point):
			return side
	return ""


## 行動區四邊的實體邊界牆(layer 3),桌寵只會被牆擋在行動區內。
func _create_walls() -> void:
	for side in SIDES:
		var body := StaticBody2D.new()
		body.collision_layer = Layers.BOUNDARY_WALL
		body.collision_mask = 0
		var shape_node := CollisionShape2D.new()
		shape_node.shape = RectangleShape2D.new()
		body.add_child(shape_node)
		add_child(body)
		_walls[side] = body


func _update_walls() -> void:
	var r := boundary_rect
	var t := WALL_THICKNESS
	var rects := {
		"top": Rect2(r.position.x - t, r.position.y - t, r.size.x + t * 2.0, t),
		"bottom": Rect2(r.position.x - t, r.end.y, r.size.x + t * 2.0, t),
		"left": Rect2(r.position.x - t, r.position.y - t, t, r.size.y + t * 2.0),
		"right": Rect2(r.end.x, r.position.y - t, t, r.size.y + t * 2.0),
	}
	for side in SIDES:
		var body: StaticBody2D = _walls[side]
		var rect: Rect2 = rects[side]
		body.position = rect.get_center()
		var shape := (body.get_child(0) as CollisionShape2D).shape as RectangleShape2D
		shape.size = rect.size


func _notify_boundary_changed() -> void:
	_update_walls()
	_update_ground_body()
	queue_redraw()
	boundary_changed.emit(boundary_rect)


func _update_ground_body() -> void:
	var ground := _ground_rect()
	_ground_body.position = ground.get_center()
	var shape := _ground_shape.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
		_ground_shape.shape = shape
	shape.size = ground.size


func _draw() -> void:
	# 繪製順序:先外框,再內側地面條,最後才是把手;底部把手已移到地面條下方,
	# 半透明把手不會再壓在棕色地面或邊框線上混色。
	if not frame_visible:
		return
	draw_rect(boundary_rect, BOUNDARY_COLOR, false, FRAME_WIDTH)
	draw_rect(_ground_rect(), GROUND_COLOR)
	for side in SIDES:
		draw_rect(_handle_rect(side), HANDLE_COLOR)
