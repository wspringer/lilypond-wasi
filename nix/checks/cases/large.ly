% Several pages of dense music: allocation pressure for boehmgc and the
% page breaker, far beyond what a one-line score exercises.
\version "@version@"
\header { tagline = ##f }
\score {
  \new PianoStaff <<
    \new Staff \relative c'' {
      \repeat unfold 120 { c8( d e f) g4-> \tuplet 3/2 { a8 b c } | }
      \bar "|."
    }
    \new Staff \relative c {
      \clef bass
      \repeat unfold 120 { <c e g>4 <d f a> <e g b>2 | }
    }
  >>
}
