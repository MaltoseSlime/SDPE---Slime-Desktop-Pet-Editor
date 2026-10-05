class_name GroupScoreboard
extends Node2D
## 「全體桌寵一起玩」的小型計分板(2026-10-04 使用者要求):場上超過兩位參加者的小遊戲(拚骰/猜拳大逃殺/
## 之後的珠璣妙算全體模式)原本每一輪都讓「每一位」在自己頭上開對話氣泡報結果,人一多聊天室/畫面就被洗版。
## 改成把這些逐輪的細節(擲出幾點、出了什麼手勢、這輪淘汰了誰…)寫進這塊獨立的小面板,只在整場真正結束時
## 才讓桌寵開口說最終結果(呼叫端自己決定,這個類別不管結束台詞)。
## 版面/拖曳都比照小遊戲棋盤(TttBoard)同一套做法:程式畫的可拖曳面板,不是視窗、不用圖片素材;沒有閒置
## 自動收(呼叫端的遊戲流程結束時會自己 queue_free() 掉,不像選牌視窗需要「等使用者」的逾時保護)。
## 2026-10-04 使用者要求:可以拖出行動區外面,但不能拖出螢幕範圍(見 _screen_rect());意外跑到螢幕外時,
## 右鍵選單「行動區重設」會呼叫 recall() 撈回來。呼叫端要記得掛進 shell.top_layer()(蓋在對話氣泡之上)。

const WIDTH := 220.0
const HEADER := 26.0
const PAD := 10.0
const LINE_HEIGHT := 18.0
const MAX_LINES := 8

var title := ""

var _area: Node
var _fraction: Variant = null   # 拖過之後記住位置(比例);沒拖過就靠邊
var _rects: Dictionary = {}
var _dragging_header := false
var _drag_grab := Vector2.ZERO
var _mouse := Vector2.ZERO
var _last_area_cache := Rect2()
var _lines: Array[String] = []


func setup(area: Node, panel_title: String) -> void:
	_area = area
	title = panel_title
	add_to_group("Cutout")
	add_to_group("screen_clamped_boards")
	z_index = 40
	_layout()


## 追加一行(例如「甲 🎲 1D20 = 14」);超過 MAX_LINES 時捨棄最舊的一行,永遠只看得到最新幾筆。
func add_line(who: String, text: String) -> void:
	_lines.append("%s %s" % [who, text] if who != "" else text)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES, _lines.size())
	_layout()


func clear_lines() -> void:
	_lines.clear()
	queue_redraw()


func _area_rect() -> Rect2:
	if _area != null and "boundary_rect" in _area:
		var rect: Rect2 = _area.boundary_rect
		return Rect2(_area.to_global(rect.position), rect.size)
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


## 可以拖到的範圍(整個螢幕,不是行動區):無頭環境讀不到螢幕資訊時退回跟 _area_rect() 一樣的假範圍。
func _screen_rect() -> Rect2:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return _area_rect()
	var origin := Vector2(get_window().position)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	return Rect2(Vector2(usable.position) - origin, Vector2(usable.size))


## 「行動區重設」用:忘記拖到哪裡了,直接退回預設(貼著行動區右上角)的位置。
func recall() -> void:
	_fraction = null
	_layout()


func panel_size() -> Vector2:
	return Vector2(WIDTH, HEADER + PAD * 2.0 + LINE_HEIGHT * MAX_LINES)


func _layout() -> void:
	var area := _area_rect()
	var screen := _screen_rect()
	var size := panel_size()
	var pos: Vector2
	if _fraction is Vector2:
		var free := (screen.size - size).max(Vector2.ONE)
		pos = screen.position + free * (_fraction as Vector2)
	else:
		pos = area.position + Vector2(area.size.x - size.x - 16.0, 16.0)   # 預設靠右上角,比較不擋到桌寵
	pos.x = clampf(pos.x, screen.position.x, maxf(screen.end.x - size.x, screen.position.x))
	pos.y = clampf(pos.y, screen.position.y, maxf(screen.end.y - size.y, screen.position.y))
	var panel := Rect2(pos, size)
	_rects.clear()
	_rects["panel"] = panel
	_rects["header"] = Rect2(panel.position, Vector2(size.x, HEADER))
	_last_area_cache = area
	queue_redraw()


func get_cutout_polygons() -> Array:
	if not _rects.has("panel"):
		return []
	var rect: Rect2 = _rects["panel"]
	return [DialogueBubble._rect_polygon(rect.grow(80.0 if _dragging_header else 4.0))]


func _process(_delta: float) -> void:
	if _area == null:
		return
	if _area_rect() != _last_area_cache:
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
			_dragging_header = false


func _on_motion() -> void:
	if _dragging_header:
		var screen := _screen_rect()
		var size := panel_size()
		var free := (screen.size - size).max(Vector2.ONE)
		var top_left := _mouse - _drag_grab
		_fraction = Vector2(clampf((top_left.x - screen.position.x) / free.x, 0.0, 1.0), clampf((top_left.y - screen.position.y) / free.y, 0.0, 1.0))
		_layout()


## 2026-10-04 使用者實機回報(步步為營那邊先發現的同一個坑):點在面板範圍內但沒打到標題列的地方(例如
## 純顯示的計分列表區)會穿透到後面的對話氣泡選項按鈕,面板既然蓋在對話氣泡之上,只要滑鼠在面板範圍內
## 就該整個吃掉這次點擊,不是只有標題列才吃。
func _on_press() -> void:
	if not _rects.has("panel") or not (_rects["panel"] as Rect2).has_point(_mouse):
		return
	get_viewport().set_input_as_handled()
	if _rects.has("header") and (_rects["header"] as Rect2).has_point(_mouse):
		_dragging_header = true
		_drag_grab = _mouse - (_rects["panel"] as Rect2).position


func _draw() -> void:
	if not _rects.has("panel"):
		return
	var look := AppSettings.appearance()
	var colors: Dictionary = look["colors"]
	var bg: Color = colors["bg"]
	var text_color: Color = colors["text"]
	var accent: Color = colors["accent"]
	var font := UiFonts.get_font(str(look["font"]))
	var panel: Rect2 = _rects["panel"]
	var local_panel := Rect2(panel.position - global_position, panel.size)
	draw_rect(local_panel, Color(bg, 0.85), true)
	draw_rect(local_panel, Color(accent, 0.7), false, 2.0)
	var header: Rect2 = _rects["header"]
	draw_string(font, Vector2(header.position.x - global_position.x + 8.0, header.position.y - global_position.y + 18.0), title, HORIZONTAL_ALIGNMENT_LEFT, header.size.x - 16.0, 14, Color(text_color, 0.95))
	var y := header.position.y - global_position.y + HEADER + PAD
	for line in _lines:
		draw_string(font, Vector2(header.position.x - global_position.x + PAD, y + 13.0), line, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - PAD * 2.0, 12, Color(text_color, 0.85))
		y += LINE_HEIGHT
