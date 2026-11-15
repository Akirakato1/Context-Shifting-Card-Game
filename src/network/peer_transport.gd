class_name PeerTransport
extends RefCounted

signal peer_connected(peer_id: String)
signal peer_disconnected(peer_id: String, reason: String)
signal message_received(peer_id: String, bytes: PackedByteArray)
signal lobby_created(code: String)
signal join_status(status: String, details: Dictionary)
signal transport_failed(reason: String)


func host_room(_signaling_url: String) -> Error:
	return ERR_UNAVAILABLE


func join_room(_signaling_url: String, _code: String, _role: String) -> Error:
	return ERR_UNAVAILABLE


func send(_peer_id: String, _bytes: PackedByteArray) -> Error:
	return ERR_UNAVAILABLE


func close_peer(_peer_id: String) -> void:
	pass


func disconnect_peer(peer_id: String, _reason: String) -> void:
	close_peer(peer_id)


func poll() -> void:
	pass
