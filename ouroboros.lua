-- ouroboros
--
-- llllllll.co/t/ouroboros
--
-- layer recordings
-- @infinitedigits
--
--    ▼ instructions below ▼
--

lattice_ = require("lattice")
grid_=include("lib/ggrid")
musicutil=require("musicutil")
engine.name="Ouroboros"

--
-- SONG SPECIFIC
--
bpm=90
chords={
  {chord="I",chord2="ii",beats=4},
  {chord="V","vi",beats=4},
  {chord="vi","vii",beats=3},
  {chord="iii","I",beats=5},
}
--
-- THANKS
--

--
-- globals
--
beats_total=0
rec_queue={}
notes_on = {}

-- script
--
reverb_settings_saved={}
reverb_settings={
  reverb=2,
  rev_eng_input=0,
  rev_return_level=0,
  rev_low_time=9,
  rev_mid_time=6,
}
function init()
  params:set("clock_tempo",bpm)

  print("starting")
  os.execute(_path.code.."ouroboros/lib/oscnotify/run.sh &")

  for k,v in pairs(reverb_settings) do
    reverb_settings_saved[k]=params:get(k)
    params:set(k,v)
  end


  params:set("reverb",1)
  params:set("rev_eng_input",-6)
  params:set("rev_return_level",-6)
  params:set("rev_low_time",9)
  params:set("rev_mid_time",6)

  -- setup osc
  osc_fun={
    oscnotify=function(args)
      print("file edited ok!")
      rerun()
    end,
  }
  osc.event=function(path,args,from)
    if string.sub(path,1,1)=="/" then
      path=string.sub(path,2)
    end
    if path~=nil and osc_fun[path]~=nil then
      osc_fun[path](args)
    else
      -- print("osc.event: '"..path.."' ?")
    end
  end

  local params_menu={
    {id="db",name="volume",min=-96,max=12,exp=false,div=0.1,default=-6,unit="db"},
  }
  for _,pram in ipairs(params_menu) do
    params:add{
      type="control",
      id=pram.id,
      name=pram.name,
      controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
      formatter=pram.formatter,
    }
    params:set_action(pram.id,function(x)
      if pram.id=="timescalein" then
        x=x*0.05
      end
      if pram.id=="rateMult" and math.abs(x)<0.1 then
        x=0.1*(x>0 and 1 or-1)
      end
      engine.set_loop(1,pram.id,x)
    end)
  end

  params:default()
  params:bang()

    -- setup the chords
  for i,c in ipairs(chords) do 
    local m = {}
    tab.print(c)
    for octave=5,0,-1 do 
      local r ={}
      notes = musicutil.generate_chord_roman(12+octave*12,1,c.chord)
      for _, note in ipairs(notes) do 
        table.insert(r,note)
      end
      notes = musicutil.generate_chord_roman(24+octave*12,1,c.chord2)
      for _, note in ipairs(notes) do 
        table.insert(r,note)
      end
      table.insert(m,r)
      tab.print(r)
    end
    chords[i].m=m
  end

  
  -- setup midi
  midi_device={}
  for i,dev in pairs(midi.devices) do
    print(i,dev,dev.port)
    if dev.port~=nil then
      local connection=midi.connect(dev.port)
      local name=string.lower(dev.name).." "..i
      print("adding "..name.." as midi device")
      midi_device[name] = connection
    end
  end


  -- initialize grid 
  g_ = grid_:new()

  clock.run(function()
    while true do
      clock.sleep(1/10)
      redraw()
    end
  end)

  -- start the looper
  for _,c in ipairs(chords) do
    beats_total=beats_total+c.beats
  end
  clock_beat=0
  clock_chord=1
  local lattice = lattice_:new()
  lattice:new_pattern{
    action=function(t)
        clock_beat=clock_beat+1
        -- print("[clock] beat",clock_beat)
        if (clock_beat>chords[clock_chord].beats) then
          clock_beat=1
          clock_chord=clock_chord+1
          if clock_chord>#chords then
            -- print("[clock] new phrase")
            clock_chord=1
            engine.sync()
            rec_queue_down()
          end
          -- print("[clock] new chord",chords[clock_chord].chord)
        end
    end,
    division=1/4,
  }
  -- arp
  arp_beat = 0
  lattice:new_pattern{
    action=function(t)
      arp_beat = arp_beat + 1
      if #notes_on==2 then 
        local x=notes_on[arp_beat%#notes_on+1]
        local note=chords[clock_chord].m[x[1]][x[2]]
        note_play(note)
      end
    end,
    division=1/16,
  }
  arp_beat2 = 0
  lattice:new_pattern{
    action=function(t)
      arp_beat2 = arp_beat2 + 1
      if #notes_on==3 then 
        local x=notes_on[arp_beat2%#notes_on+1]
        local note=chords[clock_chord].m[x[1]][x[2]]
        note_play(note)
      end
    end,
    division=1/24,
  }
  arp_beat3 = 0
  lattice:new_pattern{
    action=function(t)
      arp_beat3 = arp_beat3 + 1
      if #notes_on>3 then 
        local x=notes_on[arp_beat3%#notes_on+1]
        local note=chords[clock_chord].m[x[1]][x[2]]
        note_play(note)
      end
    end,
    division=1/32,
  }
  lattice:hard_restart()


end

function note_play(note)
  midi_device['boutique 3']:note_on(note,120,1)
  midi_device['boutique 3']:note_off(note,120,1)
end

function rec_queue_up(x)
  -- don't queue up twice
  for _,v in ipairs(rec_queue) do
    if v==x then
      do return end
    end
  end
  table.insert(rec_queue,x)
  print("[rec] queued",x)
end

function rec_queue_down()
  if next(rec_queue)==nil then 
    do return end 
  end
  local x=table.remove(rec_queue,1)
  engine.record(x,beats_total*clock.get_beat_sec())
  print("[rec] recording",x)
end

function key(k,z)
  if k>1 and z==1 then
    rec_queue_up(k)
  end
end


function enc(k,d)
end

function rerun()
  norns.script.load(norns.state.script)
end


function cleanup()
  os.execute("pkill -f oscnotify")
  for k,v in pairs(reverb_settings_saved) do
    params:set(k,v)
  end
end


function redraw()
  screen.clear()

  screen.level(15)
  screen.move(64,32)
  screen.text("ouroboros")
  screen.move(72,18)
  screen.text(clock_beat)
  screen.move(36,18)
  screen.text(clock_chord.."/"..#chords)

  screen.update()
end
