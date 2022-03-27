(define (run-prompt)
  (display "running prompt")
  (newline))

(define (run-file f)
  (display "running file")
  (newline))

(define (main args)
  (case (length args)
    ((0) (run-prompt))
    ((1) (run-file (car args)))
    (else (begin (display "Usage: lox [script]")
                 (exit 64)))))

(main (cdr (program-arguments)))
