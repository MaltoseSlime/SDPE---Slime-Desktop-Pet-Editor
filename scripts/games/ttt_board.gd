class_name TttBoard
extends Node2D
## 井字棋棋盤:全場同時最多一塊(見 TttGame.active_board),程式畫的可拖曳面板(不是視窗、不用圖片素材)。
## 標題列可以拖著移動;使用者對戰時輪到自己就能點格子下棋。右上角 ✕ 取消(不計戰績),「投降」文字按鈕算桌寵贏
## (只有使用者對戰才會顯示)。閒置 IDLE_TIMEOUT 秒沒人互動就視同取消自動收掉,任何一次點擊/拖曳都會重置倒數。

signal cell_pressed(index: int)
signal cancel_pressed
signal surrender_pressed

const CELL := 56.0
const PAD := 14.0
const HEADER := 30.0
const SURRENDER_HEIGHT := 26.0
const IDLE_TIMEOUT := 600.0

var board: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0]   # 0 空、1 = X、2 = O
var interactive := false   # 現在是不是在等使用者點格子
var show_surrender := false
var status_text := ""

var _area: Node
var _fraction: Variant = null   # 拖過之後記住位置(比例);沒拖過就置中
var _rects: Dictionary = {}
var _dragging_header := false
var _drag_grab := Vector2.ZERO
var _mouse := Vector2.ZERO
var _idle_left := IDLE_TIMEOUT
var _last_area_cache := Rect2()


func setup(area: Node) -> void:
	_area = area
	add_to_group("Cutout")
	z_index = 40
	_layout()


func _area_rect() -> Rect2:
	if _area != null and "boundary_rect" in _area:
		var rect: Rect2 = _area.boundary_rect
		return Rect2(_area.to_global(rect.position), rect.size)
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


func panel_size() -> Vector2:
	return Vector2(PAD * 2.0 + CELL * 3.0, HEADER + PAD * 2.0 + CELL * 3.0 + (SURRENDER_HEIGHT if show_surrender else 0.0))


func _layout() -> void:
	var area := _area_rect()
	var size := panel_size()
	var pos: Vector2
	if _fraction is Vector2:
		var free := (area.size - size).max(Vector2.ONE)
		pos = area.position + free * (_fraction as Vector2)
	else:
		pos = area.position + (area.size - size) * 0.5
	pos.x = clampf(pos.x, area.position.x, maxf(area.end.x - size.x, area.position.x))
	pos.y = clampf(pos.y, area.position.y, maxf(area.end.y - size.y, area.position.y))
	var panel := Rect2(pos, size)
	_rects.clear()
	_rects["panel"] = panel
	_rects["header"] = Rect2(panel.position, Vector2(size.x - 28.0, HEADER))
	_rects["close"] = Rect2(panel.end.x - 26.0, panel.position.y + 4.0, 22.0, 22.0)
	var grid_origin := panel.position + Vector2(PAD, HEADER + PAD)
	for i in 9:
		var col := i % 3
		var row := i / 3
		_rects["cell:%d" % i] = Rect2(grid_origin + Vector2(col * CELL, row * CELL), Vector2(CELL, CELL))
	if show_surrender:
		_rects["surrender"] = Rect2(panel.position.x + PAD, panel.end.y - SURRENDER_HEIGHT + 4.0, size.x - PAD * 2.0, SURRENDER_HEIGHT - 6.0)
	_last_area_cache = area
	queue_redraw()


func get_cutout_polygons() -> Array:
	if not _rects.has("panel"):
		return []
	var rect: Rect2 = _rects["panel"]
	return [DialogueBubble._rect_polygon(rect.grow(80.0 if _dragging_header else 4.0))]


func _process(delta: float) -> void:
	if _area == null:
		return
	if _area_rect() != _last_area_cache:
		_layout()
	_idle_left -= delta
	if _idle_left <= 0.0:
		cancel_pressed.emit()


func note_activity() -> void:
	_idle_left = IDLE_TIMEOUT


func refresh() -> void:
	_layout()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = get_viewport().get_canvas_transform().affine_inverse() * event.position
	if event is InputEventMouseMotion:
		_on_motion()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press()
		else:
			_on_release()


func _id_at(point: Vector2) -> String:
	for id: String in ["close", "surrender", "header"]:
		if _rects.has(id) and (_rects[id] as Rect2).has_point(point):
			return id
	for i in 9:
		var id := "cell:%d" % i
		if _rects.has(id) and (_rects[id] as Rect2).has_point(point):
			return id
	return ""


func _on_motion() -> void:
	if _dragging_header:
		var area := _area_rect()
		var size := panel_size()
		var free := (area.size - size).max(Vector2.ONE)
		var top_left := _mouse - _drag_grab
		_fraction = Vector2(clampf((top_left.x - area.position.x) / free.x, 0.0, 1.0), clampf((top_left.y - area.position.y) / free.y, 0.0, 1.0))
		_layout()


func _on_press() -> void:
	var id := _id_at(_mouse)
	if id == "":
		return
	get_viewport().set_input_as_handled()
	note_activity()
	match id:
		"header":
			_dragging_header = true
			_drag_grab = _mouse - (_rects["panel"] as Rect2).position
		"close":
			cancel_pressed.emit()
		"surrender":
			if show_surrender:
				surrender_pressed.emit()
		_:
			if id.begins_with("cell:") and interactive:
				var index := int(id.trim_prefix("cell:"))
				if int(board[index]) == 0:
					cell_pressed.emit(index)


func _on_release() -> void:
	_dragging_header = false


func _draw() -> void:
	if not _rects.has("panel"):
		return
	var look := AppSettings.appearance()
	var colors: Dictionary = look["colors"]
	var bg: Color = colors["bg"]
	var text_color: Color = colors["text"]
	var accent: Color = colors["accent"]
	var muted: Color = colors["muted"]
	var font := UiFonts.get_font(str(look["font"]))
	var panel: Rect2 = _rects["panel"]
	var local_panel := Rect2(panel.position - global_position, panel.size)
	draw_rect(local_panel, Color(bg, 0.95), true)
	draw_rect(local_panel, Color(accent, 0.7), false, 2.0)
	var header: Rect2 = _rects["header"]
	draw_string(font, Vector2(header.position.x - global_position.x + 6.0, header.position.y - global_position.y + 20.0), status_text, HORIZONTAL_ALIGNMENT_LEFT, header.size.x, 15, Color(text_color, 0.95))
	var close: Rect2 = _rects["close"]
	draw_string(font, Vector2(close.position.x - global_position.x + 4.0, close.position.y - global_position.y + 16.0), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(muted, 0.9))
	for i in 9:
		var cell: Rect2 = _rects["cell:%d" % i]
		var local_cell := Rect2(cell.position - global_position, cell.size)
		draw_rect(local_cell.grow(-2.0), Color(text_color, 0.05), true)
		draw_rect(local_cell.grow(-2.0), Color(muted, 0.4), false, 1.5)
		var mark := int(board[i])
		var c := local_cell.get_center()
		if mark == 1:
			draw_line(c - Vector2(16, 16), c + Vector2(16, 16), accent, 4.0)
			draw_line(c + Vector2(-16, 16), c + Vector2(16, -16), accent, 4.0)
		elif mark == 2:
			draw_arc(c, 18.0, 0.0, TAU, 24, Color(text_color, 0.85), 4.0)
	if show_surrender and _rects.has("surrender"):
		var surrender: Rect2 = _rects["surrender"]
		draw_string(font, Vector2(surrender.position.x - global_position.x, surrender.position.y - global_position.y + 15.0), tr("投降"), HORIZONTAL_ALIGNMENT_CENTER, surrender.size.x, 14, Color(1.0, 0.55, 0.55, 0.9))
