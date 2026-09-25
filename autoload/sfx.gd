extends Node
## Sound (prototype: render/audio.ts, a tiny synth bus). The prototype synthesised every sound
## with WebAudio oscillators; here each one is rendered once at boot into an AudioStreamWAV
## with the same waveform, pitch sweep (exponential), decay and optional noise layer.
## Hard cap on simultaneous voices + a per-sound throttle, like the prototype.
## Gameplay events pick the sounds (the prototype's fx.ts `consume`).

const MIX_RATE := 22050
const MAX_VOICES := 12
## id: [wave, f0, f1, dur, vol, gap_ms, noise]
const SOUNDS := {
	shot = ["square", 880, 520, 0.04, 0.025, 45, false],
	hit = ["triangle", 300, 120, 0.05, 0.05, 35, false],
	kill = ["sawtooth", 260, 60, 0.09, 0.05, 40, false],
	boom = ["sawtooth", 120, 30, 0.35, 0.14, 120, true],
	hurt = ["square", 180, 70, 0.18, 0.1, 100, false],
	dodge = ["sine", 500, 900, 0.08, 0.05, 60, false],
	perfect = ["sine", 1320, 440, 0.5, 0.14, 150, false],
	tell = ["square", 220, 240, 0.22, 0.08, 90, false],
	lunge = ["sawtooth", 160, 60, 0.16, 0.09, 90, true],
	commit = ["triangle", 330, 660, 0.15, 0.06, 150, false],
	swing = ["sine", 700, 240, 0.07, 0.05, 40, true],
	slam = ["sawtooth", 200, 45, 0.22, 0.1, 80, true],
	slash = ["square", 420, 140, 0.06, 0.06, 30, false],
	splat = ["triangle", 140, 40, 0.2, 0.12, 60, true],
	jump = ["sine", 300, 620, 0.1, 0.06, 60, false],
	dive = ["sawtooth", 900, 180, 0.14, 0.06, 80, false],
	pick = ["sine", 880, 1320, 0.06, 0.04, 35, false],
	level = ["triangle", 523, 1046, 0.4, 0.12, 200, false],
	cast = ["sine", 400, 1000, 0.2, 0.08, 100, false],
	blast = ["sawtooth", 150, 40, 0.28, 0.12, 70, true],
	shoot = ["square", 620, 320, 0.07, 0.035, 50, false],
	chest = ["triangle", 660, 990, 0.3, 0.1, 200, false],
	champ = ["sawtooth", 110, 220, 0.35, 0.08, 300, false],
	drink = ["sine", 300, 520, 0.18, 0.06, 90, false],
}
const MASTER_GAIN := 0.6

var enabled := true
var volume := 1.0            ## 0..1, the System tab's slider
var _streams := {}
var _last := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for id in SOUNDS:
		_streams[id] = _render(SOUNDS[id])
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)
	Events.game_event.connect(_on_event)


func active_voices() -> int:
	var n := 0
	for p in _players:
		if p.playing:
			n += 1
	return n


func play(id: String) -> void:
	if not enabled or not _streams.has(id):
		return
	var spec: Array = SOUNDS[id]
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, -100000)) < spec[5]:
		return
	for p in _players:
		if not p.playing:
			_last[id] = now
			p.stream = _streams[id]
			p.volume_db = linear_to_db(maxf(0.0001, volume))
			p.play()
			return
	# cap: drop the new sound


func _render(spec: Array) -> AudioStreamWAV:
	var wave: String = spec[0]
	var f0: float = spec[1]
	var f1: float = maxf(20.0, spec[2])
	var dur: float = spec[3]
	var vol: float = spec[4] * MASTER_GAIN
	var noise: bool = spec[6]
	var n := int((dur + 0.02) * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(wave) ^ int(f0)
	for i in n:
		var t := float(i) / MIX_RATE
		var u := minf(1.0, t / dur)
		var f := f0 * pow(f1 / f0, u)             # exponential ramp, like the prototype
		phase = fmod(phase + f / MIX_RATE, 1.0)
		var s: float
		match wave:
			"square":
				s = 1.0 if phase < 0.5 else -1.0
			"triangle":
				s = 4.0 * absf(phase - 0.5) - 1.0
			"sawtooth":
				s = 2.0 * phase - 1.0
			_:
				s = sin(phase * TAU)
		var env := vol * pow(0.0001 / vol, u) if t < dur else 0.0   # exponential decay to silence
		var out := s * env
		if noise and t < dur:
			out += rng.randf_range(-1.0, 1.0) * vol * 0.8 * pow(0.0001 / (vol * 0.8), u)
		data.encode_s16(i * 2, clampi(int(out * 32767.0 * 2.2), -32768, 32767))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = MIX_RATE
	st.stereo = false
	st.data = data
	return st


func _on_event(type: int, _x: float, _y: float, a: float, b: float, _z: float) -> void:
	match type:
		Ev.SHOT: play("shot")
		Ev.HIT: play("hit")
		Ev.KILL: play("boom" if b > 12.0 else "kill")
		Ev.PLAYER_HURT: play("hurt")
		Ev.PLAYER_DEATH: play("boom")
		Ev.DODGE: play("dodge")
		Ev.PERFECT_DODGE: play("perfect")
		Ev.TELL: play("tell")
		Ev.LUNGE: play("lunge")
		Ev.SQUAD_COMMIT: play("commit")
		Ev.SWING:
			var ws := Ev.unpack_swing(b)
			var heavy: bool = Content.weapons[clampi(ws.x, 0, Content.weapons.size() - 1)].swing(ws.y).heavy
			play("slam" if heavy else "swing")
		Ev.MELEE_HIT: play("slash")
		Ev.WALL_SPLAT, Ev.LAND: play("splat")
		Ev.RING_OUT: play("kill")
		Ev.JUMP: play("jump")
		Ev.DIVE_START: play("dive")
		Ev.DIVE_SLAM: play("slam")
		Ev.PICKUP: play("drink" if int(a) == Tuning.PICKUP_HEAL else "pick")
		Ev.LEVEL_UP, Ev.TECH_BOUGHT, Ev.JOB_CHANGED, Ev.WEAPON_FOUND: play("level")
		Ev.DRINK, Ev.WELL_USED: play("drink")
		Ev.SKILL_CAST: play("cast")
		Ev.BLAST: play("cast" if int(b) == 2 else "blast")
		Ev.ENEMY_SHOT: play("shoot")
		Ev.LOOT, Ev.ITEM_APPEAR: play("chest")
		Ev.CHAMPION: play("champ")
		Ev.ROOM_ENTER: play("commit")
		Ev.DOORS_SEALED, Ev.DENIED, Ev.NO_MANA: play("tell")
		Ev.WEAPON_EQUIP: play("pick")
		Ev.ROOM_EXIT: play("dodge")
		Ev.ROOM_CLEARED: play("perfect")
