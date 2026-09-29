% Resolution of \include against both the input directory and the
% library mounted at /lilypond/ly, plus a non-default note language.
\version "@version@"
\header { tagline = ##f }
\include "articulate.ly"
\include "include-part.ly"
\language "deutsch"
\score {
  \articulate { \partMusic h'4 b' }
  \layout { }
}
