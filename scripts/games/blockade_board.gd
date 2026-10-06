class_name BlockadeBoard
extends Node2D
## 步步為營(標準 Quoridor 9x9)棋盤:跟井字棋(TttBoard)同一套做法 —— 全場同時最多一塊(見
## BlockadeGame.active_board)、程式畫可拖曳、不用圖片素材。牆不是填格子,是放在格子縫隙裡(橫向/縱向、
## 一次卡住兩段邊),使用者對戰時用三顆模式鈕切換:「｜」縱牆、「Ｏ」移動棋子、「－」橫牆,目前選中的那顆
## 背景變暗,下面一行小字描述目前模式("放置直牆(剩 N 面)"/"移動棋子"/"放置橫牆(剩 N 面)")。放牆模式下
## 滑鼠移到棋盤上會先畫一條半透明的預覽線(顏色跟真正放下去的牆不一樣),點了才真的送出。右上角 ✕ 取消
## (不計戰績),「投降」算桌寵贏(只有使用者對戰才顯示)。拖出行動區外面但不能拖出螢幕範圍,閒置
## IDLE_TIMEOUT 沒人互動自動收掉,規則跟 TttBoard 完全一樣。

signal action_chosen(kind: String, orientation: String, target: Vector2i)
signal cancel_pressed
signal surrender_pressed

const GRID_N := 9
const CELL := 28.0
const GAP := 7.0
const STEP := CELL + GAP
const PAD := 14.0
const HEADER := 26.0
const MODE_ROW := 46.0
const SURRENDER_HEIGHT := 24.0
const IDLE_TIMEOUT := 600.0

## {"pos": {"A": Vector2i, "B": Vector2i}, "walls_left": {"A": int, "B": int}, "walls": Dictionary[Vector2i, String]}
var state: Dictionary = {}
var interactive := false
var wall_mode_kind := "move"   # "move" / "vwall" / "hwall"
var walls_left_hint := 0
var show_surrender := false
var status_text := ""

var _area: Node
var _fraction: Variant = null
var _rects: Dictionary = {}
var _dragging_header := false
var _drag_grab := Vector2.ZERO
var _mouse := Vector2.ZERO
var _idle_left := IDLE_TIMEOUT
var _last_area_cache := Rect2()


func setup(area: Node) -> void:
	_area = area
	add_to_group("Cutout")
	add_to_group("screen_clamped_boards")
	z_index = 40
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


func _grid_size() -> float:
	return GRID_N * CELL + (GRID_N - 1) * GAP


func panel_size() -> Vector2:
	var grid := _grid_size()
	return Vector2(PAD * 2.0 + grid, HEADER + (MODE_ROW if show_surrender else 0.0) + PAD * 2.0 + grid + (SURRENDER_HEIGHT if show_surrender else 0.0))


func _layout() -> void:
	var area := _area_rect()
	var screen := _screen_rect()
	var size := panel_size()
	var pos: Vector2
	if _fraction is Vector2:
		var free := (screen.size - size).max(Vector2.ONE)
		pos = screen.position + free * (_fraction as Vector2)
	else:
		pos = area.position + (area.size - size) * 0.5
	pos.x = clampf(pos.x, screen.position.x, maxf(screen.end.x - size.x, screen.position.x))
	pos.y = clampf(pos.y, screen.position.y, maxf(screen.end.y - size.y, screen.position.y))
	var panel := Rect2(pos, size)
	_rects.clear()
	_rects["panel"] = panel
	_rects["header"] = Rect2(panel.position, Vector2(size.x - 28.0, HEADER))
	_rects["close"] = Rect2(panel.end.x - 26.0, panel.position.y + 4.0, 22.0, 22.0)
	var grid_top := panel.position.y + HEADER + (MODE_ROW if show_surrender else 0.0) + PAD
	if show_surrender:
		var btn_w := 40.0
		var btn_y := panel.position.y + HEADER + 2.0
		var btn_x := panel.position.x + PAD
		_rects["mode_vwall"] = Rect2(btn_x, btn_y, btn_w, 24.0)
		_rects["mode_move"] = Rect2(btn_x + btn_w + 6.0, btn_y, btn_w, 24.0)
		_rects["mode_hwall"] = Rect2(btn_x + (btn_w + 6.0) * 2.0, btn_y, btn_w, 24.0)
	_rects["grid_origin"] = Rect2(Vector2(panel.position.x + PAD, grid_top), Vector2.ZERO)
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
		if interactive and wall_mode_kind != "move":
			queue_redraw()   # 牆的預覽線跟著滑鼠即時更新
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press()
		else:
			_on_release()


## 滑鼠所在的格子座標(不管在不在格子的實心範圍內,給移動模式點擊用)。
func _cell_at(local: Vector2) -> Vector2i:
	var origin: Vector2 = (_rects["grid_origin"] as Rect2).position
	return Vector2i(clampi(int(floor((local.x - origin.x) / STEP)), 0, GRID_N - 1), clampi(int(floor((local.y - origin.y) / STEP)), 0, GRID_N - 1))


## 滑鼠最靠近的牆縫格座標(給放牆模式點擊/預覽用):抓最近的「格子交叉點」。
func _slot_at(local: Vector2) -> Vector2i:
	var origin: Vector2 = (_rects["grid_origin"] as Rect2).position
	var sx := int(round((local.x - origin.x - CELL * 0.5) / STEP))
	var sy := int(round((local.y - origin.y - CELL * 0.5) / STEP))
	return Vector2i(clampi(sx, 0, GRID_N - 2), clampi(sy, 0, GRID_N - 2))


func _on_motion() -> void:
	if _dragging_header:
		var screen := _screen_rect()
		var size := panel_size()
		var free := (screen.size - size).max(Vector2.ONE)
		var top_left := _mouse - _drag_grab
		_fraction = Vector2(clampf((top_left.x - screen.position.x) / free.x, 0.0, 1.0), clampf((top_left.y - screen.position.y) / free.y, 0.0, 1.0))
		_layout()


func _id_at(point: Vector2) -> String:
	for id: String in ["close", "mode_vwall", "mode_move", "mode_hwall", "surrender", "header"]:
		if _rects.has(id) and (_rects[id] as Rect2).has_point(point):
			return id
	return ""


## 2026-10-04 使用者實機回報:點在棋盤面板範圍內、但沒打到按鈕也沒打到棋格的地方(留白、還沒輪到自己時
## 點格子…)時,點擊會「穿透」到棋盤後面的對話氣泡選項按鈕。棋盤既然蓋在對話氣泡之上(top_layer),只要
## 滑鼠在面板範圍內就該整個吃掉這次點擊,不管有沒有實際觸發動作,不能只在打到按鈕/格子時才吃。
func _on_press() -> void:
	if not _rects.has("panel") or not (_rects["panel"] as Rect2).has_point(_mouse):
		return
	get_viewport().set_input_as_handled()
	var id := _id_at(_mouse)
	if id != "":
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
			"mode_move":
				wall_mode_kind = "move"
				queue_redraw()
			"mode_vwall":
				if walls_left_hint > 0:
					wall_mode_kind = "vwall"
					queue_redraw()
			"mode_hwall":
				if walls_left_hint > 0:
					wall_mode_kind = "hwall"
					queue_redraw()
		return
	if not interactive or not _rects.has("grid_origin"):
		return
	var grid: Rect2 = Rect2((_rects["grid_origin"] as Rect2).position, Vector2(_grid_size(), _grid_size()))
	if not grid.has_point(_mouse):
		return
	note_activity()
	if wall_mode_kind == "move":
		action_chosen.emit("MOVE", "", _cell_at(_mouse))
	else:
		action_chosen.emit("WALL", "V" if wall_mode_kind == "vwall" else "H", _slot_at(_mouse))


func _on_release() -> void:
	_dragging_header = false


func _cell_rect(origin: Vector2, x: int, y: int) -> Rect2:
	return Rect2(origin + Vector2(x * STEP, y * STEP), Vector2(CELL, CELL))


## 橫牆(擋住縱向移動)的畫面矩形:橫跨 slot.x、slot.x+1 兩欄,夾在 slot.y/slot.y+1 兩列中間的縫隙。
func _h_wall_rect(origin: Vector2, slot: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(slot.x * STEP, slot.y * STEP + CELL), Vector2(STEP * 2.0 - GAP, GAP))


## 縱牆(擋住橫向移動)的畫面矩形:橫跨 slot.y、slot.y+1 兩列,夾在 slot.x/slot.x+1 兩欄中間的縫隙。
func _v_wall_rect(origin: Vector2, slot: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(slot.x * STEP + CELL, slot.y * STEP), Vector2(GAP, STEP * 2.0 - GAP))


func _draw() -> void:
	if not _rects.has("panel") or state.is_empty():
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
	draw_string(font, Vector2(header.position.x - global_position.x + 6.0, header.position.y - global_position.y + 19.0), status_text, HORIZONTAL_ALIGNMENT_LEFT, header.size.x, 13, Color(text_color, 0.95))
	var close: Rect2 = _rects["close"]
	draw_string(font, Vector2(close.position.x - global_position.x + 4.0, close.position.y - global_position.y + 16.0), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(muted, 0.9))
	if show_surrender:
		_draw_mode_buttons(font, text_color, accent, muted)
	var outline := Color.BLACK if bg.get_luminance() > 0.5 else Color.WHITE
	var origin: Vector2 = (_rects["grid_origin"] as Rect2).position - global_position
	var pos: Dictionary = state.get("pos", {})
	var walls: Dictionary = state.get("walls", {})
	for y in GRID_N:
		for x in GRID_N:
			var cell_pos := Vector2i(x, y)
			var local_cell := _cell_rect(origin, x, y)
			draw_rect(local_cell, Color(text_color, 0.05), true)
			var c := local_cell.get_center()
			if pos.get("A", Vector2i(-1, -1)) == cell_pos:
				draw_circle(c, 11.0, Color(outline, 0.55))
				draw_circle(c, 9.0, accent)
			elif pos.get("B", Vector2i(-1, -1)) == cell_pos:
				draw_circle(c, 11.0, Color(outline, 0.55))
				draw_circle(c, 9.0, text_color)
	var wall_owners: Dictionary = state.get("wall_owners", {})
	for slot: Vector2i in walls:
		var orientation: String = str(walls[slot])
		var owner: String = str(wall_owners.get(slot, "A"))
		var wall_color: Color = accent if owner == "A" else text_color   # 敵我雙方的牆顏色不同,各自跟自己棋子同色
		var rect := _h_wall_rect(origin, slot) if orientation == "H" else _v_wall_rect(origin, slot)
		# 外框線(跟井字棋的圈叉同一個做法):先在牆的外面畫一圈對比色的輪廓,再疊上敵我顏色的牆面,
		# 不管哪種配色,牆跟底色都分得清楚。
		draw_rect(rect.grow(2.0), Color(outline, 0.55), true)
		draw_rect(rect, wall_color, true)
	if interactive and wall_mode_kind != "move":
		var slot := _slot_at(_mouse)
		var preview_rect := _h_wall_rect(origin, slot) if wall_mode_kind == "hwall" else _v_wall_rect(origin, slot)
		draw_rect(preview_rect, Color(1.0, 0.85, 0.2, 0.55), true)   # 預覽色跟上面兩種實際牆色(accent/text_color)都不一樣
	if show_surrender and _rects.has("surrender"):
		var surrender: Rect2 = _rects["surrender"]
		draw_string(font, Vector2(surrender.position.x - global_position.x, surrender.position.y - global_position.y + 15.0), tr("投降"), HORIZONTAL_ALIGNMENT_CENTER, surrender.size.x, 14, Color(1.0, 0.55, 0.55, 0.9))


func _draw_mode_buttons(font: Font, text_color: Color, accent: Color, muted: Color) -> void:
	var specs := [["mode_vwall", "｜"], ["mode_move", "Ｏ"], ["mode_hwall", "－"]]
	for spec: Array in specs:
		var id: String = spec[0]
		var glyph: String = spec[1]
		if not _rects.has(id):
			continue
		var rect: Rect2 = _rects[id]
		var local_rect := Rect2(rect.position - global_position, rect.size)
		var kind := id.trim_prefix("mode_")
		var active := wall_mode_kind == kind
		var disabled := kind != "move" and walls_left_hint <= 0
		draw_rect(local_rect, Color(accent, 0.45) if active else Color(text_color, 0.06), true)
		draw_rect(local_rect, Color(muted, 0.5), false, 1.0)
		draw_string(font, local_rect.position + Vector2(local_rect.size.x * 0.5 - 6.0, 17.0), glyph, HORIZONTAL_ALIGNMENT_CENTER, local_rect.size.x, 14, Color(text_color, 0.4 if disabled else 0.95))
	var caption := tr("移動棋子")
	match wall_mode_kind:
		"vwall":
			caption = tr("放置直牆(剩 %d 面)") % walls_left_hint
		"hwall":
			caption = tr("放置橫牆(剩 %d 面)") % walls_left_hint
	var caption_y: float = (_rects["mode_move"] as Rect2).end.y - global_position.y + 14.0
	var caption_x: float = (_rects["mode_vwall"] as Rect2).position.x - global_position.x
	draw_string(font, Vector2(caption_x, caption_y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(text_color, 0.85))
