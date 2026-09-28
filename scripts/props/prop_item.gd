class_name PropItem
extends CharacterBody2D
## 丟在桌面上的一個小道具(丟入拾取模式):套用和角色相同的重力與平臺碰撞(可以落在動態平臺上),用獨立的「道具碰撞層」不和角色本體、視窗邊界牆互相干擾。
## 原點在底邊中心(腳底)。有圖就畫圖(縮成最長邊 SIZE),沒有圖就用程式畫替代圖示(色塊 + 名稱第一個字)。
## 是「Cutout」群組成員:提供自己的形狀給穿透多邊形,才看得到。

const Layers := preload("res://scripts/common/physics_layers.gd")
const SIZE := 44.0
const GRAVITY := 1400.0
const MAX_FALL_SPEED := 1600.0
## 逾時前最後幾秒開始閃爍提醒(透明度上下,頻率遠低於每秒 3 次)。
const WARN_SECONDS := 3.0
## 搖晃式消失:每一輪 = 快速晃一下(SHAKE_BURST 秒)+ 停頓,合起來 SHAKE_SECONDS 秒;振幅 SHAKE_AMPLITUDE 像素。
const SHAKE_SECONDS := 0.55
const SHAKE_BURST := 0.2
const SHAKE_AMPLITUDE := 3.0

var def: PropDef
var texture: Texture2D
var age := 0.0
## 落地後靜置的秒數(逾時自動消失從落地開始算;被抓起來就歸零)。所有道具(丟入式、拖曳式)都適用。
var rest_time := 0.0
## 放開時正壓在這隻桌寵身上(候選)= 手動遞交給它;固定模式的桌寵只收這種道具。
var delivered_to: Node
## 剛丟出來(例如桌寵放下手上的道具)這麼多秒內不會被拾取。
var pickup_delay := 0.0
var landed := false
var collected := false
## 被使用者抓著拖曳中(不受重力)。
var dragging := false
## 被使用後的表現動畫進行中(不再受重力、也不再被拾取或拖曳):見 begin_consume。
var consuming := false
var _consume_anim := "none"
var _consume_shakes := 3
var _consume_time := 0.0
var _consume_start := Vector2.ZERO
## 進階貼圖(見 PropLibrary.load_sprite):有的話用它畫,依狀態播 預設 / 被使用 / 拖曳中 的動畫;沒有就畫簡單版的一張圖或替代圖示。
var _sprite: AnimatedSprite2D
var _sprite_state := ""
## 觸發式「被使用」動畫正在播;剩幾次。循環式「被使用」用 _using_hold(每次交互續命)。
var _used_active := false
var _used_plays := 0
var _using_hold := 0.0
var _drag_plays := 0
var _drag_done := false
## 使用動畫(觸發式)比消耗動畫長時,消耗動畫要延長到播完。
var _consume_extra := 0.0
const USE_LOOP_HOLD := 0.7
## 圓球(def.shape == "ball"):圓形碰撞箱、會彈跳與滾動旋轉;桌寵玩球時由 PetBallPlay 踢(kick)或頂在頭上(carried_by,位置由它決定)。
const BALL_RADIUS := SIZE * 0.45
const BALL_BOUNCE := 0.55
const BALL_ROLL_FRICTION := 70.0
var carried_by: Node
var _roll := 0.0
## 桌寵正在玩它的期限(msec);玩的時候不計自動消失。使用者最後一次碰它(抓、放)的時間:玩球時的好感度回饋看它。
var play_until_msec := 0
var user_touch_msec := -100000
var _drag_offset := Vector2.ZERO
var _drag_velocity := Vector2.ZERO
var _last_drag_position := Vector2.ZERO


func setup(prop_def: PropDef, prop_texture: Texture2D) -> void:
	def = prop_def
	texture = prop_texture
	collision_layer = Layers.PROP
	collision_mask = Layers.PLATFORM | Layers.BOUNDARY_WALL
	var shape_node := CollisionShape2D.new()
	if def.shape == "ball":
		var circle := CircleShape2D.new()
		circle.radius = BALL_RADIUS
		shape_node.shape = circle
		shape_node.position = Vector2(0.0, -BALL_RADIUS)
	else:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(SIZE * 0.8, SIZE * 0.8)
		shape_node.shape = shape
		shape_node.position = Vector2(0.0, -SIZE * 0.4)
	add_child(shape_node)
	add_to_group("Cutout")
	add_to_group("props")
	z_index = 5
	if def.has_light():
		var glow := PropLight.new()
		add_child(glow)
		glow.setup(self)


func _physics_process(delta: float) -> void:
	age += delta
	_update_sprite(delta)
	if consuming:
		_step_consume(delta)
		return
	if dragging:
		velocity = Vector2.ZERO
		return
	if carried_by != null:
		velocity = Vector2.ZERO   # 頂在桌寵頭上:位置由 PetBallPlay 每影格設定
		return
	if def != null and def.shape == "ball":
		_ball_step(delta)
	else:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		move_and_slide()
		landed = is_on_floor()
	if landed and not being_played():
		rest_time += delta
	if def != null and def.timeout_seconds > 0.0 and rest_time > def.timeout_seconds - WARN_SECONDS:
		queue_redraw()


## 圓球的一步:重力、彈跳(撞到地面往上彈、撞牆反彈)、滾動摩擦與轉動。
func _ball_step(delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
	var before := velocity
	move_and_slide()
	landed = is_on_floor()
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if normal.y < -0.6 and before.y > 140.0:
			velocity.y = -before.y * BALL_BOUNCE
		elif absf(normal.x) > 0.6 and absf(before.x) > 30.0:
			velocity.x = -before.x * 0.7
	if landed:
		velocity.x = move_toward(velocity.x, 0.0, BALL_ROLL_FRICTION * delta)
	if absf(velocity.x) > 1.0 or not landed:
		_roll = fposmod(_roll + velocity.x * delta / BALL_RADIUS, TAU)
		if _sprite != null:
			_sprite.rotation = _roll
		queue_redraw()


## 踢(或拋)這顆球:給它一個速度。
func kick(impulse: Vector2) -> void:
	carried_by = null
	velocity = impulse
	landed = false


## 桌寵正在玩它:接下來 1.5 秒不計自動消失(每影格由 PetBallPlay 續命)。
func mark_played() -> void:
	play_until_msec = Time.get_ticks_msec() + 1500
	rest_time = 0.0


func being_played() -> bool:
	return Time.get_ticks_msec() < play_until_msec


## 裝上進階貼圖(SpriteFrames,需要 default_0);比例縮到最長邊 SIZE,軸心(腳底)對齊道具原點。
func set_sprite_frames(frames: SpriteFrames) -> void:
	if frames == null or not frames.has_animation(&"default_0"):
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	var cell := Vector2(frames.get_frame_texture(&"default_0", 0).get_size())
	var body: Variant = frames.get_meta("body_size") if frames.has_meta("body_size") else cell
	var body_size: Vector2 = body if body is Vector2 and body != Vector2.ZERO else cell
	var below := float(frames.get_meta("ground_below")) if frames.has_meta("ground_below") else 0.0
	var factor := SIZE / maxf(maxf(body_size.x, body_size.y), 1.0)
	_sprite.scale = Vector2.ONE * factor
	_sprite.position = Vector2(0.0, -SIZE * 0.5) if def.shape == "ball" else Vector2(0.0, (-cell.y * 0.5 + below) * factor)   # 球以中心為軸轉動
	_sprite.animation_finished.connect(_on_sprite_finished)
	add_child(_sprite)
	_enter_sprite_state("default")


func has_sprite() -> bool:
	return _sprite != null


func _has_state(state: String) -> bool:
	return _sprite != null and _sprite.sprite_frames.has_animation(StringName(state + "_0"))


## 進入一個狀態動畫(從第一幀播)。
func _enter_sprite_state(state: String) -> void:
	_sprite_state = state
	match state:
		"used":
			if def.used_mode == "trigger" and _used_plays <= 0:
				_used_plays = def.used_count
		"drag":
			_drag_plays = def.drag_count if def.drag_mode == "trigger" else 0
	_sprite.play(StringName(state + "_0"))


## 交互開始(拾取、被摩擦):進階貼圖的「被使用」動畫開始。觸發式播 used_count 次;循環式在交互持續期間循環(每次交互續命)。
func use_started() -> void:
	if not _has_state("used"):
		return
	if def.used_mode == "trigger":
		_used_active = true
		_used_plays = def.used_count
		_sprite_state = ""   # 強迫重新進入,連續觸發時從頭播
	else:
		_using_hold = USE_LOOP_HOLD


## 循環式「被使用」:交互還在持續時呼叫,動畫不會停。
func keep_using() -> void:
	if _using_hold > 0.0:
		_using_hold = USE_LOOP_HOLD


func _on_sprite_finished() -> void:
	match _sprite_state:
		"used":
			if def.used_mode == "trigger":
				_used_plays -= 1
				if _used_plays > 0:
					_sprite.play(&"used_0")
				else:
					_used_active = false
			else:
				_sprite.play(&"used_0")
		"drag":
			if def.drag_mode == "trigger":
				_drag_plays -= 1
				if _drag_plays > 0:
					_sprite.play(&"drag_0")
				else:
					_drag_done = true
			else:
				_sprite.play(&"drag_0")


## 依目前狀況決定要播哪個狀態動畫:拖曳中 > 被使用 > 預設。觸發式的播完就回預設。
func _update_sprite(delta: float) -> void:
	if _sprite == null:
		return
	_using_hold = maxf(_using_hold - delta, 0.0)
	if consuming and def.used_mode == "loop" and _has_state("used"):
		_using_hold = USE_LOOP_HOLD
	if not dragging:
		_drag_done = false
	var wanted := "default"
	if dragging and not _drag_done and _has_state("drag"):
		wanted = "drag"
	elif (_used_active or _using_hold > 0.0) and _has_state("used"):
		wanted = "used"
	if wanted != _sprite_state:
		_enter_sprite_state(wanted)
	var alpha := 1.0
	if def.timeout_seconds > 0.0 and rest_time > def.timeout_seconds - WARN_SECONDS:
		alpha = 0.55 + 0.45 * absf(sin((rest_time - (def.timeout_seconds - WARN_SECONDS)) * PI * 1.2))
	_sprite.self_modulate.a = alpha


## 被使用了:播表現動畫後自己消失。none 立刻消失;shake / shake_v 左右(上下)晃 shakes 輪,每輪快速晃一下再停頓(只晃,不縮小),最後一輪結束時很快淡出;float_up 向上飄 70 像素同時淡出;fade 原地淡出。
func begin_consume(anim: String, shakes := 3) -> void:
	dragging = false
	consuming = true
	collected = true
	_consume_anim = anim
	_consume_shakes = clampi(shakes, PropDef.MIN_SHAKES, PropDef.MAX_SHAKES)
	_consume_time = 0.0
	_consume_start = global_position
	velocity = Vector2.ZERO
	remove_from_group("Cutout")
	_consume_extra = 0.0
	if _has_state("used") and def.used_mode == "trigger":
		use_started()
		var used_frames := _sprite.sprite_frames
		var speed := used_frames.get_animation_speed(&"used_0")
		var length := 0.0
		for i in used_frames.get_frame_count(&"used_0"):
			length += used_frames.get_frame_duration(&"used_0", i)
		_consume_extra = (length / maxf(speed, 0.01)) * def.used_count
	elif _has_state("used"):
		use_started()
	if anim == "none" and _consume_extra <= 0.0:
		queue_free()


## 動畫總長(秒)。
func consume_duration() -> float:
	return maxf(consume_seconds(_consume_anim, _consume_shakes), _consume_extra)


## 某種使用動畫要多久(交互行為的「持續到道具用完」用它估時間)。
static func consume_seconds(anim: String, shakes: int) -> float:
	match anim:
		"shake", "shake_v":
			return SHAKE_SECONDS * clampi(shakes, PropDef.MIN_SHAKES, PropDef.MAX_SHAKES)
		"float_up":
			return 1.0
	return 0.6


func _step_consume(delta: float) -> void:
	_consume_time += delta
	var total := consume_duration()
	var progress := clampf(_consume_time / total, 0.0, 1.0)
	match _consume_anim:
		"shake", "shake_v":
			var burst_progress := clampf(fmod(_consume_time, SHAKE_SECONDS) / SHAKE_BURST, 0.0, 1.0)
			var wiggle := sin(burst_progress * TAU) * SHAKE_AMPLITUDE
			if _consume_anim == "shake":
				global_position = _consume_start + Vector2(wiggle, 0.0)
				rotation = wiggle * 0.015
			else:
				global_position = _consume_start + Vector2(0.0, wiggle)
			modulate.a = 1.0 if progress < 0.92 else (1.0 - progress) / 0.08
		"float_up":
			global_position = _consume_start + Vector2(0.0, -70.0 * ease(progress, 0.6))
			modulate.a = 1.0 - progress
		"none":
			modulate.a = 1.0 if progress < 0.9 else (1.0 - progress) / 0.1   # 立刻消失 + 進階貼圖的使用動畫:動畫播完才收
		_:
			modulate.a = 1.0 - progress
	if progress >= 1.0:
		queue_free()


## 抓起:mouse 是滑鼠的畫布座標,之後每個物理影格呼叫 drag_step 跟著滑鼠走。
func begin_drag(mouse: Vector2) -> void:
	dragging = true
	landed = false
	rest_time = 0.0
	delivered_to = null
	carried_by = null
	user_touch_msec = Time.get_ticks_msec()
	_drag_offset = global_position - mouse
	_last_drag_position = global_position
	_drag_velocity = Vector2.ZERO
	queue_redraw()


## 跟著滑鼠(夾在 bounds 裡),並記下速度,放開時當作丟出去的初速。
func drag_step(mouse: Vector2, delta: float, bounds: Rect2) -> void:
	var target := Vector2(clampf(mouse.x + _drag_offset.x, bounds.position.x, bounds.end.x), clampf(mouse.y + _drag_offset.y, bounds.position.y + SIZE, bounds.end.y))
	_drag_velocity = _drag_velocity.lerp((target - _last_drag_position) / maxf(delta, 0.001), 0.35)
	_last_drag_position = target
	global_position = target


## 放開:恢復重力,帶著拖曳的速度丟出去(有上限)。
func end_drag() -> void:
	dragging = false
	user_touch_msec = Time.get_ticks_msec()
	velocity = _drag_velocity.limit_length(900.0)
	queue_redraw()


## 全域座標的碰觸範圍(拾取判定用)。
func touch_rect() -> Rect2:
	return Rect2(global_position - Vector2(SIZE * 0.5, SIZE), Vector2(SIZE, SIZE))


func get_cutout_polygons() -> Array:
	if consuming:
		return []
	var rect := touch_rect().grow(120.0 if dragging else 4.0)   # 拖曳中放大,滑鼠快速移動時視窗才不會漏掉事件
	return [DialogueBubble._rect_polygon(rect)]


func _draw() -> void:
	if def == null:
		return
	var alpha := 1.0
	if def.timeout_seconds > 0.0 and rest_time > def.timeout_seconds - WARN_SECONDS:
		alpha = 0.55 + 0.45 * absf(sin((rest_time - (def.timeout_seconds - WARN_SECONDS)) * PI * 1.2))
	if dragging:
		draw_arc(Vector2(0.0, -SIZE * 0.5), SIZE * 0.75, 0.0, TAU, 32, Color(1, 1, 1, 0.6), 2.0, true)
	if _sprite != null:
		return
	if def.shape == "ball":
		_draw_ball(alpha)
		return
	if texture != null:
		var texture_size := texture.get_size()
		var factor := SIZE / maxf(maxf(texture_size.x, texture_size.y), 1.0)
		var draw_size := texture_size * factor
		draw_texture_rect(texture, Rect2(Vector2(-draw_size.x * 0.5, -draw_size.y), draw_size), false, Color(1, 1, 1, alpha))
		return
	# 沒有圖:程式畫的替代圖示。
	var hue := float(absi(def.display_name.hash()) % 360) / 360.0
	var fill := Color.from_hsv(hue, 0.45, 0.95, alpha)
	var box := Rect2(Vector2(-SIZE * 0.5, -SIZE), Vector2(SIZE, SIZE))
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(10)
	style.border_color = Color(0, 0, 0, 0.35 * alpha)
	style.set_border_width_all(2)
	draw_style_box(style, box)
	var font := UiFonts.get_font("黑體")
	var letter := def.display_name.left(1)
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	draw_string(font, Vector2(-text_size.x * 0.5, -SIZE * 0.5 + text_size.y * 0.3), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.1, 0.1, 0.12, alpha))

## 圓球的畫法:有圖就以球心為軸轉動那張圖;沒有圖是色球加一個轉動時看得出來的深色斑點與名稱第一個字。
func _draw_ball(alpha: float) -> void:
	var center := Vector2(0.0, -BALL_RADIUS)
	draw_set_transform(center, _roll)
	if texture != null:
		var texture_size := texture.get_size()
		var factor := BALL_RADIUS * 2.0 / maxf(maxf(texture_size.x, texture_size.y), 1.0)
		draw_texture_rect(texture, Rect2(-texture_size * factor * 0.5, texture_size * factor), false, Color(1, 1, 1, alpha))
	else:
		var hue := float(absi(def.display_name.hash()) % 360) / 360.0
		draw_circle(Vector2.ZERO, BALL_RADIUS, Color.from_hsv(hue, 0.5, 0.95, alpha))
		draw_circle(Vector2(BALL_RADIUS * 0.45, -BALL_RADIUS * 0.3), BALL_RADIUS * 0.28, Color(0, 0, 0, 0.25 * alpha))
		draw_arc(Vector2.ZERO, BALL_RADIUS, 0.0, TAU, 28, Color(0, 0, 0, 0.35 * alpha), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0)

