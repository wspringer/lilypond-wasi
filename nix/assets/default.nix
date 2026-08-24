# LilyPond runtime data for the WASI module, adapted from
# hlolli/lilypond-wasm (GPL-3.0-or-later): the Scheme library, the ly/
# includes, and the fonts — Emmentaler built natively with fontforge and
# metapost (the wasm target cannot run either), text fonts from URW base35
# and DejaVu.
{
  dejavu_fonts,
  fetchFromGitHub,
  fontforge,
  lib,
  perl,
  python3,
  src,
  stdenvNoCC,
  t1utils,
  texlive,
  version,
}:
let
  kpathseaBin = texlive.pkgs.kpathsea.out;
  kpathseaData = texlive.pkgs.kpathsea.tex;
  metapostBin = texlive.pkgs.metapost.out;
  metapostData = texlive.pkgs.metapost.tex;

  urwBase35 = fetchFromGitHub {
    name = "lilypond-urw-base35-fonts";
    owner = "ArtifexSoftware";
    repo = "urw-base35-fonts";
    tag = "20200910";
    hash = "sha256-YQl5IDtodcbTV3D6vtJi7CwxVtHHl58fG6qCAoSaP4U=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "lilypond-assets";
  inherit version;

  inherit src;

  patches = [ ./0001-use-bundled-svg-text-fonts.patch ];

  strictDeps = true;

  nativeBuildInputs = [
    fontforge
    kpathseaBin
    metapostBin
    perl
    python3
    t1utils
  ];

  dontConfigure = true;
  enableParallelBuilding = true;

  buildPhase = ''
    runHook preBuild

    export TEXMFCNF="${kpathseaData}/web2c"
    export TEXMF="{${metapostData},${kpathseaData}}"

    # These targets need only host tools and do not run LilyPond.
    env -u out make -C scm default \
      config=/dev/null \
      configure-srcdir=. \
      PYTHON="${python3}/bin/python3"
    env -u out make -C mf default \
      config=/dev/null \
      configure-srcdir=. \
      FONTFORGE="${fontforge}/bin/fontforge" \
      PERL="${perl}/bin/perl" \
      PYTHON="${python3}/bin/python3"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    data_dir="$out/share/lilypond"
    mkdir -p \
      "$data_dir/ly" \
      "$data_dir/scm/lily" \
      "$data_dir/fonts/otf" \
      "$data_dir/fonts/svg" \
      "$data_dir/fonts/text"

    cp ly/*.ly "$data_dir/ly/"
    cp scm/*.scm scm/out/font-encodings.scm "$data_dir/scm/lily/"
    # PostScript prologs — the EPS backend loads these at engrave time
    mkdir -p "$data_dir/ps"
    cp ps/*.ps "$data_dir/ps/"
    cp mf/*.conf "$data_dir/fonts/"
    cp ${./fonts.conf} "$data_dir/fonts/fonts.conf"
    cp mf/out/emmentaler-*.otf "$data_dir/fonts/otf/"
    cp mf/out/emmentaler-*.svg "$data_dir/fonts/svg/"

    cp \
      ${urwBase35}/fonts/C059-*.otf \
      ${urwBase35}/fonts/NimbusMonoPS-*.otf \
      ${urwBase35}/fonts/NimbusSans-*.otf \
      "$data_dir/fonts/text/"

    cp \
      ${dejavu_fonts}/share/fonts/truetype/DejaVuSerif.ttf \
      ${dejavu_fonts}/share/fonts/truetype/DejaVuSerif-{Bold,BoldItalic,Italic}.ttf \
      ${dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf \
      ${dejavu_fonts}/share/fonts/truetype/DejaVuSans-{Bold,BoldOblique,Oblique}.ttf \
      ${dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf \
      ${dejavu_fonts}/share/fonts/truetype/DejaVuSansMono-{Bold,BoldOblique,Oblique}.ttf \
      "$data_dir/fonts/text/"

    test -s "$data_dir/scm/lily/font-encodings.scm"
    test -s "$data_dir/fonts/otf/emmentaler-20.otf"
    test -s "$data_dir/fonts/text/C059-Roman.otf"

    runHook postInstall
  '';

  doCheck = false;
  doInstallCheck = false;

  meta = {
    description = "LilyPond runtime data and fonts for the WASI module";
    homepage = "https://lilypond.org/";
    license = with lib.licenses; [ gpl3Plus ofl free ];
    platforms = lib.platforms.all;
  };
}
