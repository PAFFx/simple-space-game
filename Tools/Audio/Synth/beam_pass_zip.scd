// A beam snapping past: a short bright crack at 0.05 s and a crackling fizz after it. No
// tone, no pitch drop.
(
var out = thisProcess.argv[0] ? "/tmp/beam_pass_zip.wav";
var seconds = 0.5;
var score;

SynthDef(\beamPassZip, {
	var snap = EnvGen.ar(Env([0, 0, 1, 0], [0.04, 0.006, 0.09], [0, 0, -5]));
	var fizz = EnvGen.ar(Env([0, 0, 0.5, 0], [0.04, 0.02, 0.35], [0, 0, -4]));
	var crack = RHPF.ar(WhiteNoise.ar, 5500, 0.5) * snap;
	var crackle = HPF.ar(Dust2.ar(2200) * (0.4 + WhiteNoise.ar.abs), 2800) * fizz;
	var sig = LPF.ar(crack + crackle + (HPF.ar(Crackle.ar(1.9), 3000) * fizz * 0.5), 15000);
	Out.ar(0, (sig * 0.4) ! 2);
}).store;

score = Score([[0.0, [\s_new, \beamPassZip, 1000, 0, 0]], [seconds, [\c_set, 0, 0]]]);
score.recordNRT(outputFilePath: out, headerFormat: "WAV", sampleFormat: "int24",
	options: ServerOptions.new.numOutputBusChannels_(2).sampleRate_(48000),
	duration: seconds, action: { 0.exit });
)
