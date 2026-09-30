class_name PropReaction
extends RefCounted
## 道具觸發後的反應(企劃書第五章):
## 1. 事件積木「當桌寵拾取/吃掉 [道具] 時」(有寫就執行);
## 2. 「免寫積木」的直接數值綁定、狀態切換綁定、解除所有負面狀態鏡(有勾就一律套用);
## 3. 可持有的道具:記成這隻桌寵目前持有的道具(同一時間一項,新的替換舊的);
## 4. 保底:沒有事件積木、也沒有任何綁定時,依「預設交互反應」——拾取 = 播放 gather 動作,無 = 單純消失。
## 每一次觸發都算一次互動(pet.prop_interactions)。


## 桌寵拾取/吃掉道具 def。回傳 {hat: 有沒有事件積木接手, bindings: 套用了幾項綁定, default: 有沒有播保底動作}。
static func collect(def: PropDef, pet: Node) -> Dictionary:
	return _trigger(def, pet, "collected")


## 桌寵被道具摩擦(貼身摩擦模式)。回傳同 collect;保底反應(預設交互反應 = 拾取)是播 interact 動作。
static func rub(def: PropDef, pet: Node) -> Dictionary:
	return _trigger(def, pet, "rubbed")


static func _trigger(def: PropDef, pet: Node, kind: String) -> Dictionary:
	var applied := _apply_bindings(def, pet)
	var handled_by_hat := false
	if pet.logic != null:
		handled_by_hat = pet.logic.run_prop_hats(kind, def.display_name)
	if kind == "collected":
		# 廣播給場上所有桌寵(不只自己):event_prop_used 讓「指定對象使用了指定物品」這種積木也收得到,
		# 跟 event_prop_collected(只有自己看得到自己拾取)是兩件獨立的事,兩者都會跑。
		var shell_state := pet.get_node_or_null("/root/DesktopShellState")
		if shell_state != null:
			shell_state.prop_used.emit(pet, def.display_name)
	if def.effect != "" and pet.effects != null:
		pet.effects.play(def.effect)
	if def.holdable and kind == "collected":
		pet.held_prop = def.display_name
	# 交互行為頁籤設的反應:動作(只做一次,或持續到道具用完 / 離開判定)與對話(已編進事件積木,上面 run_prop_hats 會跑);有設就不再播保底動作。
	var rule := InteractionRules.prop_rule(pet.interaction_rules, def.display_name, "collected" if kind == "collected" else "rubbed")
	if not rule.is_empty():
		handled_by_hat = true
		if str(rule["action"]) != "":
			var seconds := PropItem.consume_seconds(def.use_anim, def.use_shakes) if kind == "collected" and def.toss else 0.0
			pet.begin_prop_action(StringName(str(rule["action"])), bool(rule["persist"]), seconds)
	var played_default := false
	if not handled_by_hat and applied == 0 and def.default_reaction == "pickup":
		pet.play_action(&"gather" if kind == "collected" else &"interact")
		played_default = true
	pet.prop_interactions += 1
	if kind == "collected":
		SaveScheduler.request("gather")   # 關鍵事件即時存檔
	_mood_from_preference(def, pet, kind)
	pet.hold_still_for(2.0 if kind == "rubbed" else 1.5)   # 洗澡、吃東西的時候不要走來走去
	return {"hat": handled_by_hat, "bindings": applied, "default": played_default}


## 和喜歡的道具互動心情變好、和不喜歡的道具互動心情變差(拿到 / 吃掉的幅度大,被摩擦每次只有一點點);互動也會讓「生氣、悲傷、疲憊」這類狀態更快消退(見 LensBehavior.hasten)。
static func _mood_from_preference(def: PropDef, pet: Node, kind: String) -> void:
	if pet.vitality == null:
		return
	var preference: String = pet.prop_preference(def)
	var big := kind == "collected"
	if preference == "like":
		pet.vitality.change_mood(4.0 if big else 0.6)
		pet.hasten_lenses("liked_prop")
	elif preference == "dislike":
		pet.vitality.change_mood(-3.0 if big else -0.5)
	pet.hasten_lenses("prop")


## 道具靠近(成為候選)時的反應:交互行為頁籤設的動作(對話由事件積木處理)。
static func candidate(def: PropDef, pet: Node) -> void:
	var rule := InteractionRules.prop_rule(pet.interaction_rules, def.display_name, "candidate")
	if not rule.is_empty() and str(rule["action"]) != "":
		pet.begin_prop_action(StringName(str(rule["action"])), bool(rule["persist"]))


## 數值綁定 + 狀態切換綁定 + 解除負面;回傳套用了幾項。
static func _apply_bindings(def: PropDef, pet: Node) -> int:
	var applied := 0
	for binding in def.value_bindings:
		ValueGateway.modify_value(pet, str(binding["key"]), float(binding["delta"]), str(binding["scope"]))
		applied += 1
	for binding in def.lens_bindings:
		if str(binding["op"]) == "enable":
			pet.enable_lens(str(binding["lens"]))
		else:
			pet.disable_lens(str(binding["lens"]))
		applied += 1
	if def.disable_negative:
		pet.disable_negative_lenses()
		applied += 1
	if def.disable_positive:
		pet.disable_positive_lenses()
		applied += 1
	if def.restore_energy > 0.0 and pet.vitality != null:
		pet.vitality.restore_energy(def.restore_energy)
		applied += 1
	return applied
