# GreenBoost for NixOS

NixOS flake packaging for **GreenBoost** — a 3-tier GPU memory extension (VRAM + DDR4 + NVMe) that enables running large Large Language Models (LLMs) on consumer NVIDIA GPUs. GreenBoost leverages NVMe as virtual VRAM, extending memory transparently for LLM workloads on systems with limited VRAM.

## Prerequisites

- NixOS with flake support enabled
- NVIDIA GPU with proprietary drivers (Ampere or newer recommended)
- NVIDIA kernel modules loaded: `nvidia.ko` and `nvidia-uvm.ko`
- **Note:** GreenBoost does *not* replace the official NVIDIA drivers. The NVIDIA driver stack must be intact and loaded.

---

Test line
### 1. Add the GreenBoost flake input
GreenBoost simple test line
~~~nix
inputs.greenboost.url = "github:you/greenboost-nix";

outputs = { self, nixpkgs, greenboost, ... }@inputs:
  let
    system = "x86_64-linux";
  in {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        greenboost.nixosModules.greenboost
        ./configuration.nix
      ];
    };
  };
~~~

### 2. Enable GreenBoost in `configuration.nix`

**Minimal configuration (RTX 5070, 12GB VRAM):**
~~~nix
greenboost = {
  enable = true;
  physicalVramGb = 12;
  virtualVramGb = 51;
  safetyReserveGb = 12;
  nvmeSwapGb = 64;
};
~~~

**Full configuration (RTX 5070 + i9-14900KF):**
~~~nix
greenboost = {
  enable = true;
  physicalVramGb = 12;
  virtualVramGb = 51;
  safetyReserveGb = 12;
  nvmeSwapGb = 64;
  nvmePoolGb = 58;
  pcoresMaxCpu = 15;
  goldenCpuMin = 4;
  goldenCpuMax = 7;
  pcoresOnly = true;
  shim = {
    enable = true;
    globalPreload = true;
    vramHeadroomMb = 512;
  };
  ollama = {
    enable = true;
    flashAttention = true;
    kvCacheType = "mmap";
    numCtx = 8192;
  };
  tune = {
    myOption = true;
  };
  debug = false;
};
~~~

### 3. Rebuild and verify

Rebuild your system and verify the GreenBoost installation:
~~~bash
sudo nixos-rebuild switch --flake .#myhost
~~~

Check GreenBoost kernel module and setup:
~~~bash
lsmod | grep greenboost
pool_info
greenboost-run --check
~~~

## What gets installed

| File/Component            | Purpose                                                          |
|---------------------------|-------------------------------------------------------------------|
| `greenboost.ko`           | Kernel module for VRAM+DDR4+NVMe pool                            |
| `libgreenboost_cuda.so`   | CUDA LD_PRELOAD library for CUDA memory offloading               |
| `greenboost-run`          | Wrapper utility to launch processes with GreenBoost injection     |
| Udev rules                | Automatic device setup/permissions                               |
| Sysctl config             | Kernel parameter tuning for pool                                 |
| Modprobe config           | Auto-load kernel modules on boot                                 |
| Ollama env                | NixOS integration: configure ollama for GB pool usage            |

## Per-service vs Global Injection

By default, GreenBoost is not injected globally and is instead enabled process-by-process:

- Use `greenboost-run <app>` to inject GreenBoost into specific processes (ad-hoc usage).
- To enable GreenBoost system-wide, set `shim.globalPreload = true` in your config:

~~~nix
greenboost = {
  shim.globalPreload = true;
};
~~~

## NVMe Swap Setup

To enable fast NVMe swap for the virtual VRAM extension, add to your `configuration.nix`:

~~~nix
swapDevices = [
  { device = "/dev/nvme0n1p3"; }
];
~~~

> Replace `/dev/nvme0n1p3` with your actual NVMe swap device.

## Updating the Source Hash

If you see an error about an incorrect output hash when updating GreenBoost,
temporarily set the source hash to `lib.fakeHash` in your flake, and build again:

~~~nix
src = fetchFromGitHub {
  owner = "greenboost";
  repo = "greenboost";
  rev = "<commit-hash>";
  hash = lib.fakeHash;
};
~~~

Copy the real hash from the error message, replace `lib.fakeHash` with it, and rebuild.

## Differences from Upstream

| Feature            | Upstream greenboost_setup.sh    | NixOS Flake (this package)      |
|--------------------|-------------------------------|-----------------------------------|
| Module build       | Imperative, bash script        | Declarative module option         |
| Kernel params      | Manual sysctl edits            | NixOS sysctl integration          |
| Shim install       | Manual LD_PRELOAD setup        | Optional NixOS module            |
| Udev               | Install by script              | NixOS udev rules managed          |
| Governor           | Manual                         | NixOS managed                     |
| Ollama             | Manual CUDA env setup          | Integrated (`greenboost.ollama`)  |
| Grub options       | Manual, if needed              | NixOS boot loader options         |
| exllamav3 support  | Not packaged                   | Not packaged; use devShell        |

## ExLlamaV3 / kvpress / ModelOpt

ExLlamaV3, kvpress, and ModelOpt are **not yet packaged** in this Nix flake.
To use these utilities, enter a devShell or create a Python virtual environment:

~~~bash
nix develop .#greenboost-devShell
~~~
or
~~~bash
python -m venv .venv && source .venv/bin/activate
pip install exllamav3 kvpress modelopt
~~~

## License

GreenBoost for NixOS is distributed under the GNU General Public License v2.0.

See the LICENSE file for details.
