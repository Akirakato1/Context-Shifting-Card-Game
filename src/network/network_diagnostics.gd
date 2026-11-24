extends RefCounted

# Match stable protocol codes only. Signaling and peers can send arbitrary error text.
const PUBLIC_REASONS := [
	"active_capacity_reached", "backpressure", "connection_closed", "connection_lost",
	"direct_connection_failed", "heartbeat_timeout", "host_closed", "host_lost",
	"invalid_reconnect_token", "invalid_signaling_payload", "join_rejected",
	"not_active_player", "player_not_disconnected", "reconnect_grace_expired",
	"reconnect_send_failed", "reconnect_unavailable", "relay_unavailable", "room_closed",
	"room_not_found", "signaling_closed", "signaling_send_failed", "signaling_timeout",
	"spectator_capacity_reached", "transport_send_failed",
]


static func log_event(role: String, event: String, reason: String = "") -> void:
	var detail := ""
	if not reason.is_empty():
		var code := reason.trim_prefix("reconnect_rejected:")
		detail = " reason=" + (code if code in PUBLIC_REASONS else "other")
	print("[network] %sZ %s %s%s" % [
		Time.get_datetime_string_from_system(true), role, event, detail,
	])
