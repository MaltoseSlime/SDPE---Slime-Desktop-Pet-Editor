class_name TttGame
extends RefCounted
## 井字棋(3x3):跟猜拳/拚骰共用同一套「對話氣泡 + 對戰中擋邀請」機制(見 GameChat.enter/leave、Pet.is_in_game),
## 但棋盤本身是場上一塊可拖曳、程式畫的面板(TttBoard),不是氣泡演出。全場同時最多一塊棋盤(見 has_active_board),
## 棋盤存在期間其他井字棋邀請一律被擋下(GameInvite.invite 檢查這裡);對戰中的桌寵靠既有的 is_busy_for_game()
## 讓自己不會去撿道具、坐家具(見 pet.gd 的 _liked_prop_goal / _container_goal)。
## 賽制 best_of 跟猜拳/拚骰共用同一顆(Pet.game_best_of、右鍵選單「賽制」):1 = 一戰定勝負、3 = 三戰兩勝、5 = 五戰三勝。
## 每一局先手:第一局隨機,之後由上一局贏家先手;平手則換邊先手。
## 使用者對戰可以「投降」(整場算桌寵贏)或按 ✕「取消」(不計戰績);棋盤閒置 10 分鐘沒人互動也視同取消收掉。

const WIN_LINES: Array = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]
const WIN_TEXT: Array[String] = ["贏了!井字棋我最強!", "哈,連線成功!", "耶,三連線!"]
const LOSE_TEXT: Array[String] = ["竟然被連線了……", "唔,這盤輸了。", "下次一定贏回來!"]
const TIE_TEXT: Array[String] = ["平手,誰都沒連成!", "下滿了還是平手!"]

## 全場只能有一塊棋盤(使用者要求):存在期間 GameInvite.invite(kind="ttt") 一律擋下,見那邊的說明。
static var active_board: TttBoard = null


static func has_active_board() -> bool:
	return active_board != null and is_instance_valid(active_board)


static func _find_shell(pet: Node) -> Node:
	return pet.get_tree().get_first_node_in_group("desktop_shell")


static func _spawn_board(shell: Node) -> TttBoard:
	var board := TttBoard.new()
	shell.add_child(board)
	board.setup(shell.action_area)
	active_board = board
	return board


static func _cleanup_board(board: TttBoard) -> void:
	if active_board == board:
		active_board = null
	if is_instance_valid(board):
		board.queue_free()


static func _winner(cells: Array) -> int:
	for line: Array in WIN_LINES:
		var mark: int = cells[line[0]]
		if mark != 0 and mark == cells[line[1]] and mark == cells[line[2]]:
			return mark
	return 3 if not cells.has(0) else 0   # 3 = 平手(下滿了沒人連線)


static func _find_winning_move(cells: Array, mark: int) -> int:
	for line: Array in WIN_LINES:
		var vals: Array = [cells[line[0]], cells[line[1]], cells[line[2]]]
		if vals.count(mark) == 2 and vals.count(0) == 1:
			for i: int in line:
				if int(cells[i]) == 0:
					return i
	return -1


## 簡單但不笨的走法:能贏先贏、擋對方的贏、搶中間、搶角落,最後隨機找空格。
static func _ai_move(cells: Array, mark: int, opp: int) -> int:
	var win := _find_winning_move(cells, mark)
	if win >= 0:
		return win
	var block := _find_winning_move(cells, opp)
	if block >= 0:
		return block
	if int(cells[4]) == 0:
		return 4
	var corners: Array = [0, 2, 6, 8]
	corners.shuffle()
	for i: int in corners:
		if int(cells[i]) == 0:
			return i
	var empties: Array = []
	for i in 9:
		if int(cells[i]) == 0:
			empties.append(i)
	return empties.pick_random() if not empties.is_empty() else -1


static func _wait(pet: Node, seconds: float) -> void:
	await pet.get_tree().create_timer(seconds).timeout


static func _cancelled(pets: Array, generations: Dictionary) -> bool:
	for pet: Node in pets:
		if not is_instance_valid(pet) or pet.action_generation != generations[pet]:
			return true
	return false


static func _flip(outcome: String) -> String:
	return "lose" if outcome == "win" else ("win" if outcome == "lose" else "tie")


## 內建反應(贏開心、輸生氣、平手不服氣),照使用者指示不經 GameChat.react()/run_game_hats():
## HTML 積木編輯器已凍結,不能加新的 event_when_ttt 事件方塊,井字棋沒有積木掛勾,只用內建台詞。
static func _react(pet: Node, outcome: String, vs_user: bool) -> void:
	if not is_instance_valid(pet):
		return
	pet.record_game_result("ttt", outcome)
	if outcome == "lose":
		pet.game_losses_in_row += 1
	elif outcome == "win":
		pet.game_losses_in_row = 0
	if pet.vitality != null:
		pet.vitality.on_game_result(outcome, vs_user)
	match outcome:
		"win":
			pet.perform_hops(1, false)
			GameChat.say(pet, "[wave]%s[/wave]" % WIN_TEXT.pick_random(), 3.0)
		"lose":
			pet.shiver(1.5)
			GameChat.say(pet, "[shake]%s[/shake]" % LOSE_TEXT.pick_random(), 3.0)
		_:
			GameChat.say(pet, TIE_TEXT.pick_random(), 2.5)


## 桌寵對桌寵。回傳 {outcome_a, outcome_b, wins_a, wins_b, rounds};中途被打斷、棋盤被搶先佔用回空字典。
static func play_pets(a: Node, b: Node, best_of := 1) -> Dictionary:
	if not is_instance_valid(a) or not is_instance_valid(b) or a == b:
		return {}
	if a.is_in_game() or has_active_board():
		return {}
	if b.is_in_game():
		GameChat.think_blocked(a, b, TranslationServer.translate("井字棋"))
		return {}
	GameChat.enter([a, b])
	var result: Dictionary = await _play_pets(a, b, best_of)
	GameChat.leave([a, b])
	return result


static func _play_pets(a: Node, b: Node, best_of := 1) -> Dictionary:
	var shell := _find_shell(a)
	if shell == null or has_active_board():
		return {}
	var generations := {a: a.action_generation, b: b.action_generation}
	var need := RpsGame.needed_wins(best_of)
	var wins_a := 0
	var wins_b := 0
	var rounds := 0
	var board := _spawn_board(shell)
	var first_mark := 1 if randf() < 0.5 else 2   # 1 = a、2 = b
	while wins_a < need and wins_b < need and rounds < maxi(best_of, 1) + 2:
		rounds += 1
		board.board = [0, 0, 0, 0, 0, 0, 0, 0, 0]
		board.status_text = TranslationServer.translate("%s VS %s (%d/%d)") % [a.get_label(), b.get_label(), rounds, maxi(best_of, 1)]
		board.refresh()
		var mark := first_mark
		var winner_mark := 0
		while winner_mark == 0:
			await _wait(a, 0.8)
			if _cancelled([a, b], generations) or not is_instance_valid(board):
				_cleanup_board(board)
				return {}
			var cells: Array = board.board
			var move := _ai_move(cells, mark, 3 - mark)
			if move < 0:
				break
			cells[move] = mark
			board.board = cells
			board.refresh()
			winner_mark = _winner(cells)
			mark = 3 - mark
		if winner_mark == 1:
			wins_a += 1
			first_mark = 1
		elif winner_mark == 2:
			wins_b += 1
			first_mark = 2
		else:
			first_mark = 3 - first_mark
		await _wait(a, 1.0)
		if _cancelled([a, b], generations) or not is_instance_valid(board):
			_cleanup_board(board)
			return {}
	var result_a := "tie" if wins_a == wins_b else ("win" if wins_a > wins_b else "lose")
	GameChat.set_result_context(a, b, result_a)
	_react(a, result_a, false)
	_react(b, _flip(result_a), false)
	await _wait(a, 1.6)
	_cleanup_board(board)
	return {"outcome_a": result_a, "outcome_b": _flip(result_a), "wins_a": wins_a, "wins_b": wins_b, "rounds": rounds}


## 使用者對桌寵。回傳 {outcome, pet_wins, user_wins};取消回空字典,中途離開回上一場結果。
static func play_user(pet: Node, best_of := 1) -> Dictionary:
	if not is_instance_valid(pet) or pet.is_in_game() or has_active_board():
		return {}
	GameChat.enter([pet])
	var result: Dictionary = await _play_user(pet, best_of)
	GameChat.leave([pet])
	return result


static func _play_user(pet: Node, best_of := 1) -> Dictionary:
	var shell := _find_shell(pet)
	if shell == null or has_active_board():
		return {}
	var generation: int = pet.action_generation
	var need := RpsGame.needed_wins(best_of)
	var board := _spawn_board(shell)
	board.show_surrender = true
	var flags := {"cancelled": false, "surrendered": false}
	board.cancel_pressed.connect(func() -> void: flags["cancelled"] = true)
	board.surrender_pressed.connect(func() -> void: flags["surrendered"] = true)
	var pet_wins := 0
	var user_wins := 0
	var rounds := 0
	var first_mark := 1 if randf() < 0.5 else 2   # 1 = 桌寵、2 = 使用者
	while pet_wins < need and user_wins < need:
		rounds += 1
		board.board = [0, 0, 0, 0, 0, 0, 0, 0, 0]
		board.status_text = TranslationServer.translate("%s VS 你 (%d/%d)") % [pet.get_label(), rounds, maxi(best_of, 1)]
		board.refresh()
		var mark := first_mark
		var winner_mark := 0
		while winner_mark == 0:
			if not is_instance_valid(pet) or pet.action_generation != generation or not is_instance_valid(board):
				_cleanup_board(board)
				return {}
			if mark == 1:
				await _wait(pet, 0.8)
				if flags["cancelled"] or flags["surrendered"] or not is_instance_valid(board):
					break
				var cells: Array = board.board
				var move := _ai_move(cells, 1, 2)
				if move < 0:
					break
				cells[move] = 1
				board.board = cells
				board.refresh()
				winner_mark = _winner(cells)
			else:
				board.interactive = true
				var chosen := [-1]
				var on_cell := func(i: int) -> void: chosen[0] = i
				board.cell_pressed.connect(on_cell)
				while chosen[0] < 0 and not flags["cancelled"] and not flags["surrendered"] and is_instance_valid(board):
					await pet.get_tree().process_frame
				if is_instance_valid(board) and board.cell_pressed.is_connected(on_cell):
					board.cell_pressed.disconnect(on_cell)
				board.interactive = false
				if flags["cancelled"] or flags["surrendered"] or not is_instance_valid(board):
					break
				var cells2: Array = board.board
				cells2[chosen[0]] = 2
				board.board = cells2
				board.refresh()
				winner_mark = _winner(cells2)
			mark = 3 - mark
		if flags["cancelled"]:
			_cleanup_board(board)
			return {}
		if flags["surrendered"]:
			winner_mark = 1   # 投降算桌寵贏這一局(也是整場)
		if winner_mark == 1:
			pet_wins += 1
			first_mark = 1
		elif winner_mark == 2:
			user_wins += 1
			first_mark = 2
		else:
			first_mark = 3 - first_mark
		if flags["surrendered"]:
			break
		await _wait(pet, 1.0)
		if not is_instance_valid(pet) or pet.action_generation != generation or not is_instance_valid(board):
			_cleanup_board(board)
			return {}
	var result := "win" if pet_wins > user_wins else ("lose" if user_wins > pet_wins else "tie")
	pet.set_counterpart_named("opponent", "user", "你")
	if result != "tie":
		pet.set_counterpart_named("winner", pet.recognition_tag if result == "win" else "user", pet.display_name if result == "win" else "你")
		pet.set_counterpart_named("loser", "user" if result == "win" else pet.recognition_tag, "你" if result == "win" else pet.display_name)
	_react(pet, result, true)
	await _wait(pet, 1.6)
	_cleanup_board(board)
	return {"outcome": result, "pet_wins": pet_wins, "user_wins": user_wins}
