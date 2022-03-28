(define (run port)
  (display "running"))

(define (run-prompt)
  (run  (current-input-port))
  (newline))

(define (run-file f)
  (let ((port (open-input-file f)))
    (run port)
    (close-port port)))

(define (main args)
  (case (length args)
    ((0) (run-prompt))
    ((1) (run-file (car args)))
    (else (begin (display "Usage: lox [script]")
                 (exit 64)))))

(main (cdr (program-arguments)))
