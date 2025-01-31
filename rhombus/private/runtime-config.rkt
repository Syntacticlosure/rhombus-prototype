#lang racket/base
(require racket/runtime-config
         racket/port
         racket/interaction-info
         racket/symbol
         shrubbery/parse
         shrubbery/print
         "set.rkt"
         (prefix-in rhombus: (submod "print.rkt" for-runtime))
         (submod "print.rkt" redirect)
         "syntax-parse-config.rkt")

(provide install-runtime-config!
         parameters)

;; Every parameter that's set in `install-runtmie-config`, needed in
;; "expand-config.rkt":
(define parameters
  (list current-interaction-info
        current-read-interaction
        print-boolean-long-form
        global-port-print-handler
        current-error-message-adjuster
        error-syntax->string-handler))

(define (install-runtime-config!)
  (current-interaction-info '#((submod rhombus reader)
                               get-interaction-info
                               #f))

  (current-read-interaction
   (lambda (src in)
     (when (terminal-port? in)
       (flush-output (current-output-port)))
     (define (ensure-count in)
       (if (port-counts-lines? in)
           in
           (let ([in (dup-input-port in)])
             (port-count-lines! in)
             in)))
     (parse-all (ensure-count in) #:source src #:mode 'interactive)))

  (print-boolean-long-form #t)

  (global-port-print-handler
   (let ([orig (global-port-print-handler)])
     (lambda (v op [mode 0])
       (if (racket-print-redirect? v)
           (orig (racket-print-redirect-val v) op 1)
           (rhombus:print v op)))))

  (current-error-message-adjuster
   (lambda (mode)
     (case mode
       [(contract)
        (lambda (str realm)
          (case realm
            [(racket/primitive)
             (values (with-handlers ([exn:fail:read? (lambda (exn) str)])
                       (let loop ([c (read (open-input-string str))])
                         (case c
                           [(number?) "Number"]
                           [(string?) "StringView"]
                           [(list?) "List"]
                           [(hash?) "Map"]
                           [(vector?) "Array"]
                           [((and/c vector? (not/c immutable?))) "MutableArray"]
                           [(pair?) "Pair"]
                           [(bytes?) "Bytes"]
                           [((and/c bytes? (not/c immutable?))) "MutableBytes"]
                           [(path?) "Path"]
                           [(srcloc?) "Srcloc"]
                           [else (format "~s" c)])))
                     'rhombus/primitive)]
            [else (values str realm)]))]
       [(message)
        (lambda (who who-realm msg msg-realm)
          (define-values (new-who new-who-realm)
            (case who-realm
              [(racket/primitive)
               (define (rhombus n) (values n 'rhombus/primitive))
               (case who
                 [(application) (rhombus '|function call|)]
                 [(=) (rhombus '.=)]
                 [(hash-ref) (rhombus 'Map.get)]
                 [(list-ref) (rhombus 'List.get)]
                 [(vector-ref) (rhombus 'Array.get)]
                 [(vector-set!) (rhombus 'Array.set)]
                 [(srcloc-source) (rhombus 'Srcloc.source)]
                 [(srcloc-line) (rhombus 'Srcloc.line)]
                 [(srcloc-column) (rhombus 'Srcloc.column)]
                 [(srcloc-position) (rhombus 'Srcloc.position)]
                 [(srcloc-span) (rhombus 'Srcloc.span)]
                 [(bytes->path) (rhombus 'Path)]
                 [(string->path) (rhombus 'Path)]
                 [(path->bytes) (rhombus 'Path.bytes)]
                 [(path->string) (rhombus 'Path.string)]
                 [(bytes-copy) (rhombus 'Bytes.copy)]
                 [(bytes-copy!) (rhombus 'Bytes.copy_from)]
                 [else (values who who-realm)])]
              [else (values who who-realm)]))
          (define-values (new-msg new-msg-realm)
            (case who-realm
              [(racket/primitive)
               (define (rhombus s) (values s 'rhombus/primitive))
               (cond
                 [(regexp-match-positions #rx"^not a procedure;\n expected a procedure that can be applied to arguments" msg)
                  => (lambda (m)
                       (rhombus (string-append "not a function" (substring msg (cdar m)))))]
                 [(regexp-match-positions #rx"^index is out of range.*?vector:" msg)
                  => (lambda (m)
                       (rhombus (string-append (regexp-replace* #rx"vector" (substring msg (caar m) (cdar m)) "array")
                                               (substring msg (cdar m)))))]
                 [else (values msg msg-realm)])]
              [(racket)
               (define (rhombus s) (values s 'rhombus/primitive))
               (cond
                 [(regexp-match-positions #rx"^arity mismatch;\n the expected number of arguments does not match the given number" msg)
                  => (lambda (m)
                       (rhombus (string-append "wrong number of arguments in function call"
                                               (substring msg (cdar m)))))]
                 [else (values msg msg-realm)])]
              [else (values msg msg-realm)]))
          (values new-who new-who-realm new-msg new-msg-realm))]
       [else #f])))

  ;; for expand-time configure or syntax errors in the REPL
  (error-syntax->string-handler
   (lambda (s len)
     (define str (shrubbery-syntax->string s #:max-length len))
     (if (equal? str "")
         "[end of group]"
         str)))

  (config-syntax-parse!))
