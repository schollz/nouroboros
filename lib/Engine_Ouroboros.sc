// Engine_Ouroboros

// Inherit methods from CroneEngine
Engine_Ouroboros : CroneEngine {

    // Ouroboros specific v0.1.0
	var server;
	var bufs;
	var buses;
	var syns;
	var oscs;
    var loops;
    // Ouroboros ^

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }


	play {
		arg id;
        if (bufs.at(id).notNil,{
            if (loops.at(id).notNil,{
                ["[ouro] sending done to loop",id].postln;
                loops.at(id).set(\done,1);
            });
            ["[ouro] started playing loop",id].postln;
            loops.put(id,Synth.before(syns.at("fx"),"looper",[
                buf: bufs.at(id),
                busReverb: buses.at("busReverb"),
                busNoCompress: buses.at("busNoCompress"),
                busCompress: buses.at("busCompress"),
            ]).onFree({
                ["[ouro] stopped playing loop",id].postln;
            }));
            NodeWatcher.register(loops.at(id));
        });
	}

    alloc {
        // Ouroboros specific v0.0.1
        var server = context.server;
        var xfade = 0.1;

		// basic players
		SynthDef("fx",{
			arg busReverb,busCompress,busNoCompress;
			var snd;
			var sndReverb=In.ar(busReverb,2);
			var sndCompress=In.ar(busCompress,2);
			var sndNoCompress=In.ar(busNoCompress,2);
			var in = (SoundIn.ar(0)*\db2.kr(0).dbamp) + (SoundIn.ar(1)*\db1.kr(0).dbamp);
			sndNoCompress = (sndNoCompress+(in*0.8));
			sndReverb = (sndReverb+(in*0.2));
			sndCompress=Compander.ar(sndCompress,sndCompress,0.05,slopeAbove:0.1,relaxTime:0.01);
			sndNoCompress=Compander.ar(sndNoCompress,sndNoCompress,1,slopeAbove:0.1,relaxTime:0.01);
			sndReverb=Fverb.ar(sndReverb[0],sndReverb[1]);

			snd=sndCompress+sndNoCompress+sndReverb;
			Out.ar(0,snd*Line.ar(0,1,3));
		}).add;

		SynthDef("looper",{
			arg id,buf,t_trig=0,busReverb,busCompress,busNoCompress,db=0,done=0;
            var amp = db.dbamp;
            var playhead = ToggleFF.kr(t_trig);
			var snd0 = PlayBuf.ar(1,buf,rate:BufRateScale.ir(buf),loop:1,trigger:1-playhead);
			var snd1 = PlayBuf.ar(1,buf,rate:BufRateScale.ir(buf),loop:1,trigger:playhead);
			var snd = SelectX.ar(Lag.kr(playhead,xfade),[snd0,snd1]);
            var reverbSend = 0.25;
			snd = snd * amp * EnvGen.ar(Env.adsr(3,1,1,3),1-done,doneAction:2);
			snd = snd * (LFNoise2.kr(1/Rand(4,6)).range(6.neg,0).dbamp); // amplitude lfo
			snd = Pan2.ar(snd,LFNoise2.kr(1/Rand(3,8),mul:0.25)); 
			Out.ar(busCompress,0*snd);
			Out.ar(busNoCompress,(1-reverbSend)*snd);
			Out.ar(busReverb,reverbSend*snd);
		}).add;

		SynthDef("recorder",{
			arg id,buf,t_trig,busReverb,busCompress,busNoCompress,db=0,done=0,side=0;
            var amp = db.dbamp;
            var snd = SoundIn.ar(side)*EnvGen.ar(Env.adsr(0.1,1,1,1));
            RecordBuf.ar(snd,buf,loop:0,doneAction:2);
			Out.ar(0,Silent.ar(2));
		}).add;

		SynthDef("track_input",{
			arg id,buf,t_trig,busReverb,busCompress,busNoCompress,db=0,done=0,side=0;
            var snd = SoundIn.ar(side);
			SendReply.kr(Impulse.kr(10),"/loop_db",[id,Lag.kr(Amplitude.kr(snd),0.5)]);
			Out.ar(0,Silent.ar(2));
		}).add;


		// initialize variables
		syns = Dictionary.new();
		buses = Dictionary.new();
		bufs = Dictionary.new();
		oscs = Dictionary.new();
		loops = Dictionary.new();

		server.sync;
		oscs.put("loop_db",OSCFunc({ |msg|
			var oscRoute=msg[0];
			var synNum=msg[1];
			var dunno=msg[2];
			var id=msg[3].asInteger;
			var db=msg[4].asFloat.ampdb;
			NetAddr("127.0.0.1", 10111).sendMsg("loop_db",id,db);
		}, '/loop_db'));
		
		// define buses
		buses.put("busCompress",Bus.audio(server,2));
		buses.put("busNoCompress",Bus.audio(server,2));
		buses.put("busReverb",Bus.audio(server,2));
		server.sync;

		// define fx
		syns.put("fx",Synth.tail(server,"fx",[
            busReverb: buses.at("busReverb"),
            busNoCompress: buses.at("busNoCompress"),
            busCompress: buses.at("busCompress"),
        ]));
		// syns.put("track_input",Synth.head(server,"track_input"));

		server.sync;
		"done loading.".postln;

        this.addCommand("sync","",{ arg msg;
            loops.keysValuesDo({ arg k, syn;
                if (syn.isRunning,{
                    syn.set(\t_trig,1);
                });
            });
        });

		this.addCommand("load_loop","is",{ arg msg;
			var id=msg[1];
			var filename=msg[2].asString;
			Buffer.read(server,filename,action:{ arg buf;
                if (loops.at(id).notNil,{
                    if (loops.at(id).isRunning,{
                        playing = true;
                    });
                });
                if (playing,{
                    loops.at(id).set(\buf,buf);
                },{
                    this.play(id);
                });
				if (bufs.at(id).notNil,{
					bufs.at(id).free;
				});
				bufs.put(id,buf);
			});
		});

		this.addCommand("record","ifis",{ arg msg;
            var id=msg[1];
            var seconds=msg[2].asFloat+(xfade*1.5);
			var side=1-msg[3];
			var filename=msg[4].asString;

            // initiate a routine to automatically start playing loop
            Routine {
                var playing = false;
                seconds.wait;
                if (loops.at(id).notNil,{
                    if (loops.at(id).isRunning,{
                        playing = true;
                    });
                });
                if (playing,{
                    loops.at(id).set(\buf,bufs.at(id));
                },{
                    this.play(id);
                });
            }.play;

            // allocate buffer and record the loop
            Buffer.alloc(server,seconds*server.sampleRate,1,completionMessage:{ arg buf;
                bufs.put(id,buf);
				["[ouro] started recording loop",id].postln;
                syns.put("record"++id,Synth.head(server,"recorder",[
                    id: id,
                    buf: buf,
					side: side,
                ]).onFree({
                    ["[ouro] finished recording loop",id].postln;
					buf.write(filename,headerFormat: "wav", sampleFormat: "int16",numFrames:seconds*server.sampleRate,completionMessage:{
						["[ouro] finished writing",filename].postln;
						Routine{
							1.wait;
							NetAddr("127.0.0.1", 10111).sendMsg("recorded",msg[1],msg[3],filename);
						}.play;
					});
                }));
            });
		});

		this.addCommand("set_loop","isf",{ arg msg;
            var id=msg[1];
            var k=msg[2];
            var v=msg[3];
            if (syns.at(id).notNil,{
                if (syns.at(id).isRunning,{
                    ["[ouro] setting syn",id,k,"=",v].postln;
                    syns.at(id).set(k,v);
                });
            });
            if (loops.at(id).notNil,{
                if (loops.at(id).isRunning,{
                    ["[ouro] setting loop",id,k,"=",v].postln;
                    loops.at(id).set(k,v);
                });
            });
		});

		this.addCommand("set_fx","sf",{ arg msg;
			var k=msg[1].asSymbol;
			var v=msg[2];
			syns.at("fx").set(k,v);
		});
    }


	free {
		bufs.keysValuesDo({ arg k, val;
			val.free;
		});
		oscs.keysValuesDo({ arg k, val;
			val.free;
		});
		syns.keysValuesDo({ arg k, val;
			val.free;
		});
		loops.keysValuesDo({ arg k, val;
			val.free;
		});
		buses.keysValuesDo({ arg k, val;
			val.free;
		});
	}
}
