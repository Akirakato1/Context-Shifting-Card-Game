extends "res://tests/test_case.gd"


func test_native_webrtc_peer_initializes() -> void:
	var peer := WebRTCPeerConnection.new()
	var result := peer.initialize({"iceServers": []})
	assert_eq(result, OK, "the native WebRTC implementation should be registered")
	peer.close()
