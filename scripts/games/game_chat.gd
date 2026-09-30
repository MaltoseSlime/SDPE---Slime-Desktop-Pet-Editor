class_name GameChat
extends RefCounted
## 小遊戲(擲骰、猜拳)的對話泡泡輔助:所有輸出都走桌寵的對話氣泡(不開任何視窗),
## 對使用者的提問用氣泡上的選項按鈕。句子帶 interrupts = true,遊戲的即時演出可以直接取代目前的氣泡。
## 沒有對話介面(自動測試)時什麼都不做、提問直接回 -1,不會卡住。

const WIN_LINES: Array[String] = ["耶!我贏了~", "哼哼,運氣不錯嘛。", "太好了!", "嘿嘿,承讓承讓。"]
const LOSE_LINES: Array[String] = ["可、可惡!再來一次!", "這、這次不算啦!!", "(氣鼓鼓)……", "哼!運氣而已!"]
const ANGRY_LINES: Array[String] = ["氣死我了!!再來!!", "怎麼又輸!!不服氣!!", "(整隻鼓成一團,抖個不停)"]
const TIE_LINES: Array[String] = ["平手?!", "居然平手……", "再來一次!"]


## 兩隻桌寵對戰結束後,替雙方記下對象:對手、贏家、輸家(平手就沒有贏家輸家)。result_a 是 a 的結果(win / lose / tie / draw)。
static func set_result_context(a: Node, b: Node, result_a: String) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	a.set_counterpart("opponent", b)
	b.set_counterpart("opponent", a)
	for pet: Node in [a, b]:
		if result_a == "win" or result_a == "lose":
			pet.set_counterpart("winner", a if result_a == "win" else b)
			pet.set_counterpart("loser", b if result_a == "win" else a)
		else:
			pet.clear_counterpart("winner")
			pet.clear_counterpart("loser")


## 這些桌寵開始 / 結束一場對戰(計數,同一隻同時參加幾場就加幾)。不管這場對戰是誰發起的(自己主動找、
## 被別隻桌寵邀請、還是被使用者叫去對戰),只要真的開打了就算「跟隨者想去做別的事情」,先離開路隊
## (見 Pet._tick_pet_follow_lifecycle 的說明;玩球的對應位置在 PetBallPlay._begin())。
static func enter(pets: Array) -> void:
	for pet: Variant in pets:
		if is_instance_valid(pet):
			if pet.is_following():
				pet.stop_follow()
			pet.game_depth += 1


static func leave(pets: Array) -> void:
	for pet: Variant in pets:
		if is_instance_valid(pet):
			pet.game_depth = maxi(pet.game_depth - 1, 0)


## 邀請被擋下時(對方正在對戰中)邀請者在心裡想的話。game_name = 猜拳 / 拚骰。
static func think_blocked(inviter: Node, busy: Node, game_name: String) -> void:
	if is_instance_valid(busy):
		think(inviter, TranslationServer.translate("(雖然想邀請%s玩%s,但看起來對方正在忙……)") % [busy.get_label(), game_name], 3.6)


## 思考泡泡(oO)裡的一句話,只有自己的心聲,不是對誰說。
static func think(pet: Node, text: String, seconds := 3.0) -> void:
	if not is_instance_valid(pet):
		return
	var state := pet.get_node("/root/DesktopShellState")
	if state.dialogue_line_requested.get_connections().is_empty():
		return
	state.dialogue_line_requested.emit(pet, {
		"text": text, "font": "", "typewriter": false, "auto_seconds": seconds,
		"bind_action": "", "options": [], "interrupts": true, "bubble": "thought",
	}, DialogueTicket.new())


## quiet = true:這句不算「值得留底」的內容(每一局都會喊、還每隻參賽的桌寵都得喊一遍的短口號,例如猜拳倒數
## 「剪刀…石頭…布!」、拚骰的「第 X 局!」、平手重來的提示)——氣泡照舊正常顯示,只是「聊天室式」模式下
## 不會把這種洗版的重複句子寫進聊天記錄(見 UiManager._show_bubble 的 chat_log 判斷)。
static func say(pet: Node, text: String, seconds := 3.0, quiet := false) -> void:
	if not is_instance_valid(pet):
		return
	var state := pet.get_node("/root/DesktopShellState")
	if state.dialogue_line_requested.get_connections().is_empty():
		return
	var line := {
		"text": text, "font": "", "typewriter": false, "auto_seconds": seconds,
		"bind_action": "", "options": [], "interrupts": true,
	}
	if quiet:
		line["chat_log"] = false
	state.dialogue_line_requested.emit(pet, line, DialogueTicket.new())


## 用氣泡問使用者一個選擇題,回傳選了第幾個(0 起算);沒有介面、被打斷、逾時都回 -1。
static func ask(pet: Node, text: String, options: Array, patience := 60.0) -> int:
	if not is_instance_valid(pet):
		return -1
	var state := pet.get_node("/root/DesktopShellState")
	if state.dialogue_line_requested.get_connections().is_empty():
		return -1
	var ticket := DialogueTicket.new()
	var result := [-1]
	ticket.finished.connect(func(choice: int) -> void: result[0] = choice)
	state.dialogue_line_requested.emit(pet, {
		"text": text, "font": "", "typewriter": false, "auto_seconds": 0.0, "patience": patience,
		"bind_action": "", "options": options, "interrupts": true,
	}, ticket)
	if not ticket.closed:
		await ticket.finished
	return int(result[0])


## 這隻桌寵的遊戲結果有積木事件(event_when_dice_contest / event_when_rps)就交給積木,沒有就用內建反應:
## 贏了開心跳一下、輸了氣得發抖(連輸越氣)、平手不服氣。kind = "dice_contest" 或 "rps",outcome = win / lose / tie(draw)。
static func react(pet: Node, kind: String, outcome: String, vs_user := false) -> void:
	if not is_instance_valid(pet):
		return
	var normalized := "tie" if outcome == "draw" else outcome
	pet.record_game_result("dice" if kind == "dice_contest" else kind, normalized)
	if normalized == "lose":
		pet.game_losses_in_row += 1
	elif normalized == "win":
		pet.game_losses_in_row = 0
	if pet.vitality != null:
		pet.vitality.on_game_result(normalized, vs_user)   # 連敗數要先更新(見 PetVitality.on_game_result)
	if pet.logic != null and pet.logic.run_game_hats(kind, normalized):
		return
	match normalized:
		"win":
			pet.perform_hops(1, false)
			say(pet, "[wave]%s[/wave]" % WIN_LINES.pick_random(), 3.0)
		"lose":
			var streak: int = pet.game_losses_in_row
			if streak >= 2:
				pet.shiver(2.5)
				say(pet, "[shake][color=#ff5a5a]%s[/color][/shake]" % ANGRY_LINES.pick_random(), 3.5)
			else:
				pet.shiver(1.5)
				say(pet, "[shake]%s[/shake]" % LOSE_LINES.pick_random(), 3.0)
		_:
			say(pet, TIE_LINES.pick_random(), 2.5)
