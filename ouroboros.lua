-- ouroboros
--
-- llllllll.co/t/ouroboros
--
-- layer recordings
-- @infinitedigits
--
--    ▼ instructions below ▼
--

waveform_=include("lib/waveform")
utils=include("lib/utils")
grid_=include("lib/ggrid")
looper_=include("lib/looper")
lattice_=require("lattice")
musicutil=require("musicutil")
engine.name="Ouroboros"

--
-- SONG SPECIFIC
--
bpm=150
chords={
  {chord="I",chord2="ii",beats=4},
  {chord="V",chord2="vi",beats=2},
  {chord="vi",chord2="vii",beats=4},
  {chord="iii",chord2="I",beats=4},
  -- {chord="IV",chord2="ii",beats=4},
  -- {chord="V","vi",beats=4},
  -- {chord="vi","vii",beats=4},
  -- {chord="I","I",beats=4},
}
--
-- THANKS
--

--
-- globals
--
position={1,1}
params_grid={"level"}
loop_db={0,0,0,0,0,0,0,0}
rendering_waveform=nil

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
  crow.output[2].action="adsr(1,1,5,1)"
  params:set("clock_tempo",bpm)

  print("starting")
  os.execute(_path.code.."ouroboros/lib/oscnotify/run.sh &")
  os.execute("mkdir -p ".."/home/we/dust/audio/ouroboros/")

  for k,v in pairs(reverb_settings) do
    reverb_settings_saved[k]=params:get(k)
    params:set(k,v)
  end

  params:set("reverb",1)
  params:set("rev_eng_input",-6)
  params:set("rev_return_level",-6)
  params:set("rev_low_time",9)
  params:set("rev_mid_time",6)

  -- setup softcut renderer
  softcut.buffer_clear()
  softcut.event_render(function(ch,start,i,s)
    if rendering_waveform~=nil then
      print(string.format("[waveform] rendered %d",rendering_waveform[1],rendering_waveform[2]))
      local max_val=0
      for i,v in ipairs(s) do
        if v>max_val then
          max_val=math.abs(v)
        end
      end
      for i,v in ipairs(s) do
        s[i]=math.abs(v)/max_val
      end
      loopers[rendering_waveform[1]]:upload_waveform(rendering_waveform[2],s)
    end
  end)

  -- setup osc
  osc_fun={
    oscnotify=function(args)
      print("file edited ok!")
      rerun()
    end,
    recorded=function(args)
      print("recorded")
      tab.print(args)
      local x=tonumber(args[1])
      local i=x<9 and 1 or 2
      local loop=x<9 and x or x-8
      loopers[i]:load_waveform(loop,args[3])
    end,
    loop_db=function(args)
      loopers[1].db_light=tonumber(args[1])
      loopers[2].db_light=tonumber(args[2])
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


  -- setup midi
  midi_device={}
  midi_device_names={"none"}
  for i,dev in pairs(midi.devices) do
    if dev.port~=nil then
      local connection=midi.connect(dev.port)
      local name=string.lower(dev.name).." "..i
      print("adding "..name.." as midi device")
      table.insert(midi_device_names,name)
      midi_device[name]=connection
    end
  end

  loopers={}
  for i=1,2 do
    table.insert(loopers,looper_:new{id=i})
  end

  params:default()
  params:bang()

  -- setup the chords
  all_notes_map={}
  for i,c in ipairs(chords) do
    local m={}
    for octave=5,0,-1 do
      local r={}
      notes=musicutil.generate_chord_roman(12+octave*12,1,c.chord)
      for _,note in ipairs(notes) do
        table.insert(r,note)
        all_notes_map[note]=true
      end
      notes=musicutil.generate_chord_roman(24+octave*12,1,c.chord2)
      for _,note in ipairs(notes) do
        table.insert(r,note)
        all_notes_map[note]=true
      end
      table.insert(m,r)
    end
    chords[i].m=m
  end
  all_notes={}
  for k in pairs(all_notes_map) do
    table.insert(all_notes,k)
  end
  table.sort(all_notes)

  next_note_in_scale=function(n,i)
    for j,n2 in ipairs(all_notes) do
      if n2==n then
        do return all_notes[i+j] end
      end
    end
  end


  -- initialize grid
  g_=grid_:new()

  clock.run(function()
    while true do
      clock.sleep(1/10)
      redraw()
    end
  end)

  -- start the looper
  beats_total=0
  for _,c in ipairs(chords) do
    beats_total=beats_total+c.beats
  end
  clock_beat=0
  clock_chord=1
  local lattice=lattice_:new()
  lattice:new_sprocket{
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
          for _,l in ipairs(loopers) do
            l:clock_loops()
          end
        end
        -- print("[clock] new chord",chords[clock_chord].chord)
      end
    end,
    division=1/4,
  }

  -- clocks for the arps
  -- arp options
  arp_option_lights={0,0,0}
  for i,denominator in ipairs({0.125,0.25,0.5,1,2,3,4,6,8,12,16,24,32}) do
    local arp_beat=0
    lattice:new_sprocket{
      action=function(t)
        arp_beat=arp_beat+1
        for _,l in ipairs(loopers) do
          l:clock_arps(arp_beat,denominator)
        end
      end,
      division=1/denominator,
    }
  end

  lattice:hard_restart()



  params.action_read=function(filename,silent)
    print("[params.action_read]",filename,silent)
    clock.run(function()
      clock.sleep(1)
      -- check all the loops and load them if they exist
      for l=1,2 do
        for i=1,8 do
          if params:get(l.."filename"..i)~="" then
            print(string.format("[params.action_read] adding %s to looper %d, slot %d",filename,l,i))
            engine.load_loop((l-1)*8+i,params:get(l.."filename"..i))
          end
        end
      end
    end)
  end

end

function key(k,z)
  if k==3 then
    g_:key_press(position[1],position[2],z==1)
  end
end

function enc(k,d)
  if k==2 then
    position[1]=util.wrap(position[1]+d,1,8)
  elseif k==3 then
    position[2]=util.wrap(position[2]+d,1,16)
  end
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

  -- screen.level(0)
  -- screen.rect(1,1,128,64)
  -- screen.fill()

  -- local gd=g_:get_visual()
  -- rows=#gd
  -- cols=#gd[1]
  -- for row=1,rows do
  --   for col=1,cols do
  --     screen.level(gd[row][col]~=0 and gd[row][col] or 1)
  --     screen.rect(col*8-7,row*8-8+1,6,6)
  --     screen.fill()
  --   end
  -- end
  -- screen.level(15)
  -- screen.rect(position[2]*8-7,position[1]*8-8+1,7,7)
  -- screen.stroke()

  for _,l in ipairs(loopers) do
    l:redraw()
  end


  screen.font_size(16)
  screen.level(10)
  screen.move(1,60)
  screen.text(clock_chord)
  screen.move(12,60)
  screen.text("/")
  screen.move(25,60)
  screen.text(#chords)

  screen.move(64,60)
  screen.text_center(chords[clock_chord].chord)

  screen.move(127-24,60)
  screen.text_right(clock_beat)
  screen.move(127-11,60)
  screen.text_right("/")
  screen.move(127,60)
  screen.text_right(chords[clock_chord].beats)


  screen.update()
end

function params_loop()

end
