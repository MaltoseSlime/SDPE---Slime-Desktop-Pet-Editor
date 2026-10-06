class_name BlockadeGame
extends RefCounted
## 步步為營(2026-10-04 使用者要求改回標準 Quoridor 規格):9x9 棋盤,牆不是填格子,是放在格子「與格子之間」
## 的縫隙,橫向或縱向、一次卡住兩段邊(標準 Quoridor 的「牆縫格」表示法)。角色 A 從頂端中央(4,0)出發要
## 走到最底一列(y=8);角色 B 從底端中央(4,8)出發要走到最頂一列(y=0);每回合二選一:走到相鄰空格、
## 跳過正面相鄰的對手(2026-10-04 使用者要求加入原版桌遊的跳棋規則,避免玩家被堵死路——見
## available_moves():對手背後沒牆就直線跳過去,背後有牆/是棋盤邊界就改成斜跳到對手左右兩側其中沒被牆
## 擋住的格子,兩種都不行這個方向就單純沒有落腳點,不影響其他方向的一般移動),或放一面牆堵路(每人限
## MAX_WALLS_PER_PLAYER 面,放牆後雙方都必須還有路可走,不能把人堵死 —— BFS 檢查)。輪到的一方沒有任何
## 合法動作直接判對手贏;連下 MAX_STEPS 步沒分勝負判平手。
##
## 牆的座標系:牆縫格座標 (x,y),x、y 各 0~GRID_N-2。横牆(orientation="H")卡住第 x、x+1 兩欄在 y/y+1
## 列之間的縱向通行;縱牆(orientation="V")卡住第 y、y+1 兩列在 x/x+1 欄之間的橫向通行(見 _step_blocked)。
## 同一個牆縫格不管哪個方向只能放一面牆。真正的 Quoridor 容許同方向的牆頭尾相接延伸成任意長度,但使用者
## 2026-10-04 明確要求限制住:同一條線上最多兩片相接,不能疊成三片連成一整條長牆(見 _chain_length_ok)。
## 棋盤畫面上敵我雙方放的牆顏色不同(A 用強調色、B 用文字色,跟兩人棋子本身的顏色一致),見
## BlockadeBoard._draw() 跟這裡的 wall_owners。
##
## AI 決策(get_best_action)看「這步讓我跟終點近多少、讓對手跟終點遠多少」評分,level(見 GameAiLevel)
## 控制「明明算出最佳動作,卻選次佳甚至隨便選」的機率。賽制(best_of)跟猜拳/拚骰/井字棋共用同一顆
## (Pet.game_best_of、右鍵選單「賽制」)。沒有積木掛勾(HTML 積木編輯器已凍結),輸贏只用內建反應,
## 不走 GameChat.react()。

const GRID_N := 9
const MAX_WALLS_PER_PLAYER := 10
const START_A := Vector2i(4, 0)
const START_B := Vector2i(4, 8)
const MAX_STEPS := 150
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

static var active_board: BlockadeBoard = null


static func has_active_board() -> bool:
	return active_board != null and is_instance_valid(active_board)


static func _find_shell(pet: Node) -> Node:
	return pet.get_tree().get_first_node_in_group("desktop_shell")


static func _spawn_board(shell: Node) -> BlockadeBoard:
	var board := BlockadeBoard.new()
	shell.top_layer().add_child(board)
	board.setup(shell.action_area)
	active_board = board
	return board


static func _cleanup_board(board: BlockadeBoard) -> void:
	if active_board == board:
		active_board = null
	if is_instance_valid(board):
		board.queue_free()


static func _wait(pet: Node, seconds: float) -> void:
	await pet.get_tree().create_timer(seconds).timeout


static func _cancelled(pets: Array, generations: Dictionary) -> bool:
	for pet: Node in pets:
		if not is_instance_valid(pet) or pet.action_generation != generations[pet]:
			return true
	return false


static func _flip(outcome: String) -> String:
	return "lose" if outcome == "win" else ("win" if outcome == "lose" else "tie")


static func _new_state() -> Dictionary:
	return {"pos": {"A": START_A, "B": START_B}, "walls_left": {"A": MAX_WALLS_PER_PLAYER, "B": MAX_WALLS_PER_PLAYER}, "walls": {}, "wall_owners": {}}


static func winner_of(pos: Dictionary) -> String:
	if (pos["A"] as Vector2i).y == GRID_N - 1:
		return "A"
	if (pos["B"] as Vector2i).y == 0:
		return "B"
	return ""


## 這一步(from→to,正交相鄰一格)有沒有被牆擋住。walls: Dictionary[Vector2i, String]("H"/"V")。
static func _step_blocked(walls: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	if to.x == from.x:   # 縱向移動,看橫牆
		var y: int = mini(from.y, to.y)
		var x: int = from.x
		return str(walls.get(Vector2i(x - 1, y), "")) == "H" or str(walls.get(Vector2i(x, y), "")) == "H"
	else:   # 橫向移動,看縱牆
		var x: int = mini(from.x, to.x)
		var y: int = from.y
		return str(walls.get(Vector2i(x, y - 1), "")) == "V" or str(walls.get(Vector2i(x, y), "")) == "V"


static func has_valid_path(walls: Dictionary, from_pos: Vector2i, target_y: int) -> bool:
	var queue: Array[Vector2i] = [from_pos]
	var visited := {from_pos: true}
	while not queue.is_empty():
		var curr: Vector2i = queue.pop_front()
		if curr.y == target_y:
			return true
		for d: Vector2i in DIRS:
			var next: Vector2i = curr + d
			if next.x < 0 or next.x >= GRID_N or next.y < 0 or next.y >= GRID_N:
				continue
			if _step_blocked(walls, curr, next) or visited.has(next):
				continue
			visited[next] = true
			queue.push_back(next)
	return false


static func get_shortest_path_length(walls: Dictionary, from_pos: Vector2i, target_y: int) -> int:
	var queue: Array[Dictionary] = [{"pos": from_pos, "dist": 0}]
	var visited := {from_pos: true}
	while not queue.is_empty():
		var node: Dictionary = queue.pop_front()
		var curr: Vector2i = node["pos"]
		var dist: int = node["dist"]
		if curr.y == target_y:
			return dist
		for d: Vector2i in DIRS:
			var next: Vector2i = curr + d
			if next.x < 0 or next.x >= GRID_N or next.y < 0 or next.y >= GRID_N:
				continue
			if _step_blocked(walls, curr, next) or visited.has(next):
				continue
			visited[next] = true
			queue.push_back({"pos": next, "dist": dist + 1})
	return 999


## 真正的 Quoridor 容許同方向的牆頭尾相接延伸成任意長度,但使用者 2026-10-04 明確要求限制住:同一條線上
## (橫牆沿 x 軸、縱牆沿 y 軸)最多只能兩片相接,不能疊到三片連成一整條長牆。算上新放這片之後,往兩個方向
## 數連續同方向的片數,到 3 就不准放。
static func _chain_length_ok(walls: Dictionary, slot: Vector2i, orientation: String) -> bool:
	var axis := Vector2i(1, 0) if orientation == "H" else Vector2i(0, 1)
	var run := 1
	var cursor := slot - axis
	while str(walls.get(cursor, "")) == orientation:
		run += 1
		cursor -= axis
	cursor = slot + axis
	while str(walls.get(cursor, "")) == orientation:
		run += 1
		cursor += axis
	return run < 3


## 這隻(role)目前所有合法的「走步」目的格,含標準 Quoridor 的跳棋規則(2026-10-04 使用者要求「避免玩家
## 堵死路」加入):跟對手正面相鄰(四個方向其中一個剛好是對手的格子)時──
## ① 對手正後方(同方向再一格)在棋盤內、且沒有牆擋,可以直線跳過去,整個跳躍算 1 步。
## ② 直線跳不行(背後有牆或是棋盤邊界)時,改成斜角跳:檢查對手左右兩側(跟跳躍方向垂直的兩格),沒被牆
## 擋住的那幾格都可以跳。③ 兩種都不行(背後有牆、左右也都被牆擋住,或對手卡在邊界角落):這個方向沒有
## 任何移動可選,但不影響其他三個方向——使用者還是可以往後退、往兩側走,或改放牆,不會被這個方向卡死
## (真的四個方向都沒有合法走步時,交給放牆的候選,再不行就是僵局保護判對手贏,不是這個函式要處理的)。
static func available_moves(walls: Dictionary, pos: Dictionary, role: String) -> Array[Vector2i]:
	var opp := "B" if role == "A" else "A"
	var my_pos: Vector2i = pos[role]
	var opp_pos: Vector2i = pos[opp]
	var moves: Array[Vector2i] = []
	for d: Vector2i in DIRS:
		var next: Vector2i = my_pos + d
		if next.x < 0 or next.x >= GRID_N or next.y < 0 or next.y >= GRID_N or _step_blocked(walls, my_pos, next):
			continue
		if next != opp_pos:
			moves.append(next)
			continue
		var behind: Vector2i = opp_pos + d
		if behind.x >= 0 and behind.x < GRID_N and behind.y >= 0 and behind.y < GRID_N and not _step_blocked(walls, opp_pos, behind):
			moves.append(behind)
			continue
		for side: Vector2i in [Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:   # 跳躍方向垂直旋轉 90 度,得到左右兩側
			var diag: Vector2i = opp_pos + side
			if diag.x < 0 or diag.x >= GRID_N or diag.y < 0 or diag.y >= GRID_N or _step_blocked(walls, opp_pos, diag):
				continue
			moves.append(diag)
	return moves


## slot 是不是能放 orientation 方向的牆:範圍內、沒被佔用、沒有疊成三片相接的長牆、放了之後雙方都還有路可走。
static func is_wall_placement_valid(walls: Dictionary, pos_a: Vector2i, pos_b: Vector2i, slot: Vector2i, orientation: String) -> bool:
	if slot.x < 0 or slot.x > GRID_N - 2 or slot.y < 0 or slot.y > GRID_N - 2:
		return false
	if walls.has(slot):
		return false
	if not _chain_length_ok(walls, slot, orientation):
		return false
	var trial: Dictionary = walls.duplicate()
	trial[slot] = orientation
	return has_valid_path(trial, pos_a, GRID_N - 1) and has_valid_path(trial, pos_b, 0)


## AI 決策:role = "A" / "B"。回傳 {} 表示沒有任何合法動作(僵局,對手直接獲勝)。level(見 GameAiLevel)
## 控制「明明算出最佳動作,卻選次佳甚至隨便選」的機率;level 不給(= 4)時完全不犯錯——t194 的純邏輯斷言
## 只檢查有沒有回傳合法動作,不受這個預設影響。實際對戰一律帶上桌寵自己的 `blockade_ai_level`(預設 3)。
static func get_best_action(state: Dictionary, role: String, level := 4) -> Dictionary:
	var opp := "B" if role == "A" else "A"
	var my_target_y := GRID_N - 1 if role == "A" else 0
	var opp_target_y := 0 if role == "A" else GRID_N - 1
	var pos: Dictionary = state["pos"]
	var walls: Dictionary = state["walls"]
	var valid_actions: Array = []
	var current_my_dist := get_shortest_path_length(walls, pos[role], my_target_y)
	var current_opp_dist := get_shortest_path_length(walls, pos[opp], opp_target_y)
	for next_pos: Vector2i in available_moves(walls, pos, role):
		var new_dist := get_shortest_path_length(walls, next_pos, my_target_y)
		var score := float(current_my_dist - new_dist) * 10.0
		if next_pos.y == my_target_y:
			score += 1000.0
		valid_actions.append({"type": "MOVE", "target": next_pos, "score": score})
	var walls_left: Dictionary = state["walls_left"]
	if int(walls_left[role]) > 0:
		for x in GRID_N - 1:
			for y in GRID_N - 1:
				var slot := Vector2i(x, y)
				for orientation: String in ["H", "V"]:
					if is_wall_placement_valid(walls, pos["A"], pos["B"], slot, orientation):
						var trial: Dictionary = walls.duplicate()
						trial[slot] = orientation
						var new_opp_dist := get_shortest_path_length(trial, pos[opp], opp_target_y)
						var new_my_dist := get_shortest_path_length(trial, pos[role], my_target_y)
						var opp_delay := new_opp_dist - current_opp_dist
						var my_delay := new_my_dist - current_my_dist
						if opp_delay > 0:
							valid_actions.append({"type": "WALL", "orientation": orientation, "target": slot, "score": float(opp_delay) * 12.0 - float(my_delay) * 8.0})
	if valid_actions.is_empty():
		return {}
	valid_actions.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["score"]) > float(y["score"]))
	var mistake := GameAiLevel.mistake_chance(level)
	if valid_actions.size() > 1 and randf() < mistake:
		return valid_actions.pick_random() if level <= 1 else valid_actions[1]
	return valid_actions[0]


static func _apply_action(state: Dictionary, role: String, action: Dictionary) -> void:
	if action["type"] == "MOVE":
		(state["pos"] as Dictionary)[role] = action["target"]
	else:
		(state["walls"] as Dictionary)[action["target"]] = action["orientation"]
		(state["wall_owners"] as Dictionary)[action["target"]] = role
		(state["walls_left"] as Dictionary)[role] = int((state["walls_left"] as Dictionary)[role]) - 1


static func _is_legal(state: Dictionary, role: String, action: Dictionary) -> bool:
	var pos: Dictionary = state["pos"]
	var walls: Dictionary = state["walls"]
	var target: Vector2i = action["target"]
	if action["type"] == "MOVE":
		return available_moves(walls, pos, role).has(target)
	elif action["type"] == "WALL":
		if int((state["walls_left"] as Dictionary)[role]) <= 0:
			return false
		return is_wall_placement_valid(walls, pos["A"], pos["B"], target, str(action.get("orientation", "")))
	return false


## 內建反應(贏開心、輸生氣、平手不服氣),跟 ttt_game 同一套做法,不經 GameChat.react()。
static func _react(pet: Node, outcome: String, vs_user: bool) -> void:
	if not is_instance_valid(pet):
		return
	pet.record_game_result("blockade", outcome)
	if outcome == "lose":
		pet.game_losses_in_row += 1
	elif outcome == "win":
		pet.game_losses_in_row = 0
	if pet.vitality != null:
		pet.vitality.on_game_result(outcome, vs_user)
	match outcome:
		"win":
			GameChat.celebrate_win(pet)
			GameChat.say(pet, "[wave]%s[/wave]" % ["贏了!路都被我走通了!", "哈,先到終點啦!", "耶,步步為營我最強!"].pick_random(), 3.0)
		"lose":
			pet.shiver(1.5)
			GameChat.say(pet, "[shake]%s[/shake]" % ["竟然被堵死了……", "唔,這盤輸了。", "下次一定贏回來!"].pick_random(), 3.0)
		_:
			GameChat.say(pet, ["平手,誰都沒走到!", "下滿了還是平手!"].pick_random(), 2.5)


## 一局(回合制走到有人抵達終點、僵局、或 MAX_STEPS 步平手為止)。回傳 "A"/"B"(贏家角色)、""(平手)、null(被打斷)。
static func _play_round(board: BlockadeBoard, a: Node, b: Node, generations: Dictionary, first_role: String, round_num: int, best_of: int, levels: Array) -> Variant:
	var state := _new_state()
	var current := first_role
	board.status_text = TranslationServer.translate("%s VS %s (%d/%d)") % [a.get_label(), b.get_label(), round_num, maxi(best_of, 1)]
	board.state = state
	board.refresh()
	var steps := 0
	while steps < MAX_STEPS:
		steps += 1
		await _wait(a, 0.8)
		if _cancelled([a, b], generations) or not is_instance_valid(board):
			return null
		var action := get_best_action(state, current, levels[0] if current == "A" else levels[1])
		if action.is_empty():
			return "B" if current == "A" else "A"
		_apply_action(state, current, action)
		board.state = state
		board.refresh()
		var win := winner_of(state["pos"])
		if win != "":
			return win
		current = "B" if current == "A" else "A"
	return ""


## 桌寵對桌寵。回傳 {outcome_a, outcome_b, wins_a, wins_b, rounds};中途被打斷、棋盤被搶先佔用回空字典。
static func play_pets(a: Node, b: Node, best_of := 1) -> Dictionary:
	if not is_instance_valid(a) or not is_instance_valid(b) or a == b:
		return {}
	if a.is_in_game() or has_active_board():
		return {}
	if b.is_in_game():
		GameChat.think_blocked(a, b, TranslationServer.translate("步步為營"))
		return {}
	GameChat.enter([a, b], "blockade")
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
	var first_role := "A" if randf() < 0.5 else "B"
	var levels := [GameAiLevel.match_level(a, b, a.blockade_ai_level), GameAiLevel.match_level(b, a, b.blockade_ai_level)]   # 好惡影響,整場擲一次
	while wins_a < need and wins_b < need and rounds < maxi(best_of, 1) + 2:
		rounds += 1
		var winner_role: Variant = await _play_round(board, a, b, generations, first_role, rounds, best_of, levels)
		if winner_role == null:
			_cleanup_board(board)
			return {}
		if winner_role == "A":
			wins_a += 1
			first_role = "A"
		elif winner_role == "B":
			wins_b += 1
			first_role = "B"
		else:
			first_role = "B" if first_role == "A" else "A"
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


## 使用者對桌寵(使用者永遠扮演角色 B,從底端出發)。回傳 {outcome, pet_wins, user_wins};取消回空字典。
static func play_user(pet: Node, best_of := 1) -> Dictionary:
	if not is_instance_valid(pet) or pet.is_in_game() or has_active_board():
		return {}
	GameChat.enter([pet], "blockade")
	var result: Dictionary = await _play_user(pet, best_of)
	GameChat.leave([pet])
	if not result.is_empty():   # 跟使用者的 1v1 打完一場(取消的不算)
		PetFavor.user_bond(pet, "duel", PetFavor.USER_SMALL, PetFavor.USER_DUEL_COOLDOWN)
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
	var first_role := "A" if randf() < 0.5 else "B"   # A = 桌寵、B = 使用者
	while pet_wins < need and user_wins < need:
		rounds += 1
		var state := _new_state()
		var current := first_role
		board.status_text = TranslationServer.translate("%s VS 你 (%d/%d)") % [pet.get_label(), rounds, maxi(best_of, 1)]
		board.state = state
		board.refresh()
		var winner_role := ""
		var steps := 0
		while steps < MAX_STEPS and winner_role == "":
			steps += 1
			if not is_instance_valid(pet) or pet.action_generation != generation or not is_instance_valid(board):
				_cleanup_board(board)
				return {}
			if flags["cancelled"] or flags["surrendered"]:
				break
			if current == "A":
				await _wait(pet, 0.8)
				if flags["cancelled"] or flags["surrendered"] or not is_instance_valid(board):
					break
				var action := get_best_action(state, "A", pet.blockade_ai_level)
				if action.is_empty():
					winner_role = "B"
					break
				_apply_action(state, "A", action)
			else:
				board.interactive = true
				board.wall_mode_kind = "move"
				board.walls_left_hint = int((state["walls_left"] as Dictionary)["B"])
				var chosen := [null]
				var on_action := func(kind: String, orientation: String, target: Vector2i) -> void:
					chosen[0] = {"type": kind, "orientation": orientation, "target": target}
				board.action_chosen.connect(on_action)
				while chosen[0] == null and not flags["cancelled"] and not flags["surrendered"] and is_instance_valid(board):
					await pet.get_tree().process_frame
					if chosen[0] != null and not _is_legal(state, "B", chosen[0]):
						chosen[0] = null   # 不合法的點擊:忽略,讓使用者重新點
				if is_instance_valid(board) and board.action_chosen.is_connected(on_action):
					board.action_chosen.disconnect(on_action)
				board.interactive = false
				if flags["cancelled"] or flags["surrendered"] or not is_instance_valid(board):
					break
				_apply_action(state, "B", chosen[0])
			board.state = state
			board.refresh()
			winner_role = winner_of(state["pos"])
			if winner_role == "":
				current = "B" if current == "A" else "A"
		if flags["cancelled"]:
			_cleanup_board(board)
			return {}
		if flags["surrendered"]:
			winner_role = "A"
		if winner_role == "A":
			pet_wins += 1
			first_role = "A"
		elif winner_role == "B":
			user_wins += 1
			first_role = "B"
		else:
			first_role = "B" if first_role == "A" else "A"
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
