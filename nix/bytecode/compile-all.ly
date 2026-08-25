\version "2.26.0"

% Load both output paths we ship — SVG and PS/EPS — explicitly, then run a
% small score through parsing, layout, page breaking, fonts, and output, so
% Guile's auto-compiler emits bytecode for every module the runtime touches.
% (Modeled on hlolli's compile-svg.ly, extended for the PS/EPS backend.)
#(use-modules
  (lily framework-svg)
  (lily output-svg)
  (lily framework-ps)
  (lily output-ps)
  (lily framework-cairo)
  (lily page))

\header {
  title = "LilyPond WASI bytecode"
  tagline = ##f
}

\score {
  \new Staff <<
    \new Voice = "melody" {
      \clef treble
      \key g \major
      \time 3/4
      g'4( a' b') | c''2.~ | c''4 b'8[ a'] g'4 | g'2. \bar "|."
    }
    \new Lyrics \lyricsto "melody" {
      Com -- piled Scheme works fine
    }
  >>
}
