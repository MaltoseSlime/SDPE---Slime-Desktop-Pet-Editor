class_name PropManager
extends Node2D
## 桌面上的小道具管理:丟一個道具到桌面(spawn)、逾時自動消失、丟入拾取判定。
## 拾取判定:道具的碰觸範圍與任一隻桌寵的互動範圍重疊就成立,而且**只有一隻**觸發(同一影格有好幾隻重疊時取離道具最近的),
## 觸發後道具自場景移除(可持有的道具改成記在桌寵身上)。睡著、被拖曳、還在進場的桌寵不會去拿。
## 桌面上的道具都能用滑鼠抓起來拖曳(調整位置、丟出去、拖到桌寵身上餵食);有「拖曳中吸引」的道具被拖著時,場上可被吸引的桌寵會追著它走。
## 判定用物理影格輪詢(場上道具最多 MAX_ITEMS 個,每個只和在場桌寵比矩形,很輕)。

signal prop_collected(def: PropDef, pet: Node)
## 貼身摩擦達到判定(拖著道具在桌寵身上來回摩擦)。
signal prop_rubbed(def: PropDef, pet: Node)
## 拖著的道具碰到(或離開)一隻桌寵:pet 是放開後會被套用的那一隻(null = 沒有)。
signal candidate_changed(def: PropDef, pet: Node)

const MAX_ITEMS := 30
## 貼身摩擦判定(比照摸摸):道具的水平來回,單次行程至少 RUB_MIN_STROKE 像素,RUB_WINDOW 秒內折返 RUB_REVERSALS 次;觸發後冷卻 RUB_COOLDOWN 秒。
const RUB_MIN_STROKE := 14.0
const RUB_REVERSALS := 4
const RUB_WINDOW := 1.2
const RUB_COOLDOWN := 1.5
## 桌寵拿到任何道具(collect(),不分道具種類)之後,這麼多秒內不會再自己去拿下一個,避免多隻桌寵在場時
## 食物之類的道具總是被同一隻先撿走用掉。使用者手動把道具拖去餵給某隻(delivered_to)不受這個限制。
const PICKUP_COOLDOWN := 5.0

var _action_area: Node
var items: Array[PropItem] = []
## 正被使用者拖曳的道具(一次只有一個)與最近的滑鼠畫布座標。
var dragged: PropItem
var _mouse := Vector2.ZERO
var candidate: Node
var _marker: PropCandidateMarker
var _rub_extreme := 0.0
var _rub_dir := 0
var _rub_started := false
var _rub_events: Array[float] = []
## 被貼身摩擦過、等「不再被擦」才播第二個特效(effect_after)的桌寵:實例 id → {pet, def}。
var _after_pending: Dictionary = {}
var _rub_cooldown_until := 0.0
## 桌寵拿到道具的冷卻(PICKUP_COOLDOWN):桌寵實例 id → 冷卻到期時間(msec)。
var _pickup_cooldown_until: Dictionary = {}


func setup(action_area: Node) -> void:
	_action_area = action_area
	add_to_group("prop_manager")
	_marker = PropCandidateMarker.new()
	add_child(_marker)


## 清空場上所有丟出來的道具(測試用又沒有桌寵願意用掉的道具不會佔著桌面)。回傳清掉幾個。
func clear_all() -> int:
	var removed := items.size()
	clear()
	return removed


## 畫布座標 point 下最上面的道具(沒有回 null);抓取範圍比碰觸範圍稍微大一點。
func item_at(point: Vector2) -> PropItem:
	for i in range(items.size() - 1, -1, -1):
		var item := items[i]
		if is_instance_valid(item) and not item.consuming and item.touch_rect().grow(6.0).has_point(point):
			return item
	return null


## 開始拖曳一個道具(從桌面抓起,或從道具欄拖出來的新道具)。
func begin_drag(item: PropItem, at_mouse := Vector2.INF) -> void:
	if dragged != null:
		end_drag()
	dragged = item
	item.begin_drag(_mouse if at_mouse == Vector2.INF else at_mouse)


## 放開:道具帶著拖曳速度落下;拖曳中的吸引效果解除。
func end_drag() -> void:
	if dragged == null:
		return
	var item := dragged
	dragged = null
	if is_instance_valid(item):
		item.delivered_to = candidate   # 放開時壓在誰身上就是手動遞交給誰(固定模式的桌寵只收這種)
		item.end_drag()
		if item.def != null and item.def.shape == "ball":
			for pet: Node in get_tree().get_nodes_in_group("pets"):
				if pet.ball_play != null and pet.ball_play.invite(item):
					break   # 使用者丟球:有興趣的桌寵(通常最近的一隻先問到)立刻跟著玩
	_clear_attraction()
	_set_candidate(null, null)
	_reset_rub()


## 道具欄用:在滑鼠位置生出一個道具並立刻抓在手上。
func spawn_dragged(def: PropDef, at_mouse: Vector2) -> PropItem:
	var item := spawn(def, at_mouse)
	item.global_position = at_mouse + Vector2(0.0, PropItem.SIZE * 0.5)
	begin_drag(item, at_mouse)
	return item


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = get_viewport().get_canvas_transform().affine_inverse() * event.position
	if get_node("/root/DesktopShellState").is_passthrough_frozen:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var recalled := item_at(_mouse)
		if recalled != null and dragged == null:
			_remove(recalled)   # 右鍵點道具 = 手動收回(回到物品欄)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var item := item_at(_mouse)
			if item != null:
				begin_drag(item)
				get_viewport().set_input_as_handled()
		elif dragged != null:
			end_drag()
			get_viewport().set_input_as_handled()


## 拖著道具時的互動:找出碰到的桌寵(候選,畫外框並觸發「成為候選互動對象」事件),摩擦模式的道具再判斷來回摩擦。
func _update_drag_interaction(item: PropItem, now: float) -> void:
	var touched := _pet_under(item)
	_set_candidate(item.def, touched)
	if touched != null:
		touched.keep_prop_action()   # 交互行為設定的持續動作:道具還在身上就繼續
		item.keep_using()
		if item.def.rub:
			touched.hold_still_for(0.4)   # 拿著要摩擦的道具靠近時,桌寵站好讓你擦
	if not item.def.rub or touched == null:
		_reset_rub()
		return
	if rub_sample(item.global_position.x, now) and now >= _rub_cooldown_until:
		_rub_cooldown_until = now + RUB_COOLDOWN
		_reset_rub()
		rub(item, touched)


## 和道具的碰觸範圍重疊、離道具最近的桌寵(進場中、被拖曳的不算)。
func _pet_under(item: PropItem) -> Node:
	var box := item.touch_rect()
	var chosen: Node = null
	var best := INF
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		if not is_instance_valid(pet) or pet.entering or pet.dragging:
			continue
		var rect: Rect2 = pet.interaction_rect()
		if not rect.intersects(box) or pet.prop_preference(item.def) == "ignore":
			continue
		var distance := (rect.get_center() - box.get_center()).length()
		if distance < best:
			best = distance
			chosen = pet
	return chosen


func _set_candidate(def: PropDef, pet: Node) -> void:
	if pet == candidate:
		return
	var previous := candidate
	candidate = pet
	if previous != null:
		_flush_after(previous)
	if _marker != null:
		_marker.set_target(pet)
	if pet != null and def != null:
		if pet.logic != null:
			pet.logic.run_prop_hats("candidate", def.display_name)
		PropReaction.candidate(def, pet)
	candidate_changed.emit(def, pet)


## 餵一個道具水平位置樣本;回傳這一刻是不是達到摩擦判定(短時間內來回折返夠多次)。折返 = 反方向離開最遠點超過 RUB_MIN_STROKE。
func rub_sample(x: float, now: float) -> bool:
	if not _rub_started:
		_rub_started = true
		_rub_extreme = x
		_rub_dir = 0
		return false
	var moved := x - _rub_extreme
	if _rub_dir == 0:
		if absf(moved) >= RUB_MIN_STROKE:
			_rub_dir = 1 if moved > 0.0 else -1
			_rub_extreme = x
	elif (_rub_dir > 0 and x > _rub_extreme) or (_rub_dir < 0 and x < _rub_extreme):
		_rub_extreme = x
	elif absf(x - _rub_extreme) >= RUB_MIN_STROKE:
		_rub_dir = -_rub_dir
		_rub_extreme = x
		_rub_events.append(now)
	while not _rub_events.is_empty() and now - _rub_events[0] > RUB_WINDOW:
		_rub_events.pop_front()
	return _rub_events.size() >= RUB_REVERSALS


func _reset_rub() -> void:
	_rub_events.clear()
	_rub_dir = 0
	_rub_started = false


## 這隻桌寵不再被道具擦了:有等著播的第二個特效就播。
func _flush_after(pet: Node) -> void:
	if not is_instance_valid(pet):
		return
	var entry: Variant = _after_pending.get(pet.get_instance_id())
	_after_pending.erase(pet.get_instance_id())
	if entry is Dictionary and pet.effects != null:
		pet.effects.play(str((entry["def"] as PropDef).effect_after))


## 摩擦達到判定(或測試直接呼叫):套用反應;摩擦後一次性消耗的道具播使用動畫後消失。
func rub(item: PropItem, pet: Node) -> Dictionary:
	var result := PropReaction.rub(item.def, pet)
	prop_rubbed.emit(item.def, pet)
	item.use_started()
	if item.def.effect_after != "":
		_after_pending[pet.get_instance_id()] = {"def": item.def}
	if item.def.consume_on_rub:
		if item == dragged:
			end_drag()
		_consume(item)
		_flush_after(pet)
	return result


## 道具被使用掉:從場上清單拿掉,播使用動畫後自己消失(不再被拾取或拖曳)。
func _consume(item: PropItem) -> void:
	if item == dragged:
		dragged = null
		_clear_attraction()
	items.erase(item)
	if is_instance_valid(item):
		item.begin_consume(item.def.use_anim, item.def.use_shakes)


## 拖曳中吸引:每個物理影格把道具座標交給場上可被吸引的桌寵當移動目標(桌寵那邊 0.3 秒沒更新就自己解除)。
func _update_attraction() -> void:
	if dragged == null or not is_instance_valid(dragged) or not dragged.def.attract_while_dragging:
		return
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		if pet.prop_preference(dragged.def) != "ignore":
			pet.set_attract_goal(dragged.global_position)


func _clear_attraction() -> void:
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		pet.clear_attract_goal()


## 場上的道具數。
func count() -> int:
	return items.size()


## 在 global_position(道具的腳底)丟一個道具;沒指定位置就從行動區上方隨機一個橫向位置掉下來。
## 場上道具太多(MAX_ITEMS)時最舊的一個先消失。回傳道具節點。
func spawn(def: PropDef, at := Vector2.INF) -> PropItem:
	while items.size() >= MAX_ITEMS:
		_remove(items[0])
	var item := PropItem.new()
	item.setup(def, PropLibrary.texture_of(def))
	item.set_sprite_frames(PropLibrary.load_sprite(def))
	var bounds := _bounds()
	if at == Vector2.INF:
		var margin := PropItem.SIZE
		at = Vector2(randf_range(bounds.position.x + margin, maxf(bounds.end.x - margin, bounds.position.x + margin)), bounds.position.y + PropItem.SIZE)
	item.global_position = at
	add_child(item)
	item.global_position = at
	items.append(item)
	return item


func clear() -> void:
	for item in items.duplicate():
		_remove(item)


## 行動區的全域範圍;沒有行動區(測試)就給一塊大的。
func _bounds() -> Rect2:
	if _action_area != null and "boundary_rect" in _action_area:
		var rect: Rect2 = _action_area.boundary_rect
		return Rect2(_action_area.to_global(rect.position), rect.size)
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


## 換螢幕、或同一台螢幕解析度變了(見 DesktopShell.apply_monitor_setting()):場上還留著的道具依新舊視窗
## 尺寸的比例挪過去,挪完夾回目前行動區範圍內(道具沒有存檔,只需要處理「現在活著的」這些)。
func rescale_positions(old_size: Vector2, new_size: Vector2) -> void:
	if old_size.x <= 0.0 or old_size.y <= 0.0 or old_size.is_equal_approx(new_size):
		return
	var scale := new_size / old_size
	var bounds := _bounds()
	for item in items:
		if not is_instance_valid(item):
			continue
		var scaled := item.global_position * scale
		item.global_position = Vector2(clampf(scaled.x, bounds.position.x, bounds.end.x), clampf(scaled.y, bounds.position.y, bounds.end.y))


func _remove(item: PropItem) -> void:
	if item == dragged:
		dragged = null
		_clear_attraction()
	items.erase(item)
	if is_instance_valid(item):
		item.collected = true
		item.queue_free()


func _physics_process(delta: float) -> void:
	if items.is_empty():
		return
	var bounds := _bounds()
	if dragged != null:
		if is_instance_valid(dragged):
			dragged.drag_step(_mouse, delta, bounds)
			_update_attraction()
			_update_drag_interaction(dragged, Time.get_ticks_msec() / 1000.0)
		else:
			dragged = null
	var pets := get_tree().get_nodes_in_group("pets")
	for item in items.duplicate():
		if not is_instance_valid(item):
			items.erase(item)
			continue
		if item.def.timeout_seconds > 0.0 and not item.dragging and (item.rest_time >= item.def.timeout_seconds or item.age >= item.def.timeout_seconds * 4.0 + 30.0):
			_remove(item)
			continue
		# 掉出行動區(平臺消失、被邊界外的東西推開)就拉回行動區裡。
		if not bounds.grow(PropItem.SIZE * 2.0).has_point(item.global_position):
			item.global_position = Vector2(clampf(item.global_position.x, bounds.position.x, bounds.end.x), clampf(item.global_position.y, bounds.position.y, bounds.end.y))
		if item.def.toss and not item.collected and not item.dragging and item.age >= item.pickup_delay:
			_try_collect(item, pets)


func _try_collect(item: PropItem, pets: Array) -> void:
	var box := item.touch_rect()
	var chosen: Node = null
	var best := INF
	for pet: Node in pets:
		if not _can_collect(pet, item):
			continue
		if not pet.interaction_rect().intersects(box):
			continue
		var distance: float = (pet.interaction_rect().get_center() - box.get_center()).length()
		if distance < best:
			best = distance
			chosen = pet
	if chosen == null:
		return
	collect(item, chosen)


## 這隻桌寵現在能不能去拿道具:睡著、被拖曳、進場中、被使用者抓著都不行;固定模式的桌寵只收「手動遞交」給它的道具(拖著放開在它身上),不會自己撿丟在旁邊的。
func _can_collect(pet: Node, item: PropItem = null) -> bool:
	if not is_instance_valid(pet) or pet.entering or pet.dragging or pet.is_sleeping():
		return false
	var delivered := item != null and item.delivered_to == pet
	if not delivered and Time.get_ticks_msec() < int(_pickup_cooldown_until.get(pet.get_instance_id(), 0)):
		return false   # 剛拿過別的道具,冷卻中(手動遞交給它的不受這個限制)
	if pet.move_mode == Pet.MoveMode.FIXED and (item == null or item.delivered_to != pet):
		return false
	if item != null and pet.prop_preference(item.def) == "ignore":
		return false   # 「不與此道具交互」:完全無視
	if item != null and item.delivered_to != pet and pet.prop_preference(item.def) == "dislike":
		return false   # 不喜歡的道具不會自己撿(拖著遞給它還是會收)
	return true


## 指定的桌寵拾取這個道具(判定成立時呼叫;測試也直接呼叫)。
func collect(item: PropItem, pet: Node) -> Dictionary:
	var def := item.def
	_consume(item)
	_pickup_cooldown_until[pet.get_instance_id()] = Time.get_ticks_msec() + int(PICKUP_COOLDOWN * 1000.0)
	var result := PropReaction.collect(def, pet)
	prop_collected.emit(def, pet)
	if def.effect_after != "":
		# 丟入式:使用動畫播完才播第二個特效。
		get_tree().create_timer(PropItem.consume_seconds(def.use_anim, def.use_shakes)).timeout.connect(func() -> void:
			if is_instance_valid(pet) and pet.effects != null:
				pet.effects.play(def.effect_after))
	return result
