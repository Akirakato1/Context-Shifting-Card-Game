extends Button

const MatchButtonArt := preload("res://src/view/match/match_button_art.gd")


func _ready() -> void:
	MatchButtonArt.skin(self, MatchButtonArt.PILL)
	var close_button: Button = $CreditsDialog.get_ok_button()
	close_button.custom_minimum_size = Vector2(112, 40)
	MatchButtonArt.skin(close_button, MatchButtonArt.PILL)


func _on_source_clicked(url: String) -> void:
	if url.begins_with("https://"):
		OS.shell_open(url)
