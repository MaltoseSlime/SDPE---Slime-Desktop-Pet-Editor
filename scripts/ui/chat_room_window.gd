class_name ChatRoomWindow
extends Control
## 「聊天室式」/「簡訊式」對話顯示(見 AppSettings.bubble_display_mode()):不用等使用者互動的句子
## (閒聊、狀態播報…)改寫進這個可拖曳/可縮放/可收合的半透明黑色視窗,而不是各自貼在桌寵旁邊的浮動氣泡。
## 兩種模式共用同一個視窗、同一套路由規則,只差在每一句訊息怎麼畫:
##  - 聊天室式(_make_chatroom_row):一行純文字「桌寵名字: 台詞」,思考泡泡是「桌寵名字oO( 台詞 )」,
##    文字顏色跟著那隻桌寵原本會用的泡泡外框色(見 DialogueBubble.chat_color()),太暗時額外加白色外框線,
##    滑鼠指到那一行時用稍淺的顏色框住(2026-10-02 使用者要求的易讀設計,見 _make_hover_row)。
##  - 簡訊式(_make_sms_bubble,2026-10-02 新增):圓角訊息氣泡,底色是那隻桌寵原本的泡泡外框色,
##    內文字色依「背景夠不夠亮」的同一套規則(跟做名字標籤 UiStyleKit.name_tag() 用的邏輯相同)選黑或白,
##    桌寵的名字寫在氣泡左上角、用外框色本身(不是黑白)。
## 每一行/每一顆氣泡的字型與字級照那隻桌寵自己的介面風格走(PetUiStyle),不是整個聊天室共用同一種——
## 桌寵各自調過的字體/字級在聊天室裡看起來要跟浮動氣泡一致。
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
## 時間戳(2026-10-02 使用者要求,見 AppSettings.chatroom_timestamp_mode()):用小小的灰色字顯示在每則
## 訊息底下,寫的是「記下這則訊息的當下」裝置系統時間(不是事後重算/不是遊戲內時間)。
const TIMESTAMP_COLOR := Color(0.75, 0.75, 0.75, 0.85)
const TIMESTAMP_FONT_SIZE := 10

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
## 目前實際套用中的顯示模式("chatroom"/"sms"),切換時用來判斷是不是真的換了樣式(見 refresh_setting())。
var _last_render_mode := ""
## 聊天記錄的原始資料(不是畫面節點),每筆 {pet, text, color, is_thought, chain, hour, minute}——
## 2026-10-02 使用者實機回報:切換聊天室式/簡訊式時之前的版本直接清空畫面,對話紀錄真的不見了,不能這樣。
## 改成保留這份原始資料,切換樣式時用新樣式把它整個重畫一次(見 _rebuild_content()),訊息本身不會消失。
## 跟畫面的 _list 一樣裁到 MAX_LINES(append_line() 裡兩邊同步裁,永遠维持一致)。
var _history: Array[Dictionary] = []
## 簡訊式的連續同一桌寵訊息分組(2026-10-02 使用者要求,見 _make_sms_bubble()/append_line() 的說明):
## 最近一則簡訊氣泡是哪隻桌寵、它目前用的 StyleBoxFlat(方便之後被接續時直接改圓角,不用整顆重建)、
## 目前這串連續發話已經有幾則。切換顯示模式清空聊天記錄時要一併重置,不然清空後的第一則會誤判成接續。
var _sms_last_pet: Node = null
var _sms_last_box: StyleBoxFlat = null
var _sms_run_length := 0
## 目前追蹤的 _sms_last_box 是不是這串連續發話「第一則」用的那顆(show_name = true 建立的);第一則被接續
## 時除了把左下角改直角,左上角還要從直角promote成圓角(單則訊息跟「第一則」的初始外觀是同一個形狀——
## 左上角直角、其餘圓角——建立當下分不出來之後會不會被接續,所以都先當單則畫,真的被接上才補畫成第一則)。
var _sms_last_is_run_start := false
## 上一則是不是「安排好的連續發話事件」的一部分(line["chain"],見 GameChat.say()/LogicInterpreter._dialogue_line()
## 的說明)——2026-10-02 使用者更正:單句閒聊即使剛好跟前一句同一隻桌寵、緊接著出現,也不算連續發話,
## 只有事先安排成一串的才算(這包含遊戲/對戰對話)。接續的判定要「這一則」跟「上一則」都是 chain 才算,
## 只看同一隻桌寵、不看 chain 的話,兩個沒關係的單句事件湊巧連續出現會被誤判成一組。
var _sms_last_was_chain := false
## 上一則(目前追蹤的終點)的時間戳 Label,如果有的話——真的被接續時要拿掉(2026-10-02 使用者要求:
## 連續發話只在最後一則才寫時間戳,不是每一則都寫),等新的終點出現才換那顆顯示。
var _sms_last_timestamp_label: Label = null
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
	# 每則對話之間的行距(不是同一則裡自動換行那幾行字之間的行距,那個是 RichTextLabel 自己的字型行高,
	# 不歸這裡管)——2026-10-02 使用者要求拉大一點,從 2 調成 9;後來實機看覺得太大,再調回 6。
	_list.add_theme_constant_override("separation", 6)
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
## 或開機時第一次套用:視窗要不要顯示跟著目前模式走。聊天室式/簡訊式之間切換時視窗要「及時切換」——
## 舊訊息是用舊樣式畫的(純文字一行 vs 圓角氣泡),混在一起會很怪,但切換完對話紀錄一定要還在
## (2026-10-02 使用者實機回報:先前版本切換時直接清空畫面,紀錄真的不見了,不能這樣)——改成用保留的
## 原始資料(_history)在新樣式下整個重畫一次,見 _rebuild_for_mode_switch()。
func refresh_setting() -> void:
	var mode := AppSettings.bubble_display_mode()
	visible = mode == "chatroom" or mode == "sms"
	if visible and _last_render_mode != "" and _last_render_mode != mode:
		_rebuild_content()
	if visible:
		_last_render_mode = mode


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
		# 2026-10-02 使用者實機回報:收合鈕貼太右邊,超出視窗右邊框了,往左推一點(24 → 28)。
		_collapse_button.position = Vector2(_window_size.x - 28.0, 3.0)
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
## chain:這句是不是「安排好的連續發話事件」的一部分(line["chain"],見 GameChat.say()/
## LogicInterpreter._dialogue_line() 的說明)——只有這個是 true,簡訊式才會考慮把它跟上一則同一隻桌寵的
## 訊息分成一組;單句閒聊(chain = false)即使剛好同一隻桌寵連續說,也一律各自獨立顯示。
func append_line(pet: Node, text: String, color: Color, is_thought: bool = false, chain: bool = false) -> void:
	if _list == null or not is_instance_valid(pet):
		return
	# 加新行之前先記住「使用者現在是不是已經捲到底」——只有原本就在底部才跟著捲到新訊息;使用者捲上去看
	# 歷史記錄時,不應該被新訊息硬拉回底部(標準聊天視窗的「貼底」行為)。
	var was_at_bottom := _is_scrolled_to_bottom()
	# 時間戳的「當下裝置時間」只在這裡(真的記錄這句的那一刻)抓一次,存進 _history——重畫(切換樣式、切換
	# 時間戳顯示設定)時要照這個存下來的時間重新排版,不能每次重畫都重抓「現在」的時間,不然舊訊息的時間戳
	# 會跟著亂跳(2026-10-02 使用者要求「切換時間戳設定時也要即時變更」,連動想清楚才不會做出這個副作用)。
	var logged_time := Time.get_time_dict_from_system()
	_history.append({"pet": pet, "text": text, "color": color, "is_thought": is_thought, "chain": chain, "hour": int(logged_time["hour"]), "minute": int(logged_time["minute"])})
	if _history.size() > MAX_LINES:
		_history.pop_front()
	_build_row(pet, text, color, is_thought, chain, int(logged_time["hour"]), int(logged_time["minute"]))
	if was_at_bottom:
		# 剛加進去的節點,ScrollContainer 的捲動範圍(max_value)這一影格還沒重算完,現在就設 scroll_vertical
		# 只會被夾到「舊的」上限,停在原地看起來像沒有跟著捲。等一影格讓版面(尤其是 RichTextLabel 自動換行
		# 的高度)真正定下來,再設一次才會真的貼到底。同一影格內連續呼叫好幾次 append_line() 只會疊出
		# 好幾個等價的延後呼叫,結果都一樣、沒有副作用。
		_scroll_to_bottom_next_frame()


## 依目前的顯示模式(聊天室式/簡訊式)建一顆訊息節點、加進 _list,並裁到 MAX_LINES——append_line()(正常
## 新增一句)跟 _rebuild_content()(切換樣式/切換時間戳設定時從 _history 整個重畫)共用同一份畫法,
## 不重複邏輯。不動 _history(那是 append_line() 自己的事;重畫時不該再往 _history 疊一次)。
## chain:這句是不是「安排好的連續發話事件」的一部分(見 append_line() 的說明)。
## hour/minute:這句「被記錄當下」的裝置時間(見 append_line()),時間戳一律照這個算,不是重畫當下的
## 「現在」——不然舊訊息重畫後時間戳會跟著亂跳。
func _build_row(pet: Node, text: String, color: Color, is_thought: bool, chain: bool, hour: int, minute: int) -> void:
	var row: Control
	if AppSettings.bubble_display_mode() == "sms":
		# 連續同一桌寵發話分組(2026-10-02 使用者要求,只在簡訊式套用):跟上一則是同一隻桌寵發的「而且
		# 兩則都是安排好的連續發話事件(chain)」才算接續——2026-10-02 使用者更正:單句閒聊不算,即使剛好
		# 同一隻桌寵連續說也不算,只看「同一隻桌寵」會分不出「這幾則是同一個事件」還是「兩個無關的單句事件
		# 湊巧連在一起」,一定要兩則都帶 chain 才行。接續時名字不再重複顯示,且要把「上一則」的左下角改
		# 直角(降格成中段或補畫成第一則,見 _make_sms_bubble 的說明);這一則變成新的終點(左上角直角、
		# 左下角圓角,跟單則訊息初始畫的形狀一樣)。
		var is_continuation := is_instance_valid(_sms_last_pet) and _sms_last_pet == pet and chain and _sms_last_was_chain
		var box_ref: Array[StyleBoxFlat] = [null]
		row = _make_sms_bubble(pet, text, color, is_thought, not is_continuation, box_ref)
		if is_continuation and _sms_last_box != null:
			var direction := _sms_direction_of(pet)
			_sms_last_box.set(_sms_corner_property(direction, "bottom"), 0)
			if _sms_last_is_run_start:
				# 上一則原本當「單則」畫(左上角/右上角直角),現在確定不是單則了,補畫成「第一則」(那個角變圓角)。
				var promoted_factor: float = float(_sms_bubble_scale_of(pet)) / 100.0
				_sms_last_box.set(_sms_corner_property(direction, "top"), int(SMS_BUBBLE_RADIUS * promoted_factor))
			_sms_run_length += 1
			# 連續發話只在「最後一則」寫時間戳(2026-10-02 使用者要求):上一則不再是終點了,把它的時間戳
			# 拿掉,新的終點(這一則)才會顯示時間戳。
			if _sms_last_timestamp_label != null and is_instance_valid(_sms_last_timestamp_label):
				var old_parent := _sms_last_timestamp_label.get_parent()
				if old_parent != null:
					old_parent.remove_child(_sms_last_timestamp_label)
				_sms_last_timestamp_label.queue_free()
				_sms_last_timestamp_label = null
		else:
			_sms_run_length = 1
		_sms_last_pet = pet
		_sms_last_box = box_ref[0]
		_sms_last_is_run_start = not is_continuation
		_sms_last_was_chain = chain
		_sms_last_timestamp_label = _append_timestamp(row as VBoxContainer, pet, hour, minute)
	else:
		var label := _make_line_label(pet, text, color, is_thought)
		var content: Control = label
		if AppSettings.chatroom_timestamp_mode() != "none":
			# 時間戳開著才多包一層 VBox(label + 時間戳兩行);沒開就照舊直接用 label,不多套一層,盡量不
			# 動到原本的節點結構(t168 等既有測試沒開時間戳,直接讀 hover row 底下第一個子節點就是 label)。
			var column := VBoxContainer.new()
			column.add_theme_constant_override("separation", 0)
			column.mouse_filter = Control.MOUSE_FILTER_PASS
			column.add_child(label)
			_append_timestamp(column, pet, hour, minute)
			content = column
		row = _make_hover_row(content)
	_list.add_child(row)
	_line_count += 1
	# remove_child() 先同步把最舊的那行從 _list 拿掉,再 queue_free()——queue_free() 本身是延遲到影格尾端
	# 才真的離開場景樹,這一幀之內連續呼叫好幾次(例如遊戲短時間內連續好幾句,或重畫時一次補一大串)的話,
	# 只用 queue_free() 會讓 get_child(0) 一直讀到同一個「還沒真的被拿掉」的舊節點,越修剪反而越修不掉。
	if _line_count > MAX_LINES and _list.get_child_count() > 0:
		var oldest := _list.get_child(0)
		_list.remove_child(oldest)
		oldest.queue_free()
		_line_count -= 1


## 聊天室式/簡訊式之間切換、或時間戳顯示設定改變時用(見 refresh_setting()/refresh_timestamps()):不是
## 清空,是保留的原始資料(_history)在新設定下整個重畫一次——舊訊息不會不見,只是改用新樣式/新的時間戳
## 顯示方式重新畫出來(2026-10-02 使用者實機回報:之前直接清空的做法不能接受,對話紀錄要留著;使用者
## 接著要求切換時間戳設定也要即時生效,同一套重畫機制剛好可以直接重用)。畫面節點跟簡訊式的分組狀態都要
## 先歸零重來,不然會把上一輪的殘留節點/分組狀態(例如 _sms_last_pet 還記得舊的)誤帶進這一輪。每則的
## 時間戳照 _history 存的「原始記錄時間」重算,不是重畫當下的「現在」。
func _rebuild_content() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_line_count = 0
	_sms_last_pet = null
	_sms_last_box = null
	_sms_run_length = 0
	_sms_last_is_run_start = false
	_sms_last_was_chain = false
	_sms_last_timestamp_label = null
	for entry: Dictionary in _history:
		var entry_pet: Node = entry["pet"]
		if is_instance_valid(entry_pet):
			_build_row(entry_pet, str(entry["text"]), entry["color"], bool(entry["is_thought"]), bool(entry.get("chain", false)), int(entry["hour"]), int(entry["minute"]))


## 不用切換聊天室式/簡訊式,現有訊息也要立刻套用新樣式的場合都呼叫這個(見 "dialogue_display" 群組廣播):
## 全局設定的「時間戳」下拉選單改了(app_settings_tab.gd);桌寵管理「聊天室設定」卡片的「即使存在聊天室
## 也顯示氣泡」「簡訊式發言方向」「簡訊氣泡外觀」任一項改了(style_editor_tab.gd)——2026-10-02 使用者
## 要求這些設定都要「即時變更」,不用等下一則新訊息才看得到差異。
func refresh_content() -> void:
	if visible:
		_rebuild_content()
	_scroll_to_bottom_next_frame()


func _scroll_to_bottom_next_frame() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 2147483647


## 目前這一刻的裝置系統時間,依 AppSettings.chatroom_timestamp_mode() 排版;"none" 回空字串。
static func _format_timestamp() -> String:
	var t := Time.get_time_dict_from_system()
	return _format_timestamp_value(int(t["hour"]), int(t["minute"]))


## 依目前的時間戳顯示設定("none"/"12h"/"24h")排版給定的時分;"none" 回空字串。hour/minute 是「這句話
## 被記錄當下」的時間(見 append_line()/_history),不是呼叫當下的「現在」,不然重畫舊訊息時時間戳會亂跳。
static func _format_timestamp_value(hour: int, minute: int) -> String:
	var mode := AppSettings.chatroom_timestamp_mode()
	if mode == "none":
		return ""
	if mode == "24h":
		return "%02d:%02d" % [hour, minute]
	var hour12 := hour % 12
	if hour12 == 0:
		hour12 = 12
	return "%d:%02d %s" % [hour12, minute, "AM" if hour < 12 else "PM"]


## 時間戳關著("none")什麼都不加,容器不變。開著才加一行小小的灰色字。
## 回傳新建的時間戳 Label(沒加就回 null)——簡訊式的連續發話要記住這個回傳值,接續時可能要整個拿掉
## (見 _build_row() 的說明,只有「最後一則」該留著時間戳)。
func _append_timestamp(container: VBoxContainer, pet: Node, hour: int, minute: int) -> Label:
	var text := _format_timestamp_value(hour, minute)
	if text == "" or container == null:
		return null
	var style: PetUiStyle = pet.ui_style if is_instance_valid(pet) else null
	var font := UiFonts.get_font(str(style.default_font)) if style != null else UiFonts.get_font("")
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", TIMESTAMP_FONT_SIZE)
	label.add_theme_color_override("font_color", TIMESTAMP_COLOR)
	container.add_child(label)
	return label


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


## 滑鼠指到一則台詞時用稍淺的顏色框住那一行,方便閱讀(2026-10-02 使用者要求)。用兩份 StyleBoxFlat
## 切換(而不是單純畫一條線),平時透明、hover 時淡淡一圈邊框 + 一點點填色;兩份的內距一樣,切換時文字
## 不會跟著跳位置。只用在「聊天室式」的純文字行;簡訊式的氣泡本身已經有底色,不需要再疊一層。
const HOVER_ROW_MARGIN := 3.0


func _make_hover_row(content: Control) -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	empty.border_color = Color(1.0, 1.0, 1.0, 0.0)
	empty.set_border_width_all(1)
	empty.set_corner_radius_all(4)
	empty.set_content_margin_all(HOVER_ROW_MARGIN)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.07)
	hover.border_color = Color(1.0, 1.0, 1.0, 0.3)
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(HOVER_ROW_MARGIN)
	row.add_theme_stylebox_override("panel", empty)
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", hover))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", empty))
	row.add_child(content)
	return row


## 「簡訊式」的一則訊息:上面一行是桌寵名字(用外框色本身寫,跟做名字標籤同一個位置概念——貼在氣泡左上角),
## 下面是圓角訊息氣泡,底色是那隻桌寵原本的泡泡外框色,內文字色依「背景夠不夠亮」選黑或白——跟
## UiStyleKit.name_tag() 決定標籤文字顏色用的是同一套規則(那裡的標籤底色也剛好是同一個外框色)。
## 圓角刻意留成幾乎是圓形的大小,只有左上角是直角,模擬經典訊息氣泡的尖角效果(2026-10-02 使用者更正:
## 原本講成左下角是講錯了,單則訊息要左上角直角才對)。換行前的最大寬度(縮放前基準值)也是每隻桌寵自己
## 設定的(InteractionRules.DEFAULT_SMS_BUBBLE_WIDTH 是沒設過時的預設值,見 _sms_bubble_width_of())。
const SMS_BUBBLE_RADIUS := 16
## 氣泡自動縮短到貼合文字時,句尾留的呼吸空間(2026-10-02 使用者要求;原本想留 17px,後來覺得不用那麼多,
## 改成 1px——純粹防呆極短句/空字串不會整個貼死沒有邊距,不是真的要留出視覺上的尾端留白)。
const TAIL_PADDING := 1.0


## 這隻桌寵的簡訊式氣泡靠哪一側("left"/"right",桌寵管理「介面與自動行為 > 聊天室設定」卡片設定,
## 存在 interaction_rules 的 sms_direction,預設 "left")。
static func _sms_direction_of(pet: Node) -> String:
	if not is_instance_valid(pet):
		return "left"
	var direction := str((pet.interaction_rules as Dictionary).get("sms_direction", "left"))
	return "right" if direction == "right" else "left"


## direction 這一側、side("top"/"bottom")那一排的「尖角/直角」要改的是哪個 StyleBoxFlat 角落屬性——
## "left" 一律動左側兩角(corner_radius_top_left/corner_radius_bottom_left),"right" 鏡射動右側兩角。
static func _sms_corner_property(direction: String, side: String) -> String:
	var edge := "right" if direction == "right" else "left"
	return "corner_radius_%s_%s" % [side, edge]


## 這隻桌寵的簡訊式氣泡外觀縮放百分比(PetUiStyle.SCALE_STEPS 其中一檔,桌寵管理「聊天室設定」卡片的
## 「簡訊氣泡外觀」設定,存在 interaction_rules 的 sms_bubble_scale,預設 100)——2026-10-02 使用者要求
## 跟這隻桌寵「字體與對話」的「字級」(style.text_scale_factor())分開,簡訊式氣泡不要跟著字級一起縮放。
static func _sms_bubble_scale_of(pet: Node) -> int:
	if not is_instance_valid(pet):
		return 100
	return PetUiStyle.nearest_scale_step(int((pet.interaction_rules as Dictionary).get("sms_bubble_scale", 100)))


## 這隻桌寵的簡訊式氣泡換行前最大寬度(縮放前基準值,桌寵管理「聊天室設定」卡片的「簡訊氣泡最大寬度」,
## 存在 interaction_rules 的 sms_bubble_width,預設 InteractionRules.DEFAULT_SMS_BUBBLE_WIDTH)。
static func _sms_bubble_width_of(pet: Node) -> float:
	if not is_instance_valid(pet):
		return InteractionRules.DEFAULT_SMS_BUBBLE_WIDTH
	return float((pet.interaction_rules as Dictionary).get("sms_bubble_width", InteractionRules.DEFAULT_SMS_BUBBLE_WIDTH))


## show_name:是不是這一串連續發話的第一則(見 append_line() 的分組說明);不是第一則就不畫名字標籤。
## box_out:長度至少 1 的陣列,回傳時 box_out[0] 會被設成這顆氣泡用的 StyleBoxFlat,呼叫端接續下一則時
## 要改它的圓角(不用整顆重建)——GDScript 沒有「回傳多個值」或「輸出參數」,這是最直接的替代寫法。
##
## 圓角規則(2026-10-02 使用者要求,同一天更正過左上/左下方向):單獨一則訊息(或還不知道會不會被接續的
## 「暫定單則」)一律只有「發言方向那一側的上角」是直角、其餘圓角,當作氣泡尖角(預設方向是左,所以預設
## 是左上角;桌寵管理可以把這隻桌寵的方向改成右,整個鏡射到右側,見 _sms_direction_of()/_sms_corner_property())。
## 這裡每一顆新氣泡建立當下一律先畫成這個「暫定單則」形狀(不管 show_name 是不是接續——建立的時候還不
## 知道「之後」會不會有人接上來,只能先當單則畫);真的被下一則接上時,呼叫端(append_line)才回頭把這
## 一則改畫(同一側的上/下角互換直角圓角,邏輯跟方向無關,只是動哪個屬性名稱依方向決定):
##  - 如果這一則本來就是某串連續發話的「第一則」(show_name = true 建的):該側上角補畫成圓角、下角改
##    直角,變成「第一則」樣式。
##  - 如果這一則本身已經是接續(show_name = false 建的,原本是「暫定終點」):該側下角改直角,上角維持
##    直角不變,變成「中段」樣式(上下都直角)。
## 這樣整串連續發話,視覺上會從第一則的下角、經過中段兩側、到最後一則(仍是「暫定終點」形狀)的上角,
## 連成一條平整的邊線(方向那一側);整條的最頂端(第一則上角)跟最底端(最後一則下角)維持圓角,像一條
## 兩端圓潤、中間貼合的氣泡鏈。文字內容、姓名條、時間戳一律不鏡射,始終在氣泡自己的左側/左上/左下角。
func _make_sms_bubble(pet: Node, text: String, color: Color, is_thought: bool, show_name: bool, box_out: Array) -> Control:
	var style: PetUiStyle = pet.ui_style
	var font := UiFonts.get_font(str(style.default_font)) if style != null else UiFonts.get_font("")
	# 簡訊式氣泡外觀(圓角/內距/寬度/字級)的縮放跟這隻桌寵「字體與對話」的「字級」分開設定(2026-10-02
	# 使用者要求:簡訊式氣泡本來跟著字級一起縮放,不想要這樣),改讀「聊天室設定」卡片自己的
	# sms_bubble_scale,不呼叫 style.text_scale_factor()。
	var factor: float = float(_sms_bubble_scale_of(pet)) / 100.0
	var direction := _sms_direction_of(pet)

	var outer := VBoxContainer.new()
	# 靠左(預設)或靠右貼齊聊天室視窗邊框,寬度只跟著內容走,不撐滿整個視窗寬度。
	outer.size_flags_horizontal = Control.SIZE_SHRINK_END if direction == "right" else Control.SIZE_SHRINK_BEGIN
	outer.add_theme_constant_override("separation", 1)
	outer.mouse_filter = Control.MOUSE_FILTER_PASS

	if show_name:
		var name_label := Label.new()
		name_label.text = pet.get_label()
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_override("font", font)
		name_label.add_theme_font_size_override("font_size", int((UiStyleKit.BASE_FONT_SIZE - 3) * factor))
		name_label.add_theme_color_override("font_color", color)
		if color.get_luminance() < DARK_LUMINANCE_THRESHOLD:
			name_label.add_theme_color_override("font_outline_color", Color.WHITE)
			name_label.add_theme_constant_override("outline_size", 3)
		outer.add_child(name_label)

	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := StyleBoxFlat.new()
	# 思考泡泡(2026-10-02 使用者要求):改用思考泡泡自己的外框色(color 參數本來就已經是 is_thought 時
	# 該用的那個顏色,見 DialogueBubble.chat_color()),而且不整顆填色,只畫外框線——跟一般說話泡泡的
	# 實心填色外觀區分開來。
	if is_thought:
		box.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		box.border_color = color
		box.set_border_width_all(maxi(int(2.0 * factor), 1))
	else:
		box.bg_color = color
	# 建立當下一律先畫成「暫定單則」形狀(發言方向那一側的上角直角、其餘圓角),不管 show_name——理由見
	# 上面函式開頭的說明,之後真的被接續才由 append_line() 回頭改。
	var radius := int(SMS_BUBBLE_RADIUS * factor)
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_right = radius
	box.corner_radius_bottom_left = radius
	box.set(_sms_corner_property(direction, "top"), 0)
	box.set_content_margin_all(10.0 * factor)
	bubble.add_theme_stylebox_override("panel", box)
	if not box_out.is_empty():
		box_out[0] = box

	var label := RichTextLabel.new()
	label.bbcode_enabled = false
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = false
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	var font_size := int(UiStyleKit.BASE_FONT_SIZE * factor)
	label.add_theme_font_override("normal_font", font)
	label.add_theme_font_size_override("normal_font_size", font_size)
	if is_thought:
		# 底色不是實心填滿了(只有外框線),黑/白對比那套規則沒有意義——直接用外框色本身當字色,
		# 太暗的話照 _make_line_label 同一套規則加白色外框線撐出對比(背景是聊天室的深色底)。
		label.add_theme_color_override("default_color", color)
		if color.get_luminance() < DARK_LUMINANCE_THRESHOLD:
			label.add_theme_color_override("font_outline_color", Color.WHITE)
			label.add_theme_constant_override("outline_size", 2)
	else:
		label.add_theme_color_override("default_color", Color.BLACK if color.get_luminance() > 0.5 else Color.WHITE)
	var display_text := "( %s )" % text if is_thought else text
	label.text = display_text
	# 氣泡寬度不是每則都撐滿「簡訊氣泡最大寬度」——那是換行前的上限,文字本來就沒那麼長時氣泡要跟著縮短
	# (2026-10-02 使用者要求):量這句話單行會有多寬,句尾留 TAIL_PADDING 的呼吸空間(原本想留 17px,
	# 使用者後來覺得不用那麼多,改成 1px,只是防呆空字串/極短句不會整個貼死沒有一點邊距),跟「最大寬度」
	# 取比較小的那個當最小寬度;比最大寬度還長的句子照舊在上限處自動換行(min() 夾住,不會超過上限)。
	var max_width := _sms_bubble_width_of(pet) * factor
	var natural_width := font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	label.custom_minimum_size.x = minf(natural_width + TAIL_PADDING * factor, max_width)
	bubble.add_child(label)
	outer.add_child(bubble)
	return outer


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
