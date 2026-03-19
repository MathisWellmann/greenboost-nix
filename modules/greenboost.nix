flake:

{ config, lib, pkgs, ... }:

let
  cfg = config.services.greenboost;
  inherit (lib) mkEnableOption mkOption types mkIf mkMerge;

  greenboost-module = flake.packages.${pkgs.system}.greenboost-module.override {
    kernel = config.boot.kernelPackages.kernel;
  };
  greenboost-shim = flake.packages.${pkgs.system}.greenboost-shim;
in
{
  options.services.greenboost = {

    enable = mkEnableOption "GreenBoost 3-tier GPU memory extension";

    physicalVramGb = mkOption {
      type = types.int;
      default = 12;
      description = "Tier 1: physical GPU VRAM in GB (auto-detected by setup, but set explicitly for NixOS reproducibility).";
    };

    virtualVramGb = mkOption {
      type = types.int;
      default = 51;
      description = "Tier 2: system RAM pool size in GB for the DDR4 DMA-BUF pool.";
    };

    safetyReserveGb = mkOption {
      type = types.int;
      default = 12;
      description = "Tier 2: minimum free system RAM in GB that GreenBoost will never touch.";
    };

    nvmeSwapGb = mkOption {
      type = types.int;
      default = 64;
      description = "Tier 3: NVMe swap capacity in GB.";
    };

    nvmePoolGb = mkOption {
      type = types.int;
      default = 58;
      description = "Tier 3: GreenBoost soft cap on T3 allocations in GB.";
    };

    pcoresMaxCpu = mkOption {
      type = types.int;
      default = 15;
      description = "Highest P-core logical CPU number (for watchdog pinning). Set to (nproc - 1) on non-hybrid CPUs.";
    };

    goldenCpuMin = mkOption {
      type = types.int;
      default = 4;
      description = "First golden-core CPU (highest boost frequency).";
    };

    goldenCpuMax = mkOption {
      type = types.int;
      default = 7;
      description = "Last golden-core CPU.";
    };

    pcoresOnly = mkOption {
      type = types.bool;
      default = true;
      description = "Pin watchdog kthread to P-cores only.";
    };

    useHugepages = mkOption {
      type = types.bool;
      default = true;
      description = "Allocate 2 MB compound pages for lower TLB/DMA overhead.";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable debug logging in kernel module and CUDA shim.";
    };

    shim = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Install the CUDA LD_PRELOAD shim system-wide.";
      };

      globalPreload = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Add the shim to /etc/ld.so.preload for automatic injection into all processes.
          Safe with v2.5+ (RTLD_NOLOAD guard), but conservative users may prefer per-service injection.
        '';
      };

      vramHeadroomMb = mkOption {
        type = types.int;
        default = 2048;
        description = "Keep at least this many MB free in real VRAM before routing to overflow.";
      };
    };

    ollama = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Configure Ollama systemd service with GreenBoost environment variables.";
      };

      flashAttention = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Ollama flash attention.";
      };

      kvCacheType = mkOption {
        type = types.str;
        default = "q8_0";
        description = "Ollama KV cache quantization type.";
      };

      numCtx = mkOption {
        type = types.int;
        default = 131072;
        description = "Ollama context window size.";
      };
    };

    tune = {
      nvmeScheduler = mkOption {
        type = types.bool;
        default = true;
        description = "Set NVMe I/O scheduler to 'none' for lowest latency.";
      };

      cpuGovernor = mkOption {
        type = types.bool;
        default = true;
        description = "Set CPU frequency governor to 'performance' on P-cores.";
      };

      transparentHugepages = mkOption {
        type = types.bool;
        default = true;
        description = "Set transparent hugepages to 'always' (required for efficient T2 allocation).";
      };

      swappiness = mkOption {
        type = types.int;
        default = 10;
        description = "vm.swappiness value (lower = prefer RAM over swap).";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [

    # ── Kernel module ──────────────────────────────────────────────────
    {
      boot.extraModulePackages = [ greenboost-module ];

      boot.kernelModules = [ "greenboost" ];

      boot.extraModprobeConfig = ''
        options greenboost \
          physical_vram_gb=${toString cfg.physicalVramGb} \
          virtual_vram_gb=${toString cfg.virtualVramGb} \
          safety_reserve_gb=${toString cfg.safetyReserveGb} \
          nvme_swap_gb=${toString cfg.nvmeSwapGb} \
          nvme_pool_gb=${toString cfg.nvmePoolGb} \
          pcores_max_cpu=${toString cfg.pcoresMaxCpu} \
          golden_cpu_min=${toString cfg.goldenCpuMin} \
          golden_cpu_max=${toString cfg.goldenCpuMax} \
          pcores_only=${if cfg.pcoresOnly then "1" else "0"} \
          use_hugepages=${if cfg.useHugepages then "1" else "0"} \
          debug_mode=${if cfg.debug then "1" else "0"}
      '';
    }

    # ── Udev rules ─────────────────────────────────────────────────────
    {
      services.udev.extraRules = ''
        # GreenBoost device permissions (video group = GPU users)
        KERNEL=="greenboost", MODE="0660", GROUP="video"
      '' + lib.optionalString cfg.tune.nvmeScheduler ''

        # NVMe tuning for T3 swap performance
        ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
        ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/read_ahead_kb}="4096"
        ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="2048"
      '';
    }

    # ── CUDA shim ──────────────────────────────────────────────────────
    (mkIf cfg.shim.enable {
      environment.systemPackages = [ greenboost-shim ];

      # Global LD_PRELOAD injection (optional — off by default)
      environment.etc = mkIf cfg.shim.globalPreload {
        "ld.so.preload".text = "${greenboost-shim}/lib/libgreenboost_cuda.so\n";
      };
    })

    # ── Sysctl tuning ─────────────────────────────────────────────────
    {
      boot.kernel.sysctl = {
        "vm.swappiness" = cfg.tune.swappiness;
        "vm.dirty_ratio" = 20;
        "vm.dirty_background_ratio" = 5;
      };
    }

    # ── Transparent hugepages ──────────────────────────────────────────
    (mkIf cfg.tune.transparentHugepages {
      boot.kernelParams = [ "transparent_hugepage=always" ];
    })

    # ── CPU governor service ───────────────────────────────────────────
    (mkIf cfg.tune.cpuGovernor {
      # Use powerManagement for governor control
      powerManagement.cpuFreqGovernor = "performance";
    })

    # ── Ollama integration ─────────────────────────────────────────────
    (mkIf cfg.ollama.enable {
      systemd.services.ollama.environment = {
        LD_PRELOAD = "${greenboost-shim}/lib/libgreenboost_cuda.so";
        GREENBOOST_ACTIVE = "1";
        GREENBOOST_VRAM_HEADROOM_MB = toString cfg.shim.vramHeadroomMb;
        GREENBOOST_DEBUG = if cfg.debug then "1" else "0";
        OLLAMA_FLASH_ATTENTION = if cfg.ollama.flashAttention then "1" else "0";
        OLLAMA_KV_CACHE_TYPE = cfg.ollama.kvCacheType;
        OLLAMA_NUM_CTX = toString cfg.ollama.numCtx;
      };
    })

  ]);
}
