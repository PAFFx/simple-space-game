// Incoming fire: the most urgent alert. Launch-warning pattern (fast, high, warbling):
// 100 ms bursts with 60 ms gaps, each burst flipping between 1500 and 2000 Hz at 25 Hz, on
// a pulse wave filtered so it is rich enough to cut through and be placed.
(
var out = thisProcess.argv[0] ? "/tmp/warning_threat.wav";
var seconds = 0.85;
var score;

SynthDef(\warningThreat, {
	var gate = EnvGen.ar(Env(
		[0] ++ ([0, 1, 1, 0] ! 5).flatten,
		[0.005] ++ ([0.06, 0.006, 0.088, 0.006] ! 5).flatten.drop(1)));
	var freq = Select.ar(LFPulse.ar(25), [DC.ar(1500), DC.ar(2000)]);
	var tone = RLPF.ar(Pulse.ar(freq, 0.35), 6000, 0.7) * 0.5 + SinOsc.ar(freq, 0, 0.4);
	var sig = tone * gate * 0.3;
	sig = sig + (FreeVerb.ar(sig, 1, 0.2, 0.7) * 0.15);
	Out.ar(0, sig ! 2);
}).store;

score = Score([[0.0, [\s_new, \warningThreat, 1000, 0, 0]], [seconds, [\c_set, 0, 0]]]);
score.recordNRT(outputFilePath: out, headerFormat: "WAV", sampleFormat: "int24",
	options: ServerOptions.new.numOutputBusChannels_(2).sampleRate_(48000),
	duration: seconds, action: { 0.exit });
)
