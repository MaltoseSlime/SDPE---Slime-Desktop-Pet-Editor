class_name Connect4Board
extends Node2D
## 四連環棋盤(7 欄 × 6 列,2026-10-18 使用者要求):做法跟井字棋棋盤(TttBoard)一樣——全場同時最多一塊(見 Connect4Game.active_board)、
## 程式畫的可拖曳面板、標題列拖著移動、右上角 ✕ 取消、使用者對戰才有「投降」、閒置 IDLE_TIMEOUT 秒自動收掉。
## 使用者下棋時點任何一欄(那一欄的哪一格都可以),棋子落到那一欄最低的空格。

signal column_pressed(column: int)
signal cancel_pressed
signal surrender_pressed

const COLS := 7
const ROWS := 6
const CELL := 40.0
const PAD := 14.0
const HEADER := 30.0
const SURRENDER_HEIGHT := 26.0
const IDLE_TIMEOUT := 600.0

var board: Array = []   # COLS × ROWS,索引 = 列 × COLS + 欄(第 0 列在最上面);0 空、1 = 第一方、2 = 第二方
var interactive := false   # 現在是不是在等使用者選欄
var show_surrender := false
var status_text := ""
## 棋子配色(見 GamePieceColors):[第一方, 第二方];空的 = 系統配色(強調色 / 文字色)。
var piece_colors: Array = []
## 最後下的那一格(畫個小圈標出來);-1 = 沒有。
var last_move := -1
## 連成一線的四格(結算時標出來)。
var winning_cells: Array = []

const PLACEMENT_KIND := "connect4"
## 全局設定的棋盤大小(AppSettings.board_scale):整塊面板用節點縮放放大縮小;版面在「縮放前」的座標裡排,
## 進出的座標(滑鼠、螢幕/行動區範圍、穿透形狀、擋滑鼠的判斷)在這裡換算。
var _k := 1.0
## 字和放字的那幾列的倍數(AppSettings.board_text_scale):棋盤縮小時字維持原本大小。
var _t := 1.0
## 標題列的字要放得下時面板至少要多寬(只會變寬,不會在對局中縮回去,免得面板忽寬忽窄)。
var _min_width := 0.0

var _area: Node
var _fraction: Variant = null
var _rects: Dictionary = {}
var _dragging_header := false
var _drag_grab := Vector2.ZERO
var _mouse := Vector2.ZERO
var _idle_left := IDLE_TIMEOUT
var _last_area_cache := Rect2()
var _font_k := 1.0


func _init() -> void:
	board = empty_board()


static func empty_board() -> Array:
	var cells: Array = []
	cells.resize(COLS * ROWS)
	cells.fill(0)
	return cells


func setup(area: Node) -> void:
	_area = area
	_k = AppSettings.board_scale(PLACEMENT_KIND)
	_t = AppSettings.board_text_scale(_k)
	scale = Vector2(_k, _k)
	add_to_group("Cutout")
	add_to_group("screen_clamped_boards")
	add_to_group("pointer_blockers")
	_fraction = BoardPlacement.load_fraction(PLACEMENT_KIND)
	z_index = 40
	_layout()


func _area_rect() -> Rect2:
	var raw := _raw_area_rect()
	return Rect2(raw.position / _k, raw.size / _k)


func _raw_area_rect() -> Rect2:
	if _area != null and "boundary_rect" in _area:
		var rect: Rect2 = _area.boundary_rect
		return Rect2(_area.to_global(rect.position), rect.size)
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


func _screen_rect() -> Rect2:
	var raw := _raw_screen_rect()
	return Rect2(raw.position / _k, raw.size / _k)


func _raw_screen_rect() -> Rect2:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return _raw_area_rect()
	var origin := Vector2(get_window().position)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	return Rect2(Vector2(usable.position) - origin, Vector2(usable.size))


func recall() -> void:
	_fraction = null
	BoardPlacement.forget(PLACEMENT_KIND)
	_layout()


func panel_size() -> Vector2:
	_min_width = maxf(_min_width, AppSettings.board_header_width(status_text, 15, _t))
	return Vector2(maxf(PAD * 2.0 + CELL * COLS, _min_width), HEADER * _t + PAD * 2.0 + CELL * ROWS + (SURRENDER_HEIGHT * _t if show_surrender else 0.0))


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
	_rects["header"] = Rect2(panel.position, Vector2(size.x - 28.0 * _t, HEADER * _t))
	_rects["close"] = Rect2(panel.end.x - 26.0 * _t, panel.position.y + 4.0 * _t, 22.0 * _t, 22.0 * _t)
	_rects["grid"] = Rect2(panel.position + Vector2((size.x - CELL * COLS) * 0.5, HEADER * _t + PAD), Vector2(CELL * COLS, CELL * ROWS))   # 面板被標題撐寬時格子置中
	if show_surrender:
		_rects["surrender"] = Rect2(panel.position.x + PAD, panel.end.y - (SURRENDER_HEIGHT - 4.0) * _t, size.x - PAD * 2.0, (SURRENDER_HEIGHT - 6.0) * _t)
	_last_area_cache = area
	queue_redraw()


func blocks_pointer(point: Vector2) -> bool:
	return _dragging_header or (_rects.has("panel") and (_rects["panel"] as Rect2).has_point(point / _k))


func get_cutout_polygons() -> Array:
	if not _rects.has("panel"):
		return []
	var rect: Rect2 = _rects["panel"]
	return [DialogueBubble._rect_polygon(Rect2(rect.position * _k, rect.size * _k).grow(80.0 if _dragging_header else 4.0))]


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
		_mouse = get_viewport().get_canvas_transform().affine_inverse() * event.position / _k
	if event is InputEventMouseMotion:
		_on_motion()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press()
		else:
			_on_release()


## 滑鼠所在的欄(不在棋盤上回 -1)。
func _column_at(point: Vector2) -> int:
	if not _rects.has("grid") or not (_rects["grid"] as Rect2).has_point(point):
		return -1
	return clampi(int((point.x - (_rects["grid"] as Rect2).position.x) / CELL), 0, COLS - 1)


func _on_motion() -> void:
	if _dragging_header:
		var screen := _screen_rect()
		var size := panel_size()
		var free := (screen.size - size).max(Vector2.ONE)
		var top_left := _mouse - _drag_grab
		_fraction = Vector2(clampf((top_left.x - screen.position.x) / free.x, 0.0, 1.0), clampf((top_left.y - screen.position.y) / free.y, 0.0, 1.0))
		_layout()
	elif interactive:
		queue_redraw()   # 滑鼠停的那一欄要亮起來


func _on_press() -> void:
	if not _rects.has("panel") or not (_rects["panel"] as Rect2).has_point(_mouse):
		return
	get_viewport().set_input_as_handled()
	note_activity()
	if (_rects["close"] as Rect2).has_point(_mouse):
		cancel_pressed.emit()
	elif show_surrender and _rects.has("surrender") and (_rects["surrender"] as Rect2).has_point(_mouse):
		surrender_pressed.emit()
	elif (_rects["header"] as Rect2).has_point(_mouse):
		_dragging_header = true
		_drag_grab = _mouse - (_rects["panel"] as Rect2).position
	elif interactive:
		var column := _column_at(_mouse)
		if column >= 0 and int(board[column]) == 0:   # 最上面那格空著 = 這一欄還放得下
			column_pressed.emit(column)


func _on_release() -> void:
	if _dragging_header and _fraction is Vector2:
		BoardPlacement.save_fraction(PLACEMENT_KIND, _fraction)
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
	_font_k = UiFonts.size_correction(str(look["font"]))
	var panel: Rect2 = _rects["panel"]
	var local_panel := Rect2(panel.position - global_position, panel.size)
	draw_rect(local_panel, Color(bg, 0.95), true)
	draw_rect(local_panel, Color(accent, 0.7), false, 2.0)
	var header: Rect2 = _rects["header"]
	draw_string(font, Vector2(header.position.x - global_position.x + 6.0 * _t, header.position.y - global_position.y + 20.0 * _t), status_text, HORIZONTAL_ALIGNMENT_LEFT, header.size.x, roundi(15 * _font_k * _t), Color(text_color, 0.95))
	var close: Rect2 = _rects["close"]
	draw_string(font, Vector2(close.position.x - global_position.x + 4.0 * _t, close.position.y - global_position.y + 16.0 * _t), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16 * _font_k * _t), Color(muted, 0.9))
	var grid: Rect2 = _rects["grid"]
	var origin := grid.position - global_position
	draw_rect(Rect2(origin, grid.size), Color(text_color, 0.06), true)
	draw_rect(Rect2(origin, grid.size), Color(muted, 0.5), false, 1.5)
	var hover := _column_at(_mouse) if interactive else -1
	if hover >= 0 and int(board[hover]) == 0:
		draw_rect(Rect2(origin + Vector2(hover * CELL, 0.0), Vector2(CELL, grid.size.y)), Color(accent, 0.18), true)
	var outline := Color.BLACK if bg.get_luminance() > 0.5 else Color.WHITE
	var color_1: Color = piece_colors[0] if piece_colors.size() == 2 else accent
	var color_2: Color = piece_colors[1] if piece_colors.size() == 2 else Color(text_color, 0.85)
	var radius := CELL * 0.5 - 5.0
	for i in COLS * ROWS:
		var c := origin + Vector2((i % COLS + 0.5) * CELL, (i / COLS + 0.5) * CELL)
		var mark := int(board[i])
		if mark == 0:
			draw_arc(c, radius, 0.0, TAU, 24, Color(muted, 0.4), 1.2, true)
			continue
		# 跟井字棋一樣先畫一圈跟底色對比夠大的輪廓,不管什麼配色都看得清楚
		draw_circle(c, radius + 2.0, Color(outline, 0.55))
		draw_circle(c, radius, color_1 if mark == 1 else color_2)
		if winning_cells.has(i):
			draw_arc(c, radius * 0.45, 0.0, TAU, 20, Color(outline, 0.9), 3.0, true)
		elif i == last_move:
			draw_circle(c, 3.0, Color(outline, 0.8))
	if show_surrender and _rects.has("surrender"):
		var surrender: Rect2 = _rects["surrender"]
		draw_string(font, Vector2(surrender.position.x - global_position.x, surrender.position.y - global_position.y + 15.0 * _t), tr("投降"), HORIZONTAL_ALIGNMENT_CENTER, surrender.size.x, roundi(14 * _font_k * _t), Color(1.0, 0.55, 0.55, 0.9))
