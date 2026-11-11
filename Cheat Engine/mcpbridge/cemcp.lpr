program cemcp;

{
ce-mcp : MCP (Model Context Protocol) bridge for Cheat Engine

An AI client (Claude Code, Claude desktop, ...) starts this program and talks MCP to it over stdin/stdout
(one JSON-RPC message per line). This program forwards every message to the MCP server inside Cheat Engine
(Extensions\AITools\mcpserver.lua) over the named pipe \\.\pipe\cheatengine-mcp and writes the answers back.

Pipe protocol: a 4 byte little endian length followed by that many bytes of JSON, in both directions.
Cheat Engine answers every message with exactly one message. A length of 0 means there is no answer.

When Cheat Engine can not be reached, requests are answered with a JSON-RPC error that says what to do.
Diagnostics go to stderr. Nothing but MCP messages is ever written to stdout.

Options:
  --pipe <name>   use another pipe name (default: cheatengine-mcp)
  --wait <sec>    how long to wait for Cheat Engine before giving up on a request (default: 15)
  --version       print the version and exit
}

{$mode objfpc}{$H+}
{$apptype console}

uses
  windows, sysutils, classes, fpjson, jsonparser;

const
  BRIDGEVERSION='1.0';
  MAXMESSAGESIZE=64*1024*1024;

var
  pipename: string='cheatengine-mcp';
  waitseconds: integer=15;

  pipe: THandle=INVALID_HANDLE_VALUE;
  stdin_h, stdout_h, stderr_h: THandle;

  inbuf: array [0..65535] of byte;
  inbufpos: integer=0;
  inbufsize: integer=0;

procedure log(s: string);
var w: dword;
begin
  s:='ce-mcp: '+s+#13#10;
  WriteFile(stderr_h, s[1], length(s), w, nil);
end;

function writeAll(h: THandle; p: pointer; size: dword): boolean;
var w: dword;
begin
  result:=true;
  while size>0 do
  begin
    w:=0;
    if (not WriteFile(h, p^, size, w, nil)) or (w=0) then exit(false);
    inc(p, w);
    dec(size, w);
  end;
end;

function readAll(h: THandle; p: pointer; size: dword): boolean;
var r: dword;
begin
  result:=true;
  while size>0 do
  begin
    r:=0;
    if (not ReadFile(h, p^, size, r, nil)) or (r=0) then exit(false);
    inc(p, r);
    dec(size, r);
  end;
end;

function readLine(out line: string): boolean;
//reads one line from stdin (without the line terminator). Returns false at the end of the input
var
  ms: TMemoryStream;
  b: byte;
  r: dword;
begin
  result:=false;
  line:='';
  ms:=TMemoryStream.create;
  try
    while true do
    begin
      if inbufpos>=inbufsize then
      begin
        r:=0;
        if (not ReadFile(stdin_h, inbuf[0], sizeof(inbuf), r, nil)) or (r=0) then
        begin
          //end of input. A last line without a line terminator still counts
          if ms.Size>0 then break;
          exit(false);
        end;
        inbufsize:=r;
        inbufpos:=0;
      end;

      b:=inbuf[inbufpos];
      inc(inbufpos);

      if b=10 then break;
      ms.WriteByte(b);
    end;

    setlength(line, ms.Size);
    if ms.Size>0 then
      move(ms.Memory^, line[1], ms.Size);

    if (length(line)>0) and (line[length(line)]=#13) then
      setlength(line, length(line)-1);

    result:=true;
  finally
    ms.free;
  end;
end;

procedure writeLine(s: string);
begin
  s:=s+#10;
  writeAll(stdout_h, @s[1], length(s));
end;

procedure closePipe;
begin
  if pipe<>INVALID_HANDLE_VALUE then
  begin
    CloseHandle(pipe);
    pipe:=INVALID_HANDLE_VALUE;
  end;
end;

function connectPipe: boolean;
//connects to cheat engine, waiting up to waitseconds for it
var
  fullname: string;
  starttime: qword;
  err: dword;
begin
  if pipe<>INVALID_HANDLE_VALUE then exit(true);

  fullname:='\\.\pipe\'+pipename;
  starttime:=GetTickCount64;

  repeat
    pipe:=CreateFile(pchar(fullname), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
    if pipe<>INVALID_HANDLE_VALUE then
    begin
      log('connected to Cheat Engine');
      exit(true);
    end;

    err:=GetLastError;
    if err=ERROR_PIPE_BUSY then
      WaitNamedPipe(pchar(fullname), 500) //another client is connected, or cheat engine is busy setting up
    else
      sleep(250);
  until GetTickCount64-starttime>=qword(waitseconds)*1000;

  log('could not connect to '+fullname+' (error '+inttostr(err)+')');
  result:=false;
end;

function exchange(const request: string; out answer: string): boolean;
//sends one message to cheat engine and reads the answer ('' when there is none)
var size: dword;
begin
  result:=false;
  answer:='';

  size:=length(request);
  if not writeAll(pipe, @size, 4) then exit;
  if (size>0) and (not writeAll(pipe, @request[1], size)) then exit;

  if not readAll(pipe, @size, 4) then exit;
  if size>MAXMESSAGESIZE then exit;

  setlength(answer, size);
  if (size>0) and (not readAll(pipe, @answer[1], size)) then exit;

  result:=true;
end;

function errorAnswer(const request: string; const message: string): string;
//builds a JSON-RPC error for the request. Returns '' when the request is a notification (those get no answer)
var
  d: TJSONData;
  o, e, r: TJSONObject;
  id: TJSONData;
begin
  result:='';
  d:=nil;
  try
    try
      d:=GetJSON(request);
    except
      d:=nil;
    end;

    if (d=nil) or (d.JSONType<>jtObject) then exit;
    o:=TJSONObject(d);

    id:=o.Find('id');
    if (id=nil) or (o.Find('method')=nil) then exit; //notification or an answer

    r:=TJSONObject.Create;
    try
      r.Add('jsonrpc', '2.0');
      r.Add('id', id.Clone);
      e:=TJSONObject.Create;
      e.Add('code', -32000);
      e.Add('message', message);
      r.Add('error', e);
      result:=r.AsJSON;
    finally
      r.free;
    end;
  finally
    if d<>nil then d.free;
  end;
end;

procedure parseParameters;
var i: integer;
begin
  i:=1;
  while i<=ParamCount do
  begin
    if (ParamStr(i)='--version') then
    begin
      writeLine('ce-mcp '+BRIDGEVERSION);
      halt(0);
    end
    else
    if (ParamStr(i)='--pipe') and (i<ParamCount) then
    begin
      inc(i);
      pipename:=ParamStr(i);
    end
    else
    if (ParamStr(i)='--wait') and (i<ParamCount) then
    begin
      inc(i);
      waitseconds:=StrToIntDef(ParamStr(i), waitseconds);
      if waitseconds<0 then waitseconds:=0;
    end
    else
      log('unknown parameter: '+ParamStr(i));

    inc(i);
  end;
end;

const
  NOTREACHABLE='Cheat Engine could not be reached. Start Cheat Engine, enable "Help -> MCP server (Claude Code / Claude Desktop)" in its menu, and try again.';

var
  line, answer: string;
  attempt: integer;
  ok: boolean;
begin
  stdin_h:=GetStdHandle(STD_INPUT_HANDLE);
  stdout_h:=GetStdHandle(STD_OUTPUT_HANDLE);
  stderr_h:=GetStdHandle(STD_ERROR_HANDLE);

  parseParameters;
  log('version '+BRIDGEVERSION+', pipe '+pipename);

  while readLine(line) do
  begin
    if trim(line)='' then continue;

    ok:=false;
    answer:='';

    //try twice: the connection may have been closed since the last message (cheat engine restarted)
    for attempt:=1 to 2 do
    begin
      if not connectPipe then break;

      if exchange(line, answer) then
      begin
        ok:=true;
        break;
      end;

      log('lost the connection to Cheat Engine');
      closePipe;
    end;

    if not ok then
      answer:=errorAnswer(line, NOTREACHABLE);

    if answer<>'' then
      writeLine(answer);
  end;

  closePipe;
end.
