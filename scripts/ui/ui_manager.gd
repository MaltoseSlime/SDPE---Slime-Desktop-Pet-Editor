extends CanvasLayer
## 頂層全域 UI 管理器(企劃書第六章「全域 UI 避讓與螢幕邊緣防裁切」):所有桌寵的對話氣泡與 Status 面板都掛在這裡,
## 每影格統一排版。
## - 對話氣泡:預設在頭頂上方;頭頂被其他氣泡/桌寵佔住或碰到螢幕上緣就垂直翻轉到腳底下方;上下都不行就橫向階梯位移。
## - Status 面板:預設在桌寵右側;放不下或被擋住就換左側,再不行退回上下位置的避讓邏輯。
## 每次排版一律先做螢幕邊界鉗制、再做重疊避讓,避讓最多重試 MAX_RETRIES 次,超過就接受目前位置(穩定優先於零重疊)。
## 先來後到:已顯示的介面保持原位(先排),後來的才避讓。
##
## 還負責「重複前一句」(桌寵右鍵選單):只重播純文字與綁定動作,不再出現選項、也不重算 Flag。

## 對話氣泡跟隨桌寵移動的平滑速度(2026-09-30 使用者要求「再更慢一點」,原本是每影格直接貼齊,現在改成
## 指數平滑跟隨;值愈小追得愈慢)。只套用在對話氣泡,Status 面板維持原本直接貼齊(面板本來就不太需要柔順感,
## 使用者這次也只提對話氣泡)。
const BUBBLE_FOLLOW_SPEED := 5.0
const GAP := 6.0
const STAGGER_PADDING := 8.0
const MAX_RETRIES := 3
## 上下都被擋、橫向也推到螢幕邊緣時最多疊幾排(見 _place 尾段):排滿一排才換下一排,不會有氣泡一路橫向
## 排到工作區外面去擋住其他視窗。
const MAX_ROWS := 4
const REPEAT_SECONDS := 3.0
const MAX_HISTORY := 10
const DECIDE_SUSPENSE := 1.2

var _prompt_window: TextPromptWindow
var _prompt_pet: Node
## 桌寵發起的提問,氣泡最多等使用者這麼久(秒)才當作沒有回答;輸入視窗一開就沒有時限。
const ASK_PATIENCE_SECONDS := 600.0

var _state: Node
## 桌寵 → 目前的氣泡/Status 面板(每隻桌寵各最多一個)。
var _bubbles: Dictionary = {}
var _panels: Dictionary = {}
## 目前顯示中的介面(氣泡與面板),依出現先後排序。
var _order: Array[Control] = []
## 桌寵 → 最近說過的幾句(最後一個是最新的,可能正顯示中),重複前一句用。
var _history: Dictionary = {}
## 桌寵 → 排隊等著顯示的句子(每項 {line, ticket})。桌寵已經有一個氣泡時,別的積木鏈(計時事件、閒聊、狀態事件…)送來的句子
## 不會把它擠掉——使用者可能還在讀、或正在猶豫要不要回答——而是排在後面,前一個氣泡收掉才輪到。
var _queued: Dictionary = {}
var _connected_pets: Dictionary = {}
var _repeat_connected: Dictionary = {}
## 每個介面(氣泡/面板)目前橫向被推開多少(相對「置中/貼齊在桌寵旁邊」的基準位置的偏移量,像素;
## 0 = 沒被推開)。遲滯用:桌寵待機時的細微晃動會讓「擋到/沒擋到」判定每影格反覆切換,若每次都從
## 偏移 0 重新試一次,介面會在原位跟推開後的位置之間快速跳動;沿用上一影格的偏移當第一個候選,
## 穩定不變時就不會重算。
var _last_offsets: Dictionary = {}
## 桌寵 → 使用者拖曳/右鍵選單固定後的氣泡位置(左上角,畫布座標)。隨時都能固定,不綁定「對話集中」的
## 模式。只存在記憶體(不跨重開機),沒固定過的桌寵沿用一般跟隨排版。
var _pinned_positions: Dictionary = {}
var _chatroom: ChatRoomWindow
## 右鍵暫時穿透期間的淡化透明度(1.0 = 沒在穿透);新出現的氣泡/面板要照這個值起始,不然穿透期間冒出來的
## 新氣泡會是不透明的,跟其他已經淡掉的介面不一致,見 set_passthrough_fade()。
var _passthrough_alpha := 1.0


func _ready() -> void:
	layer = 10
	# 排版要早於 DesktopShell 彙整穿透多邊形,介面的點擊範圍才不會慢一影格。
	process_priority = -100
	_state = get_node("/root/DesktopShellState")
	_state.dialogue_line_requested.connect(_on_line_requested)
	_state.pet_registered.connect(_connect_pet)
	_state.text_input_requested.connect(_on_text_input)
	_state.dialogue_close_requested.connect(_close_bubble)
	for pet in get_tree().get_nodes_in_group("pets"):
		_connect_pet(pet)
	set_process(false)


## 換螢幕、或同一台螢幕解析度變了(見 DesktopShell.apply_monitor_setting()):固定氣泡(使用者拖曳/右鍵
## 固定的位置)跟聊天室視窗的展開位置都是絕對座標,依新舊視窗尺寸的比例挪過去。
func rescale_layout(old_size: Vector2, new_size: Vector2) -> void:
	if old_size.x <= 0.0 or old_size.y <= 0.0 or old_size.is_equal_approx(new_size):
		return
	var scale := new_size / old_size
	for pet: Node in _pinned_positions.keys():
		_pinned_positions[pet] = (_pinned_positions[pet] as Vector2) * scale
	if _chatroom != null:
		_chatroom.rescale_window_position(old_size, new_size)


## action_area/hover_ball:轉交給聊天室視窗(收合圖示的拖曳範圍限制、避開懸浮球,見 ChatRoomWindow.setup())。
## 由 DesktopShell 在 add_child(ui_manager) 之後明確呼叫(跟懸浮球等其他行動區相關元件同一套「外部明確 setup」慣例)。
func setup(action_area: Node, hover_ball: HoverBall) -> void:
	_chatroom = ChatRoomWindow.new()
	add_child(_chatroom)
	_chatroom.setup(action_area, hover_ball)


func _connect_pet(pet: Node) -> void:
	if _connected_pets.has(pet):
		return
	_connected_pets[pet] = true
	pet.status_requested.connect(_toggle_status.bind(pet))
	pet.decide_requested.connect(_on_decide.bind(pet))
	pet.timer_input_requested.connect(_on_timer_input.bind(pet))
	pet.tree_exiting.connect(_forget_pet.bind(pet))
	pet.interrupted.connect(_drop_queued.bind(pet))
	pet.bubble_pin_toggle_requested.connect(_on_bubble_pin_toggle.bind(pet))


func _forget_pet(pet: Node) -> void:
	_drop_queued(pet)
	if _prompt_pet == pet and is_instance_valid(_prompt_window):
		_prompt_window.cancel()
	_close_bubble(pet)
	_close_status(pet)
	_history.erase(pet)
	_connected_pets.erase(pet)
	_repeat_connected.erase(pet)
	_pinned_positions.erase(pet)


# --- 對話氣泡 ---

func _on_line_requested(pet: Node, line: Dictionary, ticket: RefCounted) -> void:
	_connect_repeat(pet)
	if _has_open_bubble(pet) and not bool(line.get("interrupts", false)):
		_enqueue(pet, line, ticket)
		return
	_present_line(pet, line, ticket)


func _present_line(pet: Node, line: Dictionary, ticket: RefCounted) -> void:
	if not _history.has(pet):
		_history[pet] = []
	_history[pet].append(line)
	if _history[pet].size() > MAX_HISTORY:
		_history[pet].pop_front()
	_show_bubble(pet, line, ticket)


func _has_open_bubble(pet: Node) -> bool:
	var bubble: DialogueBubble = _bubbles.get(pet)
	return bubble != null and is_instance_valid(bubble) and not bubble.is_closed()


func _enqueue(pet: Node, line: Dictionary, ticket: RefCounted) -> void:
	if not _queued.has(pet):
		_queued[pet] = []
	# 憑證只被呼叫者短暫拿著時,要由佇列持有它,不然排隊期間就被釋放了(見 _show_bubble 的說明)。
	_queued[pet].append({"line": line, "ticket": ticket})


## 桌寵被打斷或離場:排隊中的句子作廢(對應的積木鏈以「沒有選擇」醒來,接著會因為世代改變而中止)。
func _drop_queued(pet: Node) -> void:
	var waiting: Array = _queued.get(pet, [])
	_queued.erase(pet)
	for entry: Dictionary in waiting:
		if entry["ticket"] != null:
			entry["ticket"].finish(-1)


func _show_next_queued(pet: Node) -> void:
	var waiting: Array = _queued.get(pet, [])
	if waiting.is_empty() or not is_instance_valid(pet):
		return
	var entry: Dictionary = waiting.pop_front()
	if waiting.is_empty():
		_queued.erase(pet)
	_present_line(pet, entry["line"], entry["ticket"])


func _connect_repeat(pet: Node) -> void:
	if not _repeat_connected.has(pet):
		_repeat_connected[pet] = true
		pet.repeat_last_requested.connect(_on_repeat_last.bind(pet))


func _show_bubble(pet: Node, line: Dictionary, ticket: RefCounted) -> void:
	_close_bubble(pet)
	# 「聊天室式」/「簡訊式」模式下,不用等使用者互動的句子(沒有選項、也不是等點擊的重要提問)改走聊天室
	# 視窗;需要互動的句子(問題、選項)還是照舊用浮動氣泡——不然使用者沒辦法在聊天室視窗裡點選項。這兩個
	# 模式只差在視窗裡每一句怎麼畫(見 ChatRoomWindow.append_line()),路由規則相同。
	var options: Array = line.get("options", [])
	var wait_click := bool(line.get("wait_click", false))
	var interactive := not options.is_empty() or wait_click
	var chatroom_mode := AppSettings.bubble_display_mode()
	var in_chatroom_family := chatroom_mode == "chatroom" or chatroom_mode == "sms"
	var chatroom_route := in_chatroom_family and not interactive
	# 「即使存在聊天室也顯示氣泡」(桌寵管理 > 交互行為,2026-10-01):個別桌寵可以要求聊天室式模式下這句
	# 也額外彈浮動氣泡,不是只寫進聊天記錄——兩邊同時顯示。只影響要不要現形,chatroom_route(要不要寫進
	# 聊天記錄)本身不變。line["force_bubble"](2026-10-02,見 GameChat.say()):這句本身的性質就是該讓
	# 使用者當下看到(計時器時間到、中途提醒…),不是桌寵個別設定,兩者任一成立就現形。
	var force_bubble := chatroom_route and (bool((pet.interaction_rules as Dictionary).get("show_bubble_in_chatroom", false)) or bool(line.get("force_bubble", false)))
	var show_in_world := not chatroom_route or force_bubble
	var bubble := DialogueBubble.new()
	add_child(bubble)
	bubble.setup(pet, line, show_in_world)
	if show_in_world:
		# 右鍵穿透期間冒出來的新氣泡也要一起淡,不然跟其他已經淡掉的不一致;純聊天室式模式下這顆氣泡本來就是
		# show_in_world=false 的隱形氣泡(setup() 已經把 modulate.a 設成 0),不能被這裡蓋掉。
		bubble.modulate.a = _passthrough_alpha
	# chat_log = false(見 GameChat.say 的 quiet 參數):每局都喊、每隻桌寵都得喊一遍的短口號,聊天室式模式下
	# 不寫進聊天記錄(不然會洗版),但氣泡本身照舊建立、計時——只是這一句略過 append_line 這一步。
	# 2026-10-02 使用者要求:等點擊(wait_click)的重要提問一定要現形成浮動氣泡(上面 interactive 已經保證),
	# 但這種句子在「對話集中」開著時也可以順便記錄進聊天室(不像一般選項句——選項要在氣泡上點,寫進聊天室
	# 記錄沒有意義;等點擊的句子是純文字重要通知,跟其他句子一樣值得留底)。
	var should_log_to_chatroom := chatroom_route or (in_chatroom_family and wait_click)
	if should_log_to_chatroom and bool(line.get("chat_log", true)):
		_chatroom.append_line(pet, bubble.chat_text(), bubble.chat_color(), bubble.is_thought, bool(line.get("chain", false)))
	_bubbles[pet] = bubble
	_order.append(bubble)
	pet.has_open_bubble = true   # 右鍵選單「固定氣泡位置」決定能不能點用(沒有氣泡可以固定就灰掉)
	# 先清理自己的登記、再通知直譯器:直譯器醒來後可能立刻開下一句,那時舊氣泡必須已經登出。
	bubble.advanced.connect(_on_bubble_advanced.bind(pet, bubble))
	bubble.position_pinned.connect(_on_bubble_position_pinned)
	if ticket != null:
		# Callable 只記得物件、不持有參考:憑證若只有呼叫者短暫拿著(例如提問氣泡的憑證),會在函式結束時被釋放、連線跟著失效,所以掛在氣泡身上。
		bubble.set_meta(&"ticket", ticket)
		bubble.advanced.connect(ticket.finish)
		# 使用者拖曳/點擊/interact 等即時互動打斷時,連氣泡一起收掉。
		pet.interrupted.connect(bubble.close_silently, CONNECT_ONE_SHOT)
	_state.dialogue_started.emit(pet)
	set_process(true)
	_layout()


## 右鍵暫時穿透開始/結束時由 DesktopShell 呼叫(見 DesktopShell._set_overlay_passthrough_fade()):
## 這個 CanvasLayer 本身沒有 modulate(CanvasLayer 不是 CanvasItem),要自己逐一淡化每個顯示中的氣泡/
## 面板/聊天室視窗;chatroom_route 的隱形氣泡(show_in_world=false)本來就 modulate.a=0,略過不動,
## 不然穿透結束時會被誤改回不透明、變成真的看得見。
func set_passthrough_fade(alpha: float) -> void:
	_passthrough_alpha = alpha
	for control in _order:
		if control is DialogueBubble and not (control as DialogueBubble).is_in_group("Cutout"):
			continue
		control.modulate.a = alpha
	if _chatroom != null:
		_chatroom.modulate.a = alpha


func _on_bubble_position_pinned(pet: Node, position: Vector2) -> void:
	_pinned_positions[pet] = position
	pet.bubble_pinned = true


## 右鍵選單「固定氣泡位置」(明確的固定/解除固定,不是只能靠拖曳——2026-09-30 使用者回饋:希望有明確的方式)。
## 已經固定就解除;沒固定就固定在目前顯示中的氣泡位置(選單項目在沒有氣泡可固定時本來就會灰掉,這裡多一層防呆)。
func _on_bubble_pin_toggle(pet: Node) -> void:
	if _pinned_positions.has(pet):
		_pinned_positions.erase(pet)
		pet.bubble_pinned = false
		return
	var bubble: DialogueBubble = _bubbles.get(pet)
	if bubble == null or not is_instance_valid(bubble) or bubble.is_closed():
		return
	_pinned_positions[pet] = bubble.global_position
	pet.bubble_pinned = true


func _on_bubble_advanced(_choice: int, pet: Node, bubble: DialogueBubble) -> void:
	if _bubbles.get(pet) == bubble:
		_bubbles.erase(pet)
		_state.dialogue_finished.emit(pet)
		if is_instance_valid(pet):
			pet.has_open_bubble = false
	_order.erase(bubble)
	_last_offsets.erase(bubble)
	if pet.interrupted.is_connected(bubble.close_silently):
		pet.interrupted.disconnect(bubble.close_silently)
	bubble.queue_free()
	set_process(not _order.is_empty())
	_show_next_queued(pet)


func _close_bubble(pet: Node) -> void:
	var bubble: DialogueBubble = _bubbles.get(pet)
	if bubble != null and is_instance_valid(bubble):
		bubble.close_silently()


## 重複前一句:純文字,沒有選項、固定秒數後自動收起。
## - 沒有氣泡在說話時:重播最近說過的那一句(連同綁定動作)。
## - 正在說話時:「前一句」是目前這一句之前的那句,所以暫時把氣泡換成它(不影響目前這句的進行與積木鏈),
##   幾秒後或點一下就換回目前這句;沒有更早的一句就什麼都不做。
func _on_repeat_last(pet: Node) -> void:
	var history: Array = _history.get(pet, [])
	if _bubbles.has(pet):
		if history.size() >= 2:
			(_bubbles[pet] as DialogueBubble).peek_line(history[history.size() - 2], REPEAT_SECONDS)
		return
	if history.is_empty():
		return
	var line: Dictionary = history[history.size() - 1]
	var repeated := line.duplicate()
	repeated["options"] = []
	repeated["auto_seconds"] = REPEAT_SECONDS
	if str(repeated.get("bind_action", "")) != "":
		pet.play_action(StringName(str(repeated["bind_action"])), -1, true)
	_show_bubble(pet, repeated, null)


# --- 文字輸入與抽籤 ---

## 向使用者要一段文字(同時只會有一個輸入視窗;已經開著就直接回「略過」)。
## 桌寵/積木自己發起的提問(request.direct = false)絕不直接跳出視窗——使用者可能正在忙別的事,視窗會搶走鍵盤焦點、打斷打字:
## 先用氣泡問(有「✎ 回答…」和「先不要」兩個按鈕,停留很久給使用者慢慢想),使用者按了「回答」才開輸入視窗;
## 不理它、按「先不要」、或桌寵被點擊打斷,都只是「沒有答案」。使用者自己從選單叫出來的(direct = true,如「幫我決定」)才直接開視窗。
func _on_text_input(pet: Node, request: Dictionary, ticket: RefCounted) -> void:
	if is_instance_valid(_prompt_window):
		ticket.finish("", false)
		return
	if bool(request.get("direct", true)):
		_open_prompt_window(pet, request, ticket)
		return
	var bubble_ticket := DialogueTicket.new()
	bubble_ticket.finished.connect(func(choice: int) -> void:
		if choice == 0 and is_instance_valid(pet) and not is_instance_valid(_prompt_window):
			_open_prompt_window(pet, request, ticket)
		else:
			ticket.finish("", false))
	_on_line_requested(pet, {
		"text": str(request.get("bubble_text", request.get("prompt", ""))), "font": "", "typewriter": true, "auto_seconds": 0.0,
		"patience": ASK_PATIENCE_SECONDS, "bind_action": "", "options": ["✎ 回答…", "先不要"],
	}, bubble_ticket)


## 開輸入視窗(使用者已經按了「回答」或是自己從選單叫出來的)。視窗開著期間(ticket.typing)桌寵被點擊/拖曳不會取消輸入;
## 也算「對話進行中」(dialogue_started/finished),自動閒聊不會在使用者打字時插話。
func _open_prompt_window(pet: Node, request: Dictionary, ticket: RefCounted) -> void:
	ticket.typing = true
	_prompt_window = TextPromptWindow.new()
	add_child(_prompt_window)
	_prompt_pet = pet
	_prompt_window.setup(pet.get_label(), str(request.get("prompt", "")), str(request.get("default", "")), int(request.get("max_length", PetText.DEFAULT_MAX_LENGTH)), ticket)
	_state.dialogue_started.emit(pet)
	var opened_window := _prompt_window
	ticket.finished.connect(func(_text: String, _accepted: bool) -> void:
		# queue_free() 是延遲到這一幀結束才真的生效,is_instance_valid(_prompt_window) 在那之前一路都是 true;
		# 如果呼叫端在同一輪(例如按下確定的當下)緊接著就想開下一個輸入視窗(見 _on_timer_input 問完時長
		# 接著問中途提醒),會被上面 _on_text_input() 的「已經有視窗開著」防呆擋下、直接判定成「沒有輸入」,
		# 中途提醒的欄位因此永遠開不出來(2026-09-29 使用者實機回報)。這裡在憑證完成的當下就同步清空
		# _prompt_window(不等 queue_free() 真的生效),下一個視窗才開得出來。
		if _prompt_window == opened_window:
			_prompt_window = null
		_prompt_pet = null
		if is_instance_valid(pet):
			_state.dialogue_finished.emit(pet))


## 右鍵選單「幫我設定計時器…」(倒數)/「幫我計時…」(碼表):問要計時多久,交給桌寵的 PetTimer。
## 計時可以留空 = 一直記錄到使用者喊停;計時器一定要有時間。看不懂的輸入桌寵會請你重新設定。
func _on_timer_input(kind: int, pet: Node) -> void:
	var countdown := kind == PetTimer.Kind.COUNTDOWN
	var ticket := InputTicket.new()
	_on_text_input(pet, {
		"prompt": tr("要計時多久?可以寫「10 分鐘」「90 秒」「1 小時 30 分」「25:00」;只寫數字就是分鐘。") if countdown else tr("要計時多久?寫法同左(例如「30 分鐘」「25:00」);留空 = 一直記錄到你叫我停止。"),
		"default": "10 分鐘" if countdown else "", "max_length": 30,
	}, ticket)
	var got: Array = [ticket.closed, false]
	if not ticket.closed:
		got = await ticket.finished
	if not bool(got[1]) or not is_instance_valid(pet):
		return
	var seconds := PetTimer.parse_duration(str(got[0]))
	var line := {"typewriter": true, "auto_seconds": 5.0, "options": []}
	if seconds < 0.0 or (countdown and seconds <= 0.0):
		line["text"] = tr("我看不懂這個時間耶……可以寫「10 分鐘」「90 秒」或「25:00」。")
		_on_line_requested(pet, line, null)
		return
	var reminder_ticket := InputTicket.new()
	_on_text_input(pet, {
		"prompt": tr("要不要順便設定中途提醒(只響一聲,不會結束計時)?可以寫「每5分鐘」「到10分鐘」,兩種可以一起寫、用逗號隔開;不需要就留空直接送出。"),
		"default": "", "max_length": 40,
	}, reminder_ticket)
	var reminder_got: Array = [reminder_ticket.closed, false]
	if not reminder_ticket.closed:
		reminder_got = await reminder_ticket.finished
	if not is_instance_valid(pet):
		return
	var reminder_spec := PetTimer.parse_reminder_spec(str(reminder_got[0]) if bool(reminder_got[1]) else "")
	if not bool(reminder_spec["ok"]):
		line["text"] = tr("中途提醒的時間我看不懂,先幫你開始計時,不加中途提醒。")
		_on_line_requested(pet, line, null)
		reminder_spec = {"ok": true, "interval": 0.0, "waypoints": [] as Array[float]}
	if not pet.pet_timer.start(kind as PetTimer.Kind, seconds, "", float(reminder_spec["interval"]), reminder_spec["waypoints"]):
		line["text"] = tr("我已經在計時了,要先停下來才能重新設定。")
		_on_line_requested(pet, line, null)


## 右鍵選單「幫我決定(抽籤)」:問使用者選項 → 桌寵抖一下 → 說出抽到的結果。
func _on_decide(pet: Node) -> void:
	var ticket := InputTicket.new()
	_on_text_input(pet, {"prompt": "有哪些選項?用逗號分隔(例如:拉麵,咖哩,壽司)", "default": "", "max_length": PetText.HARD_MAX_LENGTH}, ticket)
	var got: Array = [ticket.closed, false]
	if not ticket.closed:
		got = await ticket.finished
	if not bool(got[1]) or not is_instance_valid(pet):
		return
	var options := PetText.parse_options(str(got[0]))
	var line := {"typewriter": true, "auto_seconds": 6.0, "options": []}
	if options.size() < 2:
		line["text"] = "至少要給我兩個選項才能抽喔。"
		_on_line_requested(pet, line, null)
		return
	pet.shiver(DECIDE_SUSPENSE)
	await get_tree().create_timer(DECIDE_SUSPENSE).timeout
	if not is_instance_valid(pet):
		return
	line["text"] = tr("抽到了:[b]%s[/b]!") % PetText.escape_bbcode(options.pick_random())
	_on_line_requested(pet, line, null)


# --- Status 面板 ---

## 右鍵選單「查看狀態」:再按一次就收起(切換)。
func _toggle_status(pet: Node) -> void:
	if _panels.has(pet):
		_close_status(pet)
		return
	var panel := StatusPanel.new()
	add_child(panel)
	panel.setup(pet)
	panel.modulate.a = _passthrough_alpha   # 理由同 _show_bubble() 的氣泡
	_panels[pet] = panel
	_order.append(panel)
	panel.closed.connect(_on_status_closed.bind(pet, panel))
	set_process(true)
	_layout()


func _on_status_closed(pet: Node, panel: StatusPanel) -> void:
	if _panels.get(pet) == panel:
		_panels.erase(pet)
	_order.erase(panel)
	panel.queue_free()
	set_process(not _order.is_empty())


func _close_status(pet: Node) -> void:
	var panel: StatusPanel = _panels.get(pet)
	if panel != null and is_instance_valid(panel):
		panel.close()


# --- 排版 ---

func _process(_delta: float) -> void:
	for control in _order:
		# 綁定動作的句子:說話期間維持該姿勢。
		if control is DialogueBubble and control.bind_action != &"":
			control.pet.extend_hold(0.3)
	_layout()


## 統一排版。順序 = 出現的先後(先來的先排、位置固定),後來的避讓前面的介面與其他桌寵。
func _layout() -> void:
	var full_screen := Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size))
	var monitors := monitor_rects()
	var placed: Array[Rect2] = []
	# 滑鼠指著對話氣泡時整個排版跳過(位置、避讓都凍結,只是照舊把目前的外框餵給後面的避讓計算),不然選項/文字
	# 內容跟著桌寵移動時使用者很難點準或閱讀(2026-09-30 使用者實機回報)。用 OS 滑鼠座標判斷,跟 HoverBall
	# 同一套做法(這個視窗本身是無邊框全螢幕穿透視窗,不能只靠 Godot 的 mouse_entered,滑鼠在穿透區時視窗根本
	# 收不到事件)。
	var os_mouse := Vector2(DisplayServer.mouse_get_position()) - Vector2(get_window().position)
	# 對話氣泡要避開聊天室視窗(2026-10-02 使用者要求),聊天室/簡訊式視窗沒顯示時這裡是空矩形,當障礙物
	# 完全沒作用。
	var chatroom_rect := Rect2()
	if _chatroom != null and _chatroom.visible:
		chatroom_rect = Rect2(_chatroom.global_position, _chatroom.size)
	for control in _order:
		var pet: Node = control.pet
		# size != ZERO:剛建立、還沒排過版的氣泡容器可能暫時是零尺寸(見 PanelContainer 的排版時序),零尺寸的矩形
		# 在(0,0)不該被滑鼠「碰到」,不然剛出現的氣泡會被凍結在還沒排版的預設位置,一直卡在畫面角落。
		# _last_offsets.has(control):這隻氣泡已經至少真正排版過一次——剛出現、還沒排過版的氣泡預設在 (0,0),
		# 不該被「滑鼠碰到」凍結住(不然要是滑鼠座標剛好也在 (0,0) 附近,新氣泡會直接卡死在畫面角落,永遠等不到
		# 第一次真正的排版;無頭測試環境下 DisplayServer.mouse_get_position() 固定回報 (0,0),就是這個情境)。
		if control is DialogueBubble and _last_offsets.has(control) and control.global_rect().has_point(os_mouse):
			placed.append(control.global_rect())
			continue
		# 氣泡固定:正在被拖曳的氣泡不搶(位置由它自己的拖曳邏輯直接設);已經固定過的桌寵之後固定出現在
		# 那個位置,不再跑一般的跟隨/避讓排版。隨時都能固定,不綁定「對話集中」的模式。
		if control is DialogueBubble:
			if control.is_dragging_pin():
				placed.append(control.global_rect())
				continue
			if _pinned_positions.has(pet):
				control.reset_size()
				control.global_position = _pinned_positions[pet]
				control.place_tag()
				if control.has_method("place_tail"):
					control.place_tail(pet.get_body_rect())
				placed.append(control.global_rect())
				continue
		# 名字標籤有一半跨在介面上緣之外,可用的螢幕範圍上緣要扣掉這一段,標籤才不會被螢幕頂端裁掉。
		var overhang: float = control.tag_overhang()
		# 對話框可以畫在行動區框架外,但一定要留在「桌寵所在的那一個螢幕」裡(多螢幕時不會跨到兩個螢幕之間或螢幕外)。
		var monitor := screen_rect_for(pet.get_body_rect(), monitors, full_screen)
		var screen := Rect2(monitor.position + Vector2(0.0, overhang), monitor.size - Vector2(0.0, overhang))
		control.reset_size()
		var obstacles: Array[Rect2] = placed.duplicate()
		for other: Node in get_tree().get_nodes_in_group("pets"):
			if other != pet:
				obstacles.append(other.get_body_rect())
		if control is DialogueBubble and chatroom_rect.size != Vector2.ZERO:
			obstacles.append(chatroom_rect)
		var body: Rect2 = pet.get_body_rect()
		var rect: Rect2
		var had_offset_before := _last_offsets.has(control)
		if control is StatusPanel:
			rect = _place_beside(control.size, body, control.flipped, screen, obstacles)
			control.flipped = rect.get_center().x < body.get_center().x
		else:
			# 思考泡泡的尾巴(幾顆小圓泡泡)要佔一段空間,泡泡離桌寵遠一點。
			var extra_gap: float = control.tail_space() if control.has_method("tail_space") else 0.0
			var previous_offset: float = _last_offsets.get(control, 0.0)
			rect = _place(control.size, body, control.flipped, screen, obstacles, GAP + extra_gap, previous_offset)
			# 一般的避讓(_place)重試有上限(MAX_ROWS),哲學上是「穩定優先於零重疊」,超過重試次數就接受
			# 目前位置,其他氣泡/桌寵這樣沒關係——但聊天室視窗這個障礙物使用者要求一定要讓開,不接受「盡力
			# 而為還是疊到」,這裡在一般避讓算完之後,對話氣泡額外做一次「保證脫離聊天室視窗」的強制修正
			# (2026-10-02 使用者實機回報:氣泡還是會跑進聊天室視窗範圍內,見 _clear_of_chatroom())。
			if control is DialogueBubble and chatroom_rect.size != Vector2.ZERO:
				rect = _clear_of_chatroom(rect, chatroom_rect, screen)
			control.flipped = rect.get_center().y > body.get_center().y
			_last_offsets[control] = rect.position.x - (body.get_center().x - control.size.x * 0.5)
		if control is DialogueBubble and had_offset_before:
			# 不是第一次排版(上一影格前就有記錄)才平滑跟隨;剛出現的氣泡要直接貼齊,不能從畫面另一頭慢慢飄過來。
			var weight := 1.0 - exp(-get_process_delta_time() * BUBBLE_FOLLOW_SPEED)
			control.global_position = control.global_position.lerp(rect.position, weight)
		else:
			control.global_position = rect.position
		control.place_tag()
		if control.has_method("place_tail"):
			control.place_tail(body)
		placed.append(rect)


## 各螢幕的可用範圍(換算成這個視窗的畫布座標:桌面全域座標 − 視窗位置);讀不到(無頭)回傳空陣列。
func monitor_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if DisplayServer.get_name() == "headless":
		return result
	var origin := Vector2(get_window().position)
	for i in DisplayServer.get_screen_count():
		var usable := DisplayServer.screen_get_usable_rect(i)
		result.append(Rect2(Vector2(usable.position) - origin, Vector2(usable.size)))
	return result


## 桌寵身體所在的螢幕範圍:和身體重疊面積最大的那個螢幕(都沒重疊就選離身體中心最近的),再和整個視窗範圍取交集;沒有螢幕資訊就用整個視窗。
static func screen_rect_for(body: Rect2, monitors: Array[Rect2], fallback: Rect2) -> Rect2:
	if monitors.is_empty():
		return fallback
	var best := monitors[0]
	var best_area := -1.0
	var best_distance := INF
	for monitor in monitors:
		var overlap := monitor.intersection(body)
		var area := overlap.size.x * overlap.size.y if overlap.size.x > 0.0 and overlap.size.y > 0.0 else 0.0
		var distance := body.get_center().distance_to(monitor.get_center())
		if area > best_area or (area == best_area and area == 0.0 and distance < best_distance):
			best = monitor
			best_area = area
			best_distance = distance
	var clipped := best.intersection(fallback)
	return clipped if clipped.size.x > 0.0 and clipped.size.y > 0.0 else fallback


## Status 面板:右側(或上次的那一側)→ 另一側 → 都不行就退回頭頂/腳底的避讓。垂直方向置中在桌寵身上再鉗制。
func _place_beside(size: Vector2, body: Rect2, left_first: bool, screen: Rect2, obstacles: Array[Rect2]) -> Rect2:
	var y := body.get_center().y - size.y * 0.5
	var right := _clamp(Rect2(Vector2(body.end.x + GAP, y), size), screen)
	var left := _clamp(Rect2(Vector2(body.position.x - size.x - GAP, y), size), screen)
	for candidate in ([left, right] if left_first else [right, left]):
		# 鉗制可能把面板推回桌寵身上,所以還要確認沒有壓到桌寵自己(obstacles 只含其他桌寵,這裡另外檢查本尊)。
		if not candidate.intersects(body) and not _hits(candidate, obstacles):
			return candidate
	return _place(size, body, false, screen, obstacles)


## 找一個合法位置:先照上次的上下方向,先鉗制螢幕再避讓;卡住就翻轉,兩邊都卡再橫向位移。
## previous_offset:上一影格算出來的橫向推開量,第一個候選一律先試「沿用這個偏移」,還站得住(沒撞到、
## 上下方向沒變、還在螢幕內)就直接用,不要每影格都從偏移 0 重新試——這是避免避讓判定在臨界值反覆
## 切換、介面跟著快速晃動的關鍵(遲滯只作用在橫向推開量,不影響「跟著桌寵目前位置」這件事本身,
## 因為 above/below 每影格本來就是照 body 現在的座標算的)。
func _place(size: Vector2, body: Rect2, flipped: bool, screen: Rect2, obstacles: Array[Rect2], gap := GAP, previous_offset := 0.0) -> Rect2:
	var base_x := body.get_center().x - size.x * 0.5
	var above := Vector2(base_x, body.position.y - size.y - gap)
	var below := Vector2(base_x, body.end.y + gap)
	# 緊貼螢幕頂部一律往下翻,確保完整顯示。
	if above.y < screen.position.y:
		flipped = true
	var first := below if flipped else above
	var second := above if flipped else below
	if not is_zero_approx(previous_offset):
		# 只有「置中位置離障礙物還有一段安全距離」才放手讓它歸位;不是勉強擦邊沒撞到就馬上收回去,
		# 不然會在「剛好卡邊」的臨界值來回切換,又製造出一種新的晃動(這次是「歸位/推開」反覆切換)。
		var centered_clearly_free := not _hits(Rect2(first, size).grow(STAGGER_PADDING), obstacles)
		if not centered_clearly_free:
			var kept := _clamp(Rect2(Vector2(base_x + previous_offset, first.y), size), screen)
			if not _hits(kept, obstacles):
				return kept
	var rect := _clamp(Rect2(first, size), screen)
	if not _hits(rect, obstacles):
		return rect
	var alternative := _clamp(Rect2(second, size), screen)
	if not _hits(alternative, obstacles) and (second.y >= screen.position.y or second == below):
		return alternative
	# 上下都被擋:先沿 X 軸往外推(維持在同一排),推到貼齊螢幕邊緣還是擋著,就換到「更遠離桌寵」的下一排,
	# 橫向位置重新從置中開始試——排滿一排才換下一排(概念上算是氣泡版的換行),不會有一長串氣泡橫向
	# 一路排到螢幕外面去擋住工作區裡的其他視窗。往外疊的方向跟 flipped 一致(原本决定貼在頭頂還是腳下的
	# 那個方向),疊到 MAX_ROWS 排都還是滿的就用最後一排最後的嘗試位置(至少保證在螢幕內)。
	var away := 1.0 if flipped else -1.0
	var row_step := size.y + gap
	var candidate := rect
	for row in MAX_ROWS:
		var row_y := first.y + away * row_step * row
		candidate = _clamp(Rect2(Vector2(rect.position.x, row_y), size), screen)
		var row_cleared := false
		for i in MAX_RETRIES:
			var blocker := _first_hit(candidate, obstacles)
			if blocker.size == Vector2.ZERO:
				row_cleared = true
				break
			var push_right := candidate.get_center().x >= blocker.get_center().x
			var pushed_x := blocker.end.x + STAGGER_PADDING if push_right else blocker.position.x - size.x - STAGGER_PADDING
			var pushed := _clamp(Rect2(Vector2(pushed_x, row_y), size), screen)
			if is_equal_approx(pushed.position.x, candidate.position.x):
				break   # 這一排已經推到螢幕邊緣還是擋著,換下一排
			candidate = pushed
		if row_cleared:
			return candidate
	return candidate


## 保證氣泡不會疊在聊天室視窗上面(2026-10-02 使用者要求):rect 沒撞到就原樣回傳;撞到了就改貼在聊天室
## 視窗的上緣或下緣(挑離原本位置比較近、夾進螢幕後也真的不再相交的那一側),兩側都還是相交(聊天室視窗
## 比螢幕還高這種極端情況)才退而求其次改貼左右兩側;再不行(聊天室視窗整個蓋住螢幕)才維持原樣,不堅持
## 到底卡死排版。跟一般的 _place() 重試邏輯分開獨立跑一次,保證結果,不是「盡力而為」。
func _clear_of_chatroom(rect: Rect2, chatroom_rect: Rect2, screen: Rect2) -> Rect2:
	if not rect.intersects(chatroom_rect):
		return rect
	var above := _clamp(Rect2(Vector2(rect.position.x, chatroom_rect.position.y - rect.size.y - GAP), rect.size), screen)
	var below := _clamp(Rect2(Vector2(rect.position.x, chatroom_rect.end.y + GAP), rect.size), screen)
	var candidates: Array[Rect2] = []
	if absf(rect.position.y - above.position.y) <= absf(rect.position.y - below.position.y):
		candidates = [above, below]
	else:
		candidates = [below, above]
	for candidate in candidates:
		if not candidate.intersects(chatroom_rect):
			return candidate
	var left := _clamp(Rect2(Vector2(chatroom_rect.position.x - rect.size.x - GAP, rect.position.y), rect.size), screen)
	var right := _clamp(Rect2(Vector2(chatroom_rect.end.x + GAP, rect.position.y), rect.size), screen)
	var side_candidates: Array[Rect2] = [left, right]
	for candidate in side_candidates:
		if not candidate.intersects(chatroom_rect):
			return candidate
	return rect   # 聊天室視窗大到整個蓋滿螢幕這種極端情況,讓不出空間,保留原位置而不是硬夾出畫面外。


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
