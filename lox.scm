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

(define (scanner-error line message)
  (report line "" message))

;; Environments
(define (new-environment enclosing)
  (cons enclosing '()))
(define (environment-define! env name value)
  (set-cdr! env
            (cons (cons name value) (cdr env))))
(define (environment-assign! env name value)
  (let ((binding (assoc name (cdr env))))
    (if binding
        (set-cdr! binding value)
        (if (car env)
            (environment-assign! (car env) name value)
            (error (string-append "Undefined variable: " name))))))
(define (environment-get env name)
  (let ((binding (assoc name (cdr env))))
    (if binding
        (cdr binding)
        (if (car env)
            (environment-get (car env) name)
            (error (string-append "Undefined variable: " name))))))

;; Scanner
(define (scan port)
  (define line 1)
  (define current 0)
  (define scanned '())
  (define (new-token type literal)
    (let ((scanned-so-far (list->string (reverse scanned))))
      (set! scanned '())
      (token type scanned-so-far literal line)))
  (define (new-token1 type)
    (new-token type #f))
  (define (match expected)
    (let ((c (peek-char port)))
      (if (or (eof-object? c)
              (not (char=? c expected)))
          #f
          (begin
            (read-char port)
            (set! scanned (cons c scanned))
            #t))))
  (define (scan-comment)
    (let ((c (read-char port)))
      (if (or (eof-object? c) (char=? c #\newline))
          #f
          (scan-comment))))
  (define (scan-string chars)
    (let ((c (peek-char port)))
      (if (eof-object? c)
          (begin
            (scanner-error line "Unterminated string")
            #f)
          (begin
            (when (char=? c #\newline) (set! line (+ line 1)))
            (read-char port)
            (set! scanned (cons c scanned))
            (if (char=? c #\")
                (new-token 'STRING (list->string (reverse chars)))
                (scan-string (cons c chars)))))))
  (define (scan-number seen-dot)
    (let ((c (peek-char port)))
      (if (and (not (eof-object? c)) (char-numeric? c))
          (begin
            (read-char port)
            (set! scanned (cons c scanned))
            (scan-number seen-dot))
          (if (and (not (eof-object? (peek-char port)))
                   (not seen-dot)
                   (char=? c #\.))
              (begin
                (read-char port)
                (if (char-numeric? (peek-char port))
                    (scan-number #t)
                    ;; We read the extra dot which is not part of the number
                    (let ((number (new-token 'NUMBER (string->number (list->string (reverse scanned)))))
                          (_ (set! scanned '(#\.)))
                          (dot (new-token1 'DOT)))
                      (list 'TOKENS number dot))))
              (new-token 'NUMBER (string->number (list->string (reverse scanned))))))))
  (define keywords '("and" "class" "else" "false" "for" "fun" "if" "nil" "or" "print" "return" "super" "this" "true" "var" "while"))
  (define (scan-identifier)
    (let ((c (peek-char port)))
      (if (and (not (eof-object? c))
               (or (char-alphabetic? c) (char-numeric? c)))
          (begin
            (read-char port)
            (set! scanned (cons c scanned))
            (scan-identifier))
          (let ((text (list->string (reverse scanned))))
            (if (member text keywords)
                (new-token1 (string->symbol (string-upcase text)))
                (new-token1 'IDENTIFIER))))))
  (define (scan-token)
    (let ((c (read-char port)))
      (set! scanned (cons c scanned))
      (case c
        ((#\() (new-token1 'LEFT-PAREN))
        ((#\)) (new-token1 'RIGHT-PAREN))
        ((#\{) (new-token1 'LEFT-BRACE))
        ((#\}) (new-token1 'RIGHT-BRACE))
        ((#\,) (new-token1 'COMMA))
        ((#\.) (new-token1 'DOT))
        ((#\-) (new-token1 'MINUS))
        ((#\+) (new-token1 'PLUS))
        ((#\;) (new-token1 'SEMICOLON))
        ((#\*) (new-token1 'STAR))
        ((#\!) (new-token1 (if (match #\=) 'BANG-EQUAL 'BANG)))
        ((#\=) (new-token1 (if (match #\=) 'EQUAL-EQUAL 'EQUAL)))
        ((#\>) (new-token1 (if (match #\=) 'GREATER-EQUAL 'GREATER)))
        ((#\<) (new-token1 (if (match #\=) 'LESS-EQUAL 'LESS)))
        ((#\/) (if (match #\/)
                   (scan-comment)
                   (new-token1 'SLASH)))
        ((#\space #\return #\tab) (set! scanned '()) #f)
        ((#\newline) (set! line (+ line 1)) (set! scanned '()) #f)
        ((#\") (scan-string '()))
        (else
         (if (char-numeric? c)
             (scan-number #f)
             (if (char-alphabetic? c)
                 (scan-identifier)
                 (scanner-error line (string-append "Unknown token: " (string c)))))))))
  (define (loop rev-tokens)
    (if (eof-object? (peek-char port))
        (reverse rev-tokens)
        (let* ((scanned (scan-token))
               (new-rev-tokens
                (if scanned
                    (if (eq? (car scanned) 'TOKENS)
                        (append (reverse scanned) rev-tokens)
                        (cons scanned rev-tokens))
                    rev-tokens)))
          (loop new-rev-tokens))))
  (loop '()))

;; Parser
(define (parse tokens)
  (define previous #f)
  (define (check type)
    (if (null? tokens)
        #f
        (eq? (token-type (car tokens)) type)))
  (define (advance)
    (set! previous (car tokens))
    (set! tokens (cdr tokens))
    previous)
  (define (match types)
    (if (null? types)
        #f
        (if (check (car types))
            (begin
              (advance)
              #t)
            (match (cdr types)))))
  (define (consume type message)
    (if (check type)
        (advance)
        (error message)))
  (define (primary)
    (cond
     ((match '(FALSE)) (list 'LITERAL #f))
     ((match '(TRUE)) (list 'LITERAL #t))
     ((match '(NIL)) (list 'LITERAL 'null))
     ((match '(NUMBER STRING)) (list 'LITERAL (token-literal previous)))
     ((match '(LEFT-PAREN))
      (let ((expr (expression)))
        (consume 'RIGHT-PAREN "Expect ')' after expression.")
        (list 'GROUPING expr)))
     ((match '(IDENTIFIER))
      (list 'VARIABLE previous))
     (else (error "Expect expression."))))
  (define (unary)
    (if (match '(BANG MINUS))
        (let ((operator previous)
               (right (unary)))
          (list 'UNARY operator right))
        (primary)))
  (define (factor)
    (define (loop expr)
      (if (match '(SLASH STAR))
          (let* ((operator previous)
                 (right (unary))
                 (expr (list 'BINARY expr operator right)))
            (loop expr))
          expr))
    (loop (unary)))
  (define (term)
    (define (loop expr)
      (if (match '(MINUS PLUS))
          (let* ((operator previous)
                 (right (factor))
                 (expr (list 'BINARY expr operator right)))
            (loop expr))
          expr))
    (loop (factor)))
  (define (comparison)
    (define (loop expr)
      (if (match '(GREATER GREATER-EQUAL LESS LESS-EQUAL))
          (let* ((operator previous)
                 (right (term))
                 (expr (list 'BINARY expr operator right)))
            (loop expr))
          expr))
    (loop (term)))
  (define (equality)
    (define (loop expr)
      (if (match '(BANG-EQUAL EQUAL-EQUAL))
          (let* ((operator previous)
                 (right (comparison))
                 (expr (list 'BINARY expr operator right)))
            (loop expr))
          expr))
    (loop (comparison)))
  (define (assignment)
    (let ((expr (equality)))
      (if (match '(EQUAL))
          (let ((equals previous)
                (value (assignment)))
            (if (eq? (car expr) 'VARIABLE)
                (let ((name (cadr expr)))
                  (list 'ASSIGNMENT name value))
                (error "Invalid assignment target")))
          expr)))
  (define (expression) (assignment))
  (define (print-statement)
    (let ((value (expression)))
      (consume 'SEMICOLON "Expect ';' after value.")
      (list 'PRINT value)))
  (define (expression-statement)
    (let ((expr (expression)))
      (consume 'SEMICOLON "Expect ';' after expression.")
      (list 'EXPRESSION expr)))
  (define (block rev-statements)
    (if (and (not (check 'RIGHT-BRACE)) (not (null? tokens)))
        (block (cons (declaration) rev-statements))
        (begin
          (consume 'RIGHT-BRACE "Expect '}' after block.")
          (reverse rev-statements))))
  (define (statement)
    (if (match '(PRINT))
        (print-statement)
        (if (match '(LEFT-BRACE))
            (list 'BLOCK (block '()))
            (expression-statement))))
  (define (var-declaration)
    (let ((name (consume 'IDENTIFIER "Expect variable name."))
          (initializer (if (match '(EQUAL)) (expression) 'null)))
      (consume 'SEMICOLON "Expect ';' after variable declaration.")
      (list 'VAR name initializer)))
  (define (declaration)
    (if (match '(VAR))
        (var-declaration)
        (statement)))
  (define (program rev-statements)
    (if (null? tokens)
        (reverse rev-statements)
        (program (cons (declaration) rev-statements))))
  (program '()))

;; Evaluation
(define (evaluate program)
  (define environment (new-environment #f))
  (define (is-truthy v)
    (if (boolean? v) v #t))
  (define (is-equal a b)
    (equal? a b))
  (define (check-number-operand operator operand)
    (if (number? operand)
        #t
        (error (string-append "Operand must be a number for: " (symbol->string operator)))))
  (define (evaluate-expr expr)
    (case (car expr)
      ((LITERAL) (cadr expr))
      ((GROUPING) (evaluate-expr (cadr expr)))
      ((UNARY)
       (let ((operator (cadr expr))
             (right (evaluate-expr(caddr expr))))
         (case operator
           ((MINUS)
            (check-number-operand operator right)
            (- right))
           ((BANG) (not (is-truthy right))))))
      ((BINARY)
       (let ((left (evaluate-expr (cadr expr)))
             (operator (caddr expr))
             (right (evaluate-expr(cadddr expr))))
         (case (car operator)
           ((MINUS)
            (check-number-operand operator left) (check-number-operand operator right)
            (- left right))
           ((SLASH)
            (check-number-operand operator left) (check-number-operand operator right)
            (/ left right))
           ((STAR)
            (check-number-operand operator left) (check-number-operand operator right)
            (* left right))
           ((PLUS)
            (if (and (number? left) (number? right))
                (+ left right)
                (if (and (string? left) (string? right))
                    (string-append left right)
                    (error "Operands to + must be two numbers or two strings"))))
           ((GREATER)
            (check-number-operand operator left) (check-number-operand operator right)
            (> left right))
           ((GREATER-EQUAL)
            (check-number-operand operator left) (check-number-operand operator right)
            (>= left right))
           ((LESS)
            (check-number-operand operator left) (check-number-operand operator right)
            (< left right))
           ((LESS-EQUAL)
            (check-number-operand operator left) (check-number-operand operator right)
            (<= left right))
           ((BANG-EQUAL) (not (is-equal left right)))
           ((EQUAL-EQUAL) (is-equal left right)))))
      ((VARIABLE)
       (let ((name (cadr expr)))
         (environment-get environment name)))
      ((ASSIGNMENT)
       (let ((name (cadr expr))
             (value (evaluate-expr (caddr expr))))
         (environment-assign! environment name value)
         value))
      (else (error "Unknown expression: " (symbol->string (car expr))))))
  (define (evaluate-print expr)
    (let ((value (evaluate-expr expr)))
      (display value) (newline)
      'null))
  (define (evaluate-var name initializer)
    (let ((value (if initializer (evaluate-expr initializer) 'null)))
      (environment-define! environment name value)
      'null))
  (define (evaluate-block statements env)
    (let ((previous-env environment))
      (set! environment (new-environment env))
      (let ((result (evaluate-program statements)))
        (set! environment previous-env)
        result)))
  (define (evaluate-program statements)
    (map (lambda (statement)
           (case (car statement)
             ((EXPRESSION) (evaluate-expr (cadr statement)))
             ((PRINT) (evaluate-print (cadr statement)))
             ((VAR) (evaluate-var (cadr statement) (caddr statement)))
             ((BLOCK) (evaluate-block (cadr statement) environment))))
         statements))
  (evaluate-program program))

;; Interface
(define (run port)
  (let* ((tokens (scan port))
         (expression (parse tokens)))
    (for-each (lambda (exp-element)
                (display exp-element))
              expression)))

(define (run-prompt)
  (run (current-input-port))
  (newline))

(define (run-file f)
  (let ((port (open-input-file f)))
    (run port)
    (close-port port)
    (when *had-error* (exit 64))))

(define (test-scanner)
  (define (test-case input expected)
    (let* ((port (open-input-string input))
           (tokens (scan port))
           (token-types (map token-type tokens)))
      (close-port port)
      (when (not (equal? token-types expected))
        (display "test-scanner failed on input ")
        (display input)
        (display ": got ")
        (display token-types)
        (newline))))
  (test-case "==" '(EQUAL-EQUAL))
  (test-case "!" '(BANG))
  (test-case "// this is a comment" '())
  (test-case "(( )){}" '(LEFT-PAREN LEFT-PAREN RIGHT-PAREN RIGHT-PAREN LEFT-BRACE RIGHT-BRACE))
  (test-case "!*+-/=<> <= ==" '(BANG STAR PLUS MINUS SLASH EQUAL LESS GREATER LESS-EQUAL EQUAL-EQUAL))
  (test-case "\"hello\" \"world\"" '(STRING STRING))
  (test-case "\"hello\n\"" '(STRING))
  (test-case "123" '(NUMBER))
  (test-case "1.23 43.5 6" '(NUMBER NUMBER NUMBER))
  (test-case "if this return super" '(IF THIS RETURN SUPER))
  (test-case "hello world" '(IDENTIFIER IDENTIFIER))
  (test-case "1+2" '(NUMBER PLUS NUMBER))
  (test-case "1+2=3" '(NUMBER PLUS NUMBER EQUAL NUMBER)))

(define (test-parser)
  (define (test-case input expected)
    (let* ((port (open-input-string input))
           (tokens (scan port))
           (expr (parse tokens)))
      (close-port port)
      (when (not (equal? expr expected))
        (display "test-parser failed on input ")
        (display input)
        (display ": got ")
        (display expr)
        (display " instead of ")
        (display expected)
        (newline))))
  (test-case "1+2;" '((EXPRESSION (BINARY (LITERAL 1) (PLUS "+" #f 1) (LITERAL 2)))))
  (test-case "1*(2+3);" '((EXPRESSION (BINARY (LITERAL 1) (STAR "*" #f 1) (GROUPING (BINARY (LITERAL 2) (PLUS "+" #f 1) (LITERAL 3)))))))
  (test-case "var x = 5;" '((VAR (IDENTIFIER "x" #f 1) (LITERAL 5))))
  (test-case "x;" '((EXPRESSION (VARIABLE (IDENTIFIER "x" #f 1)))))
  (test-case "x = 3;" '((EXPRESSION (ASSIGNMENT (IDENTIFIER "x" #f 1) (LITERAL 3)))))
  (test-case "{ var x; 1; }" '((BLOCK ((VAR (IDENTIFIER "x" #f 1) null) (EXPRESSION (LITERAL 1))))))
  (test-case "var x = 5; { var x = 3; x; } x;" ' ((VAR (IDENTIFIER "x" #f 1) (LITERAL 5)) (BLOCK ((VAR (IDENTIFIER "x" #f 1) (LITERAL 3)) (EXPRESSION (VARIABLE (IDENTIFIER "x" #f 1))))) (EXPRESSION (VARIABLE (IDENTIFIER "x" #f 1))))))

(define (test-evaluate)
  (define (test-case input expected)
    (let* ((port (open-input-string input))
           (tokens (scan port))
           (expr (parse tokens))
           (value (evaluate expr)))
      (close-port port)
      (when (not (equal? value expected))
        (display "test-evaluate failed on input ")
        (display input)
        (display ": got ")
        (display value)
        (display " instead of ")
        (display expected)
        (newline))))
  (test-case "1+2;" '(3))
  (test-case "print true; print 2 + 1;" '(null null))
  (test-case "var x = 5; x+1;" '(null 6))
  (test-case "var x = 5; x = 3; x;" '(null 3 3))
  (test-case "var x = 5; { var x = 3; x; } x;" '(null (null 3) 5)))

(define (test)
  (test-scanner)
  (test-parser)
  (test-evaluate)
)

(define (main args)
  (case (length args)
    ((0) (run-prompt))
    ((1) (if (string=? (car args) "--test")
             (test)
             (run-file (car args))))
    (else (begin (display "Usage: lox [script]")
                 (exit 64)))))

(main (cdr (program-arguments)))

