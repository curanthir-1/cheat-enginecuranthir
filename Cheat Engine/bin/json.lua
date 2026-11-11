--json.lua : small JSON encoder/decoder for Cheat Engine Lua scripts and extensions
--usage: local json=require 'json'
--  json.encode(value)  : returns a JSON string
--  json.decode(string) : returns the Lua value (raises an error on invalid JSON)
--
--Tables are encoded as arrays when they have a metatable with isArray=true, or when they
--are a non-empty sequence (t[1]~=nil). Everything else is encoded as an object.
--Give an empty table the metatable {isArray=true} to get [] instead of {}.
--json.null can be used to explicitly encode a null value. Decoded nulls become nil.

local json={}

json.null=setmetatable({},{__tostring=function() return 'null' end})

local escapes={['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'}

local function encodeString(s)
  --escape control characters and replace invalid UTF-8 sequences so the output is always valid JSON
  local out={}
  local i=1
  local len=#s
  while i<=len do
    local c=s:byte(i)
    if c<0x80 then
      local ch=s:sub(i,i)
      if escapes[ch] then
        out[#out+1]=escapes[ch]
      elseif c<0x20 or c==0x7f then
        out[#out+1]=string.format('\\u%04x',c)
      else
        out[#out+1]=ch
      end
      i=i+1
    else
      local n
      if c>=0xc2 and c<=0xdf then n=1
      elseif c>=0xe0 and c<=0xef then n=2
      elseif c>=0xf0 and c<=0xf4 then n=3
      end

      local valid=n~=nil and (i+n<=len)
      if valid then
        for j=1,n do
          local cc=s:byte(i+j)
          if cc<0x80 or cc>0xbf then valid=false break end
        end
      end

      if valid then
        out[#out+1]=s:sub(i,i+n)
        i=i+n+1
      else
        out[#out+1]='\\ufffd'
        i=i+1
      end
    end
  end
  return '"'..table.concat(out)..'"'
end

local function isArray(t)
  local mt=getmetatable(t)
  if mt and mt.isArray~=nil then
    return mt.isArray==true
  end
  return t[1]~=nil
end

local encodeValue

local function encodeTable(t, seen)
  if seen[t] then error('json.encode: circular reference') end
  seen[t]=true

  local parts={}
  if isArray(t) then
    local n=0
    for k in pairs(t) do
      if type(k)=='number' and k>n and math.floor(k)==k then n=k end
    end
    for i=1,n do
      parts[i]=encodeValue(t[i], seen)
    end
    seen[t]=nil
    return '['..table.concat(parts,',')..']'
  else
    local keys={}
    for k in pairs(t) do
      local tk=type(k)
      if tk=='string' or tk=='number' then keys[#keys+1]=k end
    end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do
      local v=t[k]
      local tv=type(v)
      if tv~='function' and tv~='userdata' and tv~='thread' then
        parts[#parts+1]=encodeString(tostring(k))..':'..encodeValue(v, seen)
      end
    end
    seen[t]=nil
    return '{'..table.concat(parts,',')..'}'
  end
end

encodeValue=function(v, seen)
  local tv=type(v)
  if v==nil or v==json.null then
    return 'null'
  elseif tv=='boolean' then
    return v and 'true' or 'false'
  elseif tv=='number' then
    if v~=v or v==math.huge or v==-math.huge then return 'null' end
    if math.type(v)=='integer' then return string.format('%d',v) end
    if v==math.floor(v) and math.abs(v)<1e15 then return string.format('%d',v) end
    local r=string.format('%.14g',v)
    if tonumber(r)~=v then r=string.format('%.17g',v) end
    return r
  elseif tv=='string' then
    return encodeString(v)
  elseif tv=='table' then
    return encodeTable(v, seen)
  else
    --userdata, functions, etc.. can not be represented. Give a readable placeholder
    return encodeString('<'..tv..'>')
  end
end

function json.encode(v)
  return encodeValue(v, {})
end


--decoder
local function decodeError(str, pos, msg)
  error(string.format('json.decode: %s at position %d', msg, pos), 0)
end

local function skipWhitespace(str, pos)
  local _,e=str:find('^[ \t\r\n]*', pos)
  return e+1
end

local function codepointToUTF8(cp)
  if cp<0x80 then
    return string.char(cp)
  elseif cp<0x800 then
    return string.char(0xc0+(cp>>6), 0x80+(cp&0x3f))
  elseif cp<0x10000 then
    return string.char(0xe0+(cp>>12), 0x80+((cp>>6)&0x3f), 0x80+(cp&0x3f))
  else
    return string.char(0xf0+(cp>>18), 0x80+((cp>>12)&0x3f), 0x80+((cp>>6)&0x3f), 0x80+(cp&0x3f))
  end
end

local unescapes={['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t'}

local function decodeString(str, pos)
  --pos is at the opening quote
  local out={}
  local i=pos+1
  while true do
    local s,e=str:find('["\\]', i)
    if not s then decodeError(str, pos, 'unterminated string') end
    if s>i then out[#out+1]=str:sub(i,s-1) end

    if str:sub(s,s)=='"' then
      return table.concat(out), s+1
    end

    local c=str:sub(s+1,s+1)
    if c=='u' then
      local hex=str:match('^%x%x%x%x', s+2)
      if not hex then decodeError(str, s, 'invalid unicode escape') end
      local cp=tonumber(hex,16)
      i=s+6
      if cp>=0xd800 and cp<=0xdbff then
        --surrogate pair
        local hex2=str:match('^\\u(%x%x%x%x)', i)
        local cp2=hex2 and tonumber(hex2,16)
        if cp2 and cp2>=0xdc00 and cp2<=0xdfff then
          cp=0x10000+((cp-0xd800)<<10)+(cp2-0xdc00)
          i=i+6
        else
          cp=0xfffd
        end
      elseif cp>=0xdc00 and cp<=0xdfff then
        cp=0xfffd
      end
      out[#out+1]=codepointToUTF8(cp)
    elseif unescapes[c] then
      out[#out+1]=unescapes[c]
      i=s+2
    else
      decodeError(str, s, 'invalid escape character')
    end
  end
end

local decodeValue

local function decodeArray(str, pos)
  local result=setmetatable({},{isArray=true})
  local n=0
  pos=skipWhitespace(str, pos+1)
  if str:sub(pos,pos)==']' then return result, pos+1 end

  while true do
    local v
    v,pos=decodeValue(str, pos)
    n=n+1
    result[n]=v
    pos=skipWhitespace(str, pos)
    local c=str:sub(pos,pos)
    if c==',' then
      pos=skipWhitespace(str, pos+1)
    elseif c==']' then
      return result, pos+1
    else
      decodeError(str, pos, "expected ',' or ']'")
    end
  end
end

local function decodeObject(str, pos)
  local result={}
  pos=skipWhitespace(str, pos+1)
  if str:sub(pos,pos)=='}' then return result, pos+1 end

  while true do
    if str:sub(pos,pos)~='"' then decodeError(str, pos, 'expected a string key') end
    local k
    k,pos=decodeString(str, pos)
    pos=skipWhitespace(str, pos)
    if str:sub(pos,pos)~=':' then decodeError(str, pos, "expected ':'") end
    pos=skipWhitespace(str, pos+1)
    local v
    v,pos=decodeValue(str, pos)
    result[k]=v
    pos=skipWhitespace(str, pos)
    local c=str:sub(pos,pos)
    if c==',' then
      pos=skipWhitespace(str, pos+1)
    elseif c=='}' then
      return result, pos+1
    else
      decodeError(str, pos, "expected ',' or '}'")
    end
  end
end

decodeValue=function(str, pos)
  local c=str:sub(pos,pos)
  if c=='{' then
    return decodeObject(str, pos)
  elseif c=='[' then
    return decodeArray(str, pos)
  elseif c=='"' then
    return decodeString(str, pos)
  elseif str:sub(pos,pos+3)=='true' then
    return true, pos+4
  elseif str:sub(pos,pos+4)=='false' then
    return false, pos+5
  elseif str:sub(pos,pos+3)=='null' then
    return nil, pos+4
  else
    local num=str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
    if num and num~='' then
      local v=math.tointeger(num) or tonumber(num)
      if v~=nil then
        return v, pos+#num
      end
    end
    decodeError(str, pos, 'unexpected character')
  end
end

function json.decode(str)
  if type(str)~='string' then
    error('json.decode: expected a string, got '..type(str), 0)
  end

  local pos=skipWhitespace(str, 1)
  if pos>#str then
    error('json.decode: empty input', 0)
  end

  local v
  v,pos=decodeValue(str, pos)
  pos=skipWhitespace(str, pos)
  if pos<=#str then
    decodeError(str, pos, 'trailing garbage')
  end
  return v
end

return json
