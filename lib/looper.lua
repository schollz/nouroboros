local Looper={}

function Looper:new(args)
  local m=setmetatable({},{__index=Looper})
  local args=args==nil and {} or args
  for k,v in pairs(args) do
    m[k]=v
  end
  m:init()

  return m
end

function Looper:init()
  if self.id==nil then
    print("[looper] error: ID not defined")
    do return end
  end
  self.notes_turned_on={}
  self.rec_queue={}
  self.rec_current=0
  self.rec_loops=0
  self.loops_recorded={}
  self.notes_on={}
  self.note_location_playing=nil
  self.arp_options={
    {0,1,2,4,6},
    {1,2,3,4,8},
    {2,4,6,8,12},
    {4,6,8,16},
    {6,8,12,24},
    {8,16,24,32},
  }
  self.buttons={}
  for i=1,6 do
    table.insert(self.buttons,{})
    for j=1,6 do
      table.insert(self.buttons[i],false)
    end
  end
  self.waveforms={}
  for i=1,8 do
    table.insert(self.waveforms,waveform_:new{id=self.id,loop=i})
  end


  local do_set_crow=function()
    if self.id==1 then
      crow.output[2].action=string.format("ar( %2.3f, %2.3f, 7)",params:get(self.id.."attack")/1000,params:get(self.id.."release"))
    else
      crow.output[4].action=string.format("adsr( %2.3f,1,7, %2.3f)",params:get(self.id.."attack")/1000,params:get(self.id.."release"))
    end
  end
  local params_menu={
    {id="db",name="volume",min=1,max=8,exp=false,div=1,default=6,values={-96,-12,-9,-6,-3,0,3,6}},
  }

  local params_menu2={
    {id="attack",name="attack",min=1,max=10000,exp=false,div=1,default=self.id==1 and 10 or 100,unit="ms",action=do_set_crow},
    {id="release",name="release",min=0.02,max=30,exp=false,div=0.02,default=self.id==1 and 0.5 or 0.5,unit="s",action=do_set_crow},
  }
  params:add_group("LOOPER "..self.id,10+#params_menu*8+#params_menu2)
  params:add_number(self.id.."loop","loop",1,8,1)
  params:set_action(self.id.."loop",function(x)
    for loop=1,8 do
      for _,pram in ipairs(params_menu) do
        if loop==x then
          params:show(self.id..pram.id..loop)
        else
          params:hide(self.id..pram.id..loop)
        end
      end
    end
    do_set_crow()
    _menu.rebuild_params()
    engine.set_fx("db"..self.id,tonumber(params:string(self.id.."db"..x)))
  end)
  for loop=1,8 do
    for _,pram in ipairs(params_menu) do
      local formatter=pram.formatter
      if formatter==nil and pram.values~=nil then
        formatter=function(param)
          return pram.values[param:get()]..(pram.unit and (" "..pram.unit) or "")
        end
      end
      local pid=self.id..pram.id..loop
      params:add{
        type="control",
        id=pid,
        name=pram.name,
        controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
        formatter=formatter,
      }
      params:set_action(pid,function(x)
        if pram.values~=nil then
          x=pram.values[x]
        end
        if pram.action~=nil then
          pram.action(x)
        else
          engine.set_loop(loop+(self.id==1 and 0 or 8),pram.id,x)
          if pram.id=="db" then
            -- set input db
            engine.set_fx("db"..self.id,x)
          end
        end
      end)
    end
  end
  -- params_menu2
  for _,pram in ipairs(params_menu2) do
    local formatter=pram.formatter
    if formatter==nil and pram.values~=nil then
      formatter=function(param)
        return pram.values[param:get()]..(pram.unit and (" "..pram.unit) or "")
      end
    end
    local pid=self.id..pram.id
    params:add{
      type="control",
      id=pid,
      name=pram.name,
      controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
      formatter=formatter,
    }
    params:set_action(pid,function(x)
      if pram.values~=nil then
        x=pram.values[x]
      end
      if pram.action~=nil then
        pram.action(x)
      end
    end)
  end

  params:add_text(self.id.."justtext","~~all loops~~")
  params:add_text(self.id.."filename","")
  params:hide(self.id.."filename")
  params:add_option(self.id.."midi_device","midi device",midi_device_names,1)
  params:add_number(self.id.."midi_channel","midi channel",1,16,1)
  params:add_option(self.id.."hold_change","static holds",{"no","yes"},1)
  params:add_option(self.id.."note_pressing","note pressing",{"press","toggle"},2)
  params:set_action(self.id.."note_pressing",function(x)
    if x==1 then
      for r=1,6 do
        for c=1,6 do
          if not self.buttons[r][c] then
            self:note_grid_off(r,c)
          end
        end
      end
    end
  end)
  params:add_number(self.id.."note_adjust","adjust note",-15,15,0)
  params:set_action(self.id.."note_adjust",function(x)
    -- if note is being held, then adjust the note pitch
    -- self:emit_note()
  end)
  params:add_option(self.id.."arp_option","arp speeds",{"1/4","1/8","1/12","1/16","1/24","1/36"})
  params:add_number(self.id.."arp_division","arp division",0,2,0)
  do_set_crow()
end

function Looper:upload_waveform(i,s)
  self.waveforms[i]:upload_waveform(s)
end

function Looper:load_waveform(i,f)
  params:set(self.id.."filename",f)
  self.waveforms[i]:load(f)
end

function Looper:pget(k)
  return params:get(self.id..k..params:get(self.id.."loop"))
end

function Looper:pset(k,v)
  return params:set(self.id..k..params:get(self.id.."loop"),v)
end


function Looper:clock_new_chord()
  self.new_chord=true
end

function Looper:clock_loops()
  if self.rec_loops>0 then
    self.rec_loops=self.rec_loops-1
  end
  if self.rec_loops==0 then
    self:rec_queue_down()
  end
end

function Looper:clock_arps(arp_beat,denominator)
  local num_notes_on=#self.notes_on
  if num_notes_on==0 then
    self.note_location_playing=nil
    do return end
  end
  local do_play_note=false
  local op=4
  if self.arp_options[params:get(self.id.."arp_option")][num_notes_on]~=nil then
    op=self.arp_options[params:get(self.id.."arp_option")][num_notes_on]
  else
    op=self.arp_options[params:get(self.id.."arp_option")][#self.arp_options[params:get(self.id.."arp_option")]]
  end
  op=op/math.pow(2,params:get(self.id.."arp_division"))
  do_play_note=(denominator==op) or (self.new_chord and params:get(self.id.."arp_option")==1)
  self.new_chord=false
  if do_play_note and num_notes_on>0 then
    self.arp_beat=arp_beat
    self:emit_note()
  end
end

function Looper:emit_note()
  local num_notes_on=#self.notes_on
  if num_notes_on==0 then
    do return end
  end
  local x=self.notes_on[self.arp_beat%num_notes_on+1]
  local note=params:get(self.id.."hold_change")==1 and chords[clock_chord].m[x[1]][x[2]] or x[3]
  if self.id==1 then
    note=params:get(self.id.."hold_change")==1 and chords1[clock_chord].m[x[1]][x[2]] or x[3]
  end
  self.note_location_playing={x[1],x[2]}
  self:note_on(note)
end

function Looper:is_note_playing(i,j)
  if self.note_location_playing==nil then
    do return end
  end
  return self.note_location_playing[1]==i and self.note_location_playing[2]==j
end

function Looper:is_note_on(i,j)
  for _,v in ipairs(self.notes_on) do
    if v[1]==i and v[2]==j then
      do return true end
    end
  end
  return false
end

function Looper:note_on(note)
  print(string.format("[looper %d] note_on %d",self.id,note))
  if params:get(self.id.."note_adjust")~=0 then
    local next_note=next_note_in_scale(note,params:get(self.id.."note_adjust"))
    if next_note~=nil then
      note=next_note
      print(string.format("[looper %d] note_on %d (adjusted)",self.id,note))
    end
  end
  for k,v in pairs(self.notes_turned_on) do
    self:note_off(k)
  end
  crow.output[self.id==1 and 1 or 3].volts=(note-24)/12
  if self.id==1 then
    crow.output[2]()
  else
    crow.output[4](true)
  end
  if params:get(self.id.."midi_device")>1 then
    midi_device[params:string(self.id.."midi_device")]:note_on(note,60,params:get(self.id.."midi_channel"))
  end
  self.notes_turned_on[note]=true
end

function Looper:note_off(note)
  print(string.format("[looper %d] note_off %d",self.id,note))
  self.notes_turned_on[note]=nil
  if params:get(self.id.."midi_device")>1 then
    midi_device[params:string(self.id.."midi_device")]:note_off(note,60,params:get(self.id.."midi_channel"))
  end
end

function Looper:notes_off()
  print(string.format("[looper %d] notes_off",self.id))
  self.note_location_playing=nil
  if self.id==2 then
    crow.output[4](false)
  end
end

function Looper:button_down(r,c)
  self.buttons[r][c]=true
end

function Looper:button_up(r,c)
  self.buttons[r][c]=false
end

function Looper:note_grid_on(r,c)
  local note=chords[clock_chord].m[r][c]
  if self.id==2 then
    note=chords1[clock_chord].m[r][c]
  end
  print(r,c,note)
  print(string.format("[looper %d] note_grid_on %d,%d on: %d",self.id,r,c,note))
  if #self.notes_on==0 then
    self:note_on(note)
  end
  table.insert(self.notes_on,{r,c,note})
end

function Looper:note_grid_off(r,c)
  print(string.format("[looper %d] note_grid_off %d,%d on",self.id,r,c))
  local j=0
  for i,v in ipairs(self.notes_on) do
    if v[1]==r and v[2]==c then
      j=i
    end
  end
  if j>0 then
    table.remove(self.notes_on,j)
  end
  if next(self.notes_on)==nil then
    self:notes_off()
  end
end

function Looper:rec_queue_up(x)
  print(string.format("[looper %d] rec_queue_up %d",self.id,x))
  -- don't queue up twice
  for _,v in ipairs(self.rec_queue) do
    if v==x then
      do return end
    end
  end
  table.insert(self.rec_queue,x)
  print(string.format("[looper %d] queued %d",self.id,x))
end

function Looper:is_in_rec_queue(i)
  for _,v in ipairs(self.rec_queue) do
    if v==i then
      do return true end
    end
  end
  do return false end
end

function Looper:is_recorded(i)
  return self.loops_recorded[i]
end

function Looper:is_recording(i)
  return self.rec_current==i
end

function Looper:rec_queue_down()
  if self.rec_current>0 then
    print(string.format("[looper %d] finished %d",self.id,self.rec_current))
    self.loops_recorded[self.rec_current]=true
  end
  if next(self.rec_queue)==nil then
    self.rec_current=0
    do return end
  end
  print(string.format("[looper %d] rec_queue_down",self.id))
  local x=table.remove(self.rec_queue,1)
  engine.record((self.id==1 and 0 or 8)+x,beats_total*clock.get_beat_sec(),self.id==1 and 0 or 1,"/home/we/dust/audio/ouroboros/"..os.date('%Y-%m-%d-%H%M%S').."_"..self.id..".wav")
  params:set(self.id.."loop",x)
  print(string.format("[looper %d] recording %d",self.id,x))
  self.rec_current=x
end

function Looper:redraw()
  if self.loop_db~=nil then
    screen.level(self.loop_db)
    screen.rect((self.id-1)*64,0,64,64)
    screen.fill()
  end
  screen.font_size(8)
  screen.level(15)
  screen.move(1,6)

  for i=1,8 do
    self.waveforms[i]:redraw((self.id-1)*64,i*8,4)
  end

  if self.rec_current>0 then
    screen.move((self.id-1)*64+10,self.rec_current*8+4)
    screen.text(string.format("recording %d",self.rec_current))
  end
  for _,q in ipairs(self.rec_queue) do
    screen.move((self.id-1)*64+10,q*8+4)
    screen.text(string.format("queued %d",q))
  end
end


return Looper




