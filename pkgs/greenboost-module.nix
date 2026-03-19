{ lib, stdenv, fetchgit, kernel, kmod }:

stdenv.mkDerivation {
  pname = "greenboost-module";
  version = "2.5";

  src = fetchgit {
    url = "https://gitlab.com/IsolatedOctopi/nvidia_greenboost.git";
    # Pin to a specific rev for reproducibility.
    # Update this hash after running: nix-prefetch-git <url>
    rev = "main";
    sha256 = lib.fakeHash;  # replace after first build attempt
  };

  sourceRoot = "source";

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ kmod ];

  # The Makefile expects KDIR to point at the kernel build tree.
  makeFlags = [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(NIX_BUILD_TOP)/source"
  ];

  buildPhase = ''
    make ''${makeFlags[@]} modules
  '';

  installPhase = ''
    install -D greenboost.ko $out/lib/modules/${kernel.modDirVersion}/extra/greenboost.ko
    install -D greenboost_ioctl.h $out/include/greenboost/greenboost_ioctl.h
  '';

  meta = with lib; {
    description = "GreenBoost kernel module — 3-tier GPU memory pool via DMA-BUF";
    homepage = "https://gitlab.com/IsolatedOctopi/nvidia_greenboost";
    license = licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
