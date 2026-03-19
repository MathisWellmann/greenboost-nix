{ lib, stdenv, fetchgit, glibc }:

stdenv.mkDerivation {
  pname = "greenboost-shim";
  version = "2.5";

  src = fetchgit {
    url = "https://gitlab.com/IsolatedOctopi/nvidia_greenboost.git";
    rev = "main";
    sha256 = lib.fakeHash;  # replace after first build attempt
  };

  sourceRoot = "source";

  # No CUDA SDK dependency — the shim defines minimal CUDA types inline
  # and resolves everything at runtime via dlsym.
  buildInputs = [ glibc ];

  buildPhase = ''
    gcc -shared -fPIC -O2 -std=gnu11 \
      -o libgreenboost_cuda.so \
      greenboost_cuda_shim.c \
      -ldl -lpthread \
      -Wl,--version-script=greenboost_cuda.map
  '';

  installPhase = ''
    install -D libgreenboost_cuda.so $out/lib/libgreenboost_cuda.so
    install -D greenboost_ioctl.h    $out/include/greenboost/greenboost_ioctl.h
    install -D greenboost_cuda.map   $out/share/greenboost/greenboost_cuda.map

    # Install helper scripts
    mkdir -p $out/bin

    cat > $out/bin/greenboost-run << 'WRAPPER'
#!/usr/bin/env bash
# Convenience wrapper: greenboost-run <command> [args...]
# Sets LD_PRELOAD and GREENBOOST_ACTIVE for the target process.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
export LD_PRELOAD="''${LD_PRELOAD:+$LD_PRELOAD:}$SCRIPT_DIR/lib/libgreenboost_cuda.so"
export GREENBOOST_ACTIVE=1
exec "$@"
WRAPPER
    chmod +x $out/bin/greenboost-run
  '';

  meta = with lib; {
    description = "GreenBoost CUDA LD_PRELOAD shim — transparent VRAM overflow to system RAM";
    homepage = "https://gitlab.com/IsolatedOctopi/nvidia_greenboost";
    license = licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
