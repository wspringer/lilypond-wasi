\version "2.27.3"
\header { tagline = ##f }
\score {
  <<
    \new Staff {
      \clef treble
      \key g \major
      \time 6/8
      \relative c'' {
        g8( a b) d4 b8 | a4.( g4) d8 | e8( fis g) b4 g8 | a4.~ a4 r8 \bar "|."
      }
    }
    \new Lyrics \lyricmode {
      En -- graved4.  by8 Web4. -- As8 -- sem8 -- bly8 works!4.
    }
  >>
  \layout { indent = 0 }
}
