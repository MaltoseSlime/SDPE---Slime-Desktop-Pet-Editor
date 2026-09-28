extends CanvasLayer
## 頂層全域 UI 管理器(企劃書第六章「全域 UI 避讓與螢幕邊緣防裁切」)的對話氣泡部分:
## 訂閱 DesktopShellState.dialogue_line_requested,替每隻桌寵開一個氣泡,並每影格統一排版——
## 預設在頭頂上方;頭頂被其他氣泡/桌寵佔住或碰到螢幕上緣就垂直翻轉到腳底下方;上下都不行就橫向階梯位移。
## 每次排版一律先做螢幕邊界鉗制、再做重疊避讓,避讓最多重試 MAX_RETRIES 次,超過就接受目前位置(穩定優先於零重疊)。
## 先來後到:已顯示的氣泡保持原位(先排),後來的才避讓。
##
## 還負責「重複前一句」(桌寵右鍵選單):只重播純文字與綁定動作,不再出現選項、也不重算 Flag。

const GAP := 6.0
const STAGGER_PADDING := 8.0
const MAX_RETRIES := 3
const REPEAT_SECONDS := 3.0

var _state: Node
var _bubbles: Dictionary = {}
var _order: Array[Node] = []
var _last_lines: Dictionary = {}
var _connected_pets: Dictionary = {}


func _ready() -> void:
	layer = 10
	# 排版要早於 DesktopShell 彙整穿透多邊形,氣泡的點擊範圍才不會慢一影格。
	process_priority = -100
	_state = get_node("/root/DesktopShellState")
	_state.dialogue_line_requested.connect(_on_line_requested)
	set_process(false)


func _on_line_requested(pet: Node, line: Dictionary, ticket: RefCounted) -> void:
	_connect_pet(pet)
	_last_lines[pet] = line
	_show(pet, line, ticket)


func _show(pet: Node, line: Dictionary, ticket: RefCounted) -> void:
	_close(pet)
	var bubble := DialogueBubble.new()
	add_child(bubble)
	bubble.setup(pet, line)
	_bubbles[pet] = bubble
	if not _order.has(pet):
		_order.append(pet)
	# 先清理自己的登記、再通知直譯器:直譯器醒來後可能立刻開下一句,那時舊氣泡必須已經登出。
	bubble.advanced.connect(_on_bubble_advanced.bind(pet, bubble))
	if ticket != null:
		bubble.advanced.connect(ticket.finish)
		# 使用者拖曳/點擊/interact 等即時互動打斷時,連氣泡一起收掉。
		pet.interrupted.connect(bubble.close_silently, CONNECT_ONE_SHOT)
	_state.dialogue_started.emit(pet)
	set_process(true)
	_layout()


func _on_bubble_advanced(_choice: int, pet: Node, bubble: DialogueBubble) -> void:
	if _bubbles.get(pet) == bubble:
		_bubbles.erase(pet)
		_order.erase(pet)
		_state.dialogue_finished.emit(pet)
	if pet.interrupted.is_connected(bubble.close_silently):
		pet.interrupted.disconnect(bubble.close_silently)
	bubble.queue_free()
	set_process(not _bubbles.is_empty())


func _close(pet: Node) -> void:
	var bubble: DialogueBubble = _bubbles.get(pet)
	if bubble != null and is_instance_valid(bubble):
		bubble.close_silently()


func _connect_pet(pet: Node) -> void:
	if _connected_pets.has(pet):
		return
	_connected_pets[pet] = true
	pet.repeat_last_requested.connect(_on_repeat_last.bind(pet))
	pet.tree_exiting.connect(_forget_pet.bind(pet))


func _forget_pet(pet: Node) -> void:
	_close(pet)
	_last_lines.erase(pet)
	_connected_pets.erase(pet)


## 重複前一句:純文字 + 綁定動作,沒有選項、固定秒數後自動收起。
func _on_repeat_last(pet: Node) -> void:
	var line: Dictionary = _last_lines.get(pet, {})
	if line.is_empty() or _bubbles.has(pet):
		return
	var repeated := line.duplicate()
	repeated["options"] = []
	repeated["auto_seconds"] = REPEAT_SECONDS
	if str(repeated.get("bind_action", "")) != "":
		pet.play_action(StringName(str(repeated["bind_action"])), -1, true)
	_show(pet, repeated, null)


func _process(_delta: float) -> void:
	for pet: Node in _order:
		var bubble: DialogueBubble = _bubbles[pet]
		# 綁定動作的句子:說話期間維持該姿勢。
		if bubble.bind_action != &"":
			pet.extend_hold(0.3)
	_layout()


## 統一排版。順序 = 出現的先後(先來的先排、位置固定),後來的避讓前面的氣泡與其他桌寵。
func _layout() -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size))
	var placed: Array[Rect2] = []
	for pet: Node in _order:
		var bubble: DialogueBubble = _bubbles[pet]
		bubble.reset_size()
		var obstacles: Array[Rect2] = placed.duplicate()
		for other: Node in get_tree().get_nodes_in_group("pets"):
			if other != pet:
				obstacles.append(other.get_body_rect())
		var body: Rect2 = pet.get_body_rect()
		var rect := _place(bubble.size, body, bubble.flipped, screen, obstacles)
		bubble.flipped = rect.get_center().y > body.get_center().y
		bubble.global_position = rect.position
		bubble.place_tag()
		placed.append(rect)


## 找一個合法位置:先照上次的上下方向,先鉗制螢幕再避讓;卡住就翻轉,兩邊都卡再橫向位移。
func _place(size: Vector2, body: Rect2, flipped: bool, screen: Rect2, obstacles: Array[Rect2]) -> Rect2:
	var above := Vector2(body.get_center().x - size.x * 0.5, body.position.y - size.y - GAP)
	var below := Vector2(body.get_center().x - size.x * 0.5, body.end.y + GAP)
	# 緊貼螢幕頂部一律往下翻,確保完整顯示。
	if above.y < screen.position.y:
		flipped = true
	var first := below if flipped else above
	var second := above if flipped else below
	var rect := _clamp(Rect2(first, size), screen)
	if not _hits(rect, obstacles):
		return rect
	var alternative := _clamp(Rect2(second, size), screen)
	if not _hits(alternative, obstacles) and (second.y >= screen.position.y or second == below):
		return alternative
	# 上下都被擋:沿 X 軸往外推,附上安全邊距;先鉗制再避讓,最多重試 MAX_RETRIES 次。
	var candidate := rect
	for i in MAX_RETRIES:
		var blocker := _first_hit(candidate, obstacles)
		if blocker.size == Vector2.ZERO:
			break
		var push_right := candidate.get_center().x >= blocker.get_center().x
		candidate.position.x = blocker.end.x + STAGGER_PADDING if push_right else blocker.position.x - size.x - STAGGER_PADDING
		candidate = _clamp(candidate, screen)
	return candidate


func _clamp(rect: Rect2, screen: Rect2) -> Rect2:
	rect.position = rect.position.clamp(screen.position, screen.end - rect.size)
	return rect


func _hits(rect: Rect2, obstacles: Array[Rect2]) -> bool:
	return _first_hit(rect, obstacles).size != Vector2.ZERO


func _first_hit(rect: Rect2, obstacles: Array[Rect2]) -> Rect2:
	for obstacle in obstacles:
		if rect.intersects(obstacle):
			return obstacle
	return Rect2()
