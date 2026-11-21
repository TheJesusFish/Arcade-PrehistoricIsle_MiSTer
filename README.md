
# SNK M68000 (Prehistoric Isle) FPGA Implementation

FPGA compatible core of SNK M68000 (Prehistoric Isle in 1930 based) arcade hardware for [**MiSTerFPGA**](https://github.com/MiSTer-devel/Main_MiSTer/wiki) written by **Erin Olafson** with assistance from [**atrac17**](https://github.com/atrac17).

The intent is for this core to be a 1:1 playable implementation of Prehistoric Isle in 1930 arcade hardware. Pending PCB verification, on loan from [**XtraSmiley**](https://twitter.com/Xtrasmiley).

<img width="" height="" src="https://github.com/va7deo/PrehistoricIsle/assets/32810066/f206a42f-416a-455d-8359-8d2549b0ed8a">

## PrehistoricIsleMD

This is the MD version of the core (`Arcade-PrehistoricIsleMD_YYYYMMDD.rbf`, MRAs `... [MD].mra` with `<rbf>PrehistoricIsleMD</rbf>`). The emulation is unchanged: CPU, interrupt, video and sound timing and output are those of the previous release. The changes:

- Framework updated to the current [**Template_MiSTer**](https://github.com/MiSTer-devel/Template_MiSTer) (`sys/`, Template project layout, HDMI PLL output on counter C5 per Template_MiSTer issue #112).
- CPU and sound modules re-imported from their original repositories at the commits the previous release used (table below).
- JTFRAME removed; the audio mixer is native code with the same output.
- Every clock is `clk_sys` with clock enables, so the whole core is timing-constrained.
- **Save states**: hold **L**, then **Down** saves, **Up** restores, **Left / Right** selects the slot (also Alt+F1 / F1 and the OSD, all on the selected slot). With "Autoincrement Slot" on, the selection moves to the next slot once a save has finished.
- **High scores** are restored from and saved to `config/nvram/<MRA name>.nvm` (entries from MAME `hiscore.dat`); saved when the OSD is opened (OSD option "Autosave Hiscores") or with "Save Hiscores".
- **Controls**: each controller drives its own player's Start and Coin; player 2 is controller 2. "Swap P1/P2 Joystick" swaps the whole controllers.
- **DIP switches** follow MAME (`-listxml`), except where the game's own DIP sheet differs (see below). Changing a DIP in the OSD no longer resets the game; it takes effect with "Reset to apply". DIP and high-score downloads no longer reach the ROM loader; only the ROM download does.
- Fixed: the OSD H/V-sync position and width adjustments (negative values acted as large positive ones, and some settings removed the V-sync pulse).
- Fixed: holding the game in reset (F3, OSD Reset, core load) no longer stops the video sync; the game still starts at the beginning of a frame.
- The OSD "Video Mode NTSC/PAL" item was removed (Y/C is set by the framework).

Button layout (changed from the previous release, so controller maps saved for these setnames need to be redone):

| Button | Default | Function |
|---|---|---|
| Shoot | A | PUSH 1 |
| Option | B | PUSH 2 |
| Start | Start | 1P / 2P Start (controller 1 / 2) |
| Coin | Select | Coin 1 / Coin 2 (controller 1 / 2) |
| Pause | R | Pause |
| Save States | L | hold for save-state controls |

Button names are from the control panel figure of the game's manual (`doc/Prehisle Manual.pdf`, p.3: PUSH 1 SHOOT, PUSH 2 OPTION). The game uses two buttons; the JAMMA third button input is still read from the keyboard (Space / Q) as before.

DIP switches: MAME 0.288 for all sets, with these differences taken from the game itself:

- **Prehistoric Isle in 1930 (US)**: Coinage as on the US manual's DIP sheet (Free Play, 1 Coin/2 Credits, 2 Coins/1 Credit, 1 Coin/1 Credit), which is how the US program decodes the switches.
- The US manual lists Bonus Life "100000/150000"; the game's bonus table (all sets) gives 100K / 200K as MAME says, so MAME's label is kept.

Note: the US set keeps a separate credit count for each side: Coin 1 (controller 1's Select, key 5) credits player 1 and Coin 2 (controller 2's Select, key 6) credits player 2.

Save states restore the game exactly. The YM3812's internal timer and envelope counters are not saved (they are inside the unmodified jtopl module): its registers are restored, so the music continues, but notes that are sounding restart their envelopes and the music tempo phase may shift by up to one timer tick.

A save made in the Native refresh mode near the end of a frame records a line that the shorter NTSC frame does not have. Such a save is not restored while Refresh Rate is NTSC (OSD message "Restore needs Native refresh"); switch to Native to restore it. A save interrupted by a reset leaves its slot empty rather than holding a partial state.

## External Modules

| Module | Function | Source (commit) | Author |
|---|---|---|---|
| [**fx68k**](https://github.com/ijor/fx68k) | [**Motorola 68000 CPU**](https://en.wikipedia.org/wiki/Motorola_68000) | ijor/fx68k @ 0602ee4 | Jorge Cwik |
| [**T80**](https://github.com/MiSTer-devel/NeoGeo_MiSTer/tree/master/rtl/cpu/T80) | [**Zilog Z80 CPU**](https://en.wikipedia.org/wiki/Zilog_Z80) | MiSTer-devel/NeoGeo_MiSTer rtl/cpu/T80 @ 90a8350 | Daniel Wallner, MiSTer changes by Sorgelig |
| [**jtopl2**](https://github.com/jotego/jtopl) | [**Yamaha OPL 2**](https://en.wikipedia.org/wiki/Yamaha_OPL#OPL2) | jotego/jtopl @ d3e73f1 | Jose Tejada |
| [**jt7759**](https://github.com/jotego/jt7759) | [**NEC µPD7759**](https://github.com/jotego/jt7759) | jotego/jt7759 @ c23dc9f | Jose Tejada |
| [**mem**](https://github.com/MiSTer-devel/Arcade-Rygar_MiSTer/tree/master/src/mem) | SDRAM Controller / Rom Downloader | Arcade-Rygar_MiSTer src/mem | Josh Bassett, modified by Erin Olafson |
| [**pause**](https://github.com/JimmyStones/Pause_MiSTer) | Pause handling | Pause_MiSTer v0002 | Jim Gregory |
| [**save states**](https://github.com/MiSTer-devel/Arcade-TaitoF2_MiSTer) | Save-state stream, DDR3 interface, save-state UI (`rtl/savestate/`) | Arcade-TaitoF2_MiSTer @ 9438df9 | Martin Donlon |
| [**core_template**](https://github.com/MiSTer-devel/Template_MiSTer) | MiSTer Framework Template | Template_MiSTer @ d6324f2 | sorgelig and contributors |

The save-state sequencer and the high-score module of this core are modelled on Arcade-TaitoF2_MiSTer (save states) and Arcade-RaizingMD_MiSTer / Arcade-IGSPGM_MiSTer (NVRAM high scores).

# Known Issues / Tasks

- [**OPL2 Audio**](https://github.com/jotego/jtopl/issues/11)  **[Issue]**  

# PCB Check List

FPGA implementation loosely based on [**mame source**](https://github.com/mamedev/mame/blob/master/src/mame/snk/prehisle.cpp) and will be verified against an authentic SNK Prehistoric Isle in 1930 PCB.

### Clock Information

| H-Sync      | V-Sync      | Source                                                                                                                                                                      |
|-------------|-------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 15.625kHz   | 54.065743Hz | [**OSSC**](https://user-images.githubusercontent.com/32810066/187164273-01cf0a2e-6eb4-47ce-ba79-830a7e977212.jpg) <br> [**OSSC**](https://mametesters.org/view.php?id=5939) |

### Crystal Oscillators

| Freq (MHz) | Use                                                   |
|------------|-------------------------------------------------------|
| 4.000      | Z80 (4 MHz)<br>YM3812CLK (4 MHz)<br>µPD7759 (640 KHz) |
| 18.000     | M68000 (9 MHz)                                        |
| 12.000     | Pixel CLK (6 MHz)                                     |

**Pixel clock:** 6.00 MHz

**Estimated geometry:**

    384 pixels/line
  
    289 pixels/line

### Main Components

| Chip                                                                   | Use           |
|------------------------------------------------------------------------|---------------|
| [**Motorola 68000 CPU**](https://en.wikipedia.org/wiki/Motorola_68000) | Main CPU      |
| [**Zilog Z80 CPU**](https://en.wikipedia.org/wiki/Zilog_Z80)           | Sound CPU     |
| [**Yamaha YM3812**](https://en.wikipedia.org/wiki/Yamaha_OPL#OPL2)     | OPL2          |
| [**NEC µPD7759**](https://github.com/jotego/jt7759)                    | ADPCM Decoder |

# Core Features

### Video Timings

- Video timings can be modified if you experience sync issues with CRT or modern displays; this will alter gameplay from it's original state.

| Refresh Rate      | Timing Parameter           | HTOTAL | VTOTAL |
|-------------------|----------------------------|--------|--------|
| 15.63kHz / 54.1Hz | PCB                        | 384    | 289    |
| 15.63kHz / 59.2Hz | NTSC (Closest Spec) / MAME | 384    | 264    |

### P1/P2 Input Swap Option

- There is a toggle to swap inputs from Player 1 to Player 2. This only swaps inputs for the joystick, it does not effect keyboard inputs.

### Audio Options

- There is a toggle to disable playback of OPL2 / µPD7759 audio. There are toggles to adjust the volume of OPL2 and the µPD7759 audio.

### Overclock Options

- There is a toggle to increase the M68000 frequency from 9MHz to 12MHz; this will alter gameplay from it's original state.

### Native Y/C Output

- Native Y/C ouput is possible with the [**analog I/O rev 6.1 pcb**](https://github.com/MiSTer-devel/Main_MiSTer/wiki/IO-Board). Using the following cables, [**HD-15 to BNC cable**](https://www.amazon.com/StarTech-com-Coax-RGBHV-Monitor-Cable/dp/B0033AF5Y0/) will transmit Y/C over the green and red lines. Choose an appropriate adapter to feed [**Y/C (S-Video)**](https://www.amazon.com/MEIRIYFA-Splitter-Extension-Monitors-Transmission/dp/B09N19XZJQ) to your display.

### H/V Adjustments

- There are two H/V toggles, H/V-sync positioning adjust and H/V-sync width adjust. Positioning will move the display for centering on CRT display. The sync width adjust can be used to for sync issues (rolling, flagging etc) without modifying the video timings.

### Scandoubler Options

- Additional toggle to enable the scandoubler without changing ini settings and new scanline option for 100% is available, this draws a black line every other frame. Below is an example.

<table><tr><th>Scandoubler Fx</th><th>Scanlines 25%</th><th>Scanlines 50%</th><th>Scanlines 75%</th><th>Scanlines 100%</th><tr><td><br> <p align="center"><img width="128" height="112" src="https://user-images.githubusercontent.com/32810066/191252689-acfb3610-89d9-4ec2-9f69-dc285d9cf6dd.png"></td><td><br> <p align="center"><img width="128" height="112" src="https://user-images.githubusercontent.com/32810066/191252701-2cd221dd-0e31-49c3-89ef-e0dcafdd4916.png"></td><td><br> <p align="center"><img width="128" height="112" src="https://user-images.githubusercontent.com/32810066/191252717-b4f7bd03-5e76-4e43-b055-1a418589a169.png"></td><td><br> <p align="center"><img width="128" height="112" src="https://user-images.githubusercontent.com/32810066/191252728-638d1a44-07ff-4060-918f-ebfb79a6f206.png"></td><td><br> <p align="center"><img width="128" height="112" src="https://user-images.githubusercontent.com/32810066/191252737-be45e006-c172-471a-80dd-ee1335cd8ede.png"></td></tr></table>

# PCB Information / Control Layout

| Title                                               | Joystick | Service Menu                                                                                                       | Dip Switches                                                                                                    | Shared Controls | Dip Default | PCB Information                                                                                                                                                                                                                                                                                                                                                                            |
|-----------------------------------------------------|----------|--------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------|-----------------|-------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Prehistoric Isle in 1930<br><br>Genshitou 1930s** | 8-Way    | [**Service Menu**](https://github.com/va7deo/PrehistoricIsle/assets/32810066/26f692bc-f688-4574-83e1-d96bcaba4d16) | [**Dip Sheet**](https://github.com/va7deo/PrehistoricIsle/assets/32810066/4c8ba229-5b43-4003-8d5e-5df6dacb203a) | Co-Op           | **Upright** | There is a level select dipswitch not documented in the manual, when toggled you can select to start at any stage or view the end credits. <br><br> There are two hidden cheat functions when setting dipswitches in certain positions. These enable a "pause" function which halts the CPU and infinite lives. <br><br> These are labeled clearly in the dip switch menu for convenience. |

<br>

### Keyboard Handler

- Keyboard inputs mapped to mame defaults for all functions.

<br>

|Services|Coin/Start|
|--|--|
|<table> <tr><th>Functions</th><th>Keymap</th></tr><tr><td>Test</td><td>F2</td></tr><tr><td>Reset</td><td>F3</td></tr><tr><td>Service</td><td>9</td></tr><tr><td>Pause</td><td>P</td></tr> </table> | <table><tr><th>Functions</th><th>Keymap</th><tr><tr><td>P1 Start</td><td>1</td></tr><tr><td>P2 Start</td><td>2</td></tr><tr><td>P1 Coin</td><td>5</td></tr><tr><td>P2 Coin</td><td>6</td></tr> </table>|

|Player 1|Player 2|
|--|--|
|<table> <tr><th>Functions</th><th>Keymap</th></tr><tr><td>P1 Up</td><td>Up</td></tr><tr><td>P1 Down</td><td>Down</td></tr><tr><td>P1 Left</td><td>Left</td></tr><tr><td>P1 Right</td><td>Right</td></tr><tr><td>P1 Bttn 1</td><td>L-Ctrl</td></tr><tr><td>P1 Bttn 2</td><td>L-Alt</td></tr><tr><td>P1 Bttn 3</td><td>Space</td></tr> </table> | <table> <tr><th>Functions</th><th>Keymap</th></tr><tr><td>P2 Up</td><td>R</td></tr><tr><td>P2 Down</td><td>F</td></tr><tr><td>P2 Left</td><td>D</td></tr><tr><td>P2 Right</td><td>G</td></tr><tr><td>P2 Bttn 1</td><td>A</td></tr><tr><td>P2 Bttn 2</td><td>S</td></tr><tr><td>P2 Bttn 3</td><td>Q</td></tr> </table>|

# Licensing

Contact the author for special licensing needs. Otherwise follow the GPLv2 license attached.
