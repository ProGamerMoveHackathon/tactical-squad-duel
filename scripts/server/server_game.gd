extends Node
## Dedicated authoritative game server.
## Simulates movement, visibility, shooting, damage and abilities, and sends
## each player a snapshot containing ONLY what their squad can currently see.

const Cfg = preload("res://scripts/config.gd")
const MapData = preload("res://scripts/map_data.gd")

const FLAG_MOVING := 1
const FLAG_SUPPRESS := 2
const FLAG_RUSH := 4
const FLAG_ALIVE := 8


class Soldier:
	var team := 0
	var idx := 0
	var weapon := 0
	var pos := Vector2.ZERO
	var facing := 0.0
	var watch_angle := 0.0
	var facing_lock := false
	var hp: float = Cfg.SOLDIER_HP
	var mp: float = Cfg.SOLDIER_MP
	var health_regen_wait := 0.0
	var alive := true
	var path := PackedVector2Array()
	var moving := false
	var last_moved := -100.0
	var fire_cd := 0.0
	var target := -1
	var acquire := 0.0
	var suppress_t := 0.0
	var rush_t := 0.0


var map := MapData.new()
var peers := [0, 0]          # peer id per slot (0 = empty)
var names := ["", ""]
var squads := [[], []]       # Array[Soldier] per team
var selected := [0, 0]
var cooldowns := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
var fogs := []               # {pos, radius, t}
var scans := []              # {team, origin, t}
var events := [[], []]       # per team, flushed with every snapshot
var vis_table := [[false, false, false, false], [false, false, false, false]]  # vis_table[team][enemy idx]
var rematch_votes := [false, false]
var loadouts := [Cfg.DEFAULT_LOADOUTS.duplicate(), Cfg.DEFAULT_LOADOUTS.duplicate()]
var loadout_ready := [false, false]
var state := Cfg.State.WAITING
var deployment := 0.0
var countdown := 0.0
var winner := -1
var time := 0.0
var rng := RandomNumberGenerator.new()


func start(port: int, cert := "", key := "") -> void:
	Net.server = self
	var err := Net.host(port, cert, key)
	if err != OK:
		push_error("Server failed to listen on port %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	rng.randomize()
	_reset_squads()
	print("[server] Tactical Squad Duel server listening on port %d%s" % [port, " (TLS)" if cert != "" else ""])


# --------------------------------------------------------------------------
# Connections
# --------------------------------------------------------------------------

func _slot_of(peer_id: int) -> int:
	return peers.find(peer_id)


func _kick(id: int) -> void:
	if Net.peer:
		Net.peer.disconnect_peer(id)


func _on_peer_connected(id: int) -> void:
	var slot := peers.find(0)
	if slot == -1:
		print("[server] peer %d rejected: server full" % id)
		Net.s_reject.rpc_id(id, "Server is full (a match is already running).")
		get_tree().create_timer(0.5).timeout.connect(_kick.bind(id))
		return
	peers[slot] = id
	names[slot] = "Player %d" % (slot + 1)
	print("[server] peer %d joined as slot %d" % [id, slot])
	Net.s_welcome.rpc_id(id, slot)
	if state == Cfg.State.WAITING:
		_begin_loadout()


func _on_peer_disconnected(id: int) -> void:
	var slot := _slot_of(id)
	if slot == -1:
		return
	print("[server] slot %d (peer %d) left" % [slot, id])
	peers[slot] = 0
	names[slot] = ""
	state = Cfg.State.WAITING
	loadout_ready = [false, false]
	_reset_squads()
	var other := 1 - slot
	if peers[other] != 0:
		events[other].append(["msg", "Opponent left. Waiting for a new opponent..."])


func on_hello(id: int, player_name: String) -> void:
	var slot := _slot_of(id)
	if slot == -1:
		return
	player_name = player_name.strip_edges().left(16)
	if player_name == "":
		player_name = "Player %d" % (slot + 1)
	names[slot] = player_name


# --------------------------------------------------------------------------
# Match flow
# --------------------------------------------------------------------------

func _begin_loadout() -> void:
	_reset_squads()
	loadout_ready = [false, false]
	state = Cfg.State.LOADOUT
	for t in 2:
		if peers[t] != 0:
			events[t].append(["msg", "Choose three abilities for every squad member."])


func _ability_count(mask: int) -> int:
	var count := 0
	for ability in 4:
		if mask & (1 << ability):
			count += 1
	return count


func on_loadout(id: int, ability_masks: Array) -> void:
	var slot := _slot_of(id)
	if slot == -1 or state != Cfg.State.LOADOUT or ability_masks.size() != Cfg.SQUAD_SIZE:
		return
	var validated := []
	for raw_mask in ability_masks:
		var mask := int(raw_mask)
		if mask < 0 or mask > 15 or _ability_count(mask) != 3:
			events[slot].append(["msg", "Every character needs exactly three abilities."])
			return
		validated.append(mask)
	loadouts[slot] = validated
	loadout_ready[slot] = true
	events[slot].append(["msg", "Loadout locked in."])
	if peers[0] != 0 and peers[1] != 0 and loadout_ready[0] and loadout_ready[1]:
		_start_match()

func _reset_squads() -> void:
	for team in 2:
		squads[team] = []
		for i in Cfg.SQUAD_SIZE:
			var s := Soldier.new()
			s.team = team
			s.idx = i
			s.weapon = Cfg.SQUAD_WEAPONS[i]
			s.pos = map.spawn_position(team, i)
			s.facing = map.spawn_facing(team)
			s.watch_angle = s.facing
			squads[team].append(s)
		cooldowns[team] = [0.0, 0.0, 0.0, 0.0]
		selected[team] = 0
	fogs.clear()
	scans.clear()
	vis_table = [[false, false, false, false], [false, false, false, false]]
	rematch_votes = [false, false]
	winner = -1


func _start_match() -> void:
	_reset_squads()
	for team in 2:
		for s: Soldier in squads[team]:
			var destination := map.spawn_position(team, s.idx)
			s.pos = map.entry_position(team, s.idx)
			s.path = map.find_path(s.pos, destination)
			s.facing = map.spawn_facing(team)
			s.watch_angle = s.facing
	state = Cfg.State.DEPLOYMENT
	deployment = Cfg.DEPLOYMENT_DURATION
	countdown = Cfg.COUNTDOWN
	for t in 2:
		events[t].append(["msg", "Squads entering the arena!"])


func on_rematch(id: int) -> void:
	var slot := _slot_of(id)
	if slot == -1 or state != Cfg.State.ENDED:
		return
	rematch_votes[slot] = true
	if rematch_votes[0] and rematch_votes[1]:
		_begin_loadout()
	else:
		events[1 - slot].append(["msg", "Opponent wants a rematch! Press Enter."])


# --------------------------------------------------------------------------
# Commands (validated)
# --------------------------------------------------------------------------

func _valid_vec(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y) and v.x > -100.0 and v.y > -100.0 \
		and v.x < Cfg.WORLD_SIZE.x + 100.0 and v.y < Cfg.WORLD_SIZE.y + 100.0


func _selected_soldier(slot: int) -> Soldier:
	var s: Soldier = squads[slot][selected[slot]]
	return s if s.alive else null


func on_select(id: int, idx: int) -> void:
	var slot := _slot_of(id)
	if slot == -1 or idx < 0 or idx >= Cfg.SQUAD_SIZE:
		return
	if not squads[slot][idx].alive:
		return
	if idx != selected[slot] and not Cfg.CONTINUE_MOVE_WHEN_DESELECTED:
		var prev: Soldier = squads[slot][selected[slot]]
		prev.path.clear()
	selected[slot] = idx


func on_move(id: int, target: Vector2, keep_facing: bool) -> void:
	var slot := _slot_of(id)
	if slot == -1 or state != Cfg.State.PLAYING or not _valid_vec(target):
		return
	var s := _selected_soldier(slot)
	if s == null:
		return
	s.path = map.find_path(s.pos, target)
	if not keep_facing:
		s.facing_lock = false


func on_face(id: int, target: Vector2) -> void:
	var slot := _slot_of(id)
	if slot == -1 or not _valid_vec(target):
		return
	if state != Cfg.State.PLAYING and state != Cfg.State.COUNTDOWN:
		return
	var s := _selected_soldier(slot)
	if s == null or target.distance_to(s.pos) < 2.0:
		return
	s.watch_angle = (target - s.pos).angle()
	s.facing_lock = true


func on_ability(id: int, ability: int, target: Vector2, via_voice: bool) -> void:
	var slot := _slot_of(id)
	if slot == -1 or not Cfg.ABILITIES.has(ability) or not _valid_vec(target):
		return
	var def: Dictionary = Cfg.ABILITIES[ability]
	if state != Cfg.State.PLAYING:
		events[slot].append(["deny", ability, "not now"])
		return
	if cooldowns[slot][ability] > 0.0:
		events[slot].append(["deny", ability, "cooling down %.1fs" % cooldowns[slot][ability]])
		return
	var casters: Array[Soldier] = []
	var equipped_alive := 0
	var mp_cost: float = def["mp_cost"]
	for s: Soldier in squads[slot]:
		if not s.alive or (int(loadouts[slot][s.idx]) & (1 << ability)) == 0:
			continue
		equipped_alive += 1
		if s.mp >= mp_cost:
			casters.append(s)
	if casters.is_empty():
		var reason := "no living character has this ability" if equipped_alive == 0 else "MP is recharging"
		events[slot].append(["deny", ability, reason])
		return
	match ability:
		Cfg.Ability.FOG:
			for s: Soldier in casters:
				var cast_target := _fog_landing(s, float(def["throw_distance"]))
				fogs.append({"pos": cast_target, "radius": def["radius"], "t": def["duration"]})
		Cfg.Ability.SCAN:
			for s: Soldier in casters:
				scans.append({"team": slot, "origin": s.pos, "t": def["duration"]})
				var count := 0
				for e in squads[1 - slot]:
					if _scan_reveals(e, s.pos):
						count += 1
				events[slot].append(["scan", s.pos, def["radius"], count])
		Cfg.Ability.SUPPRESS:
			for s: Soldier in casters:
				s.suppress_t = def["duration"]
		Cfg.Ability.RUSH:
			for s: Soldier in casters:
				s.rush_t = def["duration"]
	for s: Soldier in casters:
		s.mp = maxf(0.0, s.mp - mp_cost)
	cooldowns[slot][ability] = float(def["cooldown"])
	events[slot].append(["ability", ability, casters[0].idx, via_voice, casters.size()])
	print("[server] slot %d used %s with %d caster(s)%s" % [slot, def["name"], casters.size(), " (voice)" if via_voice else ""])


func _fog_landing(s: Soldier, throw_distance: float) -> Vector2:
	var direction := Vector2.from_angle(s.facing)
	var open_distance := map.raycast(s.pos, direction, throw_distance)
	# Keep the landing point out of the wall. When cover is directly in front,
	# this collapses to zero and the fog is dropped at the caster's feet.
	var wall_clearance := Cfg.SOLDIER_RADIUS + 2.0
	var landing_distance := throw_distance
	if open_distance < throw_distance - 0.01:
		landing_distance = maxf(0.0, open_distance - wall_clearance)
	return s.pos + direction * landing_distance


func _scan_reveals(e: Soldier, origin: Vector2) -> bool:
	return e.alive and e.pos.distance_to(origin) <= Cfg.ABILITIES[Cfg.Ability.SCAN]["radius"] \
		and time - e.last_moved <= Cfg.SCAN_MOVE_MEMORY


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if Net.server != self:
		return
	time += dt
	match state:
		Cfg.State.DEPLOYMENT:
			deployment -= dt
			for team in 2:
				for s: Soldier in squads[team]:
					_move_soldier(s, dt)
			if deployment <= 0.0:
				deployment = 0.0
				for team in 2:
					for s: Soldier in squads[team]:
						s.pos = map.spawn_position(team, s.idx)
						s.path.clear()
				state = Cfg.State.COUNTDOWN
				countdown = Cfg.COUNTDOWN
				for t in 2:
					events[t].append(["msg", "Get ready!"])
		Cfg.State.COUNTDOWN:
			countdown -= dt
			_update_facing_only(dt)
			if countdown <= 0.0:
				state = Cfg.State.PLAYING
				for t in 2:
					events[t].append(["msg", "FIGHT!"])
		Cfg.State.PLAYING:
			_simulate(dt)
	_compute_visibility()
	_broadcast()


func _fog_list() -> Array:
	var out := []
	for fog in fogs:
		out.append([fog["pos"], fog["radius"]])
	return out


func _update_facing_only(dt: float) -> void:
	for team in 2:
		for s in squads[team]:
			if s.facing_lock:
				s.facing = rotate_toward(s.facing, s.watch_angle, Cfg.TURN_SPEED * dt)


func _simulate(dt: float) -> void:
	for t in 2:
		for a in 4:
			cooldowns[t][a] = maxf(0.0, cooldowns[t][a] - dt)
	for i in range(fogs.size() - 1, -1, -1):
		fogs[i]["t"] -= dt
		if fogs[i]["t"] <= 0.0:
			fogs.remove_at(i)
	for i in range(scans.size() - 1, -1, -1):
		scans[i]["t"] -= dt
		if scans[i]["t"] <= 0.0:
			scans.remove_at(i)

	var all: Array = squads[0] + squads[1]
	for s: Soldier in all:
		if not s.alive:
			continue
		_advance_regeneration(s, dt)
		s.mp = minf(Cfg.SOLDIER_MP, s.mp + Cfg.SOLDIER_MP / Cfg.MP_RECOVERY_TIME * dt)
		s.suppress_t = maxf(0.0, s.suppress_t - dt)
		s.rush_t = maxf(0.0, s.rush_t - dt)
		_move_soldier(s, dt)

	# Soldier separation
	for i in all.size():
		var a: Soldier = all[i]
		if not a.alive:
			continue
		for j in range(i + 1, all.size()):
			var b: Soldier = all[j]
			if not b.alive:
				continue
			var diff := b.pos - a.pos
			var d := diff.length()
			var min_d := Cfg.SOLDIER_RADIUS * 2.0
			if d < min_d:
				var n := diff / d if d > 0.001 else Vector2.RIGHT
				var push := (min_d - d) * 0.5
				a.pos -= n * push
				b.pos += n * push
	for s: Soldier in all:
		if s.alive:
			s.pos = map.resolve_circle(s.pos, Cfg.SOLDIER_RADIUS)

	_compute_visibility()
	var fog_list := _fog_list()
	for s: Soldier in all:
		if s.alive:
			_shoot(s, dt, fog_list)
	_check_victory()


func _advance_regeneration(s: Soldier, dt: float) -> void:
	var regen_delta := maxf(0.0, dt - s.health_regen_wait)
	s.health_regen_wait = maxf(0.0, s.health_regen_wait - dt)
	if regen_delta > 0.0 and s.hp < Cfg.SOLDIER_HP:
		s.hp = minf(Cfg.SOLDIER_HP, s.hp + Cfg.HEALTH_REGEN_RATE * regen_delta)


func _move_soldier(s: Soldier, dt: float) -> void:
	var desired := s.watch_angle if s.facing_lock else s.facing
	s.moving = false
	if not s.path.is_empty():
		while s.path.size() >= 2 and map.clear_walk(s.pos, s.path[1], Cfg.SOLDIER_RADIUS):
			s.path.remove_at(0)
		var tgt: Vector2 = s.path[0]
		var diff := tgt - s.pos
		var dist := diff.length()
		var speed := Cfg.MOVE_SPEED
		if s.rush_t > 0.0:
			speed *= Cfg.ABILITIES[Cfg.Ability.RUSH]["speed_mult"]
		var step := speed * dt
		if dist > 0.01:
			var dir_angle := diff.angle()
			if not s.facing_lock:
				desired = dir_angle
				s.watch_angle = dir_angle
		if dist <= step:
			s.pos = tgt
			s.path.remove_at(0)
		else:
			s.pos += diff / dist * step
		s.moving = true
		s.last_moved = time
	s.facing = rotate_toward(s.facing, desired, Cfg.TURN_SPEED * dt)


func _compute_visibility() -> void:
	var fog_list := _fog_list()
	for team in 2:
		var enemies: Array = squads[1 - team]
		for e: Soldier in enemies:
			var seen := false
			if e.alive:
				for s: Soldier in squads[team]:
					if s.alive and map.can_see(s.pos, s.facing, e.pos, fog_list):
						seen = true
						break
			vis_table[team][e.idx] = seen


func _shoot(s: Soldier, dt: float, fog_list: Array) -> void:
	s.fire_cd = maxf(0.0, s.fire_cd - dt)
	var w: Dictionary = Cfg.WEAPONS[s.weapon]
	var suppressed := s.suppress_t > 0.0
	var cone := Cfg.weapon_cone(s.weapon, suppressed)
	var rng_max: float = w["range"]
	var best: Soldier = null
	var best_d := INF
	for e: Soldier in squads[1 - s.team]:
		if not e.alive:
			continue
		var diff := e.pos - s.pos
		var d := diff.length()
		if d > rng_max + Cfg.SOLDIER_RADIUS:
			continue
		if d > Cfg.SOLDIER_RADIUS * 2.0 and absf(angle_difference(s.facing, diff.angle())) > cone * 0.5:
			continue
		if not map.has_los(s.pos, e.pos, fog_list):
			continue
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		s.target = -1
		s.acquire = 0.0
		return
	if best.idx != s.target:
		s.target = best.idx
		s.acquire = Cfg.REACTION_TIME
	if s.acquire > 0.0:
		s.acquire -= dt
		return
	if s.fire_cd > 0.0:
		return

	var interval: float = w["interval"]
	var acc: float = w["accuracy"]
	if suppressed:
		interval /= Cfg.ABILITIES[Cfg.Ability.SUPPRESS]["rate_mult"]
		acc *= Cfg.ABILITIES[Cfg.Ability.SUPPRESS]["accuracy_mult"]
	if s.moving:
		acc *= 0.8
	acc *= 1.0 - 0.35 * clampf(best_d / rng_max, 0.0, 1.0)
	s.fire_cd = interval

	var dmg := 0
	var ends := []
	var dir := (best.pos - s.pos).normalized()
	var perp := Vector2(-dir.y, dir.x)
	for _p in int(w["pellets"]):
		if rng.randf() < acc:
			dmg += int(w["damage"])
			ends.append(best.pos + perp * rng.randf_range(-5.0, 5.0))
		else:
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			ends.append(best.pos + perp * side * rng.randf_range(14.0, 30.0) + dir * rng.randf_range(0.0, 60.0))
	var muzzle := s.pos + Vector2.from_angle(s.facing) * (Cfg.SOLDIER_RADIUS + 4.0)
	var shot_ev := ["shot", s.team, s.idx, muzzle, ends, dmg]
	events[s.team].append(shot_ev)
	if vis_table[best.team][s.idx]:
		events[best.team].append(shot_ev)
	else:
		# Hidden shooter: only reveal the rough direction of incoming fire.
		var ang := (s.pos - best.pos).angle() + rng.randf_range(-0.25, 0.25)
		events[best.team].append(["incoming", best.idx, ang, dmg])

	if dmg > 0:
		events[best.team].append(["card_hit", best.idx, dmg])
		var actual_damage := minf(float(dmg), best.hp)
		s.mp = minf(Cfg.SOLDIER_MP, s.mp + actual_damage * Cfg.MP_RESTORE_PER_DAMAGE)
		best.hp -= dmg
		best.health_regen_wait = Cfg.HEALTH_REGEN_DELAY
		if best.hp <= 0:
			best.hp = 0
			best.alive = false
			best.path.clear()
			for t in 2:
				events[t].append(["kill", best.team, best.idx, best.pos, s.team, s.idx])
			if selected[best.team] == best.idx:
				_auto_select(best.team)


func _auto_select(team: int) -> void:
	for i in Cfg.SQUAD_SIZE:
		var j: int = (selected[team] + 1 + i) % Cfg.SQUAD_SIZE
		if squads[team][j].alive:
			selected[team] = j
			return


func _check_victory() -> void:
	var alive := [0, 0]
	for t in 2:
		for s: Soldier in squads[t]:
			if s.alive:
				alive[t] += 1
	if alive[0] > 0 and alive[1] > 0:
		return
	state = Cfg.State.ENDED
	if alive[0] == 0 and alive[1] == 0:
		winner = -1
	else:
		winner = 0 if alive[0] > 0 else 1
	print("[server] match ended, winner: %d" % winner)


# --------------------------------------------------------------------------
# Snapshots
# --------------------------------------------------------------------------

func _flags(s: Soldier) -> int:
	var f := 0
	if s.moving: f |= FLAG_MOVING
	if s.suppress_t > 0.0: f |= FLAG_SUPPRESS
	if s.rush_t > 0.0: f |= FLAG_RUSH
	if s.alive: f |= FLAG_ALIVE
	return f


func _broadcast() -> void:
	var fog_data := []
	for fog in fogs:
		fog_data.append([fog["pos"], fog["radius"], fog["t"]])
	for team in 2:
		var pid: int = peers[team]
		if pid == 0:
			events[team].clear()
			continue
		var own := []
		for s: Soldier in squads[team]:
			var tgt: Vector2 = s.path[s.path.size() - 1] if not s.path.is_empty() else s.pos
			own.append([s.idx, s.pos, s.facing, s.hp, _flags(s), tgt, s.watch_angle if s.facing_lock else INF, s.mp])
		var en := []
		var scanned := []
		var enemy_alive := []
		for e: Soldier in squads[1 - team]:
			enemy_alive.append(e.alive)
			# Show both formations during the cinematic border entry.
			if vis_table[team][e.idx] or state == Cfg.State.DEPLOYMENT or state == Cfg.State.COUNTDOWN or (state == Cfg.State.ENDED and e.alive):
				en.append([e.idx, e.pos, e.facing, e.hp, _flags(e)])
			elif e.alive:
				for sc in scans:
					if sc["team"] == team and _scan_reveals(e, sc["origin"]):
						scanned.append([e.idx, e.pos])
						break
		var snap := {
			"st": state,
			"dp": deployment,
			"ct": countdown,
			"win": winner,
			"sel": selected[team],
			"own": own,
			"en": en,
			"sc": scanned,
			"ea": enemy_alive,
			"fg": fog_data,
			"cd": cooldowns[team].duplicate(),
			"ev": events[team],
			"rm": rematch_votes.duplicate(),
			"names": names.duplicate(),
			"lo": loadouts[team].duplicate(),
			"rd": loadout_ready.duplicate(),
			"conn": [peers[0] != 0, peers[1] != 0],
		}
		events[team] = []
		Net.s_snapshot.rpc_id(pid, snap)
