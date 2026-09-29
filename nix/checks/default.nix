# Engrave checks for one LilyPond variant: does the WASI module, run the
# way release consumers run it, produce correct SVG and EPS — and fail
# like LilyPond (not like a crashed wasm module) when the input is bad?
#
# One derivation per case, so a failure names the case. Run them all with
#   nix flake check
# or one with
#   nix build .#checks.<system>.dev-text
{
  lib,
  runCommand,
  wasmtime,
  libxml2,
  # per-variant:
  lilypond,
  assets,
  bytecode,
  # the wasi guile these were built against:
  guile,
}:

let
  # "2.27.3+gca8dc08" -> "2.27.3": what the input files declare.
  lilypondVersion = lib.head (lib.splitString "+" lilypond.version);

  check = name: script:
    runCommand "lilypond-wasi-check-${name}-${lilypond.version}"
      {
        nativeBuildInputs = [ wasmtime libxml2 ];
        LILYPOND = lilypond;
        ASSETS = assets;
        BYTECODE = bytecode;
        GUILE = guile;
        LILYPOND_VERSION = lilypondVersion;
      }
      ''
        source ${./lib.sh}
        ${script}
        touch $out
      '';

  case = file: "stage ${./cases}/${file}";
in
{
  svg = check "svg" ''
    ${case "basic.ly"}
    engrave basic.log --formats=svg -o /work/basic /work/basic.ly
    assert_clean basic.log
    assert_svg work/basic.svg
  '';

  eps = check "eps" ''
    ${case "basic.ly"}
    engrave basic.log -dbackend=ps -dcrop --formats=eps -o /work/basic /work/basic.ly || true
    assert_clean_until_png basic.log
    # C059-Roman comes along even without text: the default text font.
    assert_eps work/basic.cropped.eps Emmentaler-20 C059-Roman
  '';

  # Cairo renders PDF and PNG in-process: no Ghostscript, so a clean exit.
  cairo = check "cairo" ''
    ${case "text.ly"}
    engrave cairo.log -dbackend=cairo -dcrop --formats=pdf,png,svg -o /work/text /work/text.ly
    assert_clean cairo.log
    head -c 5 work/text.cropped.pdf | grep -q '^%PDF-' || fail "text.cropped.pdf: not a PDF"
    head -c 8 work/text.cropped.png | od -An -tx1 | tr -d ' \n' | grep -q '^89504e470d0a1a0a$' \
      || fail "text.cropped.png: not a PNG"
    assert_svg work/text.cropped.svg
  '';

  text = check "text" ''
    ${case "text.ly"}
    engrave svg.log --formats=svg -o /work/text /work/text.ly
    assert_clean svg.log
    assert_svg work/text.svg
    # The SVG only names families (the backend writes what markup asked
    # for); the EPS below is what proves they resolved to real fonts.
    for family in C059 "Nimbus Sans" "Nimbus Mono PS"; do
      grep -q "font-family=\"$family\"" work/text.svg \
        || fail "text.svg: family $family not used"
    done
    assert_svg_text work/text.svg "Serif Title"
    assert_svg_text work/text.svg "Mono Markup"

    engrave eps.log -dbackend=ps -dcrop --formats=eps -o /work/text /work/text.ly || true
    assert_clean_until_png eps.log
    assert_eps work/text.cropped.eps \
      Emmentaler-20 C059-Roman C059-Bold NimbusSans-Regular NimbusMonoPS-Regular
  '';

  large = check "large" ''
    ${case "large.ly"}
    engrave large.log --formats=svg -o /work/large /work/large.ly
    assert_clean large.log
    # Multi-page SVG output is one file per page: large-1.svg, large-2.svg, …
    pages=0
    for svg in work/large-*.svg; do
      assert_svg "$svg"
      pages=$((pages + 1))
    done
    [ "$pages" -ge 3 ] || fail "large.ly: expected at least 3 pages, got $pages"
  '';

  scheme = check "scheme" ''
    ${case "scheme.ly"}
    engrave scheme.log --formats=svg -o /work/scheme /work/scheme.ly
    assert_clean scheme.log
    assert_svg work/scheme.svg
    assert_svg_text work/scheme.svg "fib-832040"
    assert_svg_text work/scheme.svg "escaped-3"
    assert_svg_text work/scheme.svg "wound-2"
    assert_svg_text work/scheme.svg "hashed"
  '';

  include = check "include" ''
    ${case "include.ly"}
    ${case "include-part.ly"}
    engrave include.log --formats=svg -o /work/include /work/include.ly
    assert_clean include.log
    assert_svg work/include.svg
  '';

  errors = check "errors" ''
    ${case "syntax-error.ly"}
    ${case "scheme-error.ly"}

    if engrave syntax.log --formats=svg -o /work/syntax /work/syntax-error.ly; then
      fail "syntax-error.ly: engraved successfully"
    fi
    grep -q 'syntax-error.ly:3:.*error: syntax error' syntax.log \
      || fail "syntax-error.ly: no located parser error"
    grep -q 'fatal error: failed files' syntax.log \
      || fail "syntax-error.ly: no failed-files summary"

    if engrave scheme.log --formats=svg -o /work/scheme /work/scheme-error.ly; then
      fail "scheme-error.ly: engraved successfully"
    fi
    grep -q 'scheme-error.ly:3:.*error: Guile signaled an error' scheme.log \
      || fail "scheme-error.ly: no located Guile error"
    grep -q 'Wrong type (expecting pair)' scheme.log \
      || fail "scheme-error.ly: Guile's own message lost"
  '';
}
