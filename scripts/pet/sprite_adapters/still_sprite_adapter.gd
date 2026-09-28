extends RefCounted
## 半身立繪 Still_A / Still_B 的轉接層(使用者提供的素材,位於 res://assets/still/still_A、still_B,各 10 張 686×944,
## 檔名是「時間軸10_0001」「時間軸9_0001」這種匯出流水號)。這類角色固定不動、貼在行動區底部,適合當雙人對話的 A/B 角色。
## 素材是「每個動作一幀」設計的表情差分(不是連續動畫):第 N 張 = 自訂動作 pose_NN(pose_01 ~ pose_10),
## 第 1 張同時是待機 idle。要換表情就在積木裡播放對應的 pose_NN(對話的「動作綁定」也能選,每句話一個表情)。
## 其他系統動作(walk、sleep…)缺圖時依規格一律降級為 idle_0;命名規則不滲進核心介面。

const SETS := {
	"A": {"dir": "res://assets/still/still_A/", "prefix": "時間軸10_"},
	"B": {"dir": "res://assets/still/still_B/", "prefix": "時間軸9_"},
}
const FRAME_COUNT := 10
## 單幀動畫的播放速度(只影響「至少佔用多久」的計算,單幀不會有畫面變化)。
const FPS := 5.0
## 素材是 686×944 的大圖,預設縮到約 1/3(約 230×315 像素),使用者可在管理視窗調整角色尺寸。
const DEFAULT_SCALE := 0.33


## 選用的浮動差分與配件設定:立繪資料夾裡的 overlays.json(眨眼、說話嘴型、手勢、身上裝飾,格式見 docs/素材包格式.md)。
## 沒有這個檔、檔案太大或不是 JSON 物件就回空字典。
static func load_config(which: String) -> Dictionary:
	var path: String = "%soverlays.json" % SETS[which]["dir"]
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 200_000:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func pose_name(index: int) -> String:
	return "pose_%02d" % index


static func build_sprite_frames(which: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var info: Dictionary = SETS[which]
	for i in range(1, FRAME_COUNT + 1):
		var path := "%s%s%04d.png" % [info["dir"], info["prefix"], i]
		var texture := load(path) as Texture2D
		if texture == null:
			continue
		var names: Array[String] = ["%s_0" % pose_name(i)]
		if i == 1:
			names.append("idle_0")
		for animation_name in names:
			frames.add_animation(StringName(animation_name))
			frames.set_animation_speed(StringName(animation_name), FPS)
			frames.set_animation_loop(StringName(animation_name), true)
			frames.add_frame(StringName(animation_name), texture)
	return frames
