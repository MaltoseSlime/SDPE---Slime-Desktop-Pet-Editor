class_name DiceGame
extends RefCounted
## 擲骰:單人檢定(擲 NDX + 加值,和檢定值比)與多人拚骰(比誰的點數大)。
## 過程與結果都顯示在桌寵的對話氣泡,不開視窗。點數存進桌寵的 dice_results[KEY],
## 對話文字可以用 {roll:KEY}(見 LogicInterpreter._placeholder_text)。拚骰結束後每個參加者的積木事件
## event_when_dice_contest(RESULT = win / lose / tie)會被觸發;沒有那個事件的桌寵用內建反應(贏了開心、輸了氣得發抖)。
## 賽制 best_of(1 一戰、3 三戰兩勝、5 五戰三勝);對話可用 {contest:score}(這一場的勝局,自己:最高的對手)、{contest:rounds}。
## 所有等待都可被打斷:任何一個參加者被使用者點擊/拖曳(action_generation 改變)整場就取消。

const MIN_SIDES := 2
const MAX_SIDES := 1000
const MAX_COUNT := 20
const MAX_TIE_ROUNDS := 3
const SUSPENSE := 0.6


static func roll(sides: int, count: int, modifier: int) -> Dictionary:
	sides = clampi(sides, MIN_SIDES, MAX_SIDES)
	count = clampi(count, 1, MAX_COUNT)
	var rolls: Array[int] = []
	var sum := 0
	for i in count:
		var value := randi_range(1, sides)
		rolls.append(value)
		sum += value
	return {"sides": sides, "count": count, "mod": modifier, "rolls": rolls, "sum": sum, "total": sum + modifier}


## 檢定值:最大可能點數(骰面 × 顆數)的百分比,無條件進位、至少 1;百分比 <= 0 = 不檢定(回 0)。
static func threshold(sides: int, count: int, percent: int) -> int:
	if percent <= 0:
		return 0
	return maxi(1, ceili(float(clampi(sides, MIN_SIDES, MAX_SIDES) * clampi(count, 1, MAX_COUNT)) * float(percent) / 100.0))


static func label(sides: int, count: int, modifier: int) -> String:
	return "%dD%d%s" % [count, sides, ("%+d" % modifier) if modifier != 0 else ""]


## 氣泡用的一行結果(BBCode):🎲 1D20+2 = [b]14[/b](檢定 ≥ 11:成功)
static func describe(result: Dictionary, dc: int) -> String:
	var text := "🎲 %s = [b]%d[/b]" % [label(result["sides"], result["count"], result["mod"]), result["total"]]
	if int(result["count"]) > 1:
		text += " (%s)" % ", ".join((result["rolls"] as Array).map(func(v: int) -> String: return str(v)))
	if dc > 0:
		var passed: bool = int(result["total"]) >= dc
		var outcome := TranslationServer.translate("[color=#4cc36a][b]成功![/b][/color]") if passed else TranslationServer.translate("[color=#ff5a5a][b]失敗……[/b][/color]")
		text += TranslationServer.translate("\n檢定 ≥ %d:%s") % [dc, outcome]
	return text


static func _store(pet: Node, key: String, result: Dictionary, dc: int) -> void:
	var entry: Dictionary = result.duplicate()
	entry["dc"] = dc
	entry["pass"] = dc <= 0 or int(result["total"]) >= dc
	pet.dice_results[key] = entry
	pet.game_vars["roll:" + key] = str(result["total"])


static func _wait(pet: Node, seconds: float) -> void:
	await pet.get_tree().create_timer(seconds).timeout


## 單人擲骰:懸念(桌寵抖一下)→ 擲 → 存結果 → (show)氣泡顯示。回傳結果字典;等待中被打斷回空字典。
static func roll_and_show(pet: Node, sides: int, count: int, modifier: int, dc: int, key: String, show := true, suspense := SUSPENSE) -> Dictionary:
	if not is_instance_valid(pet):
		return {}
	var generation: int = pet.action_generation
	if suspense > 0.0:
		pet.shiver(suspense)
		await _wait(pet, suspense)
		if not is_instance_valid(pet) or pet.action_generation != generation:
			return {}
	var result := roll(sides, count, modifier)
	_store(pet, key, result, dc)
	if show:
		GameChat.say(pet, describe(result, dc), 4.0)
	return pet.dice_results[key]


## 一「局」拚骰:每個人依序擲骰,點數最大的贏;並列第一名時 tie_mode = "reroll" 只讓並列的重擲(最多 MAX_TIE_ROUNDS 輪),
## "draw" 直接算平手。回傳 {totals: {桌寵 → 點數}, winners: [桌寵…]};被打斷回空字典。
static func _play_round(initiator: Node, everyone: Array, sides: int, count: int, modifier: int, tie_mode: String, key: String, generations: Dictionary) -> Dictionary:
	var totals := {}
	var contenders: Array = everyone.duplicate()
	var winners: Array = contenders
	var tie_round := 0
	while true:
		tie_round += 1
		for pet: Node in contenders:
			pet.shiver(SUSPENSE)
			await _wait(initiator, SUSPENSE + 0.1)
			if _cancelled(everyone, generations):
				return {}
			var result := roll(sides, count, modifier)
			_store(pet, key, result, 0)
			totals[pet] = int(result["total"])
			GameChat.say(pet, describe(result, 0), 3.0)
			await _wait(initiator, 0.5)
			if _cancelled(everyone, generations):
				return {}
		var best := -1000000
		for pet: Node in contenders:
			best = maxi(best, int(totals[pet]))
		winners = contenders.filter(func(p: Node) -> bool: return int(totals[p]) == best)
		if winners.size() == 1 or tie_mode == "draw" or tie_round >= MAX_TIE_ROUNDS:
			break
		for pet: Node in winners:
			GameChat.say(pet, "平手!再擲一次!", 1.6, true)
		await _wait(initiator, 1.5)
		if _cancelled(everyone, generations):
			return {}
		contenders = winners
	return {"totals": totals, "winners": winners}


## 多人拚骰,best_of 局制(1 = 一戰定勝負、3 = 三戰兩勝、5 = 五戰三勝;多人時是先拿下足夠局數的贏,每局點數最大的拿一分)。
## 回傳 {outcomes: {桌寵 → win/lose/tie}, totals: {桌寵 → 最後一局點數}, wins: {桌寵 → 贏的局數}, rounds};取消回空字典。
## 只有整場打完才算一筆戰績、才觸發結果事件。
static func contest(initiator: Node, pets: Array, sides: int, count: int, modifier: int, tie_mode := "reroll", key := "contest", best_of := 1) -> Dictionary:
	# 場上有任何一隻正在對戰中:發起的桌寵被擋下(自己在打就直接無效)。
	if is_instance_valid(initiator) and initiator.is_in_game():
		return {}
	for busy: Variant in pets:
		if is_instance_valid(busy) and busy != initiator and busy.is_in_game():
			GameChat.think_blocked(initiator, busy, TranslationServer.translate("拚骰"))
			return {}
	GameChat.enter(pets)
	var result: Dictionary = await _contest(initiator, pets, sides, count, modifier, tie_mode, key, best_of)
	GameChat.leave(pets)
	return result


static func _contest(initiator: Node, pets: Array, sides: int, count: int, modifier: int, tie_mode: String, key: String, best_of: int) -> Dictionary:
	var contenders: Array = pets.filter(func(p: Node) -> bool: return is_instance_valid(p))
	if contenders.size() < 2:
		GameChat.say(initiator, "一個人沒辦法拚骰啦……", 2.5)
		return {}
	var everyone: Array = contenders.duplicate()
	var generations := {}
	var wins := {}
	for pet: Node in everyone:
		generations[pet] = pet.action_generation
		wins[pet] = 0
	var need := RpsGame.needed_wins(best_of)
	var totals := {}
	var winners: Array = []
	var rounds := 0
	while true:
		rounds += 1
		if best_of > 1:
			for pet: Node in everyone:
				GameChat.say(pet, TranslationServer.translate("第 %d 局!") % rounds, 1.2, true)
			await _wait(initiator, 1.0)
			if _cancelled(everyone, generations):
				return {}
		var round_result := await _play_round(initiator, everyone, sides, count, modifier, tie_mode, key, generations)
		if round_result.is_empty():
			return {}
		totals = round_result["totals"]
		winners = round_result["winners"]
		if winners.size() == 1:
			wins[winners[0]] += 1
		if best_of <= 1:
			break
		var top := 0
		for pet: Node in everyone:
			top = maxi(top, int(wins[pet]))
		for pet: Node in everyone:
			var line := TranslationServer.translate("[b]贏了這局![/b]") if winners.size() == 1 and winners[0] == pet else (TranslationServer.translate("這局平手") if winners.has(pet) and winners.size() > 1 else TranslationServer.translate("輸了這局……"))
			GameChat.say(pet, TranslationServer.translate("%s\n(已贏 %d 局)") % [line, wins[pet]], 1.6)
		await _wait(initiator, 1.5)
		if _cancelled(everyone, generations):
			return {}
		# 有人拿滿局數就結束;平手局不算分,所以總局數多給幾局,超過就用目前勝局判定。
		if top >= need or rounds >= best_of + MAX_TIE_ROUNDS:
			break
	var champions: Array = winners
	if best_of > 1:
		var top_wins := 0
		for pet: Node in everyone:
			top_wins = maxi(top_wins, int(wins[pet]))
		champions = everyone.filter(func(p: Node) -> bool: return int(wins[p]) == top_wins)
	var outcomes := {}
	var best_total := -1000000
	for pet: Node in everyone:
		best_total = maxi(best_total, int(totals.get(pet, -1000000)))
	var champion_name := "沒有人" if champions.size() != 1 else str(champions[0].get_label())
	for pet: Node in everyone:
		var outcome := "lose"
		if champions.has(pet):
			outcome = "win" if champions.size() == 1 else "tie"
		outcomes[pet] = outcome
		var others: Array = everyone.filter(func(p: Node) -> bool: return p != pet)
		others.sort_custom(func(a: Node, b: Node) -> bool: return int(totals.get(a, 0)) > int(totals.get(b, 0)))
		var best_other_wins := 0
		for other: Node in others:
			best_other_wins = maxi(best_other_wins, int(wins[other]))
		# 對象:對手 = 點數最高的其他人;贏家 = 唯一的冠軍(有的話);輸家 = 勝局最少、點數最低的那位(平手或沒有唯一冠軍就沒有輸家)。
		if not others.is_empty():
			pet.set_counterpart("opponent", others[0])
		if champions.size() == 1:
			pet.set_counterpart("winner", champions[0])
		else:
			pet.clear_counterpart("winner")
		var ranked: Array = everyone.duplicate()
		ranked.sort_custom(func(x: Node, y: Node) -> bool: return int(wins[x]) < int(wins[y]) or (int(wins[x]) == int(wins[y]) and int(totals.get(x, 0)) < int(totals.get(y, 0))))
		if not ranked.is_empty() and champions.size() == 1 and ranked[0] != champions[0]:
			pet.set_counterpart("loser", ranked[0])
		else:
			pet.clear_counterpart("loser")
		pet.game_vars["contest:mine"] = str(totals.get(pet, 0))
		pet.game_vars["contest:best"] = str(best_total)
		pet.game_vars["contest:winner"] = champion_name
		pet.game_vars["contest:opponent"] = str(others[0].get_label()) if not others.is_empty() else ""
		pet.game_vars["contest:score"] = "%d:%d" % [wins[pet], best_other_wins]
		pet.game_vars["contest:rounds"] = str(rounds)
	await _wait(initiator, 0.8)
	if _cancelled(everyone, generations):
		return {}
	for pet: Node in everyone:
		GameChat.react(pet, "dice_contest", outcomes[pet])
	return {"outcomes": outcomes, "totals": totals, "wins": wins, "rounds": rounds}

static func _cancelled(pets: Array, generations: Dictionary) -> bool:
	for pet: Node in pets:
		if not is_instance_valid(pet) or pet.action_generation != generations[pet]:
			return true
	return false
