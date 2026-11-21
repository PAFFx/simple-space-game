// New sensor contact: the source's low ping rebuilt clean. Harmonics 3 and 4 of 750 Hz
// (2250 / 3000 Hz) in a short-long double blip, 8 ms edges so it never clicks or startles.
(
var out = thisProcess.argv[0] ? "/tmp/warning_contact.wav";
var seconds = 0.6;
var score;

SynthDef(\warningContact, {
	var blip = { |start, dur| EnvGen.ar(Env([0, 0, 1, 1, 0], [start, 0.008, dur - 0.016, 0.008])) };
	var env = blip.(0.02, 0.05) + blip.(0.14, 0.10);
	var tone = SinOsc.ar(2250, 0, 0.6) + SinOsc.ar(3000, 0, 0.45) + SinOsc.ar(750, 0, 0.12);
	var sig = tone * env * 0.35;
	sig = sig + (FreeVerb.ar(sig, 1, 0.2, 0.7) * 0.2);
	Out.ar(0, sig ! 2);
}).store;

score = Score([[0.0, [\s_new, \warningContact, 1000, 0, 0]], [seconds, [\c_set, 0, 0]]]);
score.recordNRT(outputFilePath: out, headerFormat: "WAV", sampleFormat: "int24",
	options: ServerOptions.new.numOutputBusChannels_(2).sampleRate_(48000),
	duration: seconds, action: { 0.exit });
)
