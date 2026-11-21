// A beam sizzling past: no tone, no pitch drop (a falling buzz sounded like a car). Hiss and
// electric crackle swell to the pass at 0.3 s and die off; only the brightness and the
// crackle density follow the swell.
(
var out = thisProcess.argv[0] ? "/tmp/beam_pass_sizzle.wav";
var seconds = 0.9;
var score;

SynthDef(\beamPassSizzle, {
	var tc = 0.3;
	var x = Line.ar(0, seconds, seconds) - tc;
	var amp = 1 / (1 + (x / Select.ar(x > 0, [DC.ar(0.05), DC.ar(0.11)])).squared);
	var hiss = HPF.ar(BPF.ar(WhiteNoise.ar, 5000, 1.6), 1800);
	var crackle = HPF.ar(Dust2.ar(300 + (2600 * amp)) * (0.5 + WhiteNoise.ar.abs), 2500);
	var arc = HPF.ar(Crackle.ar(1.92), 3000) * 0.4;
	var sig = LPF.ar((hiss * 0.8) + crackle + arc, 3500 + (12000 * amp));
	sig = sig * amp * EnvGen.ar(Env([0, 1, 1, 0], [0.005, seconds - 0.04, 0.035]));
	Out.ar(0, (sig * 0.3) ! 2);
}).store;

score = Score([[0.0, [\s_new, \beamPassSizzle, 1000, 0, 0]], [seconds, [\c_set, 0, 0]]]);
score.recordNRT(outputFilePath: out, headerFormat: "WAV", sampleFormat: "int24",
	options: ServerOptions.new.numOutputBusChannels_(2).sampleRate_(48000),
	duration: seconds, action: { 0.exit });
)
