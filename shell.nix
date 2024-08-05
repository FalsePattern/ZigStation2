{ pkgs ? import <nixpkgs> {},
  run ? "zsh"
}: let
  fhs = pkgs.buildFHSUserEnv {
    name = "ps2dev";
    targetPkgs = pkgs: (with pkgs; [
      autoconf
      gnumake
      clang
      clang-tools
      gcc
      wget
      git
      patch
      texinfo
      bash
      file
      bison
      flex
      gettext
      gsl
      gnum4
      gmp.dev
      gmp.out
      mpfr.out
      mpfr.dev
      libmpc
      cmake
      zlib.dev
      zlib.out
    ]);
    runScript = run;
  };
in pkgs.stdenv.mkDerivation {
  name = "ps2dev-shell";
  nativeBuildInputs = [ fhs ];
  hardeningDisable = [ "format" ];
  shellHook = ''
    # or whatever you want
    export PS2DEV=$HOME/ps2
    mkdir -p $PS2DEV
    chown -R $USER: $PS2DEV

    # setup login env
    export PS2SDK=$PS2DEV/ps2sdk
    export PATH=$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin
    export CMAKE_INSTALL_PREFIX=$PS2DEV/bin
    exec ps2dev
    '';
}
