-- local pattern_time = require("pattern")
local GGrid={}

function GGrid:new(args)
  local m=setmetatable({},{__index=GGrid})
  local args=args==nil and {} or args

  m.grid_on=args.grid_on==nil and true or args.grid_on

  -- initiate the grid
  m.g=grid.connect()
  m.g.key=function(x,y,z)
    if m.grid_on then
      m:grid_key(x,y,z)
    end
  end
  print("grid columns: "..m.g.cols)

  -- setup visual
  m.visual={}
  m.grid_width=16
  for i=1,8 do
    m.visual[i]={}
    for j=1,m.grid_width do
      m.visual[i][j]=0
    end
  end

  -- keep track of pressed buttons
  m.pressed_buttons={}

  -- grid refreshing
  m.grid_refresh=metro.init()
  m.grid_refresh.time=0.05
  m.grid_refresh.event=function()
    if m.grid_on then
      m:grid_redraw()
    end
  end
  m.grid_refresh:start()

  m.blinks = {
    {v=0,max=15}
  }

  return m
end

function GGrid:grid_key(x,y,z)
  self:key_press(y,x,z==1)
  self:grid_redraw()
end

function GGrid:key_held_action(row,col)
  -- if col==16 then
  --   -- enqueue recording
  --   rec_queue_up(row)
  -- end

end

function GGrid:key_press(row,col,on)
  local k=row..","..col
  local time_on=0
  if on then
    self.pressed_buttons[k]=0
  else
    time_on=self.pressed_buttons[k]
    self.pressed_buttons[k]=nil
  end

  if row>=2 and row<=7 and col>=2 and col<=7 then
    -- note space
    local r = row-1
    local c = col-1
    local note=chords[clock_chord].m[r][c]
    if on then
      if #notes_on==0 then
        note_play(note)
      end
      table.insert(notes_on,{r,c,note})
    else
      print("note off")
      local j=0
      for i,v in ipairs(notes_on) do
        if v[1]==r and v[2]==c then
          j=i
        end
      end
      if j>0 then
        table.remove(notes_on,j)
      end
    end
  elseif row>=4 and row<=6 and col==8 then 
    -- arp options
    if on then 
      pset("arp_option",row-1)
    end
  elseif row==1 and col<=8 then 
    -- register recording queue
    if on then 
      rec_queue_up(col)
    end
  elseif row==8 and col<=8 then
    -- set loop
    if on then 
      params:set("loop",col)
    end
    -- if not on and time_on<20 then
    -- end
  elseif row==7 and col==8 then
    -- hold changer
    if on then
      pset("hold_change",3-pget("hold_change"))
    end
  end
end

function GGrid:get_visual()
  -- do blinking
  for i,v in ipairs(self.blinks) do 
    self.blinks[i].v = self.blinks[i].v + 1
    if self.blinks[i].v > self.blinks[i].max then 
      self.blinks[i].v = 0
    end
  end

  -- clear visual
  for row=1,8 do
    for col=1,self.grid_width do
      self.visual[row][col]=self.visual[row][col]-1
      if self.visual[row][col]<0 then
        self.visual[row][col]=0
      end
    end
  end

  -- illuminate loops in recording queu
  for i,loop in ipairs(rec_queue) do
    self.visual[1][loop]=5
  end

  -- illuminate currently recording loop
  if rec_current>0 then 
    self.visual[1][rec_current] = 15
  end

  -- illuminate loops that have data
  for loop,_ in pairs(loops_recorded) do 
    self.visual[8][loop]=5
  end

  -- illuminate current loop
  self.visual[8][params:get("loop")]=15

  -- illuminate the arp option lights
  for i,v in ipairs(arp_option_lights) do 
    self.visual[i+3][8] = v*10 + (pget("arp_option")==i and 5 or 0)
  end
  -- illuminate the hold change
  self.visual[7][8] = pget("hold_change")*10


  -- illuminate currently pressed button
  for k,_ in pairs(self.pressed_buttons) do
    self.pressed_buttons[k]=self.pressed_buttons[k]+1
    local row,col=k:match("(%d+),(%d+)")
    row=tonumber(row)
    col=tonumber(col)
    if self.pressed_buttons[k]==20 then -- 1 second
      print("[ggrid] holding ",row,col,"for >1 second")
      self:key_held_action(row,col)
    end
    self.visual[row][col]=15
  end


  -- illuminate the notes
  -- (special)
  for i=1,6 do 
    for j=1,6 do 
      local row=i+1
      local col=j+1
      if note_location_playing~=nil and note_location_playing[1]==i and note_location_playing[2]==j then
        self.visual[row][col]=15
      else
        self.visual[row][col]=loop_db[params:get("loop")]
      end
    end
  end



  return self.visual
end

function GGrid:grid_redraw()
  self.g:all(0)
  local gd=self:get_visual()
  local s=1
  local e=self.grid_width
  local adj=0
  for row=1,8 do
    for col=s,e do
      if gd[row][col]~=0 then
        self.g:led(col+adj,row,gd[row][col])
      end
    end
  end
  self.g:refresh()
end

return GGrid
