% Text through pango -> fontconfig -> freetype, in each bundled family.
% fontconfig substitutes a missing family without any warning, so the
% check pins the exact set of fonts embedded in the EPS.
\version "@version@"
\header {
  title = "Serif Title"
  composer = \markup \sans "Sans Composer"
  tagline = ##f
}
<<
  \new Staff \relative c'' { c4 d e f | g1 \bar "|." }
  \new Lyrics \lyricmode { Ly -- ric syl -- la -- bles }
>>
\markup \typewriter "Mono Markup"
\markup \bold "Bold Markup"
