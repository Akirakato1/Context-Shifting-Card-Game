extends "res://tests/test_case.gd"

const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDeckEditor = preload("res://src/view/lobby/ability_deck_editor.tscn")


func test_editor_emits_per_ability_counts_for_host_only() -> void:
	var editor := AbilityDeckEditor.instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(editor)
	await tree.process_frame
	var submitted: Array[Dictionary] = []
	editor.recipe_changed.connect(func(recipe: Dictionary): submitted.append(recipe))
	var catalog := AbilityCatalog.public_catalog({"context_exchange": 12})
	var open := editor.get_node("Open") as Button
	var dialog := editor.get_node("DeckDialog") as ConfirmationDialog
	assert_false(dialog.visible)
	editor.render(catalog, true)
	open.pressed.emit()
	var copies := dialog.find_child("context_exchange", true, false) as SpinBox
	assert_true(copies.editable)
	assert_eq(int(copies.value), 12)
	copies.value = 11
	assert_true(dialog.get_ok_button().disabled)
	dialog.confirmed.emit()
	assert_true(submitted.is_empty())
	copies.value = 13
	assert_false(dialog.get_ok_button().disabled)
	dialog.confirmed.emit()
	assert_eq(submitted[0].context_exchange, 13)
	assert_eq(submitted[0].context_convergence, 0)

	editor.render(catalog, false)
	copies = dialog.find_child("context_exchange", true, false) as SpinBox
	assert_false(copies.editable)
	assert_eq(int(copies.value), 12)
	dialog.confirmed.emit()
	assert_eq(submitted.size(), 1)
	editor.queue_free()
	await tree.process_frame
