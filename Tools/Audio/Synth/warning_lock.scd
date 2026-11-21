// Someone has a lock on you: the source's medium ping rebuilt clean, one unit the game
// repeats. Harmonics 2, 3, 4, 6 of 960 Hz with its flutter (amplitude wobble).
(
var out = thisProcess.argv[0] ? "/tmp/warning_lock.wav";
var seconds = 0.6;
var score;

SynthDef(\warningLock, {
	var env = EnvGen.ar(Env([0, 0, 1, 1, 0], [0.01, 0.012, 0.42, 0.04]));
	var flutter = 1 - (0.3 * (SinOsc.ar(14) * 0.5 + 0.5));
	var tone = SinOsc.ar(1920, 0, 0.45) + SinOsc.ar(2880, 0, 0.45)
		+ SinOsc.ar(3840, 0, 0.4) + SinOsc.ar(5760, 0, 0.3);
	var sig = tone * env * flutter * 0.3;
	sig = sig + (FreeVerb.ar(sig, 1, 0.2, 0.7) * 0.2);
	Out.ar(0, sig ! 2);
}).store;

score = Score([[0.0, [\s_new, \warningLock, 1000, 0, 0]], [seconds, [\c_set, 0, 0]]]);
score.recordNRT(outputFilePath: out, headerFormat: "WAV", sampleFormat: "int24",
	options: ServerOptions.new.numOutputBusChannels_(2).sampleRate_(48000),
	duration: seconds, action: { 0.exit });
)
