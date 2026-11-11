--MCP (Model Context Protocol) server for the AI tools
--
--This exposes the tools registered with registerAITool to an external AI client, such as Claude Code or the
--Claude desktop app, so the assistant of a subscription can drive Cheat Engine instead of an API key.
--
--How it works:
--  AI client  <--stdio (MCP, JSON-RPC)-->  ce-mcp.exe  <--named pipe-->  this script inside Cheat Engine
--
--The bridge (ce-mcp.exe) only forwards messages. Every message on the pipe is a 4 byte length followed by that
--many bytes of JSON (one JSON-RPC message). This script answers every request with exactly one such message; a
--length of 0 means "no answer" (used for notifications).
--
--The server is off until it is enabled in the menu: Help -> MCP server (Claude Code / Claude Desktop).
--Any program running on this computer can connect while it is enabled, and can then use the tools (which
--include running Lua code and writing memory), so only enable it when you use it.

local json=require 'json'
local settings=getSettings('AITOOLS',true)

MCP_PIPENAME='cheatengine-mcp'

local SUPPORTED_PROTOCOLS={['2024-11-05']=true, ['2025-03-26']=true, ['2025-06-18']=true}
local LATEST_PROTOCOL='2025-06-18'

local running=false
local serverthread=nil
local statusMenuItem=nil

local function rpcResult(id, result)
  return json.encode({jsonrpc='2.0', id=id, result=result})
end

local function rpcError(id, code, message)
  if id==nil then id=json.null end
  return json.encode({jsonrpc='2.0', id=id, error={code=code, message=message}})
end

local function buildToolList()
  local names={}
  for name,tool in pairs(aitools) do
    if tool.enabled and tool.functionToCall then
      names[#names+1]=name
    end
  end
  table.sort(names)

  local list={}
  for i=1,#names do
    local tool=aitools[names[i]]
    local schema=convertSchemaToOpenAI(tool.parameters) --plain JSON schema with lowercase types
    if schema.type==nil then schema.type='object' end
    if schema.properties==nil then schema.properties={} end
    list[i]={name=names[i], description=tool.description or '', inputSchema=schema}
  end
  setmetatable(list,{isArray=true})
  return list
end

local function callTool(name, arguments)
  local tool=aitools[name]
  if tool==nil or not tool.enabled or tool.functionToCall==nil then
    return {content={{type='text', text='Unknown tool: '..tostring(name)}}, isError=true}
  end

  if type(arguments)~='table' then arguments={} end

  local ok,res=pcall(tool.functionToCall, arguments)
  local text
  local isError=false
  if not ok then
    text='The tool raised an error: '..tostring(res)
    isError=true
  else
    if type(res)=='table' then
      if res.Error~=nil or res.error~=nil then isError=true end
      local encoded,encodedtext=pcall(json.encode, res)
      if encoded then
        text=encodedtext
      else
        text='The tool result could not be encoded: '..tostring(encodedtext)
        isError=true
      end
    elseif res==nil then
      text='The tool returned nothing'
    else
      text=tostring(res)
    end
  end

  return {content={{type='text', text=text}}, isError=isError}
end

local function getInstructions()
  local text='These tools control the Cheat Engine instance running on this computer: open a process, scan and read '..
             'its memory, disassemble code, set watchpoints, manage the address list and run Cheat Engine Lua or '..
             'auto assembler scripts. Addresses are hexadecimal strings unless a tool says otherwise. Start with '..
             'getOpenedProcessName; use openProcess when no process is opened yet.'

  local catalog=(getSkillsCatalogPrompt and getSkillsCatalogPrompt()) or ''
  if catalog~='' then
    text=text..'\n\n'..catalog
  end
  return text
end

--handles one JSON-RPC message (string) and returns the answer (string), or nil when there is no answer
function mcpHandleMessage(text)
  local ok,msg=pcall(json.decode, text)
  if not ok or type(msg)~='table' then
    return rpcError(nil, -32700, 'Parse error')
  end

  if getmetatable(msg) and getmetatable(msg).isArray then
    return rpcError(nil, -32600, 'Batch requests are not supported')
  end

  local id=msg.id
  local method=msg.method

  if type(method)~='string' then
    if id~=nil and (msg.result~=nil or msg.error~=nil) then
      return nil --an answer to something we never asked. Ignore it
    end
    return rpcError(id, -32600, 'Invalid request')
  end

  if id==nil then
    return nil --a notification (notifications/initialized, notifications/cancelled, ...). Nothing to do or answer
  end

  local params=msg.params
  if type(params)~='table' then params={} end

  if method=='initialize' then
    local version=params.protocolVersion
    if not SUPPORTED_PROTOCOLS[version] then
      version=LATEST_PROTOCOL
    end

    return rpcResult(id, {
      protocolVersion=version,
      capabilities={tools={listChanged=false}},
      serverInfo={name='cheat-engine', title='Cheat Engine', version=tostring(getCEVersion())},
      instructions=getInstructions()
    })
  elseif method=='ping' then
    return rpcResult(id, {})
  elseif method=='tools/list' then
    return rpcResult(id, {tools=buildToolList()})
  elseif method=='tools/call' then
    if type(params.name)~='string' then
      return rpcError(id, -32602, 'Missing tool name')
    end
    return rpcResult(id, callTool(params.name, params.arguments))
  elseif method=='resources/list' then
    return rpcResult(id, {resources=setmetatable({},{isArray=true})})
  elseif method=='prompts/list' then
    return rpcResult(id, {prompts=setmetatable({},{isArray=true})})
  else
    return rpcError(id, -32601, 'Method not found: '..method)
  end
end

local function serveClient(pipe)
  --returns when the client disconnects or the server is stopped
  pipe.Timeout=0 --wait as long as it takes for the next request

  while running and pipe.connected do
    local size=pipe.readDword()
    if size==nil or not pipe.connected then break end
    if not running then break end

    local answer
    if size>0 then
      if size>64*1024*1024 then break end --nonsense. Drop the connection
      local request=pipe.readString(size)
      if request==nil or not pipe.connected then break end

      local ok,r=pcall(mcpHandleMessage, request)
      if ok then
        answer=r
      else
        answer=rpcError(nil, -32603, 'Internal error: '..tostring(r))
      end
    end

    if answer then
      pipe.writeDword(#answer)
      pipe.writeString(answer)
    else
      pipe.writeDword(0)
    end
  end
end

local function updateMenu()
  if statusMenuItem then
    statusMenuItem.Checked=running
  end
end

function mcpServerIsRunning()
  return running
end

function mcpServerStart()
  if running then return true end
  running=true

  serverthread=createThread(function(t)
    t.Name='MCP server'
    while running do
      local pipe=createPipe(MCP_PIPENAME, 256*1024, 256*1024)
      if pipe==nil or not pipe.valid then
        --the name is taken (another cheat engine instance has its MCP server enabled). Try again in a while
        if pipe then pipe.destroy() end
        for i=1,20 do
          if not running then break end
          sleep(100)
        end
      else
        pipe.acceptConnection() --blocks till a client (or mcpServerStop) connects
        if running then
          pcall(serveClient, pipe)
        end
        pipe.destroy()
      end
    end
  end)

  synchronize(updateMenu)
  return true
end

function mcpServerStop()
  if not running then return end
  running=false

  --the server thread is waiting for a client (or for the next request). Connecting and disconnecting wakes it up
  local c=connectToPipe(MCP_PIPENAME, 500)
  if c then c.destroy() end

  serverthread=nil
  updateMenu()
end

local function addMenuItem()
  local mi=createMenuItem(MainForm)
  mi.Caption=translate('MCP server (Claude Code / Claude Desktop)')
  mi.Hint=translate('Lets an AI client on this computer use the Cheat Engine AI tools through ce-mcp.exe')
  mi.OnClick=function()
    if running then
      mcpServerStop()
      settings.MCPServer='0'
    else
      if settings.MCPServerExplained~='1' then
        local r=messageDialog(translate('While the MCP server is enabled, an AI client that you connect to it (for example Claude Code or the Claude desktop app, through ce-mcp.exe) can use the Cheat Engine AI tools. That includes running Lua code inside Cheat Engine and reading and writing the memory of the opened process, without asking you first.\n\nAny program running on this computer can connect while it is enabled.\n\nEnable the MCP server? It will also be started automatically the next time Cheat Engine starts, until you turn it off here.'), mtConfirmation, mbYes, mbNo)
        if r~=mrYes then return end
        settings.MCPServerExplained='1'
      end
      mcpServerStart()
      settings.MCPServer='1'
    end
    updateMenu()
  end

  MainForm.miHelp.insert(MainForm.miLuaDocumentation.MenuIndex, mi)
  statusMenuItem=mi
  updateMenu()
end

local ok,err=pcall(addMenuItem)
if not ok then
  print('MCP server: could not add the menu item: '..tostring(err))
end

if settings.MCPServer=='1' then
  mcpServerStart()
end
