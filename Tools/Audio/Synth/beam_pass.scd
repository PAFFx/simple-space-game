// A beam going by the cockpit (ProjectileSpec.pass_sound). Peak at `tc` s (= the spec's
// pass_lead): crackling electric hiss and a buzzing core, Doppler pitch drop through the
// pass, brightness and level swelling at the closest point, a short comb for the
// "spaceship pass" colour. argv: [out_path].
(
var out = thisProcess.argv[0] ? "/tmp/beam_pass.wav";
var seconds = 1.4;
var score;

SynthDef(\beamPass, {
	var tc = 0.3;
	var t = Line.ar(0, seconds, seconds);
	var x = (t - tc);
	// Doppler: high coming in, low going away.
	var r = 1 + (0.32 * (x.neg / 0.07).tanh);
	// Swell to the pass; quick in, longer out.
	var amp = 1 / (1 + (x / Select.ar(x > 0, [DC.ar(0.06), DC.ar(0.16)])).squared);
	var bright = 700 + (11000 * amp);
	var core = Mix([Saw.ar(150 * r, 0.5), Saw.ar(301 * r, 0.3), SinOsc.ar(1170 * r, 0, 0.12)]);
	var hiss = BPF.ar(WhiteNoise.ar, 2600 * r, 1.4) * 0.9;
	var crackle = HPF.ar(Dust2.ar(1400), 1500) * 0.6;
	var sig = (RLPF.ar(core, bright, 0.45) * 0.5) + LPF.ar(hiss + crackle, bright);
	sig = sig * amp * EnvGen.ar(Env([0, 1, 1, 0], [0.01, seconds - 0.06, 0.05]));
	sig = sig + (DelayC.ar(sig, 0.02, 0.0035 + (0.0015 * SinOsc.ar(0.9))) * 0.6);
	Out.ar(0, (sig * 0.35) ! 2);
}).store;

score = Score([[0.0, [\s_new, \beamPass, 1000, 0, 0]], [seconds, [\c_set, 0, 0]]]);
score.recordNRT(outputFilePath: out, headerFormat: "WAV", sampleFormat: "int24",
	options: ServerOptions.new.numOutputBusChannels_(2).sampleRate_(48000),
	duration: seconds, action: { 0.exit });
)
