// Template for a synthesized source: copy it, change the SynthDef, point a recipe at it
// (source = "Synth/<name>.scd"). Rendered offline (NRT, no audio device) by
//   Tools/Audio/sfx_lab.sh synth Tools/Audio/Synth/<name>.scd <out.wav> [seconds]
// argv: [out_path, seconds].
(
var out = thisProcess.argv[0] ? "/tmp/sc_render.wav";
var seconds = (thisProcess.argv[1] ? "1.0").asFloat;
var score;

SynthDef(\sfx, {
	// A short two-tone cockpit chirp as a placeholder.
	var env = EnvGen.ar(Env.perc(0.005, 0.25), doneAction: 2);
	var tone = SinOsc.ar([1200, 1800]).sum * 0.3 * env;
	Out.ar(0, tone ! 2);
}).store;

score = Score([
	[0.0, [\s_new, \sfx, 1000, 0, 0]],
	[seconds, [\c_set, 0, 0]],
]);
score.recordNRT(
	outputFilePath: out,
	headerFormat: "WAV",
	sampleFormat: "int24",
	options: ServerOptions.new.numOutputBusChannels_(2).sampleRate_(48000),
	duration: seconds,
	action: { 0.exit }
);
)
