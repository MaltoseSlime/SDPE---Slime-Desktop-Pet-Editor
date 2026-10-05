class_name MastermindBoard
extends Node2D
## 珠璣妙算(Mastermind)的獨立小面板:跟 GroupScoreboard 一樣程式畫、可拖曳(放桌寵頭上太吵,照
## 規格書的要求「嚴禁對任何桌寵節點開對話氣泡洗版」),但多了使用者猜色用的按鈕(GroupScoreboard 純顯示,
## 沒有互動)。歷史列表格式:「[猜的人] 🔴🟡🔵 | 1A1B」,最新 MAX_LINES 筆,其餘跟棋盤(TttBoard)/
## 計分板(GroupScoreboard)同一套拖曳與螢幕範圍限制、閒置自動收、「行動區重設」撈回來的規則。
## 2026-10-04 使用者要求色票從 4 色加到 6 色、密碼長度改成每隻桌寵自己設的題型(3 或 4 格):色塊數量
## 跟著 `code_length` 動態長,呼叫端(MastermindGame._run)要在 `set_controls(true)` 之前先設好 `code_length`。

signal guess_submitted(colors: Array)
signal forfeit_pressed
signal cancel_pressed

const WIDTH := 240.0
const HEADER := 26.0
const PAD := 10.0
const STATUS_HEIGHT := 18.0
const LINE_HEIGHT := 16.0
const MAX_LINES := 6
const SLOT_SIZE := 34.0
const SLOT_GAP := 8.0
const BUTTON_ROW_HEIGHT := 24.0
const IDLE_TIMEOUT := 600.0

var title := ""
var status_text := ""
var controls_active := false   # 現在是不是在等使用者選色、按「猜測」/「棄權」
var code_length := 3   # 這一場的密碼長度(3 或 4),決定下面色塊的數量

var _area: Node
var _fraction: Variant = null
var _rects: Dictionary = {}
var _dragging_header := false
var _drag_grab := Vector2.ZERO
var _mouse := Vector2.ZERO
var _last_area_cache := Rect2()
var _lines: Array[String] = []
var _slot_colors: Array = []
var _idle_left := IDLE_TIMEOUT


func setup(area: Node, panel_title: String) -> void:
	_area = area
	title = panel_title
	add_to_group("Cutout")
	add_to_group("screen_clamped_boards")
	z_index = 40
	_layout()


func add_line(text: String) -> void:
	_lines.append(text)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES, _lines.size())
	_layout()


## 開始輪到使用者選色:面板下方浮現 code_length 個循環色塊 + 「猜測」/「棄權」兩顆按鈕,重設成預設色。
func set_controls(active: bool) -> void:
	controls_active = active
	if active:
		_slot_colors = []
		for i in code_length:
			_slot_colors.append(0)
	_layout()


func _area_rect() -> Rect2:
	if _area != null and "boundary_rect" in _area:
		var rect: Rect2 = _area.boundary_rect
		return Rect2(_area.to_global(rect.position), rect.size)
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


func _screen_rect() -> Rect2:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return _area_rect()
	var origin := Vector2(get_window().position)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	return Rect2(Vector2(usable.position) - origin, Vector2(usable.size))


func recall() -> void:
	_fraction = null
	_layout()


func panel_size() -> Vector2:
	var h := HEADER + STATUS_HEIGHT + PAD + LINE_HEIGHT * MAX_LINES + PAD
	if controls_active:
		h += SLOT_SIZE + 6.0 + BUTTON_ROW_HEIGHT + PAD
	return Vector2(WIDTH, h)


func _layout() -> void:
	var area := _area_rect()
	var screen := _screen_rect()
	var size := panel_size()
	var pos: Vector2
	if _fraction is Vector2:
		var free := (screen.size - size).max(Vector2.ONE)
		pos = screen.position + free * (_fraction as Vector2)
	else:
		pos = area.position + Vector2(area.size.x - size.x - 16.0, 16.0)
	pos.x = clampf(pos.x, screen.position.x, maxf(screen.end.x - size.x, screen.position.x))
	pos.y = clampf(pos.y, screen.position.y, maxf(screen.end.y - size.y, screen.position.y))
	var panel := Rect2(pos, size)
	_rects.clear()
	_rects["panel"] = panel
	_rects["header"] = Rect2(panel.position, Vector2(size.x - 28.0, HEADER))
	_rects["close"] = Rect2(panel.end.x - 26.0, panel.position.y + 4.0, 22.0, 22.0)
	var lines_top := panel.position.y + HEADER + STATUS_HEIGHT
	if controls_active:
		var slots_y := lines_top + PAD + LINE_HEIGHT * MAX_LINES + PAD
		for i in code_length:
			_rects["slot:%d" % i] = Rect2(panel.position.x + PAD + i * (SLOT_SIZE + SLOT_GAP), slots_y, SLOT_SIZE, SLOT_SIZE)
		var button_y := slots_y + SLOT_SIZE + 6.0
		var button_w := (size.x - PAD * 2.0 - 8.0) * 0.5
		_rects["submit"] = Rect2(panel.position.x + PAD, button_y, button_w, BUTTON_ROW_HEIGHT)
		_rects["forfeit"] = Rect2(panel.position.x + PAD + button_w + 8.0, button_y, button_w, BUTTON_ROW_HEIGHT)
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


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = get_viewport().get_canvas_transform().affine_inverse() * event.position
	if event is InputEventMouseMotion:
		_on_motion()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press()
		else:
			_dragging_header = false


func _on_motion() -> void:
	if _dragging_header:
		var screen := _screen_rect()
		var size := panel_size()
		var free := (screen.size - size).max(Vector2.ONE)
		var top_left := _mouse - _drag_grab
		_fraction = Vector2(clampf((top_left.x - screen.position.x) / free.x, 0.0, 1.0), clampf((top_left.y - screen.position.y) / free.y, 0.0, 1.0))
		_layout()


func _id_at(point: Vector2) -> String:
	var ids: Array[String] = ["close"]
	for i in code_length:
		ids.append("slot:%d" % i)
	ids.append("submit")
	ids.append("forfeit")
	ids.append("header")
	for id: String in ids:
		if _rects.has(id) and (_rects[id] as Rect2).has_point(point):
			return id
	return ""


## 2026-10-04 使用者實機回報(步步為營那邊先發現的同一個坑):點在面板範圍內但沒打到任何按鈕的地方
## 會穿透到後面的對話氣泡選項按鈕,面板既然蓋在對話氣泡之上,只要滑鼠在面板範圍內就該整個吃掉這次點擊。
func _on_press() -> void:
	if not _rects.has("panel") or not (_rects["panel"] as Rect2).has_point(_mouse):
		return
	get_viewport().set_input_as_handled()
	var id := _id_at(_mouse)
	if id == "":
		return
	note_activity()
	match id:
		"header":
			_dragging_header = true
			_drag_grab = _mouse - (_rects["panel"] as Rect2).position
		"close":
			cancel_pressed.emit()
		"submit":
			if controls_active:
				guess_submitted.emit(_slot_colors.duplicate())
		"forfeit":
			if controls_active:
				forfeit_pressed.emit()
		_:
			if id.begins_with("slot:") and controls_active:
				var index := int(id.trim_prefix("slot:"))
				_slot_colors[index] = (int(_slot_colors[index]) + 1) % MastermindGame.COLOR_PALETTE.size()
				queue_redraw()


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
	draw_string(font, Vector2(header.position.x - global_position.x + 8.0, header.position.y - global_position.y + 18.0), title, HORIZONTAL_ALIGNMENT_LEFT, header.size.x - 16.0, 14, Color(text_color, 0.95))
	var close: Rect2 = _rects["close"]
	draw_string(font, Vector2(close.position.x - global_position.x + 4.0, close.position.y - global_position.y + 16.0), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(muted, 0.9))
	var status_y := header.position.y - global_position.y + HEADER + 13.0
	draw_string(font, Vector2(header.position.x - global_position.x + PAD - 2.0, status_y), status_text, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - PAD * 2.0, 12, Color(text_color, 0.85))
	var y := status_y + STATUS_HEIGHT
	for line: String in _lines:
		draw_string(font, Vector2(header.position.x - global_position.x + PAD - 2.0, y + 13.0), line, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - PAD * 2.0, 12, Color(text_color, 0.85))
		y += LINE_HEIGHT
	if controls_active:
		for i in code_length:
			var slot: Rect2 = _rects["slot:%d" % i]
			var local_slot := Rect2(slot.position - global_position, slot.size)
			draw_rect(local_slot, Color(text_color, 0.08), true)
			draw_rect(local_slot, Color(muted, 0.5), false, 1.5)
			var emoji: String = str(MastermindGame.COLOR_PALETTE[int(_slot_colors[i])])
			draw_string(font, local_slot.position + Vector2(6.0, 24.0), emoji, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		var submit: Rect2 = _rects["submit"]
		var local_submit := Rect2(submit.position - global_position, submit.size)
		draw_rect(local_submit, Color(accent, 0.25), true)
		draw_string(font, local_submit.position + Vector2(local_submit.size.x * 0.5 - 20.0, 17.0), tr("猜測"), HORIZONTAL_ALIGNMENT_CENTER, local_submit.size.x, 13, Color(text_color, 0.95))
		var forfeit: Rect2 = _rects["forfeit"]
		var local_forfeit := Rect2(forfeit.position - global_position, forfeit.size)
		draw_rect(local_forfeit, Color(text_color, 0.05), true)
		draw_string(font, local_forfeit.position + Vector2(local_forfeit.size.x * 0.5 - 20.0, 17.0), tr("棄權"), HORIZONTAL_ALIGNMENT_CENTER, local_forfeit.size.x, 13, Color(1.0, 0.55, 0.55, 0.9))
