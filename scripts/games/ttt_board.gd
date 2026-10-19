class_name TttBoard
extends Node2D
## 井字棋棋盤:全場同時最多一塊(見 TttGame.active_board),程式畫的可拖曳面板(不是視窗、不用圖片素材)。
## 標題列可以拖著移動;使用者對戰時輪到自己就能點格子下棋。右上角 ✕ 取消(不計戰績),「投降」文字按鈕算桌寵贏
## (只有使用者對戰才會顯示)。閒置 IDLE_TIMEOUT 秒沒人互動就視同取消自動收掉,任何一次點擊/拖曳都會重置倒數。
## 2026-10-04 使用者要求:可以拖出行動區外面,但不能拖出螢幕範圍(見 _screen_rect());預設位置還是貼著
## 行動區置中。意外跑到螢幕外(換解析度、換螢幕)時,右鍵選單「行動區重設」會呼叫 recall() 撈回來(見
## DesktopShell._on_tray_recall(),靠 "screen_clamped_boards" 群組找到所有這類面板)。

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
## 棋子配色(見 GamePieceColors):[第一方, 第二方];空的 = 系統配色(強調色 / 文字色)。
var piece_colors: Array = []

## BoardPlacement 記位置用的鍵(一種面板一個)。
const PLACEMENT_KIND := "ttt"
## 全局設定的棋盤大小(AppSettings.board_scale):整塊面板用節點縮放放大縮小;版面在「縮放前」的座標裡排,
## 進出的座標(滑鼠、螢幕/行動區範圍、穿透形狀、擋滑鼠的判斷)在這裡換算。
var _k := 1.0
## 字和放字的那幾列的倍數(AppSettings.board_text_scale):棋盤縮小時字維持原本大小。
var _t := 1.0
## 標題列的字要放得下時面板至少要多寬(只會變寬,不會在對局中縮回去,免得面板忽寬忽窄)。
var _min_width := 0.0

var _area: Node
var _fraction: Variant = null   # 拖過之後記住位置(比例);沒拖過就置中
var _rects: Dictionary = {}
var _dragging_header := false
var _drag_grab := Vector2.ZERO
var _mouse := Vector2.ZERO
var _idle_left := IDLE_TIMEOUT
var _last_area_cache := Rect2()


var _font_k := 1.0

func setup(area: Node) -> void:
	_area = area
	_k = AppSettings.board_scale(PLACEMENT_KIND)
	_t = AppSettings.board_text_scale(_k)
	scale = Vector2(_k, _k)
	add_to_group("Cutout")
	add_to_group("screen_clamped_boards")
	add_to_group("pointer_blockers")
	_fraction = BoardPlacement.load_fraction(PLACEMENT_KIND)   # 上次拖到哪,這次就在哪生成
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


## 可以拖到的範圍(整個螢幕,不是行動區):無頭環境讀不到螢幕資訊時退回跟 _area_rect() 一樣的假範圍。
func _screen_rect() -> Rect2:
	var raw := _raw_screen_rect()
	return Rect2(raw.position / _k, raw.size / _k)


func _raw_screen_rect() -> Rect2:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return _raw_area_rect()
	var origin := Vector2(get_window().position)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	return Rect2(Vector2(usable.position) - origin, Vector2(usable.size))


## 「行動區重設」用:忘記拖到哪裡了,直接退回預設(貼著行動區置中)的位置。
func recall() -> void:
	_fraction = null
	BoardPlacement.forget(PLACEMENT_KIND)
	_layout()


func panel_size() -> Vector2:
	_min_width = maxf(_min_width, AppSettings.board_header_width(status_text, 15, _t))
	return Vector2(maxf(PAD * 2.0 + CELL * 3.0, _min_width), HEADER * _t + PAD * 2.0 + CELL * 3.0 + (SURRENDER_HEIGHT * _t if show_surrender else 0.0))


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
	var grid_origin := panel.position + Vector2((size.x - CELL * 3.0) * 0.5, HEADER * _t + PAD)   # 面板被標題撐寬時格子置中
	for i in 9:
		var col := i % 3
		var row := i / 3
		_rects["cell:%d" % i] = Rect2(grid_origin + Vector2(col * CELL, row * CELL), Vector2(CELL, CELL))
	if show_surrender:
		_rects["surrender"] = Rect2(panel.position.x + PAD, panel.end.y - (SURRENDER_HEIGHT - 4.0) * _t, size.x - PAD * 2.0, (SURRENDER_HEIGHT - 6.0) * _t)
	_last_area_cache = area
	queue_redraw()


## 滑鼠在面板範圍內(或正拖著標題列)時,後面的桌寵不該收到按壓/右鍵/摸摸,見 pet_interaction.gd 的 pointer_blocked()。
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
		var screen := _screen_rect()
		var size := panel_size()
		var free := (screen.size - size).max(Vector2.ONE)
		var top_left := _mouse - _drag_grab
		_fraction = Vector2(clampf((top_left.x - screen.position.x) / free.x, 0.0, 1.0), clampf((top_left.y - screen.position.y) / free.y, 0.0, 1.0))
		_layout()


## 2026-10-04 使用者實機回報(步步為營那邊先發現的同一個坑):點在面板範圍內但沒打到任何按鈕/格子的地方
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
		"surrender":
			if show_surrender:
				surrender_pressed.emit()
		_:
			if id.begins_with("cell:") and interactive:
				var index := int(id.trim_prefix("cell:"))
				if int(board[index]) == 0:
					cell_pressed.emit(index)


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
	_font_k = UiFonts.size_correction(str(look["font"]))   # 寫死的字級乘上字體的視覺校正(Silver 會放大)
	var panel: Rect2 = _rects["panel"]
	var local_panel := Rect2(panel.position - global_position, panel.size)
	draw_rect(local_panel, Color(bg, 0.95), true)
	draw_rect(local_panel, Color(accent, 0.7), false, 2.0)
	var header: Rect2 = _rects["header"]
	draw_string(font, Vector2(header.position.x - global_position.x + 6.0 * _t, header.position.y - global_position.y + 20.0 * _t), status_text, HORIZONTAL_ALIGNMENT_LEFT, header.size.x, roundi(15 * _font_k * _t), Color(text_color, 0.95))
	var close: Rect2 = _rects["close"]
	draw_string(font, Vector2(close.position.x - global_position.x + 4.0 * _t, close.position.y - global_position.y + 16.0 * _t), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16 * _font_k * _t), Color(muted, 0.9))
	for i in 9:
		var cell: Rect2 = _rects["cell:%d" % i]
		var local_cell := Rect2(cell.position - global_position, cell.size)
		draw_rect(local_cell.grow(-2.0), Color(text_color, 0.05), true)
		draw_rect(local_cell.grow(-2.0), Color(muted, 0.4), false, 1.5)
		var mark := int(board[i])
		var c := local_cell.get_center()
		# 2026-09-30 使用者實機回報:「筆記本」配色的 accent(#e2dad0)跟 bg(#e3e1de)幾乎同色,叉直接畫在
		# 底色上等於隱形。不能假設任何配色組的 accent/text 一定跟 bg 有足夠對比,所以先用跟 bg 對比夠大的
		# 顏色(黑或白,依 bg 亮度挑)畫一條加寬的底線當輪廓,再疊上真正的顏色,不管什麼配色都看得清楚。
		var outline := Color.BLACK if bg.get_luminance() > 0.5 else Color.WHITE
		var color_x: Color = piece_colors[0] if piece_colors.size() == 2 else accent
		var color_o: Color = piece_colors[1] if piece_colors.size() == 2 else Color(text_color, 0.85)
		if mark == 1:
			draw_line(c - Vector2(16, 16), c + Vector2(16, 16), Color(outline, 0.55), 7.0)
			draw_line(c + Vector2(-16, 16), c + Vector2(16, -16), Color(outline, 0.55), 7.0)
			draw_line(c - Vector2(16, 16), c + Vector2(16, 16), color_x, 4.0)
			draw_line(c + Vector2(-16, 16), c + Vector2(16, -16), color_x, 4.0)
		elif mark == 2:
			draw_arc(c, 18.0, 0.0, TAU, 24, Color(outline, 0.55), 7.0)
			draw_arc(c, 18.0, 0.0, TAU, 24, color_o, 4.0)
	if show_surrender and _rects.has("surrender"):
		var surrender: Rect2 = _rects["surrender"]
		draw_string(font, Vector2(surrender.position.x - global_position.x, surrender.position.y - global_position.y + 15.0 * _t), tr("投降"), HORIZONTAL_ALIGNMENT_CENTER, surrender.size.x, roundi(14 * _font_k * _t), Color(1.0, 0.55, 0.55, 0.9))
