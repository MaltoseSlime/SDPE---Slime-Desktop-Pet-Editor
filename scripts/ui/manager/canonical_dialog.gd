class_name CanonicalDialog
extends ConfirmationDialog
## 關閉遊戲前的「本體指定」提醒:同一個角色在場有好幾個複製品,而且各自的狀態(局部數值、事件 Flag、啟用中的狀態鏡)已經不一樣時,
## 問使用者要讓哪一隻當本體(下次啟動從它的狀態開始),預設依政策選「最早」或「最晚」生成的那隻,政策可在這裡改並記住。
## 三個出口:「指定為本體並離開」(resolved,choice=選定者)、「不指定直接離開」(resolved,choice=null,這組不存)、「取消」(canceled,不離開)。

signal resolved(choice: Node, policy: String)

var _pets: Array = []
var _pet_option: OptionButton
var _policy_option: OptionButton


func setup(key: String, pets: Array, policy: String) -> void:
	_pets = pets
	title = "同角色有複製品尚未指定本體"
	# 主視窗底下的確認視窗不能是獨佔式:獨佔視窗開著時,Windows 會把主視窗的穿透形狀整個丟掉(整個螢幕都點不到後面的程式)。
	# 不設 always_on_top:這種視窗會被 Godot 設成主視窗(一直置頂)的 transient 子視窗,跟置頂在 Windows 原生
	# 視窗上互斥(#117698,4.7.2 尚未修正),硬設會把視窗卡死;身為 owned window,Windows 本來就會自動疊在
	# 主視窗上面,不需要自己也置頂(見 desktop_shell.gd 的 _check_defaults_update() 有更完整的說明)。
	exclusive = false
	transient = false
	theme = ManagerUi.make_theme()
	ok_button_text = "指定為本體並離開"
	cancel_button_text = "取消(不離開)"
	add_button("不指定直接離開", true, "skip")
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = tr("「%s」在場有 %d 個複製品,各自的數值/旗標/狀態鏡已經不一樣。\n要讓哪一個當本體(下次啟動從它的狀態開始)?") % [key, pets.size()]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420.0
	box.add_child(label)
	_pet_option = OptionButton.new()
	for pet: Node in pets:
		_pet_option.add_item(tr("%s(第 %d 個生成)  %s") % [pet.get_label(), pet.spawn_serial, _summary(pet)])
	box.add_child(_pet_option)
	_policy_option = OptionButton.new()
	_policy_option.add_item(tr("預設:以最早生成的當本體"))
	_policy_option.add_item(tr("預設:以最晚生成的當本體"))
	_policy_option.item_selected.connect(func(index: int) -> void: _pet_option.select(pets.size() - 1 if index == 1 else 0))
	box.add_child(_policy_option)
	add_child(box)
	_policy_option.select(1 if policy == "latest" else 0)
	_pet_option.select(pets.size() - 1 if policy == "latest" else 0)
	confirmed.connect(func() -> void: resolved.emit(_pets[_pet_option.selected], _policy()))
	custom_action.connect(func(action: StringName) -> void:
		if action == &"skip":
			resolved.emit(null, _policy()))


func _policy() -> String:
	return "latest" if _policy_option.selected == 1 else "earliest"


## 每隻的狀態摘要(前幾個數值與 Flag),讓使用者看得出差在哪。
func _summary(pet: Node) -> String:
	var parts: PackedStringArray = []
	for key in pet.local_values:
		parts.append("%s=%s" % [key, str(snappedf(float(pet.local_values[key]), 0.1))])
		if parts.size() >= 3:
			break
	for key in pet.flags:
		if parts.size() >= 5:
			break
		parts.append("%s=%s" % [key, pet.flags[key]])
	return "[" + ", ".join(parts) + "]"
