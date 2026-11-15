class_name FakePeerTransport
extends "res://src/network/peer_transport.gd"

var sent: Array[Dictionary] = []
var closed: Array[Dictionary] = []
var send_error: Error = OK
var poll_count := 0


func send(peer_id: String, bytes: PackedByteArray) -> Error:
	if send_error != OK:
		return send_error
	sent.append({"peer_id": peer_id, "bytes": bytes.duplicate()})
	return OK


func close_peer(peer_id: String) -> void:
	close_with_reason(peer_id, "closed")


func disconnect_peer(peer_id: String, reason: String) -> void:
	close_with_reason(peer_id, reason)


func close_with_reason(peer_id: String, reason: String) -> void:
	closed.append({"peer_id": peer_id, "reason": reason})
	peer_disconnected.emit(peer_id, reason)


func poll() -> void:
	poll_count += 1


func inject_message(peer_id: String, bytes: PackedByteArray) -> void:
	message_received.emit(peer_id, bytes)


func clear_sent() -> void:
	sent.clear()
