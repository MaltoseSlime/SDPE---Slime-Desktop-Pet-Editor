extends RefCounted
## Mal 史萊姆素材的轉接層(使用者提供的外部素材,位於 res://assets/sample_pets/Mal/)。
##
## Mal 的檔名規則是「動作_方向_幀」(idle_r_0、walk_l_2),左右分成兩組檔案;本專案的規則是
## 「動作名稱_編號」加上視覺根節點 scale.x 翻轉,兩邊不相容,而 Mal 的命名是給其他桌寵專案用的。
## 所以 Mal 的檔名不動,對應關係全部集中在這個檔案:只取朝右的 _r_ 幀,左右由 Pet 翻轉,
## Mal 的命名不會滲進 Pet.play_action() 等核心介面。

const SPRITE_DIR := "res://assets/sample_pets/Mal/"
const FRAME_COUNT := 4
const FPS := 6.0

## 本專案動作名稱 → Mal 檔名裡的動作名稱。
## Mal 沒有的動作(sit、lay、gather、enter、leave)刻意不列,讓 play_action() 的 fallback 規則接手。
const ACTION_MAP := {
	&"idle": "idle",
	&"walk": "walk",
	&"run": "walk",
	&"rise": "jump",
	&"fall": "fall",
	&"drag": "drag",
	&"sleep": "sleep",
	&"interact": "pet",
	# dance:Mal 沒有專用的跳舞素材,先借 jumpstart(起跳預備動作,身體上下彈)當佔位,方便測試自主跳舞。
	&"dance": "jumpstart",
}


static func build_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for action: StringName in ACTION_MAP:
		var animation := StringName("%s_0" % action)
		frames.add_animation(animation)
		frames.set_animation_speed(animation, FPS)
		frames.set_animation_loop(animation, true)
		for i in FRAME_COUNT:
			var texture := load("%s%s_r_%d.png" % [SPRITE_DIR, ACTION_MAP[action], i]) as Texture2D
			frames.add_frame(animation, texture)
	# 眨眼差分:Mal 沒有專用的閉眼圖,拿 pet(被摸摸時瞇眼的樣子)的第一幀當 idle 的 _bl。
	frames.add_animation(&"idle_0_bl")
	frames.set_animation_speed(&"idle_0_bl", 6.0)
	frames.set_animation_loop(&"idle_0_bl", false)
	frames.add_frame(&"idle_0_bl", load("%spet_r_0.png" % SPRITE_DIR) as Texture2D)
	return frames
