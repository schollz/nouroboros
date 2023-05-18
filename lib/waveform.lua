local Waveform={}

function Waveform:new(args)
  local m=setmetatable({},{__index=Waveform})
  local args=args==nil and {} or args
  for k,v in pairs(args) do
    m[k]=v
  end
  m:init()
  return m
end

function Waveform:init()
  self.is_rendering=false
  self.rendering_name=nil
  self.renders={}
end

function Waveform:load(fname)
  self.queue=fname
end

function Waveform:load_()
  if self.queue==nil or rendering_waveform~=nil then
    do return end
  end
  rendering_waveform={self.id,self.loop}
  local fname=self.queue
  self.queue=nil
  self.rendering_name=fname
  self.current=fname
  _,self.basename,_=string.match(fname,"(.-)([^\\/]-%.?([^%.\\/]*))$")
  print("[waveform] doing render",fname)
  local ch,samples=audio.file_info(fname)
  local length=samples/48000
  clock.run(function()
    print(string.format("[waveform] loading %s",fname))
    softcut.buffer_read_mono(fname,0,1,-1,1,1)
    print(string.format("[waveform] rendering %2.1f sec of %s",length,fname))
    softcut.render_buffer(1,1,length,63)
  end)
end

function Waveform:upload_waveform(s)
  self.renders[self.rendering_name]=s
  rendering_waveform=nil
end

function Waveform:redraw(x,y,h)
  if self.queue~=nil then
    self:load_()
  end
  if self.current==nil or self.renders[self.current]==nil then
    do return end
  end
  screen.level(params:get(self.id.."db"..self.loop)*2)
  for i,v in ipairs(self.renders[self.current]) do
    screen.move(i+x,y)
    screen.line(i+x,y+v*h)
    screen.stroke()
    screen.move(i+x,y)
    screen.line(i+x,y-v*h)
    screen.stroke()
  end
end

return Waveform
