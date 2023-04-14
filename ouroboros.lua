-- ouroboros
--
-- llllllll.co/t/ouroboros
--
-- layer recordings
-- @infinitedigits
--
--    ▼ instructions below ▼
--

lattice_=require("lattice")
grid_=include("lib/ggrid")
musicutil=require("musicutil")
engine.name="Ouroboros"

--
-- SONG SPECIFIC
--
bpm=120
chords={
  {chord="I",chord2="ii",beats=2},
  {chord="V","vi",beats=2},
  {chord="vi","vii",beats=2},
  {chord="iii","I",beats=2},
}
--
-- THANKS
--

--
-- globals
--
beats_total=0
rec_queue={}
rec_current=0
notes_on={}
position={1,1}
params_grid={"level"}

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

  params_loop()

  params:default()
  params:bang()

  -- setup the chords
  for i,c in ipairs(chords) do
    local m={}
    for octave=5,0,-1 do
      local r={}
      notes=musicutil.generate_chord_roman(12+octave*12,1,c.chord)
      for _,note in ipairs(notes) do
        table.insert(r,note)
      end
      notes=musicutil.generate_chord_roman(24+octave*12,1,c.chord2)
      for _,note in ipairs(notes) do
        table.insert(r,note)
      end
      table.insert(m,r)
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
      midi_device[name]=connection
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
  for _,c in ipairs(chords) do
    beats_total=beats_total+c.beats
  end
  clock_beat=0
  clock_chord=1
  local lattice=lattice_:new()
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
  arp_beat=0
  lattice:new_pattern{
    action=function(t)
      arp_beat=arp_beat+1
      if #notes_on==2 then
        local x=notes_on[arp_beat%#notes_on+1]
        local note=chords[clock_chord].m[x[1]][x[2]]
        note_play(note)
      end
    end,
    division=1/16,
  }
  arp_beat2=0
  lattice:new_pattern{
    action=function(t)
      arp_beat2=arp_beat2+1
      if #notes_on==3 then
        local x=notes_on[arp_beat2%#notes_on+1]
        local note=chords[clock_chord].m[x[1]][x[2]]
        note_play(note)
      end
    end,
    division=1/24,
  }
  arp_beat3=0
  lattice:new_pattern{
    action=function(t)
      arp_beat3=arp_beat3+1
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
  if rec_current>0 then
    print("[rec] finished recording",rec_current)
  end
  if next(rec_queue)==nil then
    rec_current=0
    do return end
  end
  local x=table.remove(rec_queue,1)
  engine.record(x,beats_total*clock.get_beat_sec())
  params:set("loop",x)
  print("[rec] recording",x)
  rec_current=x
end

function key(k,z)
  if k==3 then
    g_:key_press(position[1],position[2],z==1)
  end
  if k==2 and z==1 then
    rec_queue_up(2)
    rec_queue_up(5)
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

  local gd=g_:get_visual()
  rows=#gd
  cols=#gd[1]
  for row=1,rows do
    for col=1,cols do
      screen.level(gd[row][col]~=0 and gd[row][col] or 1)
      screen.rect(col*8-7,row*8-8+1,6,6)
      screen.fill()
    end
  end
  screen.level(15)
  screen.rect(position[2]*8-7,position[1]*8-8+1,7,7)
  screen.stroke()

  screen.font_size(16)
  screen.level(15)
  screen.move(1,60-16)
  screen.text(clock_chord)
  screen.move(12,60-16)
  screen.text("/")
  screen.move(25,60-16)
  screen.text(#chords)

  screen.move(1,60)
  screen.text(clock_beat)
  screen.move(12,60)
  screen.text("/")
  screen.move(25,60)
  screen.text(chords[clock_chord].beats)

  screen.font_size(8)
  screen.level(15)
  screen.move(1,6)
  if rec_current>0 then
    if next(rec_queue)~=nil then
      screen.text(string.format("recording %d, then %d",rec_current,rec_queue[1]))
    else
      screen.text(string.format("recording %d",rec_current))
    end
  elseif next(rec_queue)~=nil then
    screen.text(string.format("queued %d",rec_queue[1]))
  end

  screen.update()
end

function params_loop()
  local params_menu={
    {id="arp_hold",name="arp hold",min=1,max=2,exp=false,div=1,default=0,unit="",values={"no","yes"}},
    {id="loop_times",name="loop times",min=1,max=3,exp=false,div=1,default=0,unit="",values={"x1","x2","x4"}},
    {id="level",name="volume",min=1,max=8,exp=false,div=1,default=6,unit="level",values={-96,-12,-9,-6,-3,0,3,6}},
  }
  params:add_number("loop","loop",1,8,1)
  params:set_action("loop",function(x)
    for loop=1,8 do
      for _,pram in ipairs(params_menu) do
        if loop==x then
          params:show(pram.id..loop)
        else
          params:hide(pram.id..loop)
        end
      end
    end
    _menu.rebuild_params()
  end)
  for loop=1,8 do
    for _,pram in ipairs(params_menu) do
      local formatter=pram.formatter
      if formatter==nil and pram.values~=nil then
        formatter=function(param)
          return pram.values[param:get()]..(pram.unit and (" "..pram.unit) or "")
        end
      end
      params:add{
        type="control",
        id=pram.id..loop,
        name=pram.name,
        controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
        formatter=formatter,
      }
      params:set_action(pram.id..loop,function(x)
        -- engine.set_loop(loop,pram.id,x)
      end)
    end
  end

end
