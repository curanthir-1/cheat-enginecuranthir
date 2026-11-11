<p align="center">
    <a href="Cheat%20Engine/images">
        <img src="Cheat%20Engine/images/celogo.png" />
    </a>
</p>

<h1 align="center">Cheat Engine</h1>

Cheat Engine is a development environment focused on modding games and applications for personal use.

> **This is a community fork, and it is Claude coded.** The changes in this fork (the cleanup, the updated build,
> the new Lua APIs, the AI tools integration and these documents) were written by Claude, Anthropic's AI model,
> using [Claude Code](https://claude.com/claude-code), at the request of the fork's owner. It is not affiliated with
> or endorsed by the original Cheat Engine project. Treat it like any other unofficial build: read the changes, and
> build it yourself if you want to be sure what you are running.

# What is different here

* Based on the last public open source code (7.5 code base). **No installer, no bundled offers.**
* The ad window, the automatic update check, the first-run server list download and a routine that downloaded and
  ran a script from the web have been removed. Cheat Engine contacts nothing unless you ask it to.
* Builds with current tools (Lazarus 3.0 / FPC 3.2.2), including a one-command cross-build from Linux and a GitHub
  Actions workflow.
* An **Extensions** folder, plus the Lua APIs current extensions need.
* The **AI Tools** extension is included and updated: `Help -> Ask AI`, with your own API key (Anthropic, OpenAI,
  DeepSeek, Gemini) or a local model.

| Document | Contents |
|---|---|
| [docs/CHANGES.md](docs/CHANGES.md) | Everything that was changed, and the known limitations |
| [docs/BUILDING.md](docs/BUILDING.md) | How to build it (Linux cross-build, Windows IDE, CI) |
| [docs/AITOOLS.md](docs/AITOOLS.md) | The AI assistant: setup, privacy, what was changed, how it was tested |

# Download

Builds are produced by GitHub Actions: open the **Actions** tab of this repository, pick the latest successful
*Build* run, and download the `CheatEngine-community` artifact. Unzip it and run `Cheat Engine.exe`. Nothing is
installed; delete the folder to remove it.

The executables are not code signed, so Windows SmartScreen or your antivirus may warn about them.

# Original project

  * [Original repository](https://github.com/cheat-engine/cheat-engine)
  * [Wiki](https://wiki.cheatengine.org/index.php?title=Main_Page)
  * [Forum (alternate)](https://opencheattables.com/)
  * [Forum (alternate)](https://fearlessrevolution.com/index.php)

## Original build instructions (Windows, Lazarus IDE)

See [docs/BUILDING.md](docs/BUILDING.md) for the scripted build. The upstream instructions follow.

  1. Download Lazarus 2.2.2 from https://sourceforge.net/projects/lazarus/files/Lazarus%20Windows%2064%20bits/Lazarus%202.2.2/ First install lazarus-2.2.2-fpc-3.2.2-win64.exe and then lazarus-2.2.2-fpc-3.2.2-cross-i386-win32-win64.exe
  
  2. Run Lazarus and click on `Project->Open Project`. Select `cheatengine.lpi` from the `Cheat Engine` folder as the project.
  3. Click on `Run->Build` or press <kbd>SHIFT+F9</kbd>.
      * you can also click on `Run->Compile many Modes` (tip: select first three compile modes)
      * If you want to run or debug from the IDE on Windows you will need to run Lazarus as administrator.
      
  Do not forget to compile secondary projects you'd like to use:
  
     speedhack.lpr: Compile both 32- and 64-bit DLL's for speedhack capability
     luaclient.lpr: Compile both 32- and 64-bit DLL's for {$luacode} capability
     DirectXMess.sln: Compile for 32-bit and 64-bit for D3D overlay and snapshot capabilities
     DotNetcompiler.sln: for the cscompile lua command
     monodatacollector.sln: Compile both 32-bit and 64-bit dll's to get Mono features to inspect the .NET environment of the process    
     dotnetdatacollector.sln: Compile both 32- and 64-bit EXE's to get .NET symbols
     dotnetinvasivedatacollector.sln: Compile this managed .DLL to add support for runtime JIT support
     cejvmti.sln: Compile both 32- and 64-bit DLL's for Java inspection support
     tcclib.sln: Compile 32-32, 64-32 and 64-64 to add {$C} and {$CCODE} support in scripts
     vehdebug.lpr: Compile 32- and 64-bit DLL's to add support for the VEH debugger interface
     dbkkernel.sln: for kernelmode functions (settings->extra) You will need to build the no-sig version and either boot with unsigned driver support, or sign the driver yourself    
    
*.SLN files require visual studio (Usually 2017)
