extends Node
## 桌寵的滑鼠互動(主企劃書第四章模組 D):點擊、拖曳、摸摸(搖晃滑鼠),
## 以及短時間內點擊/摸摸次數達標時自動觸發 interact 動作。只發訊號與計數,
## 實際的反應(對話、特效、數值)由事件積木或預設設定決定,這裡不寫死。
##
## 拖曳期間桌寵座標即時錨定在滑鼠上並播放 drag;放開時把拖曳速度當成初速度拋出。
## 右鍵穿透凍結期間不處理任何輸入(見 DesktopShellState.is_passthrough_frozen)。

signal clicked
## 連按兩下(兩次點擊間隔不超過 DOUBLE_CLICK_TIME 秒)。
signal double_clicked
signal petted
## 摸摸期間每偵測到一次來回搖晃就發一次(比 petted 更頻繁),讓桌寵知道「手還在摸」,把摸摸反應延長到停手後一秒。
signal petting_moved
signal drag_started
signal drag_ended
signal interact_triggered
## 在桌寵身上按右鍵(不論穿透與否都只在桌寵本身的範圍內),由 Pet 決定要開什麼選單。
signal context_menu_requested

## 短時間滑動窗口內的點擊/摸摸次數達到門檻,就觸發 interact(例如 2 秒內 6 次)。
@export var interact_threshold := 6
@export var interact_window := 2.0
@export var interact_duration := 1.5

const CLICK_MAX_MOVE := 6.0
const CLICK_MAX_TIME := 0.6
const DOUBLE_CLICK_TIME := 0.45
## 摸摸要「久一點」才成立:在 PET_WINDOW 秒內來回搖晃 PET_REVERSALS 次,而且每一下至少要滑 PET_MIN_STROKE 像素(手抖一下不算)。
const PET_REVERSALS := 8
const PET_WINDOW := 2.0
const PET_MIN_STROKE := 14.0
const PET_COOLDOWN := 1.2
const THROW_MAX_SPEED := 1400.0

## 專屬行為計數器(點擊、摸摸、拖曳、跟隨次數)。
var click_count := 0
var pet_count := 0
var drag_count := 0
var follow_count := 0

var _pet: CharacterBody2D
var _shell_state: Node
var _mouse := Vector2.ZERO
var _pressing := false
var _dragging := false
var _press_position := Vector2.ZERO
var _press_time := 0.0
var _grab_offset := Vector2.ZERO
var _last_drag_position := Vector2.ZERO
var _drag_velocity := Vector2.ZERO
var _events: Array[float] = []
var _reversals: Array[float] = []
var _last_direction := 0.0
var _stroke := 0.0
var _pet_cooldown_until := 0.0


func setup(pet: CharacterBody2D) -> void:
	_pet = pet
	_shell_state = get_node("/root/DesktopShellState")
	_shell_state.passthrough_started.connect(_cancel)


## 滑鼠下同時有好幾隻桌寵重疊時,一次只讓一隻收到按壓/右鍵/摸摸,不然會把重疊的全部抓起來:
## 正在被拖曳的那隻優先;其次是「有畫東西的像素」剛好在滑鼠下的(pixel_precise 時才檢查,摸摸的每次滑鼠移動用矩形就好);
## 再來是畫在最上面的(同一個圖層裡節點順序最後的)。沒有任何一隻在滑鼠下回傳 null。
static func topmost_pet_at(tree: SceneTree, point: Vector2, pixel_precise := false) -> Node:
	var hits: Array = []
	for pet: Node in tree.get_nodes_in_group("pets"):
		if not pet.is_queued_for_deletion() and pet.hit_test(point):
			hits.append(pet)
	if hits.is_empty():
		return null
	for pet: Node in hits:
		if pet.dragging:
			return pet
	if pixel_precise:
		var opaque: Array = hits.filter(func(pet: Node) -> bool: return pet.pixel_hit(point))
		if not opaque.is_empty():
			hits = opaque
	var best: Node = hits[0]
	for pet: Node in hits:
		# 畫在前面的優先:先比圖層(z_index,半身立繪在後面的帶裡),同一層再比節點順序。
		if pet.z_index > best.z_index or (pet.z_index == best.z_index and pet.get_index() > best.get_index()):
			best = pet
	return best


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		# 直接用事件帶的座標(換算成畫布座標),不依賴 get_global_mouse_position()。
		_mouse = _pet.get_viewport().get_canvas_transform().affine_inverse() * event.position
	if _shell_state.is_passthrough_frozen:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press()
		else:
			_on_release()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# 右鍵點在桌寵身上:開桌寵選單,並標記已處理,避免行動區把它當成「右鍵暫時穿透」的觸發。
		if topmost_pet_at(get_tree(), _mouse, true) == _pet:
			get_viewport().set_input_as_handled()
			context_menu_requested.emit()
	elif event is InputEventMouseMotion:
		_on_motion(event)


func _physics_process(delta: float) -> void:
	if not _dragging:
		return
	var target: Vector2 = _pet.clamp_to_bounds(_mouse + _grab_offset)
	_drag_velocity = _drag_velocity.lerp((target - _last_drag_position) / delta, 0.35)
	_last_drag_position = target
	_pet.global_position = target
	_pet.velocity = Vector2.ZERO


var _last_click_time := -100.0


func _on_press() -> void:
	if prop_dragging():
		return
	if topmost_pet_at(get_tree(), _mouse, true) != _pet:
		return
	# 點到的這隻浮到最上面(同一個圖層的最後一個節點),下次重疊時它會優先被抓。
	var layer := _pet.get_parent()
	if layer != null:
		layer.move_child(_pet, -1)
	_pressing = true
	_press_position = _mouse
	_press_time = _now()
	_grab_offset = _pet.global_position - _mouse
	_last_drag_position = _pet.global_position
	_drag_velocity = Vector2.ZERO


func _on_release() -> void:
	if _dragging:
		_dragging = false
		_pressing = false
		_pet.end_drag(_drag_velocity.limit_length(THROW_MAX_SPEED))
		_try_drop_on_furniture()
		drag_ended.emit()
		return
	if _pressing and _now() - _press_time <= CLICK_MAX_TIME:
		click_count += 1
		_register_event()
		clicked.emit()
		if _now() - _last_click_time <= DOUBLE_CLICK_TIME:
			_last_click_time = -100.0
			double_clicked.emit()
		else:
			_last_click_time = _now()
	_pressing = false


func _on_motion(event: InputEventMouseMotion) -> void:
	if _pressing and not _dragging:
		if _mouse.distance_to(_press_position) > CLICK_MAX_MOVE and _pet.can_drag():
			_dragging = true
			drag_count += 1
			_pet.begin_drag()
			drag_started.emit()
		return
	if prop_dragging():
		_reversals.clear()   # 抓著道具在桌寵身上摩擦不算摸摸(道具自己的摩擦判定在 PropManager)
		_last_direction = 0.0
		_stroke = 0.0
		return
	if not _pressing and topmost_pet_at(get_tree(), _mouse) == _pet:
		_track_petting(event.relative.x)


## 放開拖曳時,桌寵剛好落在某件家具的範圍內就直接自動去用(反向的拖曳互動:道具是拖到桌寵身上,這個是拖桌寵去用家具)。
## 挑放開點附近最近的一個目前沒人用的錨點;找不到(家具沒有錨點、都被佔用、或放開點根本沒碰到任何家具)就什麼都不做,
## 照原本的拋擲行為走。
func _try_drop_on_furniture() -> void:
	var point: Vector2 = _pet.global_position
	for node: Node in get_tree().get_nodes_in_group("furniture"):
		var item := node as FurnitureItem
		if item == null or not item.touch_rect().has_point(point):
			continue
		var wanted_type := item.nearest_free_anchor_type(point)
		if wanted_type != "":
			_pet.use_furniture(item, wanted_type)
			return


## 使用者現在是不是正抓著一個道具(從桌面抓起或從道具欄拖出來)。
func prop_dragging() -> bool:
	for manager: Node in get_tree().get_nodes_in_group("prop_manager"):
		if manager.dragged != null:
			return true
	return false


## 在桌寵身上來回搖晃滑鼠(水平方向在短時間內反轉數次)視為「摸摸」。
func _track_petting(relative_x: float) -> void:
	if absf(relative_x) < 2.0:
		return
	var now := _now()
	var direction := signf(relative_x)
	if _last_direction != 0.0 and direction != _last_direction:
		if _stroke >= PET_MIN_STROKE:
			_reversals.append(now)
			petting_moved.emit()
		_stroke = 0.0
	_stroke += absf(relative_x)
	_last_direction = direction
	while not _reversals.is_empty() and now - _reversals[0] > PET_WINDOW:
		_reversals.pop_front()
	if _reversals.size() >= PET_REVERSALS and now >= _pet_cooldown_until:
		_reversals.clear()
		_pet_cooldown_until = now + PET_COOLDOWN
		pet_count += 1
		_register_event()
		petted.emit()


## 點擊與摸摸共用同一個滑動窗口,達標就觸發 interact;窗口是獨立的短期暫存,不計入累計計數器。
func _register_event() -> void:
	var now := _now()
	_events.append(now)
	while not _events.is_empty() and now - _events[0] > interact_window:
		_events.pop_front()
	if _events.size() >= interact_threshold:
		_events.clear()
		_pet.begin_interact(interact_duration)
		interact_triggered.emit()


## 穿透凍結開始時取消進行中的按壓/拖曳,避免放開事件收不到而卡在拖曳狀態。
func _cancel() -> void:
	if _dragging:
		_pet.end_drag(Vector2.ZERO)
		drag_ended.emit()
	_dragging = false
	_pressing = false


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
