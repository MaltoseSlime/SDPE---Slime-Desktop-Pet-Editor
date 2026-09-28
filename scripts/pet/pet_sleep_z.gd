class_name PetSleepZ
extends Node2D
## 睡著時頭上飄出的「Zzz」:用這隻桌寵自己的介面字體(PetUiStyle.default_font)畫字,從小 z 到大 Z 依序冒出來、往上飄並左右輕搖、邊飄邊放大再淡出。
## 不需要素材(文字向量繪製);字級跟著角色身體大小與介面縮放率,大隻的角色 Z 也大。是純裝飾:不擋滑鼠(輸入穿透),但視窗的可見區域要包含它,所以在 Cutout 群組裡提供自己的矩形。

## 每顆 Z 出現的間隔(秒,隨機)。
const SPAWN_INTERVAL := Vector2(0.8, 1.4)
const LIFETIME := 2.8
## 一輪三顆的字與字級(占身體高度的比例):小 z → 中 Z → 大 Z,然後從頭再來。
const STAGES: Array[Dictionary] = [
	{"text": "z", "size": 0.14},
	{"text": "Z", "size": 0.20},
	{"text": "Z", "size": 0.28},
]
const MIN_FONT_SIZE := 12
const MAX_FONT_SIZE := 160
## 上飄的距離(占身體高度的比例)與水平搖擺的幅度(像素,乘介面縮放率)。
const RISE_FRACTION := 0.8
const WOBBLE := 9.0
const SCALE_RANGE := Vector2(0.7, 1.3)

var enabled := true
var _pet: Node
var _floaters: Array[Dictionary] = []
var _spawn_left := 0.4
var _stage := 0


func setup(pet: Node) -> void:
	_pet = pet
	add_to_group("Cutout")
	z_index = 20


func _process(delta: float) -> void:
	if _pet == null:
		return
	var sleeping: bool = enabled and not _pet.entering and _pet.current_activity() == &"sleep"
	if sleeping:
		_spawn_left -= delta
		if _spawn_left <= 0.0:
			_spawn_left = randf_range(SPAWN_INTERVAL.x, SPAWN_INTERVAL.y)
			_spawn()
	for floater in _floaters:
		_update(floater, delta)
	_floaters = _floaters.filter(func(f: Dictionary) -> bool:
		if float(f["age"]) >= LIFETIME:
			(f["label"] as Label).queue_free()
			return false
		return true)


## 角色本體的高度(像素,已乘上角色縮放;判定框的高度,不含穿透形狀的安全邊距)。量不到(素材還沒載入)就用 96。
func _body_height() -> float:
	var height: float = _pet.effective_hitbox_size().y * _pet.params.scale_multiplier
	return height if height > 8.0 else 96.0


## 桌寵頭頂中央(全域座標):以腳底軸心往上一個本體高度(判定框的偏移一起算)。
func _head_point() -> Vector2:
	var offset: Vector2 = _pet.effective_hitbox_offset() * _pet.params.scale_multiplier
	return _pet.to_global(Vector2(offset.x, offset.y - _body_height()))


func _spawn() -> void:
	var style: PetUiStyle = _pet.ui_style
	var body_height := _body_height()
	var stage: Dictionary = STAGES[_stage % STAGES.size()]
	_stage += 1
	var font_size := clampi(int(body_height * float(stage["size"]) * maxf(style.scale_factor(), 0.5) * UiFonts.size_correction(style.default_font)), MIN_FONT_SIZE, MAX_FONT_SIZE)
	var label := Label.new()
	label.text = str(stage["text"])
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.top_level = true
	label.add_theme_font_override("font", UiFonts.get_font(style.default_font))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", style.text)
	var outline := style.background
	outline.a = 1.0
	label.add_theme_color_override("font_outline_color", outline)
	label.add_theme_constant_override("outline_size", maxi(font_size / 8, 2))
	add_child(label)
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	_floaters.append({
		"label": label, "age": 0.0, "origin": _head_point() + Vector2(randf_range(-0.12, 0.12) * body_height * 0.6, 0.0),
		"phase": randf() * TAU, "rise": body_height * RISE_FRACTION, "font_size": font_size,
	})
	_update(_floaters[-1], 0.0)


func _update(floater: Dictionary, delta: float) -> void:
	floater["age"] = float(floater["age"]) + delta
	var t := clampf(float(floater["age"]) / LIFETIME, 0.0, 1.0)
	var label: Label = floater["label"]
	var factor: float = _pet.ui_style.scale_factor()
	var sway := sin(t * TAU * 1.5 + float(floater["phase"])) * WOBBLE * factor
	# 越飄越往右上(像是從頭頂斜著冒出來),搖擺疊在上面。
	var offset := Vector2(sway + t * 26.0 * factor, -t * float(floater["rise"]))
	label.scale = Vector2.ONE * lerpf(SCALE_RANGE.x, SCALE_RANGE.y, t)
	label.global_position = (floater["origin"] as Vector2) + offset - label.pivot_offset
	# 淡入很快、後段淡出。
	label.modulate.a = minf(t * 8.0, 1.0) * (1.0 - smoothstep(0.65, 1.0, t))


## 全域座標下每顆 Z 佔的矩形(穿透形狀用)。
func floater_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for floater in _floaters:
		var label: Label = floater["label"]
		if is_instance_valid(label):
			var scaled := label.size * label.scale
			rects.append(Rect2(label.global_position + label.pivot_offset - scaled * 0.5, scaled))
	return rects


func get_cutout_polygons() -> Array:
	var polygons: Array = []
	for rect in floater_rects():
		polygons.append(DialogueBubble._rect_polygon(rect.grow(6.0)))
	return polygons


func active_count() -> int:
	return _floaters.size()
