;; Token
(define (token type lexeme literal line)
  (list type lexeme literal line))
(define token-type car)
(define token-lexeme cadr)
(define token-literal caddr)
(define token-line cadddr)
(define (token-to-string token)
  (display (token-type token))
  (display " ")
  (display (token-lexeme token))
  (display " ")
  (display (token-literal token)))

;; Error-reporting
(define *had-error* #f)
(define (report line where message)
  (display "[line ")
  (display line)
  (display "] Error ")
  (display where)
  (display ": ")
  (display message)
  (newline)
  (set! *had-error* #t))

(define (error line message)
  (report line "" message))

(define (scan port)
  (define line 1)
  (define current 0)
  (define (scan-token)
    (case (read-char port)
      ((#\() 'LEFT-PAREN)
      ((#\)) 'RIGHT-PAREN)
      (else (error "bli" "foo")))
    )
  (define (loop rev-tokens)
    (if (eof-object? (peek-char port))
        (reverse rev-tokens)
        (loop (cons (scan-token) rev-tokens))))
  (loop '()))

(define (run port)
  (let ((tokens (scan port)))
    (for-each (lambda (token)
                (display token))
              tokens)))

(define (run-prompt)
  (run (current-input-port))
  (newline))

(define (run-file f)
  (let ((port (open-input-file f)))
    (run port)
    (close-port port)
    (when *had-error* (exit 64))))

(define (main args)
  (case (length args)
    ((0) (run-prompt))
    ((1) (run-file (car args)))
    (else (begin (display "Usage: lox [script]")
                 (exit 64)))))

(main (cdr (program-arguments)))
