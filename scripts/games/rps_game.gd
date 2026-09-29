class_name RpsGame
extends RefCounted
## 猜拳(剪刀石頭布):使用者對桌寵(用氣泡上的選項按鈕出拳)、桌寵對桌寵。全程在對話氣泡裡演出,不開視窗。
## 結果的處理與擲骰一樣:每個參加者的積木事件 event_when_rps(RESULT = win / lose / draw)會被觸發,
## 沒有的用內建反應(贏了開心、輸了氣得發抖、連輸越氣)。對話文字可用 {rps:mine}(自己出什麼)、{rps:theirs}(對方出什麼)、
## {rps:opponent}(對手名字;對使用者就是「你」)、{rps:score}(這一場的勝局數,自己:對方)、{rps:rounds}(打了幾局)。
## 賽制 best_of:1 = 一戰定勝負、3 = 三戰兩勝、5 = 五戰三勝;整場打完才算一筆戰績、才觸發結果事件。

const NAMES: Array[String] = ["石頭", "剪刀", "布"]
const EMOJI: Array[String] = ["✊", "✌", "✋"]
const MAX_DRAWS := 3
const COUNTDOWN_STEP := 0.55


## a 出的贏 b 嗎?(石頭 0 贏剪刀 1,剪刀贏布 2,布贏石頭)
static func beats(a: int, b: int) -> bool:
	return (a - b + 3) % 3 == 2


## 從 a 的角度:win / lose / draw。
static func outcome_for(a: int, b: int) -> String:
	if a == b:
		return "draw"
	return "win" if beats(a, b) else "lose"


static func gesture(index: int) -> String:
	return "%s %s" % [EMOJI[index], NAMES[index]]


static func _wait(pet: Node, seconds: float) -> void:
	await pet.get_tree().create_timer(seconds).timeout


static func _flip(outcome: String) -> String:
	return "lose" if outcome == "win" else ("win" if outcome == "lose" else "draw")


## 幾勝就贏了:一戰 = 1、三戰兩勝 = 2、五戰三勝 = 3。
static func needed_wins(best_of: int) -> int:
	return floori(maxi(best_of, 1) / 2.0) + 1


## 兩隻桌寵的一「局」:倒數 → 同時出拳;平手自動重來(最多 MAX_DRAWS 次,還是平手就是平手局)。
## 回傳 {a, b}(最後一次的出拳);被打斷回空字典。
static func _pet_round(a: Node, b: Node, generations: Dictionary) -> Dictionary:
	var gesture_a := 0
	var gesture_b := 0
	for attempt in MAX_DRAWS:
		for word in ["剪刀…", "石頭…", "布!"]:
			GameChat.say(a, word, COUNTDOWN_STEP + 0.3)
			GameChat.say(b, word, COUNTDOWN_STEP + 0.3)
			await _wait(a, COUNTDOWN_STEP)
			if _cancelled([a, b], generations):
				return {}
		gesture_a = randi() % 3
		gesture_b = randi() % 3
		GameChat.say(a, gesture(gesture_a), 2.5)
		GameChat.say(b, gesture(gesture_b), 2.5)
		await _wait(a, 1.3)
		if _cancelled([a, b], generations):
			return {}
		if gesture_a != gesture_b:
			break
		if attempt < MAX_DRAWS - 1:
			GameChat.say(a, "平手!再來!", 1.4)
			GameChat.say(b, "平手!再來!", 1.4)
			await _wait(a, 1.2)
			if _cancelled([a, b], generations):
				return {}
	return {"a": gesture_a, "b": gesture_b}


## 桌寵對桌寵,best_of 局制(1 = 一戰定勝負、3 = 三戰兩勝、5 = 五戰三勝)。
## 回傳 {outcome_a, outcome_b, a, b, wins_a, wins_b, rounds}(a、b 是最後一局的出拳);被打斷回空字典。
## 只有整場打完才算一筆戰績、才觸發結果事件;{rps:score} = 自己:對方 的勝局數。
## 對戰進行期間雙方都算「在對戰中」(Pet.game_depth),這時別人的邀請進不來(見 GameInvite.invite)。
static func play_pets(a: Node, b: Node, best_of := 1) -> Dictionary:
	if is_instance_valid(a) and is_instance_valid(b):
		if a.is_in_game():
			return {}   # 自己還在打,別的邀請進不來
		if b.is_in_game():
			GameChat.think_blocked(a, b, TranslationServer.translate("猜拳"))
			return {}
	GameChat.enter([a, b])
	var result: Dictionary = await _play_pets(a, b, best_of)
	GameChat.leave([a, b])
	return result


static func _play_pets(a: Node, b: Node, best_of := 1) -> Dictionary:
	if not is_instance_valid(a) or not is_instance_valid(b) or a == b:
		return {}
	var generations := {a: a.action_generation, b: b.action_generation}
	var need := needed_wins(best_of)
	var wins_a := 0
	var wins_b := 0
	var rounds := 0
	var last := {}
	# 平手局不算分,所以總局數多給幾局的空間;超過就用目前比數判定。
	while wins_a < need and wins_b < need and rounds < maxi(best_of, 1) + MAX_DRAWS:
		rounds += 1
		if best_of > 1:
			var header := TranslationServer.translate("第 %d 局!(%d : %d)") % [rounds, wins_a, wins_b]
			GameChat.say(a, header, 1.4)
			GameChat.say(b, TranslationServer.translate("第 %d 局!(%d : %d)") % [rounds, wins_b, wins_a], 1.4)
			await _wait(a, 1.2)
			if _cancelled([a, b], generations):
				return {}
		last = await _pet_round(a, b, generations)
		if last.is_empty():
			return {}
		var round_a := outcome_for(last["a"], last["b"])
		if round_a == "win":
			wins_a += 1
		elif round_a == "lose":
			wins_b += 1
		if best_of > 1:
			var draw_line := TranslationServer.translate("這局平手!")
			var win_line := TranslationServer.translate("[b]贏了這局![/b]")
			var lose_line := TranslationServer.translate("輸了這局……")
			var line_a := draw_line if round_a == "draw" else (win_line if round_a == "win" else lose_line)
			GameChat.say(a, "%s\n(%d : %d)" % [line_a, wins_a, wins_b], 1.6)
			var line_b := draw_line if round_a == "draw" else (win_line if round_a == "lose" else lose_line)
			GameChat.say(b, "%s\n(%d : %d)" % [line_b, wins_b, wins_a], 1.6)
			await _wait(a, 1.5)
			if _cancelled([a, b], generations):
				return {}
	var result_a := "tie" if wins_a == wins_b else ("win" if wins_a > wins_b else "lose")
	if best_of <= 1:
		result_a = outcome_for(last["a"], last["b"])
	a.game_vars["rps:mine"] = gesture(last["a"])
	a.game_vars["rps:theirs"] = gesture(last["b"])
	a.game_vars["rps:opponent"] = str(b.get_label())
	a.game_vars["rps:score"] = "%d:%d" % [wins_a, wins_b]
	a.game_vars["rps:rounds"] = str(rounds)
	b.game_vars["rps:mine"] = gesture(last["b"])
	b.game_vars["rps:theirs"] = gesture(last["a"])
	b.game_vars["rps:opponent"] = str(a.get_label())
	b.game_vars["rps:score"] = "%d:%d" % [wins_b, wins_a]
	b.game_vars["rps:rounds"] = str(rounds)
	GameChat.set_result_context(a, b, result_a)
	await _wait(a, 0.4)
	if _cancelled([a, b], generations):
		return {}
	GameChat.react(a, "rps", result_a)
	GameChat.react(b, "rps", _flip(result_a))
	return {"outcome_a": result_a, "outcome_b": _flip(result_a), "a": last["a"], "b": last["b"], "wins_a": wins_a, "wins_b": wins_b, "rounds": rounds}


## 使用者對桌寵:氣泡問「你要出什麼?」(按鈕),桌寵倒數後同時出拳。平手自動重來;
## best_of > 1 時是多局制(每局都問一次,比數寫在氣泡上),整場分出勝負才算一筆戰績;結束後問要不要再來一場。
## 回傳最後一場桌寵視角的結果字典 {outcome, pet, user, pet_wins, user_wins};中途離開、被打斷、沒有介面回空字典或上一場的結果。
static func play_user(pet: Node, best_of := 1) -> Dictionary:
	if is_instance_valid(pet) and pet.is_in_game():
		return {}   # 玩家的遊戲要求:桌寵正在對戰,直接無效
	GameChat.enter([pet])
	var result: Dictionary = await _play_user(pet, best_of)
	GameChat.leave([pet])
	return result


static func _play_user(pet: Node, best_of := 1) -> Dictionary:
	if not is_instance_valid(pet):
		return {}
	var generation: int = pet.action_generation
	var need := needed_wins(best_of)
	var last := {}
	while true:
		var pet_wins := 0
		var user_wins := 0
		var rounds := 0
		var result := ""
		var pet_gesture := 0
		var choice := 0
		while pet_wins < need and user_wins < need:
			var prompt := "剪刀石頭布!你要出什麼?"
			if best_of > 1:
				prompt = TranslationServer.translate("第 %d 局!(我 %d : %d 你)\n你要出什麼?") % [rounds + 1, pet_wins, user_wins]
			choice = await GameChat.ask(pet, prompt, [gesture(0), gesture(1), gesture(2), "不玩了"], 60.0)
			if not is_instance_valid(pet) or pet.action_generation != generation:
				return last
			if choice < 0 or choice > 2:
				if choice == 3:
					GameChat.say(pet, "好吧……下次再玩!", 2.0)
				return last
			for word in ["剪刀…", "石頭…", "布!"]:
				GameChat.say(pet, word, COUNTDOWN_STEP + 0.3)
				await _wait(pet, COUNTDOWN_STEP)
				if not is_instance_valid(pet) or pet.action_generation != generation:
					return last
			pet_gesture = randi() % 3
			var round_result := outcome_for(pet_gesture, choice)
			if round_result != "draw":
				rounds += 1
			if round_result == "win":
				pet_wins += 1
			elif round_result == "lose":
				user_wins += 1
			var verdict: String = {"win": "我贏了!", "lose": "你贏了!", "draw": "平手!"}[round_result]
			var score := "" if best_of <= 1 else TranslationServer.translate("\n(我 %d : %d 你)") % [pet_wins, user_wins]
			GameChat.say(pet, TranslationServer.translate("我出 %s\n你出 %s\n→ [b]%s[/b]%s") % [gesture(pet_gesture), gesture(choice), verdict, score], 3.0)
			await _wait(pet, 1.8)
			if not is_instance_valid(pet) or pet.action_generation != generation:
				return last
		result = "win" if pet_wins > user_wins else "lose"
		pet.set_counterpart_named("opponent", "user", "你")
		pet.set_counterpart_named("winner", pet.recognition_tag if result == "win" else "user", pet.display_name if result == "win" else "你")
		pet.set_counterpart_named("loser", "user" if result == "win" else pet.recognition_tag, "你" if result == "win" else pet.display_name)
		pet.game_vars["rps:mine"] = gesture(pet_gesture)
		pet.game_vars["rps:theirs"] = gesture(choice)
		pet.game_vars["rps:opponent"] = "你"
		pet.game_vars["rps:score"] = "%d:%d" % [pet_wins, user_wins]
		pet.game_vars["rps:rounds"] = str(rounds)
		last = {"outcome": result, "pet": pet_gesture, "user": choice, "pet_wins": pet_wins, "user_wins": user_wins}
		if best_of > 1:
			GameChat.say(pet, TranslationServer.translate("[b]%s[/b]\n最終比數 我 %d : %d 你") % ["這一場我贏了!" if result == "win" else "這一場你贏了!", pet_wins, user_wins], 2.5)
			await _wait(pet, 1.6)
			if not is_instance_valid(pet) or pet.action_generation != generation:
				return last
		GameChat.react(pet, "rps", result, true)
		await _wait(pet, 1.8)
		if not is_instance_valid(pet) or pet.action_generation != generation:
			return last
		var again := await GameChat.ask(pet, "再來一場嗎?" if best_of > 1 else "再來一局嗎?", ["再來一場" if best_of > 1 else "再來一局", "不玩了"], 30.0)
		if again != 0:
			return last
	return last

static func _cancelled(pets: Array, generations: Dictionary) -> bool:
	for pet: Node in pets:
		if not is_instance_valid(pet) or pet.action_generation != generations[pet]:
			return true
	return false


## 大逃殺猜拳(2026-09-28,使用者要求):使用者 + 場上所有目前有空(不在對戰中)的桌寵一起玩。每輪全員同時
## 出拳:場上剛好只出現兩種手勢時,打不贏的那批被淘汰(GameChat.leave 立刻放行,恢復自主行為);出現一種
## (全部一樣)或三種手勢時算平手,全員晉級重猜一次;重複直到剩最後一位。host = 發起這場的桌寵(右鍵選單
## 「與桌寵猜拳」),負責在自己還活著時開口問使用者出什麼,被淘汰後改由下一個還活著的桌寵問。
static func play_battle_royale(host: Node) -> Dictionary:
	if not is_instance_valid(host) or host.is_in_game():
		return {}
	var pets: Array = [host]
	for other: Node in host.get_tree().get_nodes_in_group("pets"):
		if other != host and is_instance_valid(other) and not other.is_in_game():
			pets.append(other)
	GameChat.enter(pets)
	var result: Dictionary = await _play_battle_royale(pets)
	GameChat.leave(pets)
	return result


static func _play_battle_royale(pets: Array) -> Dictionary:
	var alive: Array = pets.filter(func(p: Node) -> bool: return is_instance_valid(p))
	if alive.is_empty():
		return {}
	var generations := {}
	for pet: Node in alive:
		generations[pet] = pet.action_generation
	var user_alive := true
	var round_num := 0
	while alive.size() + int(user_alive) > 1:
		round_num += 1
		var speaker: Node = alive[0]
		for pet: Node in alive:
			GameChat.say(pet, TranslationServer.translate("第 %d 輪!還剩 %d 位") % [round_num, alive.size() + int(user_alive)], 1.4)
		await _wait(speaker, 1.2)
		if _cancelled(alive, generations):
			return {}
		var user_choice := -1
		if user_alive:
			user_choice = await GameChat.ask(speaker, "剪刀石頭布!你要出什麼?", [gesture(0), gesture(1), gesture(2), "不玩了"], 60.0)
			if not is_instance_valid(speaker) or _cancelled(alive, generations):
				return {}
			if user_choice < 0 or user_choice > 2:
				user_alive = false
				if user_choice == 3:
					for pet: Node in alive:
						GameChat.say(pet, "使用者棄權啦!", 1.6)
					await _wait(speaker, 1.2)
					if _cancelled(alive, generations):
						return {}
		for word in ["剪刀…", "石頭…", "布!"]:
			for pet: Node in alive:
				GameChat.say(pet, word, COUNTDOWN_STEP + 0.3)
			await _wait(speaker, COUNTDOWN_STEP)
			if _cancelled(alive, generations):
				return {}
		var gestures := {}
		for pet: Node in alive:
			gestures[pet] = randi() % 3
		for pet: Node in alive:
			GameChat.say(pet, gesture(gestures[pet]), 2.2)
		await _wait(speaker, 1.3)
		if _cancelled(alive, generations):
			return {}
		var distinct := {}
		for value: int in gestures.values():
			distinct[value] = true
		if user_alive:
			distinct[user_choice] = true
		if distinct.size() != 2:
			# 平手(全部一樣或三種都出現):全員晉級,重來一輪。打到第 20 輪還是平手(一個都還沒淘汰)就直接
			# 結束,不要無止盡玩下去(2026-09-30 使用者要求)。
			if round_num >= 20:
				var giveup_line := TranslationServer.translate("這樣下去似乎沒完沒了……下次再比吧?")
				for pet: Node in alive:
					GameChat.say(pet, giveup_line, 1.8)
				await _wait(speaker, 1.6)
				return {"winner": ""}
			for pet: Node in alive:
				GameChat.say(pet, "平手!全員晉級,再猜一次!", 1.4)
			await _wait(speaker, 1.2)
			if _cancelled(alive, generations):
				return {}
			continue
		var values: Array = distinct.keys()
		var winning_gesture: int = values[0] if beats(values[0], values[1]) else values[1]
		var survivors: Array = []
		for pet: Node in alive:
			if gestures[pet] == winning_gesture:
				survivors.append(pet)
			else:
				GameChat.say(pet, "被淘汰了……下次加油!", 1.8)
				GameChat.react(pet, "rps", "lose")
				GameChat.leave([pet])
		if user_alive and user_choice != winning_gesture:
			user_alive = false
		alive = survivors
		if not alive.is_empty():
			await _wait(alive[0], 1.4)
			if _cancelled(alive, generations):
				return {}
	var winner: Node = alive[0] if alive.size() == 1 else null
	if winner != null:
		GameChat.say(winner, "[wave]我是冠軍!![/wave]", 3.0)
		GameChat.react(winner, "rps", "win")
	elif user_alive and not pets.is_empty() and is_instance_valid(pets[0]):
		GameChat.say(pets[0], "你是冠軍!!真厲害!", 3.0)
	return {"winner": winner.recognition_tag if winner != null else ("user" if user_alive else "")}
