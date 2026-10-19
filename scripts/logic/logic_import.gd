class_name LogicImport
extends RefCounted
## 匯入積木檔(網頁端積木編輯器導出的 *.logic.json)的共用流程:桌寵管理「記憶與檔案」分頁的「匯入積木檔…」
## 與系統匣的「導入積木檔…」都走這裡。
## 2026-10-19 使用者要求加「完全取代」:匯入本來只換掉使用者自己那層,性格(對話池/反應事件)與交互行為規則
## (遇見台詞/道具台詞)這兩層照樣會產生事件——積木檔裡刪掉的這類事件會回來、改成新積木的會跟原本的一起跑,
## 想「匯出 → 整份重寫 → 匯入」頂掉全部事件的使用者會很困惑。
## 完全取代 = 對話池、反應事件改成「不套用」,遇見台詞清空、道具規則的台詞清空(道具規則的動作保留),
## 之後這隻桌寵只跑積木檔裡的事件。匯出積木檔(LogicInterpreter.to_data)本來就把這兩層一起匯出,
## 所以「匯出 → 重寫 → 完全取代匯入」不會弄丟東西。


## 現在由性格/交互行為規則產生的事件:{chat, reactions(各為 {name, count}), encounters, props, total}。
static func layer_counts(pet: Node) -> Dictionary:
	var result := {"chat": {"name": "", "count": 0}, "reactions": {"name": "", "count": 0}, "encounters": 0, "props": 0, "total": 0}
	for section: String in ["chat", "reactions"]:
		var id := PersonalityApplier.choice_of(pet, section)
		var personality := PersonalityApplier.personality_of(pet, id)
		if personality.is_empty():
			continue
		var hats: Array = PersonalityFile.chat_hats(personality) if section == "chat" else PersonalityFile.reaction_hats(personality)
		result[section] = {"name": str(personality.get("name", id)), "count": hats.size()}
	for block: Dictionary in InteractionRules.compile(pet.interaction_rules):
		var id := str(block.get("id", ""))
		if id.begins_with("rule_c"):
			result["encounters"] += 1
		elif id.begins_with("rule_p"):
			result["props"] += 1
	result["total"] = int(result["chat"]["count"]) + int(result["reactions"]["count"]) + int(result["encounters"]) + int(result["props"])
	return result


## 讀檔、補回性格/規則層、去重、存一份自動載入用的備份。full_replace 見檔頭。
## persist:完全取代時順便把桌寵設定存檔(系統匣那條路沒有「儲存」鈕可按;桌寵管理裡交給視窗的「儲存」)。
## 回傳 {ok, skipped(與性格內容重複而略過的事件數), replaced(有沒有真的做完全取代)}。
static func import_file(pet: Node, path: String, full_replace := false, persist := false) -> Dictionary:
	if not pet.logic.load_file(path):
		return {"ok": false, "skipped": 0, "replaced": false}
	if full_replace:
		_drop_layers(pet)
	# logic.load_file() 內部的 clear() 連性格對話池/反應層、交互行為規則層都會一起清空(見 LogicInterpreter.clear()
	# 的說明),這兩層不是從匯入的檔案來的,得在這裡重新補回去,不然匯入後這隻桌寵會暫時「失憶」成沒性格、沒交互行為規則。
	PersonalityApplier.rebuild_layer(pet)
	pet.set_interaction_rules(pet.interaction_rules)
	# 雙重重複第 1 類(見 LogicInterpreter.dedupe_top_blocks()):匯出再原封不動匯入的內容,跟剛補回來的
	# 性格/規則層完全相同的部分直接拿掉,不然會雙重觸發。要等上面兩行補完性格/規則層才能比對,順序不能換。
	var skipped: int = pet.logic.dedupe_top_blocks()
	PetRoster.store_logic(pet.recognition_tag, path, CharacterFiles.folder_of(pet))
	if skipped > 0:
		# dedupe 動的是記憶體內容,PetRoster.store_logic() 剛存的是原始檔案(未去重),覆蓋成去重後的
		# 版本,下次開機重新套用才不會又長出同一批重複。
		pet.logic.save_user_only_file(PetRoster.logic_path(pet.recognition_tag, CharacterFiles.folder_of(pet)))
	if full_replace and persist:
		PetProfile.save_pet(pet)
	return {"ok": true, "skipped": skipped, "replaced": full_replace}


static func _drop_layers(pet: Node) -> void:
	PersonalityApplier.apply(pet, {"chat": "", "reactions": ""}, {"ignore_own_chat": false, "ignore_own_reactions": false})
	var rules: Dictionary = (pet.interaction_rules as Dictionary).duplicate(true)
	rules["characters"] = []
	for rule: Dictionary in rules.get("props", []):
		rule["line"] = ""   # 只有台詞的規則 clean() 會整條拿掉;有動作的保留動作
	pet.set_interaction_rules(rules)


## 選好檔案後呼叫:這隻桌寵有性格/規則層事件時先問要「一起保留」還是「完全取代」,沒有就直接 on_chosen.call(false)。
## on_chosen(full_replace: bool);按取消不呼叫。
static func ask_mode(parent: Node, top_window: Window, pet: Node, on_chosen: Callable) -> void:
	var counts := layer_counts(pet)
	if int(counts["total"]) == 0 or DisplayServer.get_name() == "headless":
		on_chosen.call(false)
		return
	var lines: Array[String] = []
	if int(counts["chat"]["count"]) > 0:
		lines.append(TranslationServer.translate("・性格對話池「%s」:%d 個閒聊事件") % [counts["chat"]["name"], counts["chat"]["count"]])
	if int(counts["reactions"]["count"]) > 0:
		lines.append(TranslationServer.translate("・性格反應事件「%s」:%d 個反應事件") % [counts["reactions"]["name"], counts["reactions"]["count"]])
	if int(counts["encounters"]) > 0:
		lines.append(TranslationServer.translate("・交互行為的遇見台詞:%d 個事件") % int(counts["encounters"]))
	if int(counts["props"]) > 0:
		lines.append(TranslationServer.translate("・交互行為的道具台詞:%d 個事件") % int(counts["props"]))
	var dialog := ConfirmationDialog.new()
	dialog.title = TranslationServer.translate("匯入積木檔")
	# 主視窗底下的確認視窗不能是獨佔式(見 DesktopShell._on_remove_pet_requested 的說明)。
	dialog.exclusive = false
	dialog.transient = false
	dialog.theme = ManagerUi.make_theme()
	dialog.dialog_autowrap = true
	dialog.dialog_text = TranslationServer.translate("「%s」除了積木檔,還有這些事件來自性格與交互行為規則:\n%s\n\n・一起保留:只換掉積木檔那層,這些事件照樣生效;積木檔裡刪掉的這類事件還是會出現。\n・完全取代:對話池、反應事件改成「不套用」,遇見台詞與道具台詞清空(道具規則的動作保留),之後只跑積木檔裡的事件。從這隻桌寵匯出再整份重寫的積木檔選這個。") % [pet.get_label(), "\n".join(lines)]
	dialog.ok_button_text = TranslationServer.translate("一起保留")
	dialog.add_button(TranslationServer.translate("完全取代"), true, "replace")
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		on_chosen.call(false))
	dialog.custom_action.connect(func(action: StringName) -> void:
		dialog.hide()
		dialog.queue_free()
		if action == &"replace":
			on_chosen.call(true))
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	FloatingWindow.popup_child_dialog(parent, top_window, dialog, Vector2i(520, 320))
