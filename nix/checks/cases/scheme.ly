% Guile beyond LilyPond's own use of it: closures, tail recursion,
% continuations, dynamic-wind, hash tables, and a music function. The
% computed results are printed as markup, so the check can see them.
\version "@version@"
\header { tagline = ##f }

#(define (fib n)
   (let loop ((a 0) (b 1) (i 0))
     (if (= i n) a (loop b (+ a b) (+ i 1)))))

#(define escaped
   (call-with-current-continuation
    (lambda (k) (for-each (lambda (x) (if (> x 2) (k x))) '(1 2 3 4)) 0)))

#(define wound '())
#(dynamic-wind
  (lambda () (set! wound (cons 'in wound)))
  (lambda () #t)
  (lambda () (set! wound (cons 'out wound))))

#(define table (make-hash-table))
#(hash-set! table 'key "hashed")

transpose-up =
#(define-music-function (music) (ly:music?)
   #{ \transpose c d #music #})

\markup { #(format #f "fib-~a" (fib 30)) }
\markup { #(format #f "escaped-~a" escaped) }
\markup { #(format #f "wound-~a" (length wound)) }
\markup { #(hash-ref table 'key) }
\transpose-up \relative c' { c4 e g c }
