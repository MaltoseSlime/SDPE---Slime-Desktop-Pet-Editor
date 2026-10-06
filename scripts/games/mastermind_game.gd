class_name MastermindGame
extends RefCounted
## 珠璣妙算(Mastermind,1A2B):猜一串顏色的暗碼,允許重複,用完次數沒人猜中就攤牌。使用者對桌寵、
## 桌寵對桌寵、全體(使用者+任意隻數的桌寵)共用同一套輪流猜測邏輯 —— 跟拚骰/猜拳大逃殺不一樣,就算只有
## 2 位參加者也一律用獨立小面板(MastermindBoard)顯示猜測紀錄,不開對話氣泡(規格書明確要求避免洗版,
## 逐輪猜色本來就不適合塞進一句對話)。只有「整場結束」這個一輩子一次的時刻才讓桌寵開口說話。
## 2026-10-04 使用者要求:色票從 4 色加到 6 色(多黑、白兩色),密碼長度(CODE_LENGTH_CHOICES = 3 或 4)
## 改成每隻桌寵右鍵選單自己設的「題型」(Pet.mastermind_code_length),不是全域固定值;長度愈長允許的
## 猜測次數也愈多(見 ATTEMPTS_BY_LENGTH)。
## 桌寵猜色策略(候選池過濾):每位桌寵自己維護一份候選組合池,猜完後用這次的結果(幾A幾B)篩掉不可能
## 的組合,8 成選池子裡排最前面的(上一輪篩完剩下的第一個),2 成隨機選池子裡的其他組合混一點運氣成分。
## 沒有積木掛勾(HTML 積木編輯器已凍結,不能加新的 event_when_mastermind),輸贏只用內建反應。

const CODE_LENGTH_CHOICES: Array[int] = [3, 4]
const DEFAULT_CODE_LENGTH := 3
const ATTEMPTS_BY_LENGTH := {3: 8, 4: 10}
const COLOR_PALETTE: Array[String] = ["🔴", "🟡", "🔵", "🟣", "⚫", "⚪"]
const REVEAL_LINES: Array[String] = ["沒人猜中啊……答案其實是 %s", "次數用完了,公布答案:%s"]
const SOLVE_LINES: Array[String] = ["破解了密碼!答案是 %s", "哈,猜中了!就是 %s!"]
const USER_WIN_LINES: Array[String] = ["唔,被你猜中了……答案是 %s", "居然被你破解了,服氣!答案是 %s"]
const FORFEIT_LINE := "這個我猜不出來,不猜了……"


static func _wait(pet: Node, seconds: float) -> void:
	await pet.get_tree().create_timer(seconds).timeout


## secret/guess 長度要一致(由呼叫端保證,見 _run 的 code_length);用 secret.size() 當長度,不寫死 3,
## 這樣 3 格跟 4 格題型可以共用同一套判定邏輯。
static func evaluate_guess(secret: Array, guess: Array) -> Dictionary:
	var length := secret.size()
	var a_count := 0
	var unmatched_secret: Array = []
	var unmatched_guess: Array = []
	for i in length:
		if guess[i] == secret[i]:
			a_count += 1
		else:
			unmatched_secret.append(secret[i])
			unmatched_guess.append(guess[i])
	var b_count := 0
	for color: String in unmatched_guess:
		var idx: int = unmatched_secret.find(color)
		if idx != -1:
			b_count += 1
			unmatched_secret.remove_at(idx)
	return {"a": a_count, "b": b_count}


## 用疊代展開取代寫死 3 層巢狀迴圈,length = 3 或 4 都能共用(6 色 3 格 = 216 組、4 格 = 1296 組,
## 一次性算完全部候選組合的成本都可忽略)。
static func _generate_full_pool(length: int) -> Array:
	var pool: Array = [[]]
	for i in length:
		var next_pool: Array = []
		for prefix: Array in pool:
			for color: String in COLOR_PALETTE:
				next_pool.append((prefix as Array) + [color])
		pool = next_pool
	return pool


static func _filter_pool(pool: Array, last_guess: Array, result: Dictionary) -> Array:
	var filtered: Array = []
	for candidate: Array in pool:
		var sim := evaluate_guess(candidate, last_guess)
		if sim["a"] == result["a"] and sim["b"] == result["b"]:
			filtered.append(candidate)
	return filtered


## level(見 GameAiLevel)控制「候選池明明篩出最可能是答案的那組,卻隨便挑池子裡別組」的機率;level 不給
## (= 4)時完全不犯錯(只要候選池還有東西就一定挑排第一的)。實際對戰一律帶上桌寵自己的 `mastermind_ai_level`
## (預設 3,跟這裡的函式預設 4 不同)。
static func _pet_guess(pool: Array, length: int, level := 4) -> Array:
	if pool.is_empty():
		var guess: Array = []
		for i in length:
			guess.append(COLOR_PALETTE.pick_random())
		return guess
	if randf() < GameAiLevel.mistake_chance(level):
		return pool.pick_random()
	return pool[0]


static func _open_board(initiator: Node) -> MastermindBoard:
	var shell: Node = initiator.get_tree().get_first_node_in_group("desktop_shell")
	if shell == null:
		return null
	var board := MastermindBoard.new()
	shell.top_layer().add_child(board)
	board.setup(shell.action_area, TranslationServer.translate("珠璣妙算"))
	return board


static func _cleanup_board(board: MastermindBoard) -> void:
	if board != null and is_instance_valid(board):
		board.queue_free()


## pet 的猜色化成人看得懂的一行:[甲] 🔴🟡🔵 | 2A1B
static func _history_line(guesser_label: String, guess: Array, result: Dictionary) -> String:
	return "%s %s | %dA%dB" % [guesser_label, "".join(guess), result["a"], result["b"]]


static func _flip_outcome(outcome: String) -> String:
	return "lose" if outcome == "win" else ("win" if outcome == "lose" else "tie")


## 內建反應(贏開心、輸不服氣、平手),照 ttt_game 同一套做法(不經 GameChat.react,因為沒有積木掛勾)。
static func _react(pet: Node, outcome: String, vs_user: bool) -> void:
	if not is_instance_valid(pet):
		return
	pet.record_game_result("mastermind", outcome)
	if outcome == "lose":
		pet.game_losses_in_row += 1
	elif outcome == "win":
		pet.game_losses_in_row = 0
	if pet.vitality != null:
		pet.vitality.on_game_result(outcome, vs_user)
	match outcome:
		"win":
			GameChat.celebrate_win(pet)
		"lose":
			pet.shiver(1.5)


## 核心流程:participants 是 Node(桌寵)或字串 "USER" 的陣列,輪流猜同一組暗碼。code_length = 3 或 4
## (題型,見 Pet.mastermind_code_length,由發起的那隻桌寵自己的設定決定)。
## 回傳 {winner}(Node、"USER" 或 ""(沒人猜中));中途被打斷回空字典。
static func _run(participants: Array, code_length := DEFAULT_CODE_LENGTH, levels := {}) -> Dictionary:
	var length: int = code_length if CODE_LENGTH_CHOICES.has(code_length) else DEFAULT_CODE_LENGTH
	var pets: Array = participants.filter(func(p: Variant) -> bool: return p is Node)
	if pets.is_empty():
		return {}
	var host: Node = pets[0]
	var generations := {}
	for pet: Node in pets:
		generations[pet] = pet.action_generation
	var board := _open_board(host)
	if board == null:
		return {}
	board.code_length = length
	var secret: Array = []
	for i in length:
		secret.append(COLOR_PALETTE.pick_random())
	var pools := {}
	for pet: Node in pets:
		pools[pet] = _generate_full_pool(length)
	var user_forfeited: bool = not participants.has("USER")
	var attempts_left: int = int(ATTEMPTS_BY_LENGTH.get(length, 8))
	var turn := 0
	var winner: Variant = null
	while attempts_left > 0 and winner == null:
		for pet: Node in pets:
			if not is_instance_valid(pet) or pet.action_generation != generations[pet]:
				_cleanup_board(board)
				return {}
		var actor: Variant = participants[turn % participants.size()]
		turn += 1
		var actor_is_user: bool = actor is String and actor == "USER"
		if actor_is_user and user_forfeited:
			continue
		var guess: Array
		if actor_is_user:
			board.status_text = TranslationServer.translate("你的回合(剩 %d 次)") % attempts_left
			board.set_controls(true)
			var submitted := [false]
			var picked_box := [[]]
			var forfeited := [false]
			var on_submit := func(colors: Array) -> void:
				picked_box[0] = colors
				submitted[0] = true
			var on_forfeit := func() -> void:
				forfeited[0] = true
				submitted[0] = true
			board.guess_submitted.connect(on_submit)
			board.forfeit_pressed.connect(on_forfeit)
			var cancelled := [false]
			var on_cancel := func() -> void:
				cancelled[0] = true
				submitted[0] = true
			board.cancel_pressed.connect(on_cancel)
			while not submitted[0]:
				if not is_instance_valid(board):
					_cleanup_board(board)
					return {}
				await host.get_tree().process_frame
			if is_instance_valid(board):
				board.guess_submitted.disconnect(on_submit)
				board.forfeit_pressed.disconnect(on_forfeit)
				board.cancel_pressed.disconnect(on_cancel)
				board.set_controls(false)
			if cancelled[0]:
				_cleanup_board(board)
				return {}
			if forfeited[0]:
				user_forfeited = true
				board.add_line(TranslationServer.translate("你棄權了。"))
				continue
			guess = []
			for index: int in picked_box[0]:
				guess.append(COLOR_PALETTE[int(index)])
		else:
			if not is_instance_valid(actor):
				continue
			board.status_text = "%s %s" % [actor.get_label(), TranslationServer.translate("思考中…")]
			await _wait(host, 0.8)
			if not is_instance_valid(board):
				_cleanup_board(board)
				return {}
			guess = _pet_guess(pools[actor], length, levels.get(actor, (actor as Node).mastermind_ai_level))
		var result := evaluate_guess(secret, guess)
		attempts_left -= 1
		var guesser_label: String = TranslationServer.translate("你") if actor_is_user else str((actor as Node).get_label())
		board.add_line(_history_line(guesser_label, guess, result))
		if int(result["a"]) == length:
			winner = actor
			break
		for pet: Node in pets:
			pools[pet] = _filter_pool(pools[pet], guess, result)
	_cleanup_board(board)
	var secret_text: String = "".join(secret)
	if winner is Node:
		GameChat.chain_say(winner, "[b]%s[/b]" % (SOLVE_LINES.pick_random() % secret_text), 3.0)
		_react(winner, "win", participants.has("USER"))
		for pet: Node in pets:
			if pet != winner:
				_react(pet, "lose", false)
		await _wait(host, 1.6)
	elif winner == "USER":
		var loser: Node = pets[0]
		GameChat.chain_say(loser, USER_WIN_LINES.pick_random() % secret_text, 3.0)
		for pet: Node in pets:
			_react(pet, "lose", true)
		await _wait(host, 1.6)
	else:
		var announcer: Node = pets.pick_random()
		if is_instance_valid(announcer):
			GameChat.chain_say(announcer, REVEAL_LINES.pick_random() % secret_text, 3.0)
			for pet: Node in pets:
				_react(pet, "tie", participants.has("USER"))
			await _wait(host, 1.6)
	var winner_tag := ""
	if winner is Node:
		winner_tag = (winner as Node).recognition_tag
	elif winner == "USER":
		winner_tag = "user"
	return {"winner": winner_tag, "secret": secret_text}


## 使用者對一隻桌寵(題型用這隻桌寵自己的 mastermind_code_length)。回傳 _run() 的結果;桌寵正在對戰中、
## 沒有互動介面回空字典。
static func play_user(pet: Node) -> Dictionary:
	if not is_instance_valid(pet) or pet.is_in_game():
		return {}
	GameChat.enter([pet], "mastermind")
	var result: Dictionary = await _run(["USER", pet], pet.mastermind_code_length)
	GameChat.leave([pet])
	if not result.is_empty():   # 跟使用者的 1v1 打完一場(取消的不算)
		PetFavor.user_bond(pet, "duel", PetFavor.USER_SMALL, PetFavor.USER_DUEL_COOLDOWN)
	return result


## 桌寵對桌寵(沒有使用者,題型用發起者 a 自己的 mastermind_code_length)。回傳 _run() 的結果。
static func play_pets(a: Node, b: Node) -> Dictionary:
	if not is_instance_valid(a) or not is_instance_valid(b) or a == b:
		return {}
	if a.is_in_game():
		return {}
	if b.is_in_game():
		GameChat.think_blocked(a, b, TranslationServer.translate("珠璣妙算"))
		return {}
	GameChat.enter([a, b], "mastermind")
	# 好惡影響 AI 等級:整場開頭每隻擲一次(見 GameAiLevel.match_level)。
	var levels := {a: GameAiLevel.match_level(a, b, a.mastermind_ai_level), b: GameAiLevel.match_level(b, a, b.mastermind_ai_level)}
	var result: Dictionary = await _run([a, b], a.mastermind_code_length, levels)
	GameChat.leave([a, b])
	# 2026-10-06:1v1 好感度增減(見 PetFavor.duel);猜中的那方贏,另一方輸,沒人猜中是平手。
	var winner_tag: String = str(result.get("winner", ""))
	var result_a := "tie"
	if winner_tag == a.recognition_tag:
		result_a = "win"
	elif winner_tag == b.recognition_tag:
		result_a = "lose"
	if not result.is_empty():   # 取消/中斷(空結果)不算對戰
		PetFavor.duel(a, b, result_a)
	return result


const GROUP_LINES: Array[String] = ["要不要一起來猜珠璣妙算?", "來猜猜看暗碼是什麼顏色組合,誰要加入?"]


## 全體模式(右鍵選單「跟場上所有桌寵」):先問場上其他有空的桌寵要不要加入,再問使用者要不要一起猜
## (使用者隨時可以在自己的回合按「棄權」退出,退出後繼續旁觀,不影響其他人);跟拚骰/猜拳大逃殺同一套
## 「先問過才拉下水」邏輯(GameInvite.invite_all_dice)。回傳 _run() 的結果;沒人理、host 忙碌回空字典。
static func play_all(host: Node, ask_user := true) -> Dictionary:
	if not is_instance_valid(host) or host.is_in_game():
		return {}
	var others: Array = host.get_tree().get_nodes_in_group("pets").filter(
			func(p: Node) -> bool: return p != host and is_instance_valid(p) and not p.is_queued_for_deletion() and not p.entering and not p.is_in_game())
	var pets: Array = [host]
	var generation: int = host.action_generation
	if not others.is_empty():
		var names: Array[String] = []
		for other: Node in others:
			names.append(str(other.get_label()))
		var address: String = "、".join(names) if names.size() <= 3 else TranslationServer.translate("大家")
		GameChat.chain_say(host, "%s,%s" % [address, host.speak_tr(GROUP_LINES.pick_random())], 2.6)
		await _wait(host, 1.9)
		if not is_instance_valid(host) or host.action_generation != generation:
			return {}
		for other: Node in others:
			if not is_instance_valid(other) or other.is_in_game():
				continue
			if other.vitality != null:
				other.vitality.note_invited()
			var refusal: Dictionary = other.game_refusal("mastermind", host)
			if randf() < float(refusal["chance"]):
				GameChat.chain_say(other, other.speak_tr(str((GameInvite.REFUSE_LINES[str(refusal["reason"])] as Array).pick_random())), 2.2)
			else:
				pets.append(other)
				GameChat.chain_say(other, other.speak_tr(str(GameInvite.ACCEPT_LINES.pick_random())), 1.6)
		await _wait(host, 1.5)
		if not is_instance_valid(host) or host.action_generation != generation:
			return {}
	var participants: Array = pets.duplicate()
	var user_joins := false
	if ask_user:
		var choice := await GameChat.ask(host, "一起來猜珠璣妙算嗎?", ["好啊", "我看就好"], 20.0)
		if not is_instance_valid(host) or host.action_generation != generation:
			return {}
		user_joins = choice == 0
	if user_joins:
		participants.append("USER")
		PetFavor.user_group(pets)   # 2026-10-06:使用者參與全體珠璣妙算
	GameChat.enter(pets, "mastermind")
	var result: Dictionary = await _run(participants, host.mastermind_code_length)
	GameChat.leave(pets)
	return result
