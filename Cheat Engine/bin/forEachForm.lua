--forEachForm.lua : helpers for extensions that add functionality to Cheat Engine forms
--usage: require('forEachForm')
--
--  forEachForm(classname, function(form))          : calls the function for every existing form of the given class
--  forEachAndFutureForm(classname, function(form)) : same, but also for every form of that class created later
--
--classname is the class name of the form (e.g 'TMemoryBrowser', 'TfrmLuaEngine', 'TfrmAutoInject')

if forEachAndFutureForm then return end --already loaded

local futureHandlers={} --classname(lowercase) -> list of functions
local handled=setmetatable({},{__mode='k'}) --function -> {form userdata id -> true}
local notification

local function formID(f)
  return userDataToInteger(f)
end

local function callOnce(f, fn)
  local id=formID(f)
  local done=handled[fn]
  if done==nil then
    done={}
    handled[fn]=done
  end

  if done[id] then return end
  done[id]=true

  local ok,err=pcall(fn, f)
  if not ok then
    print('forEachForm: error in handler for '..tostring(f.ClassName)..': '..tostring(err))
  end
end

function forEachForm(classname, fn)
  local lc=classname:lower()
  for i=0,getFormCount()-1 do
    local f=getForm(i)
    if f and f.ClassName and f.ClassName:lower()==lc then
      callOnce(f, fn)
    end
  end
end

function forEachAndFutureForm(classname, fn)
  local lc=classname:lower()

  if futureHandlers[lc]==nil then
    futureHandlers[lc]={}
  end
  table.insert(futureHandlers[lc], fn)

  if notification==nil then
    notification=registerFormAddNotification(function(f)
      --the form has just been created and its components may not have been loaded yet. Handle it a moment later
      local cn=f.ClassName
      if cn==nil then return end
      local list=futureHandlers[cn:lower()]
      if list==nil then return end

      local t=createTimer(nil, false)
      t.Interval=1
      t.OnTimer=function(timer)
        timer.Enabled=false
        timer.destroy()
        for i=1,#list do
          callOnce(f, list[i])
        end
      end
      t.Enabled=true
    end)
  end

  forEachForm(classname, fn)
end
