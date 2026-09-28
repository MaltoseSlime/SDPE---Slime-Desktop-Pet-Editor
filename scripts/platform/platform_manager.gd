extends Node2D
## 依桌面視窗矩形生成的動態平臺與視窗邊界牆(平臺來源 A,主企劃書第二章)。
##
## - 站立平臺:各視窗的上緣,單向碰撞(只有從上方落下才會被擋住),layer 1。
## - 視窗邊界牆:各視窗的四邊,一般實體碰撞,layer 4,只有漂浮模式的桌寵會撞到。
## 只處理跟行動區有重疊的視窗,且原地重用節點、只在視窗矩形或行動區改變時才更新;
## 站立中的視窗被移走或關掉時,平臺直接消失,桌寵順著重力自然掉落。

const Layers := preload("res://scripts/common/physics_layers.gd")
const WindowRectSource := preload("res://scripts/platform/window_rect_source.gd")

const PLATFORM_THICKNESS := 8.0
const WALL_THICKNESS := 8.0
const MIN_PLATFORM_WIDTH := 24.0
## 平臺線段離行動區底部至少要有這麼高,免得跟底部地面重疊。
const MIN_HEIGHT_ABOVE_GROUND := 16.0
const PET_CHECK_INTERVAL := 2.0

## 目前有效的站立平臺(行動區座標),桌寵規劃跳躍時查詢;每筆的 position.y 是平臺上緣。
var platform_rects: Array[Rect2] = []

var _action_area: Node2D
var _source: Node
var _windows: Array[Rect2] = []
var _platforms: Array[StaticBody2D] = []
var _walls: Array[Array] = []


func setup(action_area: Node2D) -> void:
	add_to_group("platform_manager")
	_action_area = action_area
	action_area.boundary_changed.connect(_on_boundary_changed)
	_source = WindowRectSource.new()
	add_child(_source)
	_source.windows_changed.connect(_on_windows_changed)
	var timer := Timer.new()
	timer.wait_time = PET_CHECK_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_update_source_state)
	add_child(timer)
	_update_source_state()


## 場上沒有任何桌寵時關掉列舉程序,不留常駐成本。
func _update_source_state() -> void:
	_source.set_enabled(not get_tree().get_nodes_in_group("pets").is_empty())


func _on_windows_changed(rects: Array[Rect2]) -> void:
	_windows = rects
	_rebuild()


func _on_boundary_changed(_rect: Rect2) -> void:
	_rebuild()


func _rebuild() -> void:
	if _action_area == null:
		return
	var area: Rect2 = _action_area.boundary_rect
	var surfaces: Array[Rect2] = []
	var wall_rects: Array[Rect2] = []
	for screen_rect in _windows:
		var rect := Rect2(to_local(screen_rect.position), screen_rect.size)
		if not rect.intersects(area):
			continue
		wall_rects.append(rect)
		var left := maxf(rect.position.x, area.position.x)
		var right := minf(rect.end.x, area.end.x)
		var top := rect.position.y
		if (
			right - left >= MIN_PLATFORM_WIDTH
			and top > area.position.y
			and top < area.end.y - MIN_HEIGHT_ABOVE_GROUND
		):
			surfaces.append(Rect2(left, top, right - left, PLATFORM_THICKNESS))
	platform_rects = surfaces
	_apply_platforms(surfaces)
	_apply_walls(wall_rects)


func _apply_platforms(rects: Array[Rect2]) -> void:
	while _platforms.size() < rects.size():
		_platforms.append(_make_platform())
	for i in _platforms.size():
		var body := _platforms[i]
		var shape_node := body.get_child(0) as CollisionShape2D
		if i < rects.size():
			body.position = rects[i].get_center()
			(shape_node.shape as RectangleShape2D).size = rects[i].size
		shape_node.disabled = i >= rects.size()


func _apply_walls(rects: Array[Rect2]) -> void:
	while _walls.size() < rects.size():
		_walls.append(_make_wall_set())
	for i in _walls.size():
		var edges: Array = _walls[i]
		if i >= rects.size():
			for edge: Dictionary in edges:
				edge["node"].disabled = true
			continue
		var r := rects[i]
		var t := WALL_THICKNESS
		var edge_rects := [
			Rect2(r.position.x - t * 0.5, r.position.y - t * 0.5, r.size.x + t, t),
			Rect2(r.position.x - t * 0.5, r.end.y - t * 0.5, r.size.x + t, t),
			Rect2(r.position.x - t * 0.5, r.position.y, t, r.size.y),
			Rect2(r.end.x - t * 0.5, r.position.y, t, r.size.y),
		]
		for k in 4:
			var edge: Dictionary = edges[k]
			var node: CollisionShape2D = edge["node"]
			var edge_rect: Rect2 = edge_rects[k]
			edge["body"].position = edge_rect.get_center()
			(node.shape as RectangleShape2D).size = edge_rect.size
			node.disabled = false


func _make_platform() -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = Layers.PLATFORM
	body.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	shape_node.shape = RectangleShape2D.new()
	shape_node.one_way_collision = true
	shape_node.disabled = true
	body.add_child(shape_node)
	add_child(body)
	return body


func _make_wall_set() -> Array:
	var edges: Array = []
	for k in 4:
		var body := StaticBody2D.new()
		body.collision_layer = Layers.WINDOW_WALL
		body.collision_mask = 0
		var shape_node := CollisionShape2D.new()
		shape_node.shape = RectangleShape2D.new()
		shape_node.disabled = true
		body.add_child(shape_node)
		add_child(body)
		edges.append({"body": body, "node": shape_node})
	return edges
