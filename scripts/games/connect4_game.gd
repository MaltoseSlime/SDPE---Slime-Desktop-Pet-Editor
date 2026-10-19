class_name Connect4Game
extends RefCounted
## 四連環(Connect 4,7 欄 × 6 列,2026-10-18 使用者要求):兩方輪流把棋子投進其中一欄,棋子落到那一欄最低的空格;
## 先讓自己的四枚棋子橫、直、斜連成一線的贏,42 格下滿都沒人連成就平手。
## 做法跟井字棋(TttGame)一樣:對話氣泡 + 對戰中擋邀請(GameChat.enter/leave)、場上一塊可拖曳的程式畫棋盤(Connect4Board,全場最多一塊)、
## 賽制 best_of 跟其他遊戲共用(Pet.game_best_of)。每一局先手:第一局隨機,之後由上一局贏家先手;平手則換邊先手。
## 使用者對戰可以「投降」(整場算桌寵贏)或按 ✕「取消」(不計戰績)。

const COLS := Connect4Board.COLS
const ROWS := Connect4Board.ROWS
const WIN_TEXT: Array[String] = ["四子連線!我贏了!", "連成一線,這盤是我的!", "耶,四連環我最強!"]
const LOSE_TEXT: Array[String] = ["竟然被連成四個了……", "唔,沒擋住。", "下次一定贏回來!"]
const TIE_TEXT: Array[String] = ["整盤下滿了,平手!", "誰都沒連成四個,平手!"]

static var active_board: Connect4Board = null


static func has_active_board() -> bool:
	return active_board != null and is_instance_valid(active_board)


static func _find_shell(pet: Node) -> Node:
	return pet.get_tree().get_first_node_in_group("desktop_shell")


static func _spawn_board(shell: Node) -> Connect4Board:
	var board := Connect4Board.new()
	shell.top_layer().add_child(board)   # 蓋在對話氣泡之上(跟井字棋一樣)
	board.setup(shell.action_area)
	active_board = board
	return board


## 參數故意不寫型別(見 TttGame._cleanup_board)。
static func _cleanup_board(board: Variant) -> void:
	if not is_instance_valid(active_board) or active_board == board:
		active_board = null
	if is_instance_valid(board):
		board.queue_free()


# --- 規則 ---

## 這一欄放得下的話,棋子會落在第幾列(最低的空格);滿了回 -1。
static func drop_row(cells: Array, column: int) -> int:
	if column < 0 or column >= COLS:
		return -1
	for row in range(ROWS - 1, -1, -1):
		if int(cells[row * COLS + column]) == 0:
			return row
	return -1


static func valid_columns(cells: Array) -> Array[int]:
	var result: Array[int] = []
	for column in COLS:
		if int(cells[column]) == 0:
			result.append(column)
	return result


## 投一枚棋子,回傳落下的格子索引(滿了回 -1);會改 cells。
static func drop(cells: Array, column: int, mark: int) -> int:
	var row := drop_row(cells, column)
	if row < 0:
		return -1
	cells[row * COLS + column] = mark
	return row * COLS + column


## 連成一線的四格(有好幾條的話回第一條);沒有回空陣列。
static func winning_line(cells: Array) -> Array:
	for row in ROWS:
		for column in COLS:
			var mark := int(cells[row * COLS + column])
			if mark == 0:
				continue
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
				var line: Array = []
				for k in 4:
					var x := column + step.x * k
					var y := row + step.y * k
					if x < 0 or x >= COLS or y >= ROWS or int(cells[y * COLS + x]) != mark:
						break
					line.append(y * COLS + x)
				if line.size() == 4:
					return line
	return []


## 1 / 2 = 那一方贏;3 = 平手(下滿了沒人連成);0 = 還沒結束。
static func winner(cells: Array) -> int:
	var line := winning_line(cells)
	if not line.is_empty():
		return int(cells[line[0]])
	return 3 if valid_columns(cells).is_empty() else 0


static func _wins_if(cells: Array, column: int, mark: int) -> bool:
	var copy := cells.duplicate()
	if drop(copy, column, mark) < 0:
		return false
	return winner(copy) == mark


## 盤面對 mark 有多有利:中間那欄的棋子加分;每個四格的窗口裡,自己三枚+一空、兩枚+兩空加分,對手三枚+一空扣分。
static func _score(cells: Array, mark: int, opp: int) -> int:
	var score := 0
	for row in ROWS:
		if int(cells[row * COLS + COLS / 2]) == mark:
			score += 3
	for row in ROWS:
		for column in COLS:
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
				var end := Vector2i(column, row) + step * 3
				if end.x < 0 or end.x >= COLS or end.y >= ROWS:
					continue
				var mine := 0
				var theirs := 0
				for k in 4:
					var value := int(cells[(row + step.y * k) * COLS + column + step.x * k])
					if value == mark:
						mine += 1
					elif value == opp:
						theirs += 1
				if theirs == 0 and mine == 3:
					score += 5
				elif theirs == 0 and mine == 2:
					score += 2
				elif mine == 0 and theirs == 3:
					score -= 4
	return score


## AI:能贏先贏、擋對方的贏、不下「會讓對方在正上方接著贏」的欄,其餘照盤面分數挑。level(見 GameAiLevel)控制
## 每一步「看得到最好的選擇卻隨便選」的機率;不給(= 4)時完全不犯錯。沒有地方可下回 -1。
static func ai_move(cells: Array, mark: int, opp: int, level := 4) -> int:
	var columns := valid_columns(cells)
	if columns.is_empty():
		return -1
	var mistake := GameAiLevel.mistake_chance(level)
	if randf() >= mistake:
		for column in columns:
			if _wins_if(cells, column, mark):
				return column
	if randf() >= mistake:
		for column in columns:
			if _wins_if(cells, column, opp):
				return column
	var safe: Array[int] = []
	for column in columns:
		var copy := cells.duplicate()
		drop(copy, column, mark)
		if not _wins_if(copy, column, opp):
			safe.append(column)
	var pool: Array[int] = safe if not safe.is_empty() else columns
	if randf() < mistake:
		return pool.pick_random()
	var best: Array[int] = []
	var best_score := -1000000
	for column in pool:
		var copy := cells.duplicate()
		drop(copy, column, mark)
		var score := _score(copy, mark, opp)
		if score > best_score:
			best_score = score
			best = [column]
		elif score == best_score:
			best.append(column)
	return best.pick_random()


# --- 對戰 ---

static func _wait(pet: Node, seconds: float) -> void:
	await pet.get_tree().create_timer(seconds).timeout


static func _cancelled(pets: Array, generations: Dictionary) -> bool:
	for pet: Node in pets:
		if not is_instance_valid(pet) or pet.action_generation != generations[pet]:
			return true
	return false


static func _flip(outcome: String) -> String:
	return "lose" if outcome == "win" else ("win" if outcome == "lose" else "tie")


## 內建反應(贏開心、輸發抖、平手),跟井字棋同一套做法。
static func _react(pet: Node, outcome: String, vs_user: bool) -> void:
	if not is_instance_valid(pet):
		return
	pet.record_game_result("connect4", outcome)
	if outcome == "lose":
		pet.game_losses_in_row += 1
	elif outcome == "win":
		pet.game_losses_in_row = 0
	if pet.vitality != null:
		pet.vitality.on_game_result(outcome, vs_user)
	match outcome:
		"win":
			pet.perform_hops(1, false)
			GameChat.say(pet, "[wave]%s[/wave]" % TranslationServer.translate(WIN_TEXT.pick_random()), 3.0)
		"lose":
			pet.shiver(1.5)
			GameChat.say(pet, "[shake]%s[/shake]" % TranslationServer.translate(LOSE_TEXT.pick_random()), 3.0)
		_:
			GameChat.say(pet, TranslationServer.translate(TIE_TEXT.pick_random()), 2.5)


static func _place(board: Connect4Board, column: int, mark: int) -> int:
	var cells: Array = board.board
	var index := drop(cells, column, mark)
	board.board = cells
	board.last_move = index
	var result := winner(cells)
	if result == 1 or result == 2:
		board.winning_cells = winning_line(cells)
	board.refresh()
	return result


## 桌寵對桌寵。回傳 {outcome_a, outcome_b, wins_a, wins_b, rounds};中途被打斷、棋盤被搶先佔用回空字典。
static func play_pets(a: Node, b: Node, best_of := 1) -> Dictionary:
	if not is_instance_valid(a) or not is_instance_valid(b) or a == b:
		return {}
	if a.is_in_game() or has_active_board():
		return {}
	if b.is_in_game():
		GameChat.think_blocked(a, b, TranslationServer.translate("四連環"))
		return {}
	GameChat.enter([a, b], "connect4")
	var result: Dictionary = await _play_pets(a, b, best_of)
	GameChat.leave([a, b])
	return result


static func _new_round(board: Connect4Board, status: String) -> void:
	board.board = Connect4Board.empty_board()
	board.last_move = -1
	board.winning_cells = []
	board.status_text = status
	board.refresh()


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
	board.piece_colors = GamePieceColors.for_pets(a, b)
	var first_mark := 1 if randf() < 0.5 else 2   # 1 = a、2 = b
	var levels := [GameAiLevel.match_level(a, b, a.connect4_ai_level), GameAiLevel.match_level(b, a, b.connect4_ai_level)]   # 好惡影響,整場擲一次
	while wins_a < need and wins_b < need and rounds < maxi(best_of, 1) + 2:
		rounds += 1
		_new_round(board, TranslationServer.translate("%s VS %s (%d/%d)") % [a.get_label(), b.get_label(), rounds, maxi(best_of, 1)])
		var mark := first_mark
		var winner_mark := 0
		while winner_mark == 0:
			await _wait(a, 0.7)
			if _cancelled([a, b], generations) or not is_instance_valid(board):
				_cleanup_board(board)
				return {}
			var column := ai_move(board.board, mark, 3 - mark, levels[0] if mark == 1 else levels[1])
			if column < 0:
				break
			winner_mark = _place(board, column, mark)
			mark = 3 - mark
		if winner_mark == 1:
			wins_a += 1
			first_mark = 1
		elif winner_mark == 2:
			wins_b += 1
			first_mark = 2
		else:
			first_mark = 3 - first_mark
		await _wait(a, 1.2)
		if _cancelled([a, b], generations) or not is_instance_valid(board):
			_cleanup_board(board)
			return {}
	var result_a := "tie" if wins_a == wins_b else ("win" if wins_a > wins_b else "lose")
	GameChat.set_result_context(a, b, result_a)
	_react(a, result_a, false)
	_react(b, _flip(result_a), false)
	await GameChat.hold_result([a, b], board, GroupScoreboard.RESULT_HOLD_SECONDS)
	_cleanup_board(board)
	return {"outcome_a": result_a, "outcome_b": _flip(result_a), "wins_a": wins_a, "wins_b": wins_b, "rounds": rounds}


## 使用者對桌寵。回傳 {outcome, pet_wins, user_wins};取消回空字典。
static func play_user(pet: Node, best_of := 1) -> Dictionary:
	if not is_instance_valid(pet) or pet.is_in_game() or has_active_board():
		return {}
	GameChat.enter([pet], "connect4")
	var result: Dictionary = await _play_user(pet, best_of)
	GameChat.leave([pet])
	if not result.is_empty() and is_instance_valid(pet):
		PetFavor.user_bond(pet, "duel", PetFavor.USER_SMALL, PetFavor.USER_DUEL_COOLDOWN)
	return result


static func _play_user(pet: Node, best_of := 1) -> Dictionary:
	var shell := _find_shell(pet)
	if shell == null or has_active_board():
		return {}
	var generation: int = pet.action_generation
	var need := RpsGame.needed_wins(best_of)
	var board := _spawn_board(shell)
	board.piece_colors = GamePieceColors.for_user(pet)   # 1 = 桌寵、2 = 使用者
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
		_new_round(board, TranslationServer.translate("%s VS 你 (%d/%d)") % [pet.get_label(), rounds, maxi(best_of, 1)])
		var mark := first_mark
		var winner_mark := 0
		while winner_mark == 0:
			if not is_instance_valid(pet) or pet.action_generation != generation or not is_instance_valid(board):
				_cleanup_board(board)
				return {}
			if mark == 1:
				await _wait(pet, 0.7)
				if flags["cancelled"] or flags["surrendered"] or not is_instance_valid(board):
					break
				var column := ai_move(board.board, 1, 2, pet.connect4_ai_level)
				if column < 0:
					break
				winner_mark = _place(board, column, 1)
			else:
				board.interactive = true
				var chosen := [-1]
				var on_column := func(column: int) -> void: chosen[0] = column
				board.column_pressed.connect(on_column)
				while chosen[0] < 0 and not flags["cancelled"] and not flags["surrendered"] and is_instance_valid(board):
					await pet.get_tree().process_frame
				if is_instance_valid(board) and board.column_pressed.is_connected(on_column):
					board.column_pressed.disconnect(on_column)
				if is_instance_valid(board):
					board.interactive = false
				if flags["cancelled"] or flags["surrendered"] or not is_instance_valid(board):
					break
				winner_mark = _place(board, chosen[0], 2)
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
		await _wait(pet, 1.2)
		if not is_instance_valid(pet) or pet.action_generation != generation or not is_instance_valid(board):
			_cleanup_board(board)
			return {}
	var result := "win" if pet_wins > user_wins else ("lose" if user_wins > pet_wins else "tie")
	pet.set_counterpart_named("opponent", "user", "你")
	if result != "tie":
		pet.set_counterpart_named("winner", pet.recognition_tag if result == "win" else "user", pet.display_name if result == "win" else "你")
		pet.set_counterpart_named("loser", "user" if result == "win" else pet.recognition_tag, "你" if result == "win" else pet.display_name)
	_react(pet, result, true)
	await GameChat.hold_result([pet], board, GroupScoreboard.RESULT_HOLD_SECONDS, func() -> bool: return bool(flags["cancelled"]))
	_cleanup_board(board)
	return {"outcome": result, "pet_wins": pet_wins, "user_wins": user_wins}
