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

  return m
end

function GGrid:grid_key(x,y,z)
  self:key_press(y,x,z==1)
  self:grid_redraw()
end

function GGrid:key_held_action(row,col)
  if col==16 then 
    -- enqueue recording
    rec_queue_up(row)
  end

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

  if row>=3 and col<=6 then
    local note=chords[clock_chord].m[row-2][col]
    if on then
      if #notes_on==0 then
        note_play(note)
      end
      table.insert(notes_on,{row-2,col,note})
    else
      print("note off")
      local j=0
      for i,v in ipairs(notes_on) do
        if v[1]==row-2 and v[2]==col then
          j=i
        end
      end
      if j>0 then
        table.remove(notes_on,j)
      end
    end
  elseif col==16 then
    if not on and time_on<20 then
      params:set("loop",row)
    end
  elseif row==2 and col==1 then 
    if on then 
     params:set("hold_change"..params:get("loop"),3-params:get("hold_change"..params:get("loop")))
    end
  end
end

function GGrid:get_visual()
  -- clear visual
  for row=1,8 do
    for col=1,self.grid_width do
      self.visual[row][col]=self.visual[row][col]-1
      if self.visual[row][col]<0 then
        self.visual[row][col]=0
      end
    end
  end

  -- illuminate current loop
  for i,loop in ipairs(rec_queue) do
    self.visual[loop][16]=9-i
  end
  self.visual[params:get("loop")][16]=15

  -- illuminate parameters
  for i,pram in ipairs(params_grid) do
    for row=9-params:get(pram..params:get("loop")),8 do
      self.visual[row][i+6]=7
    end
  end

  -- illuminate hold change
  self.visual[2][1] = params:get("hold_change"..params:get("loop"))==2 and 14 or 4

  -- illuminate currently pressed button
  for k,_ in pairs(self.pressed_buttons) do
    self.pressed_buttons[k] = self.pressed_buttons[k]+1
    local row,col=k:match("(%d+),(%d+)")
    row=tonumber(row)
    col=tonumber(col)
    if self.pressed_buttons[k]==20 then -- 1 second
      print("[ggrid] holding ",row,col,"for >1 second")
      self:key_held_action(row,col)
    end
    self.visual[row][col]=15
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
