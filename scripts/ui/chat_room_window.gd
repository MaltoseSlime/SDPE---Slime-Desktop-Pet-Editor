class_name ChatRoomWindow
extends Control
## 「聊天室式」對話顯示(見 AppSettings.bubble_display_mode()):不用等使用者互動的句子(閒聊、狀態播報…)
## 改寫進這個可拖曳/可縮放/可收合的半透明黑色視窗,而不是各自貼在桌寵旁邊的浮動氣泡。訊息格式「桌寵名字: 台詞」,
## 思考泡泡是「桌寵名字oO( 台詞 )」;文字顏色跟著那隻桌寵原本會用的泡泡外框色(見 DialogueBubble.chat_color()),
## 太暗(黑底看不清楚)時額外加白色外框線。每一行的字型與字級照那隻桌寵自己的介面風格走(PetUiStyle),不是
## 整個聊天室共用同一種——桌寵各自調過的字體/字級在聊天室裡看起來要跟浮動氣泡一致。
## 收合時縮成一個會 hover 放大的小圖示(assets/ui/chatroom_icon.png),不畫底色方框(徹底藏起來,只留圖示本身);
## 點一下展開回來。位置/大小/收合狀態存在 user://settings.cfg 的 [chatroom]。全程用 UiManager 統一管理。

const SETTINGS_PATH := "user://settings.cfg"
const TITLE_HEIGHT := 26.0
const MIN_SIZE := Vector2(220.0, 140.0)
const DEFAULT_SIZE := Vector2(320.0, 220.0)
const DEFAULT_POSITION := Vector2(40.0, 40.0)
const RESIZE_GRAB := 16.0
const ICON_SIZE := Vector2(40.0, 40.0)
## assets/ui/chatroom_icon.png 是 36x84 的雙幀 spritesheet(每幀 36x42,上下疊放,見 _build_children)。
const ICON_FRAME_SIZE := Vector2(36.0, 42.0)
const ICON_IDLE_ALPHA := 0.28   # 跟 HoverBall.IDLE_ALPHA 一致(2026-09-30 使用者要求兩者閒置時淡的程度一樣)
const ICON_HOVER_SCALE := 1.15
const ICON_ANIM_SECONDS := 0.15
## 每行是獨立的 RichTextLabel 節點(見 _make_line_label),即使桌寵自己玩遊戲、話多一點,幾百個小文字節點
## 對效能來說也不算負擔;250 條大約是一般使用情境下還讀得回去、又不會捲很久才到頂的量,加上洗版口號本來就
## 不記錄(見 GameChat.say 的 quiet 參數),實際佔用的行數會比這個數字看起來的閒聊量還要少。
const MAX_LINES := 250
## 底色跟聊天記錄文字之間留的內縮空間(2026-09-30 使用者實機回報:文字太貼邊)。
const CONTENT_INSET := 17.0
const BORDER_WIDTH := 3
## 文字亮度低於這個值視為「太暗」,加白色外框線才看得清楚(黑色半透明底)。
const DARK_LUMINANCE_THRESHOLD := 0.4
const ICON_DRAG_THRESHOLD := 6.0

var _area: Node
var _hover_ball: HoverBall
var _scroll: ScrollContainer
var _list: VBoxContainer
var _collapse_button: Button
var _resize_handle: Control
var _icon_button: TextureButton
var _icon_tween: Tween
var _window_size := DEFAULT_SIZE
var _collapsed := false
var _dragging := false
var _resizing := false
var _resize_start_size := Vector2.ZERO
var _resize_start_mouse := Vector2.ZERO
var _line_count := 0
## 展開狀態下視窗的自由拖曳位置(左上角);收合時 global_position 改由 _icon_fraction 換算,兩者分開存,
## 收合/展開互相切換不會互相覆蓋對方記住的位置。
var _window_position := DEFAULT_POSITION
## 收合圖示在行動區裡的位置(0~1 的比例,行動區大小改了圖示還在同一個角落;跟 HoverBall._fraction 同一套做法)。
var _icon_fraction := Vector2(0.05, 0.05)
var _icon_press_local := Vector2.ZERO
var _icon_dragging := false


## action_area:收合後的圖示要能拖曳、且不能跑出行動區(跟懸浮球同一套做法,見 HoverBall.ball_center())。
## hover_ball:收合圖示要避開懸浮球,兩個都是使用者能拖著到處放的東西,疊在一起會分不清楚哪個是哪個
## (2026-09-30 使用者要求;彼此互推沒關係,這裡做成圖示自己避開球,球本身的位置不受影響)。
func setup(action_area: Node, hover_ball: HoverBall) -> void:
	_area = action_area
	_hover_ball = hover_ball
	add_to_group("dialogue_display")
	add_to_group("floating_windows")   # 借用既有的「外觀改了」廣播(見 AppSettingsTab._apply_appearance),收到就重畫邊框色
	add_to_group("Cutout")
	z_index = 25
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_children()
	_load()
	refresh_setting()
	if _area != null and "boundary_changed" in _area.get_signal_list().map(func(s: Dictionary) -> String: return str(s["name"])):
		_area.boundary_changed.connect(func(_rect: Rect2) -> void: _reposition_icon())


func _build_children() -> void:
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)

	_collapse_button = Button.new()
	_collapse_button.text = "—"
	_collapse_button.custom_minimum_size = Vector2(20.0, 20.0)
	_collapse_button.tooltip_text = tr("收合聊天室")
	_collapse_button.pressed.connect(func() -> void: _set_collapsed(true))
	add_child(_collapse_button)

	_resize_handle = Control.new()
	_resize_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize_handle.gui_input.connect(_on_resize_handle_input)
	add_child(_resize_handle)

	# 素材是 36x84 的雙幀 spritesheet(每幀 36x42,上下疊放):第一幀平時顯示,第二幀是 TextureButton 內建的
	# 「按下」狀態圖,點下去那一瞬間自動切換,放開才觸發展開(2026-09-30 使用者告知素材用法)。
	var sheet: Texture2D = load("res://assets/ui/chatroom_icon.png")
	var frame_normal := AtlasTexture.new()
	frame_normal.atlas = sheet
	frame_normal.region = Rect2(0.0, 0.0, ICON_FRAME_SIZE.x, ICON_FRAME_SIZE.y)
	var frame_pressed := AtlasTexture.new()
	frame_pressed.atlas = sheet
	frame_pressed.region = Rect2(0.0, ICON_FRAME_SIZE.y, ICON_FRAME_SIZE.x, ICON_FRAME_SIZE.y)
	_icon_button = TextureButton.new()
	_icon_button.texture_normal = frame_normal
	_icon_button.texture_hover = frame_normal
	_icon_button.texture_pressed = frame_pressed
	_icon_button.ignore_texture_size = true
	_icon_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_icon_button.custom_minimum_size = ICON_SIZE
	_icon_button.size = ICON_SIZE
	_icon_button.pivot_offset = ICON_SIZE * 0.5
	_icon_button.modulate.a = ICON_IDLE_ALPHA
	_icon_button.tooltip_text = tr("展開聊天室")
	_icon_button.mouse_entered.connect(func() -> void: _animate_icon(true))
	_icon_button.mouse_exited.connect(func() -> void: _animate_icon(false))
	_icon_button.pressed.connect(func() -> void: _set_collapsed(false))
	_icon_button.gui_input.connect(_on_icon_input)
	add_child(_icon_button)


## 收合小圖示的 hover 動畫:滑鼠移過去放大一點、變不透明;移開變回原大小、半透明(平時低調)。
func _animate_icon(hover: bool) -> void:
	if _icon_tween != null and _icon_tween.is_valid():
		_icon_tween.kill()
	_icon_tween = create_tween()
	_icon_tween.set_parallel(true)
	_icon_tween.tween_property(_icon_button, "scale", Vector2.ONE * ICON_HOVER_SCALE if hover else Vector2.ONE, ICON_ANIM_SECONDS)
	_icon_tween.tween_property(_icon_button, "modulate:a", 1.0 if hover else ICON_IDLE_ALPHA, ICON_ANIM_SECONDS)


## 收合圖示的拖曳(跟 HoverBall._on_motion/_on_press 同一套邏輯):按住超過門檻才算拖曳,拖曳中吃掉事件
## 讓 TextureButton 不會在放開時誤判成一次點擊(展開);沒拖過門檻的放開才是真的點擊,交回按鈕自己處理。
## 懸浮球選單開著時整個圖示不能點、不能拖(2026-09-30 使用者要求,選單現在畫在圖示之上,底下的圖示不該
## 被誤點穿透——渲染順序跟 Godot 的滑鼠命中判定是兩回事,懸浮球是手畫的 Node2D、圖示是真的 Control,
## Godot 不會自動照畫面上下疊放順序去仲裁兩者搶到同一次點擊,所以在這裡直接問懸浮球現在有沒有展開來擋掉)。
func _on_icon_input(event: InputEvent) -> void:
	if _hover_ball != null and is_instance_valid(_hover_ball) and _hover_ball.is_expanded():
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_icon_press_local = event.position
			_icon_dragging = false
		elif _icon_dragging:
			_icon_dragging = false
			_save()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if not _icon_dragging and event.position.distance_to(_icon_press_local) < ICON_DRAG_THRESHOLD:
			return
		_icon_dragging = true
		var area := _area_rect()
		global_position = _avoid_ball(_clamp_icon_top_left(global_position + event.relative, area), area)
		if area.size.x > 0.0 and area.size.y > 0.0:
			_icon_fraction = ((global_position - area.position) / area.size).clamp(Vector2.ZERO, Vector2.ONE)
		get_viewport().set_input_as_handled()


## 展開視窗可以拖出行動區之外(2026-09-30 使用者要求),但不能拖到完全看不見、抓不回來——標題列(拖曳手把
## 本身)至少留 DRAG_HANDLE_MARGIN 像素在螢幕範圍內,使用者永遠有地方點得到再拖回來。這個視窗本身就是
## 覆蓋單一螢幕的疊加視窗,視窗的可視範圍(get_viewport().get_visible_rect())直接當螢幕範圍用。
const DRAG_HANDLE_MARGIN := 40.0


func _clamp_to_screen(pos: Vector2) -> Vector2:
	var screen := get_viewport().get_visible_rect().size
	return Vector2(
		clampf(pos.x, DRAG_HANDLE_MARGIN - _window_size.x, screen.x - DRAG_HANDLE_MARGIN),
		clampf(pos.y, 0.0, screen.y - DRAG_HANDLE_MARGIN))


## 行動區範圍(全域座標),跟 HoverBall._area_rect() 同一套做法;讀不到行動區就退回一個保底大小。
func _area_rect() -> Rect2:
	if _area != null and "boundary_rect" in _area:
		var rect: Rect2 = _area.boundary_rect
		return Rect2(_area.to_global(rect.position), rect.size)
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


## 圖示左上角夾在行動區內(行動區比圖示還小就直接置中,夾不出合理範圍;跟 HoverBall.ball_center() 同一套道理)。
func _clamp_icon_top_left(raw: Vector2, area: Rect2) -> Vector2:
	if area.size.x <= ICON_SIZE.x or area.size.y <= ICON_SIZE.y:
		return area.position + (area.size - ICON_SIZE) * 0.5
	return Vector2(
		clampf(raw.x, area.position.x, area.end.x - ICON_SIZE.x),
		clampf(raw.y, area.position.y, area.end.y - ICON_SIZE.y))


## 依目前記住的比例算出圖示位置,再夾進行動區(行動區大小改變時用——例如使用者調整行動區邊框)。
func _icon_top_left() -> Vector2:
	var area := _area_rect()
	return _avoid_ball(_clamp_icon_top_left(area.position + area.size * _icon_fraction, area), area)


## 圖示跟懸浮球疊在一起時把圖示推開(球的位置不受影響,只有圖示自己避開;圖示概略當成一個圓形——用對角線
## 一半當半徑——不用真的算矩形跟圓形的最近距離,夠用就好)。推開後再夾一次行動區範圍,避免被推出框外。
func _avoid_ball(pos: Vector2, area: Rect2) -> Vector2:
	if _hover_ball == null or not is_instance_valid(_hover_ball):
		return pos
	var ball_center: Vector2 = _hover_ball.ball_center()
	var icon_center := pos + ICON_SIZE * 0.5
	var min_dist := HoverBall.BALL_RADIUS + ICON_SIZE.length() * 0.5
	var to_icon := icon_center - ball_center
	var dist := to_icon.length()
	if dist >= min_dist:
		return pos
	var direction := to_icon / dist if dist > 0.0001 else Vector2.RIGHT
	var pushed_center := ball_center + direction * min_dist
	return _clamp_icon_top_left(pushed_center - ICON_SIZE * 0.5, area)


## 行動區範圍變了(拖邊框調整大小):收合狀態下圖示要跟著重新夾回行動區內,不能被留在框外點不到。
func _reposition_icon() -> void:
	if _collapsed:
		global_position = _icon_top_left()
		queue_redraw()


## 換螢幕、或同一台螢幕解析度變了(見 DesktopShell.apply_monitor_setting()):展開狀態下自由拖曳的位置是
## 絕對座標,依新舊視窗尺寸的比例挪過去;收合圖示是比例位置(_icon_fraction),不用跟著調。
func rescale_window_position(old_size: Vector2, new_size: Vector2) -> void:
	if old_size.x <= 0.0 or old_size.y <= 0.0 or old_size.is_equal_approx(new_size):
		return
	_window_position *= new_size / old_size
	if not _collapsed:
		global_position = _window_position
	_save()


# --- 存讀設定 ---

func _load() -> void:
	var config := ConfigFile.new()
	var loaded := config.load(SETTINGS_PATH) == OK
	_window_position = DEFAULT_POSITION
	_window_size = DEFAULT_SIZE
	_collapsed = false
	if loaded:
		_window_position = Vector2(float(config.get_value("chatroom", "x", _window_position.x)), float(config.get_value("chatroom", "y", _window_position.y)))
		_window_size = Vector2(float(config.get_value("chatroom", "w", DEFAULT_SIZE.x)), float(config.get_value("chatroom", "h", DEFAULT_SIZE.y))).max(MIN_SIZE)
		_collapsed = bool(config.get_value("chatroom", "collapsed", false))
		_icon_fraction = Vector2(clampf(float(config.get_value("chatroom", "icon_x", _icon_fraction.x)), 0.0, 1.0), clampf(float(config.get_value("chatroom", "icon_y", _icon_fraction.y)), 0.0, 1.0))
	global_position = _window_position
	_set_collapsed(_collapsed)


func _save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("chatroom", "x", _window_position.x)
	config.set_value("chatroom", "y", _window_position.y)
	config.set_value("chatroom", "w", _window_size.x)
	config.set_value("chatroom", "h", _window_size.y)
	config.set_value("chatroom", "collapsed", _collapsed)
	config.set_value("chatroom", "icon_x", _icon_fraction.x)
	config.set_value("chatroom", "icon_y", _icon_fraction.y)
	config.save(SETTINGS_PATH)


## AppSettings 的「對話集中」設定改了(見 app_settings_tab.gd 的 "dialogue_display" 群組廣播),
## 或開機時第一次套用:視窗要不要顯示跟著目前模式走。
func refresh_setting() -> void:
	visible = AppSettings.bubble_display_mode() == "chatroom"


## 外觀(配色組)改了(見 "floating_windows" 群組廣播):邊框色跟著強調色重畫(聊天內容的字型是各桌寵自己的,
## 不受這個影響,只有標題文字跟著編輯器外觀走)。
func refresh_theme() -> void:
	queue_redraw()


## "floating_windows" 群組還會廣播「浮動視窗保持在最上層」開關(見 AppSettingsTab._build_performance()),
## 但這個視窗不是獨立的 OS 視窗(只是畫布圖層上的一個 Control),置頂與它無關——留空接住廣播就好,不然
## call_group 找不到這個方法會直接噴腳本錯誤(這裡借用同一個群組只是為了收 refresh_theme,不是真的置頂視窗)。
func refresh_on_top() -> void:
	pass


# --- 版面 ---

func _set_collapsed(collapsed: bool) -> void:
	if _collapsed and not collapsed:
		global_position = _window_position   # 展開:換回展開狀態自己記住的自由位置
	elif not _collapsed and collapsed:
		_window_position = global_position   # 收合:先記住展開時的位置,global_position 之後交給圖示的比例位置管
	_collapsed = collapsed
	_scroll.visible = not collapsed
	_collapse_button.visible = not collapsed
	_resize_handle.visible = not collapsed
	_icon_button.visible = collapsed
	if collapsed:
		global_position = _icon_top_left()
	_apply_size()
	_save()


func _apply_size() -> void:
	var effective := ICON_SIZE if _collapsed else _window_size
	# custom_minimum_size 要先設:Godot 的 Control 指定 size 時會自動夾到「不小於目前的 custom_minimum_size」,
	# 收合時要縮小,若還沒把下限也一起降下來,size 會被夾住、繼續停在展開時的舊尺寸(2026-09-30 使用者實機
	# 回報:收合後色塊沒有真的變小)。
	custom_minimum_size = effective
	size = effective
	if not _collapsed:
		_scroll.position = Vector2(CONTENT_INSET, TITLE_HEIGHT)
		_scroll.size = Vector2(_window_size.x - CONTENT_INSET * 2.0, _window_size.y - TITLE_HEIGHT - CONTENT_INSET)
		_collapse_button.position = Vector2(_window_size.x - 24.0, 3.0)
		_resize_handle.position = _window_size - Vector2(RESIZE_GRAB, RESIZE_GRAB)
		_resize_handle.size = Vector2(RESIZE_GRAB, RESIZE_GRAB)
	queue_redraw()


# --- 拖曳(標題列)與縮放(右下角把手) ---

func _gui_input(event: InputEvent) -> void:
	if _collapsed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.y < TITLE_HEIGHT:
			_dragging = true
			accept_event()
		elif not event.pressed and _dragging:
			_dragging = false
			_save()
			accept_event()
	elif event is InputEventMouseMotion and _dragging and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		global_position = _clamp_to_screen(global_position + event.relative)
		_window_position = global_position
		accept_event()


func _on_resize_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_resizing = true
			_resize_start_size = _window_size
			_resize_start_mouse = get_global_mouse_position()
			get_viewport().set_input_as_handled()
		elif _resizing:
			_resizing = false
			_save()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _resizing:
		var delta := get_global_mouse_position() - _resize_start_mouse
		_window_size = (_resize_start_size + delta).max(MIN_SIZE)
		_apply_size()
		get_viewport().set_input_as_handled()


# --- 內容 ---

## 一行的 BBCode 原始碼(拆成純函式方便測試)。一般說話是「桌寵名字: 台詞」,思考泡泡改用「桌寵名字oO( 台詞 )」
## (照泡泡本來的樣子,思考不是對誰說的)。color 太暗(黑底看不清楚)時加白色外框線(RichTextLabel 的
## outline_size 標籤;外框顏色固定用主題色白色,見 _make_line_label 的 font_outline_color 覆寫,BBCode
## 沒辦法每段指定不同外框顏色,只能開關粗細)。
static func _format_line(pet_name: String, text: String, color: Color, is_thought: bool = false) -> String:
	var dark := color.get_luminance() < DARK_LUMINANCE_THRESHOLD
	var open_outline := "[outline_size=3]" if dark else ""
	var close_outline := "[/outline_size]" if dark else ""
	var safe_name := PetText.escape_bbcode(pet_name)
	var safe_text := PetText.escape_bbcode(text)
	var body := "%soO( %s )" % [safe_name, safe_text] if is_thought else "%s: %s" % [safe_name, safe_text]
	return "%s[color=#%s]%s[/color]%s" % [open_outline, color.to_html(false), body, close_outline]


## 加一行,字型/字級照 pet 自己的介面風格走(PetUiStyle,跟牠原本的浮動氣泡一致),不是整個聊天室共用同一種。
## color 是那句原本會用的泡泡外框色(見 DialogueBubble.chat_color()),is_thought 是那句原本是不是思考泡泡。
func append_line(pet: Node, text: String, color: Color, is_thought: bool = false) -> void:
	if _list == null or not is_instance_valid(pet):
		return
	# 加新行之前先記住「使用者現在是不是已經捲到底」——只有原本就在底部才跟著捲到新訊息;使用者捲上去看
	# 歷史記錄時,不應該被新訊息硬拉回底部(標準聊天視窗的「貼底」行為)。
	var was_at_bottom := _is_scrolled_to_bottom()
	_list.add_child(_make_line_label(pet, text, color, is_thought))
	_line_count += 1
	# remove_child() 先同步把最舊的那行從 _list 拿掉,再 queue_free()——queue_free() 本身是延遲到影格尾端
	# 才真的離開場景樹,這一幀之內連續呼叫 append_line() 好幾次(例如遊戲短時間內連續好幾句)的話,
	# 只用 queue_free() 會讓 get_child(0) 一直讀到同一個「還沒真的被拿掉」的舊節點,越修剪反而越修不掉。
	if _line_count > MAX_LINES and _list.get_child_count() > 0:
		var oldest := _list.get_child(0)
		_list.remove_child(oldest)
		oldest.queue_free()
		_line_count -= 1
	if was_at_bottom:
		# 剛加進去的節點,ScrollContainer 的捲動範圍(max_value)這一影格還沒重算完,現在就設 scroll_vertical
		# 只會被夾到「舊的」上限,停在原地看起來像沒有跟著捲。等一影格讓版面(尤其是 RichTextLabel 自動換行
		# 的高度)真正定下來,再設一次才會真的貼到底。同一影格內連續呼叫好幾次 append_line() 只會疊出
		# 好幾個等價的延後呼叫,結果都一樣、沒有副作用。
		_scroll_to_bottom_next_frame()


func _scroll_to_bottom_next_frame() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 2147483647


## 現在的捲動位置是不是(接近)最底部;還沒滿到需要捲動時(沒有捲軸)一律算在底部。留一點容許值,捲動值是
## 浮點數,新增內容導致範圍剛變大時不見得能精準等於最大值。
func _is_scrolled_to_bottom() -> bool:
	var bar := _scroll.get_v_scroll_bar()
	if bar == null:
		return true
	return _scroll.scroll_vertical >= bar.max_value - bar.page - 4.0


func _make_line_label(pet: Node, text: String, color: Color, is_thought: bool) -> RichTextLabel:
	var style: PetUiStyle = pet.ui_style
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = false
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS   # 滾輪事件要能繼續往上交給 ScrollContainer
	label.add_theme_color_override("default_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	label.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if style != null:
		label.add_theme_font_override("normal_font", UiFonts.get_font(str(style.default_font)))
		label.add_theme_font_size_override("normal_font_size", int(UiStyleKit.BASE_FONT_SIZE * style.text_scale_factor()))
	label.text = _format_line(pet.get_label(), text, color, is_thought)
	return label


# --- Cutout group 介面 ---

func get_cutout_polygons() -> Array:
	if not visible:
		return []
	return [DialogueBubble._rect_polygon(Rect2(global_position, size))]


# --- 繪製 ---

## 收合時完全不畫底色方框(圖示本身就是全部的視覺),徹底「藏起來」,不是縮成一個小色塊。
func _draw() -> void:
	if _collapsed:
		return
	var accent: Color = (AppSettings.appearance()["colors"] as Dictionary)["accent"]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	style.border_color = accent
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(10)
	draw_style_box(style, Rect2(Vector2.ZERO, size))
	var font := UiFonts.get_font(str((AppSettings.appearance() as Dictionary)["font"]))
	draw_string(font, Vector2(10.0, TITLE_HEIGHT * 0.68), tr("聊天室"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, accent)
