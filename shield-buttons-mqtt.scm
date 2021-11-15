#!/usr/bin/guile \
-e main -s
!#
(use-modules (ice-9 popen))
(use-modules (ice-9 rdelim))
(use-modules (ice-9 format))
(use-modules (srfi srfi-1))

(define button-eventcode-map
  '(("dpad_up" . "103")
    ("dpad_down" . "108")
    ("dpad_left" . "105")
    ("dpad_right" . "106")
    ("dpad_center" . "28")
    ("back" . "1")
    ("home" . "172")
    ("menu" . "139")
    ("volume_up" . "115")
    ("volume_down" . "114")
    ("a" . "304")
    ("b" . "305")
    ("x" . "307")
    ("y" . "308")
    ("l1" . "310")
    ("r1" . "311")
    ("rtrigger" . "312")
    ("ltrigger" . "313")
    ("select" . "314")
    ("start" . "315")
    ))
  
(define (words arg)
  (string-split arg #\space))

(define (unwords arg)
  (string-join arg " "))

(define (button->topic name)
  (string-append
   "home/downstairs/shield/button/" name))

(define (buttons-to-topics arg)
  (map button->topic arg))

(define (button->eventcode b)
  (let ((ec (assoc-ref button-eventcode-map b)))
    (cond (ec ec)
          (else "0"))))

(define (eventcode->adb-cmd eventcode)
  (string-append
   "sendevent /dev/input/event3 1 " eventcode " 1 "
   "; sendevent /dev/input/event3 0 0 0"
   "; sendevent /dev/input/event3 1 " eventcode " 0 "
   "; sendevent /dev/input/event3 0 0 0"
   "\n"))

(define (topics-to-args topics)
  (fold (lambda (a b) (string-append " -t " a b))
        ""
        topics))

(define (handle-msg h-adb topic-actions topic msg)
  (let ((action (assoc-ref topic-actions topic)))
    (if action
        (action h-adb)
        (display (string-append "bad:  " topic "\n"))
        )))

(define (handle-line h-adb topic-actions line)
  (let* ((parts (words line))
         (msgid (car parts)))
    (if (string=? "MSG" msgid)
        (let
            ((topic (cadr parts))
             (msg (unwords (cddr parts))))
          (handle-msg h-adb topic-actions topic msg)))))

(define (make-mqtt-cmd host topics)
  (string-append
   "mosquitto_sub"
   " -F \"MSG %t %p\""
   " -h " host
   (topics-to-args topics)))

(define (putstrln arg)
  (display (string-append arg "\n")))

(define (launch-cmd cmd)
  (putstrln
   (string-append "executing: " cmd))
  (open-input-pipe cmd))

(define (make-topic-action button-eventcode-pair)
   (let*
      ((button (car button-eventcode-pair))
       (eventcode (cdr button-eventcode-pair))
       (topic (button->topic button))
       (cmd (eventcode->adb-cmd eventcode))
       (debug-msg (string-append "executing: " cmd))
       (debug-action (lambda () (putstrln debug-msg)))
       (action
        (lambda (handle)
          (debug-action)
          (display cmd handle))))
    (cons topic action)))

(define (msg-loop h-mqtt h-adb topic-actions)
  (let* ((line (read-line h-mqtt)))
    (cond
     ((eof-object? line) '())
     (else 
      (handle-line h-adb topic-actions line)
      (msg-loop h-mqtt h-adb topic-actions))
     )))

(define (connect-loop mqtt-cmd topic-actions)
  (let ((h-mqtt (launch-cmd mqtt-cmd))
        (h-adb (open-output-pipe "adb shell")))
    (msg-loop h-mqtt h-adb topic-actions)
    (close-pipe h-mqtt)
    (sleep 10)
    (connect-loop mqtt-cmd topic-actions)))

(define (main args)
  (let* ((topic-actions
          (map make-topic-action button-eventcode-map))
         (topics (map car topic-actions))
         (mqtt-cmd (make-mqtt-cmd "mqtt-broker" topics)))
    (connect-loop mqtt-cmd topic-actions)))

