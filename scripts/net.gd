extends Node
## Network layer (autoload "Net"). Every RPC lives here so that the server and
## the clients share the same node path (/root/Net).
##
## Client -> server RPCs only carry *intent* (select, move, face, ability,
## rematch). The server validates everything and answers with per-player
## snapshots that only contain what that player is allowed to see.

const Cfg = preload("res://scripts/config.gd")

signal welcomed(slot: int)
signal snapshot_received(data: Dictionary)
signal rejected(reason: String)
signal connection_ok
signal connection_lost(reason: String)

var server = null  # ServerGame node when running as dedicated server
var peer: WebSocketMultiplayerPeer


func _ready() -> void:
	multiplayer.connected_to_server.connect(func(): connection_ok.emit())
	multiplayer.connection_failed.connect(func(): connection_lost.emit("Could not connect to server"))
	multiplayer.server_disconnected.connect(func(): connection_lost.emit("Disconnected from server"))


# --------------------------------------------------------------------------
# Setup
# --------------------------------------------------------------------------

func host(port: int, cert_path := "", key_path := "") -> Error:
	peer = WebSocketMultiplayerPeer.new()
	var tls: TLSOptions = null
	if cert_path != "" and key_path != "":
		var cert := X509Certificate.new()
		var key := CryptoKey.new()
		if cert.load(cert_path) != OK or key.load(key_path) != OK:
			push_error("Failed to load TLS certificate/key")
			return ERR_CANT_OPEN
		tls = TLSOptions.server(key, cert)
	var err := peer.create_server(port, "*", tls)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func join(url: String) -> Error:
	leave()
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	peer = null


func is_online() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# --------------------------------------------------------------------------
# Client -> Server
# --------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func c_hello(player_name: String) -> void:
	if server:
		server.on_hello(multiplayer.get_remote_sender_id(), player_name)


@rpc("any_peer", "call_remote", "reliable")
func c_select(idx: int) -> void:
	if server:
		server.on_select(multiplayer.get_remote_sender_id(), idx)


@rpc("any_peer", "call_remote", "reliable")
func c_move(target: Vector2, keep_facing: bool) -> void:
	if server:
		server.on_move(multiplayer.get_remote_sender_id(), target, keep_facing)


@rpc("any_peer", "call_remote", "reliable")
func c_face(target: Vector2) -> void:
	if server:
		server.on_face(multiplayer.get_remote_sender_id(), target)


@rpc("any_peer", "call_remote", "reliable")
func c_ability(ability: int, target: Vector2, via_voice: bool) -> void:
	if server:
		server.on_ability(multiplayer.get_remote_sender_id(), ability, target, via_voice)


## Unit-addressed orders (voice squad commands) that don't change the selection.
## queue = append to the current path instead of replacing it.
@rpc("any_peer", "call_remote", "reliable")
func c_unit_move(idx: int, target: Vector2, queue: bool) -> void:
	if server:
		server.on_unit_move(multiplayer.get_remote_sender_id(), idx, target, queue)


@rpc("any_peer", "call_remote", "reliable")
func c_unit_face(idx: int, target: Vector2) -> void:
	if server:
		server.on_unit_face(multiplayer.get_remote_sender_id(), idx, target)


@rpc("any_peer", "call_remote", "reliable")
func c_unit_stop(idx: int) -> void:
	if server:
		server.on_unit_stop(multiplayer.get_remote_sender_id(), idx)


@rpc("any_peer", "call_remote", "reliable")
func c_rematch() -> void:
	if server:
		server.on_rematch(multiplayer.get_remote_sender_id())


# --------------------------------------------------------------------------
# Server -> Client
# --------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func s_welcome(slot: int) -> void:
	welcomed.emit(slot)


@rpc("authority", "call_remote", "reliable")
func s_snapshot(data: Dictionary) -> void:
	snapshot_received.emit(data)


@rpc("authority", "call_remote", "reliable")
func s_reject(reason: String) -> void:
	rejected.emit(reason)
