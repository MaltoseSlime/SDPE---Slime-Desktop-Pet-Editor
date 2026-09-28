class_name InputTicket
extends RefCounted
## 一次「向使用者要一段文字」的完成憑證:輸入視窗在使用者按確定/略過/關閉、或被打斷時呼叫 finish()。只會生效一次。
## accepted = false 表示使用者略過(text 是空字串),呼叫端應保留原本的值。

signal finished(text: String, accepted: bool)

var closed := false
## 使用者已經按了「回答」、輸入視窗正開著。這段期間桌寵被點擊/拖曳等互動打斷不會取消輸入(避免使用者打到一半的字被吃掉)。
var typing := false


func finish(text: String, accepted: bool) -> void:
	if closed:
		return
	closed = true
	finished.emit(text, accepted)
