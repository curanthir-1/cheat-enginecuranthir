--apicompat.lua : Lua helper functions that newer Cheat Engine extensions (like AITools) expect,
--implemented on top of the functions this build already has.
--
--  getFunctionRange(address)               : returns start,stop of the function the address belongs to (nil on failure)
--  enumSectionsOfModule(modulename)        : returns a table of the PE sections of a loaded module
--  debug_getCurrentContextTable(extended)  : returns the registers of the currently broken thread as a table
--  debug_stacktrace(stackpointer, size)    : returns a list of probable return addresses found on the stack
--
--Functions are only defined when the build does not already provide them.

local function findModule(nameOrAddress)
  local ml=enumModules()
  if ml==nil then return nil end

  if type(nameOrAddress)=='number' then
    for i=1,#ml do
      local m=ml[i]
      if nameOrAddress>=m.Address and nameOrAddress<m.Address+(m.Size or getModuleSize(m.Name) or 0) then
        return m
      end
    end
  else
    local lc=nameOrAddress:lower()
    for i=1,#ml do
      if ml[i].Name:lower()==lc then return ml[i] end
    end
    --allow the name without the extension as well
    for i=1,#ml do
      local n=ml[i].Name:lower()
      if n:gsub('%.[^%.]*$','')==lc then return ml[i] end
    end
  end
  return nil
end

local function parsePEHeader(base)
  --returns a table with the header info of the PE image loaded at base, or nil
  local mz=readSmallInteger(base)
  if mz~=0x5a4d then return nil end

  local lfanew=readInteger(base+0x3c)
  if lfanew==nil or lfanew<=0 or lfanew>0x10000 then return nil end

  local nt=base+lfanew
  if readInteger(nt)~=0x4550 then return nil end

  local r={}
  r.base=base
  r.numberOfSections=readSmallInteger(nt+6)
  r.sizeOfOptionalHeader=readSmallInteger(nt+0x14)
  r.optionalHeader=nt+0x18
  r.is64=readSmallInteger(r.optionalHeader)==0x20b
  r.dataDirectory=r.optionalHeader+(r.is64 and 0x70 or 0x60)
  r.sectionHeaders=r.optionalHeader+r.sizeOfOptionalHeader
  if r.numberOfSections==nil or r.sizeOfOptionalHeader==nil then return nil end
  return r
end

if enumSectionsOfModule==nil then
  function enumSectionsOfModule(modulename)
    local m
    if type(modulename)=='number' then
      m=findModule(modulename)
    elseif type(modulename)=='string' then
      m=findModule(modulename)
      if m==nil then
        local a=getAddressSafe(modulename)
        if a then m=findModule(a) end
      end
    end
    if m==nil then return nil end

    local pe=parsePEHeader(m.Address)
    if pe==nil then return nil end

    local result={}
    for i=0,pe.numberOfSections-1 do
      local sh=pe.sectionHeaders+i*40
      local name=readString(sh, 8) or ''
      local characteristics=readInteger(sh+36) or 0
      if characteristics<0 then characteristics=characteristics+0x100000000 end

      local e={}
      e.Name=name
      e.Address=m.Address+(readInteger(sh+12) or 0)
      e.Size=readInteger(sh+8) or 0
      e.FileAddress=readInteger(sh+20) or 0
      e.FileSize=readInteger(sh+16) or 0
      e.Executable=(characteristics & 0x20000000)~=0
      e.Readable=(characteristics & 0x40000000)~=0
      e.Writable=(characteristics & 0x80000000)~=0
      e.ContainsCode=(characteristics & 0x20)~=0
      result[#result+1]=e
    end
    return result
  end
end

local function getFunctionRangeFromExceptionTable(address)
  --64-bit windows modules have a table describing the start and end of every (non-leaf) function
  local m=findModule(address)
  if m==nil then return nil end

  local pe=parsePEHeader(m.Address)
  if pe==nil or not pe.is64 then return nil end

  local rva=readInteger(pe.dataDirectory+3*8)
  local size=readInteger(pe.dataDirectory+3*8+4)
  if rva==nil or size==nil or rva<=0 or size<12 then return nil end

  local tableaddress=m.Address+rva
  local count=size//12
  local target=address-m.Address

  local function u32(a)
    local v=readInteger(a)
    if v==nil then return nil end
    if v<0 then v=v+0x100000000 end
    return v
  end

  local low,high=0,count-1
  while low<=high do
    local mid=(low+high)//2
    local entry=tableaddress+mid*12
    local s=u32(entry)
    local e=u32(entry+4)
    if s==nil or e==nil then return nil end

    if target<s then
      high=mid-1
    elseif target>=e then
      low=mid+1
    else
      return m.Address+s, m.Address+e-1
    end
  end
  return nil
end

local endOpcodes={['ret']=true, ['retn']=true, ['int 3']=true, ['??']=true}

local function getFunctionRangeByDisassembling(address)
  --estimate: walk back until the previous instruction looks like the end of another function (ret/int 3/padding)
  --then walk forward till the first instruction that ends this function
  local d=createDisassembler()
  local start=address
  local stop=address

  local ok=pcall(function()
    local a=address
    for i=1,4096 do
      local prev=getPreviousOpcode(a)
      if prev==nil or prev>=a or (a-prev)>15 then break end

      d.disassemble(prev)
      local ldd=d.LastDisassembleData
      local opcode=(ldd.opcode or ''):lower()
      local bytes=ldd.bytes or {}
      if endOpcodes[opcode] or opcode=='nop' or (opcode=='jmp' and i>1) or (#bytes>=2 and bytes[1]==0 and bytes[2]==0) then
        break
      end
      a=prev
    end
    start=a

    a=address
    for i=1,100000 do
      d.disassemble(a)
      local ldd=d.LastDisassembleData
      local opcode=(ldd.opcode or ''):lower()
      local bytes=ldd.bytes or {}
      if #bytes==0 then break end

      if endOpcodes[opcode] or (#bytes>=2 and bytes[1]==0 and bytes[2]==0) then
        if opcode=='ret' or opcode=='retn' then
          stop=a+#bytes-1
        else
          stop=a-1
        end
        break
      end
      a=a+#bytes
      stop=a-1
    end
  end)

  d.destroy()

  if not ok or stop<start then return nil end
  return start,stop
end

if getFunctionRange==nil then
  function getFunctionRange(address)
    if type(address)=='string' then
      address=getAddressSafe(address)
    end
    if type(address)~='number' then return nil end

    local start,stop
    local ok=pcall(function()
      start,stop=getFunctionRangeFromExceptionTable(address)
    end)
    if ok and start and stop then return start,stop end

    return getFunctionRangeByDisassembling(address)
  end
end

local gpr64={'RAX','RBX','RCX','RDX','RSI','RDI','RBP','RSP','R8','R9','R10','R11','R12','R13','R14','R15','RIP','EFLAGS'}
local gpr32={'EAX','EBX','ECX','EDX','ESI','EDI','EBP','ESP','EIP','EFLAGS'}

if debug_getCurrentContextTable==nil then
  function debug_getCurrentContextTable(extended)
    --Inside a breakpoint callback the register globals have already been filled in for the current thread.
    --Outside of one, debug_getContext refreshes them (when the debugger is broken on a thread)
    pcall(debug_getContext, extended==true)

    local names=targetIs64Bit() and gpr64 or gpr32
    local r={}
    local found=false
    for i=1,#names do
      local v=_G[names[i]]
      if type(v)=='number' then
        r[names[i]]=v
        found=true
      end
    end

    if not found then return nil end

    if extended then
      for i=0,7 do
        local v=_G['FP'..i]
        if v~=nil then r['FP'..i]=v end
      end
      for i=0,15 do
        local v=_G['XMM'..i]
        if v~=nil then r['XMM'..i]=v end
      end
    end

    return r
  end
end

if debug_stacktrace==nil then
  local function looksLikeReturnAddress(a)
    --a return address is preceded by a call instruction
    local b=readBytes(a-7, 7, true)
    if b==nil or #b<7 then return false end
    if b[3]==0xe8 then return true end                      --call rel32
    if b[6]==0xff and (b[7] & 0x38)==0x10 then return true end  --call reg / call [reg]
    if b[5]==0xff and (b[6] & 0x38)==0x10 then return true end  --call [reg+disp8]
    if b[4]==0xff and (b[5] & 0x38)==0x10 then return true end  --call [reg+reg*x+disp8]
    if b[2]==0xff and (b[3] & 0x38)==0x10 then return true end  --call [disp32] / call [reg+disp32]
    if b[1]==0xff and (b[2] & 0x38)==0x10 then return true end  --call [reg+reg*x+disp32]
    return false
  end

  function debug_stacktrace(stackpointer, size)
    local result={}
    if type(stackpointer)~='number' then return result end
    size=size or 1024

    local pointersize=targetIs64Bit() and 8 or 4
    for offset=0,size-pointersize,pointersize do
      local v=readPointer(stackpointer+offset)
      if v and v>0x10000 and inModule(v) then
        local ok,isret=pcall(looksLikeReturnAddress, v)
        if ok and isret then
          local e={}
          e.stackAddress=string.format('0x%x', stackpointer+offset)
          e.returnAddress=string.format('0x%x', v)
          e.symbol=getNameFromAddress(v)
          result[#result+1]=e
        end
      end
    end
    return result
  end
end

if tostringx==nil then
  --tostring that also shows the contents of tables
  local function tostringxInternal(v, depth, seen)
    if type(v)~='table' then
      if type(v)=='string' and depth>0 then return '"'..v..'"' end
      return tostring(v)
    end

    if seen[v] or depth>4 then return '{...}' end
    seen[v]=true

    local parts={}
    local count=0
    for k,val in pairs(v) do
      count=count+1
      if count>200 then
        parts[#parts+1]='...'
        break
      end
      parts[#parts+1]=tostring(k)..'='..tostringxInternal(val, depth+1, seen)
    end
    seen[v]=nil
    return '{'..table.concat(parts,', ')..'}'
  end

  function tostringx(v)
    return tostringxInternal(v, 0, {})
  end
end
