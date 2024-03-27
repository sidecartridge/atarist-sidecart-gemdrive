# ATARI ST Sidecart GEMDRIVE Firmware

This repository hosts the firmware code for the Sidecart Hard disk GEM drive emulator designed for Atari ST/STE/Mega systems. In tandem with the [Sidecart Raspberry Pico firmware](https://github.com/diegoparrilla/atarist-sidecart-raspberry-pico), this firmware facilitates the functioning of the Sidecart GEMDRIVE.

## Introduction

The Sidecart ROM Emulator simulates the function of Atari ST cartridges, including their contained ROM memory, in line with classic TOS Atari ST applications, as prepared by the code in this repository. However, the functionality of Sidecart extends beyond the realm of simple ROM emulation; it also has the capacity to perform various additional operations.

The Sidecart GEMDRIVE is a hard disk emulator that leverages the Sidecart ROM Emulator to simulate the function of the Atari ST hard disk GEM drive.

The source is bifurcated into:

1. The driver, an assembler program in `/src` directory within the file `gemdrive.s`.

2. A bootstrapping ROM, an assembly program housed in the `/src` directory within the file `main.s`. This ROM embeds the driver and launches it.

There is also a third file in `src` called `gemdrive_prg.s` created for testing purposes in emulators, for example.

**Note**: This ROM cannot be loaded or emulated like conventional ROMs. It has to be merged directly into the Sidecart RP2040 ROM Emulator firmware. Additional details are available in the [Sidecart Raspberry Pico firmware](https://github.com/diegoparrilla/atarist-sidecart-raspberry-pico).

Newcomers to Sidecart are encouraged to peruse the official [Sidecart ROM Emulator website](https://sidecartridge.com) for a comprehensive understanding.

## Requirements

- An Atari ST/STE/MegaST/MegaSTE computer. You can also use an emulator such as Hatari or STEEM for testing purposes, but you cannot really test the GEMDRIVE functionality there.

- The [atarist-toolkit-docker](https://github.com/diegoparrilla/atarist-toolkit-docker) is pivotal. Familiarize yourself with its installation and usage.

- A `git` client, command line or GUI, your pick.

- A Makefile attuned with GNU Make.

## Building the ROM

You don't really need an Atari ST to build the binaries, just follow these steps to build the program:

1. Clone this repository:

```
$ git clone https://github.com/diegoparrilla/atarist-sidecart-gemdrive.git
```

2. Navigate to the cloned repository:

```
cd atarist-sidecart-gemdrive
```

3. Trigger the `build.sh` script to build the ROM images:

```
./build.sh
```

4. The `dist` folder now houses the binary files: `GEMDRIVE.BIN`, which needs to be incorporated into the Sidecart RP2040 ROM Emulator firmware, and `GEMDRIVE.IMG`, a raw binary file tailored for direct emulation by SidecarT (intended for testing).

## Developing GEMDRIVE

For those inclined to tweak the ROM loader, it's possible. The GEMDRIVE is crafted in 68000 assembly and compiles via the [atarist-toolkit-docker](https://github.com/diegoparrilla/atarist-toolkit-docker).

For illustration, let's use the Hatari emulator on macOS:

1. Begin by ensuring the repository is cloned. If not:

```
$ git clone https://github.com/diegoparrilla/atarist-sidecart-gemdrive.git
```

2. Enter the cloned repository:

```
cd atarist-sidecart-gemdrive
```

3. Establish the `ST_WORKING_FOLDER` environment variable, linking it to the root directory of the cloned repository:

```
export ST_WORKING_FOLDER=<ABSOLUTE_PATH_TO_THE_FOLDER_WHERE_YOU_CLONED_THE_REPO>
```

4. Embark on your code modifications within the `/src` folder. For insights on leveraging the environment, refer to the [atarist-toolkit-docker](https://github.com/diegoparrilla/atarist-toolkit-docker) examples.

5. Leverage the provided Makefile for the build. The `stcmd` command connects with the tools in the Docker image. Engage the `_DEBUG` flag (set to 1) to activate debug messages and bypass direct ROM usage. There is also a `RELEASE_MODE` flag to enable construction for the final release. For example, to build the ROM in debug mode in an emulator this command will build a TOS file with testing data (loads an image in RAM):

```
stcmd make DEBUG_MODE=1 RELEASE_MODE=0
```

If you want to build a TOS file for testing with a Sidecart and an Atari ST computer, run this:

```
stcmd make DEBUG_MODE=1 RELEASE_MODE=1
```

If you want to build a ROM binary for the firmware to embed in the RP2040 firmware, run this:

```
stcmd make DEBUG_MODE=0 RELEASE_MODE=1
```

6. If `DEBUG_MODE=1` the outcome is `GEMDRIVE.TOS` in the `dist` folder. This file is ready for execution on the Atari ST emulator or computer. If using Hatari, you can launch it as follows (assuming `hatari` is path-accessible):

```
hatari --fast-boot true --tos-res med dist/GEMDRIVE.TOS &
```

## Releases

For releases, head over to the [Releases page](https://github.com/diegoparrilla/atarist-sidecart-gemdrive/releases). The latest release is always recommended.

Note: The build output isn't akin to standard ROM images. The release files have to be incorporated into the Sidecart RP2040 ROM Emulator firmware.

## Resources 

- [Sidecart ROM Emulator website](https://sidecartridge.com)
- [Sidecart Raspberry Pico firmware](https://github.com/diegoparrilla/atarist-sidecart-raspberry-pico) - Where the second phase of the Sidecart ROM Emulator firmware evolution unfolds.

## License

The project is licensed under the GNU General Public License v3.0. The full license is accessible in the [LICENSE](LICENSE) file.
