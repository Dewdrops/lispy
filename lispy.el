;;; lispy.el --- vi-like Paredit.

;; Copyright (C) 2014 Oleh Krehel

;; Author: Oleh Krehel <ohwoeowho@gmail.com>
;; URL: https://github.com/abo-abo/lispy
;; Version: 0.7
;; Package-Requires: ((helm "1.5.3") (ace-jump-mode "2.0") (s "1.4.0") (noflet "0.0.10"))
;; Keywords: lisp

;; This file is not part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Due to the structure of Lisp syntax it's very rare for the
;; programmer to want to insert characters right before "(" or right
;; after ")".  Thus unprefixed printable characters can be used to call
;; commands when the point is at one of these locations, which are
;; further referred to as special.
;;
;; Conveniently, when located at special position it's very clear to
;; which sexp the list-manipulating command will be applied to, what
;; the result be and where the point should end up afterwards.  You
;; can enhance this effect with `show-paren-mode' or similar.
;;
;; Here's an illustration to this effect, with `lispy-clone' ("*"
;; represents the point):
;; |--------------------+-----+--------------------|
;; | before             | key | after              |
;; |--------------------+-----+--------------------|
;; |  (looking-at "(")* |  c  |  (looking-at "(")  |
;; |                    |     |  (looking-at "(")* |
;; |--------------------+-----+--------------------|
;; | *(looking-at "(")  |  c  | *(looking-at "(")  |
;; |                    |     |  (looking-at "(")  |
;; |--------------------+-----+--------------------|
;;
;; When special, the digit keys call `digit-argument' which is very
;; convenient since most Lispy commands accept a numeric argument.
;; For instance, "3c" is equivalent to "ccc" (clone sexp 3 times), and
;; "4j" is equivalent to "jjjj" (move point 4 sexps down).  Some
;; useful applications are "9l" and "9a" - they exit list forwards and
;; backwards respectively at most 9 times which makes them effectively
;; equivalent to `end-of-defun' and `beginning-of-defun'.
;;
;; To move the point into a special position, use:
;; "]" - calls `lispy-forward'
;; "[" - calls `lispy-backward'
;; "C-3" - calls `lispy-out-forward' (exit current list forwards)
;; ")" - calls `lispy-out-forward-nostring' (exit current list
;;       forwards, but self-insert in strings and comments)
;;
;; These are the few Lispy commands that don't care whether the point
;; is special or not.  Other such bindings are `DEL', `C-d', `C-k'.
;;
;; To get out of the special position, you can use any of the good-old
;; navigational commands such as `C-f' or `C-n'.
;; Additionally `SPC' will break out of special to get around the
;; situation when you have the point between open parens like this
;; "(|(" and want to start inserting.  `SPC' will change the code to
;; this: "(| (".
;;
;; A lot of Lispy commands come in pairs: one reverses the other.
;; Some examples are:
;; |-----+--------------------------+------------+-------------------|
;; | key | command                  | key        | command           |
;; |-----+--------------------------+------------+-------------------|
;; | j   | `lispy-down'             | k          | `lispy-up'        |
;; | s   | `lispy-move-down'        | w          | `lispy-move-up'   |
;; | o   | `lispy-counterclockwise' | p          | `lispy-clockwise' |
;; | >   | `lispy-slurp'            | <          | `lispy-barf'      |
;; | c   | `lispy-clone'            | C-d or DEL |                   |
;; | C   | `lispy-convolute'        | C          | reverses itself   |
;; | d   | `lispy-different'        | d          | reverses itself   |
;; | M-j | `lispy-split'            | +          | `lispy-join'      |
;; | O   | `lispy-oneline'          | M          | `lispy-multiline' |
;; | S   | `lispy-stringify'        | C-u "      | `lispy-quotes'    |
;; | ;   | `lispy-comment'          | C-u ;      | `lispy-comment'   |
;; |-----+--------------------------+------------+-------------------|
;;
;; Among other cool commands are:
;; |-----+------------------------------------|
;; | key | command                            |
;; |-----+------------------------------------|
;; | f   | `lispy-flow'                       |
;; | u   | `undo'                             |
;; | e   | `lispy-eval'                       |
;; | m   | `lispy-mark-list'                  |
;; | l   | `lispy-out-forward'                |
;; | a   | `lispy-out-backward'               |
;; | E   | `lispy-eval-and-insert'            |
;; | /   | `lispy-splice'                     |
;; | i   | `indent-sexp'                      |
;; | r   | `lispy-raise'                      |
;; | R   | `lispy-raise-some'                 |
;; | J   | `outline-next-visible-heading'     |
;; | K   | `outline-previous-visible-heading' |
;; | g   | `lispy-goto'                       |
;; | q   | `lispy-ace-paren'                  |
;; | h   | `lispy-ace-symbol'                 |
;; | Q   | `lispy-ace-char'                   |
;; | D   | `lispy-describe'                   |
;; | F   | `lispy-follow'                     |
;; | N   | `lispy-normalize'                  |
;; | C-1 | `lispy-describe-inline'            |
;; | C-2 | `lispy-arglist-inline'             |
;; | v   | `lispy-view'                       |
;; |-----+------------------------------------|
;;
;; Most special commands will leave the point special after they're
;; done.  This allows to chain them as well as apply them
;; continuously by holding the key.  Some useful holdable keys are
;; "jkopf<>cws;".
;; Not so useful, but fun is "/": start it from "|(" position and hold
;; until all your Lisp code is turned into Python :).
;;
;; Some Clojure support depends on packages `cider' or `nrepl'.
;; Some Scheme support depends on `geiser'.
;; Some Common Lisp support depends on `slime'.
;; You can get them from MELPA.
;;
;;; Code:
(eval-when-compile
  (require 'cl)
  (require 'noflet)
  (require 'org))
(require 'help-fns)
(require 'edebug)
(require 'outline)
(require 'semantic)
(require 'ace-jump-mode)
(require 'newcomment)
(require 'lispy-inline)

;; ——— Customization ———————————————————————————————————————————————————————————
(defgroup lispy nil
  "List navigation and editing for the Lisp family."
  :group 'bindings
  :prefix "lispy-")

(defvar lispy-left "[([{]"
  "Opening delimiter.")

(defvar lispy-right "[])}]"
  "Closing delimiter.")

(defvar lispy-no-space nil
  "If t, don't insert a space before parens/brackets/braces/colons.")
(make-variable-buffer-local 'lispy-no-space)

(defvar lispy-mode-map (make-sparse-keymap))

;;;###autoload
(define-minor-mode lispy-mode
    "Minor mode for navigating and editing Lisp.

When `lispy-mode' is on, brackets move forward and backward through
lists.

Commands are provided to insert (), [], {}, \"\".

:, ^, RET, SPC are re-defined to provide appropriate whitespace,
besides inserting.

C-k, C-y, C-j, C-d, DEL, C-e and ; are re-defined as well.

Various unprefixed keys are special when positioned at \"(\" or behind
\")\". Otherwise they insert themselves.
For instance, > inserts itself, or grows current list, depending on
the context.

\\{lispy-mode-map}"
  :keymap lispy-mode-map
  :group 'lispy
  :lighter " LY")

;; ——— Macros ——————————————————————————————————————————————————————————————————
(defmacro dotimes-protect (n &rest bodyform)
  "Execute N times the BODYFORM unless an error is signaled.
Return nil couldn't execute BODYFORM at least once.
Otherwise return t."
  `(let ((i 0)
         out)
     (ignore-errors
       (while (<= (incf i) ,n)
         ,@bodyform
         (setq out t)))
     out))

(defmacro lispy-save-excursion (&rest body)
  "More intuitive (`save-excursion' BODY)."
  `(let ((out (save-excursion
                ,@body)))
     (when (bolp)
       (back-to-indentation))
     out))

;; ——— Globals: navigation —————————————————————————————————————————————————————
(defun lispy-forward (arg)
  "Move forward list ARG times or until error.
Return t if moved at least once,
otherwise call `lispy-out-forward' and return nil."
  (interactive "p")
  (when (= arg 0)
    (setq arg 2000))
  (lispy--exit-string)
  (let ((pt (point))
        (r (dotimes-protect arg
             (forward-list))))
    ;; `forward-list' returns true at and of buffer
    (if (or (null r)
            (= pt (point))
            (and (not (looking-back lispy-right))
                 (progn
                   (backward-list)
                   (forward-list)
                   (= pt (point)))))
        (prog1 nil
          (lispy--out-forward 1))
      t)))

(defun lispy-backward (arg)
  "Move backward list ARG times or until error.
If couldn't move backward at least once, move up backward and return nil."
  (interactive "p")
  (when (= arg 0)
    (setq arg 2000))
  (lispy--exit-string)
  (let ((pt (point))
        (r (dotimes-protect arg
             (backward-list))))
    ;; `backward-list' returns true at beginning of buffer
    (if (or (null r)
            (= pt (point))
            (and (not (looking-at lispy-left))
                 (progn
                   (forward-list)
                   (backward-list)
                   (= pt (point)))))
        (prog1 nil
          (lispy--out-forward 1)
          (backward-list))
      t)))

(defun lispy-out-forward (arg)
  "Move outside list forwards ARG times.
Return nil on failure, t otherwise."
  (interactive "p")
  (if (region-active-p)
      (dotimes-protect arg
        (when (save-excursion (ignore-errors (up-list) t))
          (let* ((at-start (= (point) (region-beginning)))
                 (bnd1 (lispy--bounds-dwim))
                 (str1 (lispy--string-dwim bnd1))
                 pt)
            (delete-region (car bnd1) (cdr bnd1))
            (cond ((looking-at " *;"))
                  ((and (looking-at "\n")
                        (looking-back "^ *"))
                   (delete-blank-lines))
                  ((looking-at "\\([\n ]+\\)[^\n ;]")
                   (delete-region (match-beginning 1)
                                  (match-end 1))))
            (up-list)
            (lispy--remove-gaps)
            (if (looking-at " *;")
                (progn
                  (forward-line 1)
                  (newline)
                  (indent-for-tab-command)
                  (forward-line -1))
              (newline-and-indent))
            (setq pt (point))
            (insert str1)
            (indent-region pt (point))
            (setq deactivate-mark)
            (set-mark pt)
            (when at-start
              (exchange-point-and-mark)))))
    (lispy--out-forward arg)))

(defun lispy-out-forward-nostring (arg)
  "Call `lispy--out-forward' with ARG unless in string or comment.
Self-insert otherwise."
  (interactive "p")
  (if (or (lispy--in-string-or-comment-p)
          (looking-back "?\\\\"))
      (self-insert-command arg)
    (lispy--out-forward arg)))

(defun lispy-out-backward (arg)
  "Move outside list forwards ARG times.
Return nil on failure, t otherwise."
  (interactive "p")
  (if (region-active-p)
      (dotimes-protect arg
        (when (save-excursion (ignore-errors (up-list) t))
          (let* ((at-start (= (point) (region-beginning)))
                 (bnd1 (lispy--bounds-dwim))
                 (str1 (lispy--string-dwim bnd1))
                 pt)
            (delete-region (car bnd1) (cdr bnd1))
            (cond ((looking-at " *;"))
                  ((and (looking-at "\n")
                        (looking-back "^ *"))
                   (delete-blank-lines))
                  ((looking-at "\\([\n ]+\\)[^\n ;]")
                   (delete-region (match-beginning 1)
                                  (match-end 1))))
            (up-list)
            (backward-list)
            (lispy--normalize 0)
            (lispy--remove-gaps)
            (setq pt (point))
            (insert str1)
            (newline-and-indent)
            (skip-chars-backward " \n")
            (indent-region pt (point))
            (setq deactivate-mark)
            (set-mark pt)
            (when at-start
              (exchange-point-and-mark)))))
    (lispy--out-backward arg)))

(defun lispy-out-forward-newline (arg)
  "Call `lispy--out-forward', then ARG times `newline-and-indent'."
  (interactive "p")
  (lispy--out-forward 1)
  (dotimes-protect arg
    (newline-and-indent)))

;; ——— Locals:  navigation —————————————————————————————————————————————————————
(defun lispy-flow (arg)
  "Move inside list ARG times.
Don't enter strings or comments.
Return nil if can't move."
  (interactive "p")
  (let ((pt (point))
        success)
    (dotimes-protect arg
      (cond ((looking-at lispy-left)
             (forward-char)
             (re-search-forward lispy-left nil t)
             (while (and (lispy--in-string-or-comment-p)
                         (re-search-forward lispy-left nil t)))
             (unless (lispy--in-string-or-comment-p)
               (setq success t))
             (backward-char))

            ((looking-back lispy-right)
             (backward-char)
             (re-search-backward lispy-right nil t)
             (while (and (lispy--in-string-or-comment-p)
                         (re-search-backward lispy-right nil t)))
             (unless (lispy--in-string-or-comment-p)
               (setq success t))
             (forward-char))))
    (and (not (= (point) pt))
         (or success
             (prog1 nil
               (goto-char pt))))))

(defun lispy-counterclockwise ()
  "Move counterclockwise inside current list."
  (interactive)
  (let ((pt (point)))
    (cond ((looking-at lispy-left)
           (lispy-forward 2)
           (lispy-backward 1))

          ((looking-back lispy-right)
           (lispy-backward 2)
           (lispy-forward 1)))
    (when (= pt (point))
      (if (looking-at lispy-left)
          (lispy-forward 1)
        (lispy-backward 1)))))

(defun lispy-clockwise ()
  "Move clockwise inside current list."
  (interactive)
  (let ((pt (point)))
    (cond ((looking-at lispy-left)
           (or (lispy-backward 1)
               (progn
                 (goto-char pt)
                 (forward-list))))

          ((looking-back lispy-right)
           (if (looking-at lispy-right)
               (lispy-backward 1)
             (unless (lispy-forward 1)
               (goto-char pt)
               (lispy-backward 1)))))))

(defun lispy-down (arg)
  "Move down ARG times inside current list."
  (interactive "p")
  (cond ((region-active-p)
         (dotimes-protect arg
           (if (= (point) (region-beginning))
               (progn
                 (forward-sexp 1)
                 (skip-chars-forward " \n"))
             (forward-sexp 1))))

        ((looking-at lispy-left)
         (lispy-forward arg)
         (let ((pt (point)))
           (if (lispy-forward 1)
               (lispy-backward 1)
             (goto-char pt))))

        ((looking-back lispy-right)
         (let ((pt (point)))
           (unless (lispy-forward arg)
             (goto-char pt)
             (lispy-backward 1))))

        (t
         (lispy-forward 1)
         (lispy-backward 1))))

(defun lispy-up (arg)
  "Move up ARG times inside current list."
  (interactive "p")
  (cond ((region-active-p)
         (dotimes-protect arg
           (if (= (point) (region-beginning))
               (backward-sexp 1)
             (progn
               (backward-sexp 1)
               (skip-chars-backward " \n")))))

        ((looking-at lispy-left)
         (let ((pt (point)))
           (unless (lispy-backward arg)
             (goto-char pt)
             (lispy-forward 1))))

        ((looking-back lispy-right)
         (lispy-backward arg)
         (let ((pt (point)))
           (if (lispy-backward 1)
               (lispy-forward 1)
             (goto-char pt))))

        (t
         (lispy-backward 1)
         (lispy-forward 1))))

(defun lispy-different ()
  "Switch to the different side of current sexp."
  (interactive)
  (cond ((and (region-active-p)
              (not (= (region-beginning) (region-end))))
         (exchange-point-and-mark))
        ((looking-at lispy-left)
         (forward-list))
        ((looking-back lispy-right)
         (backward-list))
        (t (error "Unexpected"))))

;; ——— Globals: kill, yank, delete, mark, copy —————————————————————————————————
(defun lispy-kill ()
  "Kill keeping parens consistent."
  (interactive)
  (cond ((or (lispy--in-comment-p) (looking-at ";"))
         (kill-line))

        ((lispy--in-string-p)
         (let ((end (cdr (lispy--bounds-string))))
           (if (> end (line-end-position))
               (kill-line)
             (delete-region (point)
                            (1- end)))))
        ((looking-at " *\n")
         (progn
           (delete-region
            (match-beginning 0)
            (match-end 0))
           (indent-for-tab-command)))
        ((and (looking-at lispy-right) (looking-back lispy-left))
         (delete-char 1)
         (backward-delete-char 1))
        (t (let* ((beg (point))
                  (str (buffer-substring-no-properties
                        beg
                        (line-end-position))))
             (if (= (cl-count ?\( str)
                    (cl-count ?\) str))
                 (kill-line)
               (if (lispy--out-forward 1)
                   (progn
                     (backward-char 1)
                     (kill-region beg (point)))
                 (goto-char beg)
                 (lispy-delete 1)))))))

(defun lispy-yank ()
  "Like regular `yank', but quotes body when called from \"|\"."
  (interactive)
  (if (and (eq (char-after) ?\")
           (eq (char-before) ?\"))
      (insert (replace-regexp-in-string "\"" "\\\\\"" (current-kill 0)))
    (yank)))

(defun lispy-delete (arg)
  "Delete ARG sexps."
  (interactive "p")
  (cond ((region-active-p)
         (delete-region
          (region-beginning)
          (region-end)))

        ((lispy--in-string-or-comment-p)
         (cond
           ((looking-at "\\\\\"")
            (delete-char 2))
           ((save-excursion
              (forward-char 1)
              (lispy--in-string-or-comment-p))
            (delete-char arg))
           (t (lispy--exit-string))))

        ((looking-at lispy-left)
         (dotimes-protect arg (lispy--delete))
         (unless (looking-at lispy-left)
           (when (looking-at " +")
             (delete-region (match-beginning 0)
                            (match-end 0)))
           (lispy--out-forward 1)
           (backward-list)))

        ((looking-at "\"")
         (kill-sexp)
         (lispy--remove-gaps)
         (when (lispy-forward 1)
           (backward-list)))

        ((looking-at lispy-right)
         (forward-char 1)
         (lispy-delete-backward 1))

        (t (delete-char arg))))

(defun lispy-delete-backward (arg)
  "From \")|\", delete ARG sexps backwards.
Otherwise (`backward-delete-char-untabify' ARG)."
  (interactive "p")
  (let (pos)
    (cond ((lispy--in-string-p)
           (cond ((save-excursion
                    (backward-char 1)
                    (not (lispy--in-string-p)))
                  (lispy--exit-string)
                  (forward-sexp))
                 ((and
                   (looking-back "\\\\\\\\(")
                   (setq pos
                         (save-excursion
                           (let ((b1 (match-beginning 0))
                                 (e1 (match-end 0))
                                 b2 e2)
                             (when (re-search-forward
                                    "\\\\\\\\)"
                                    (cdr (lispy--bounds-string)) t)
                               (setq b2 (match-beginning 0)
                                     e2 (match-end 0))
                               (delete-region b2 e2)
                               (delete-region b1 e1)
                               b1)))))
                  (goto-char pos))
                 ((and
                   (looking-back "\\\\\\\\)")
                   (setq pos
                         (save-excursion
                           (let ((b1 (match-beginning 0))
                                 (e1 (match-end 0))
                                 b2 e2)
                             (when (re-search-backward
                                    "\\\\\\\\("
                                    (car (lispy--bounds-string)) t)
                               (setq b2 (match-beginning 0))
                               (setq e2 (match-end 0))
                               (delete-region b1 e1)
                               (delete-region b2 e2)
                               (+ b2 (- e1 b1)))))))
                  (goto-char pos))
                 (t (backward-delete-char-untabify arg))))
          ((and (looking-back lispy-right) (not (looking-back "\\\\.")))
           (let ((pt (point)))
             (lispy-backward arg)
             (delete-region pt (point))
             (just-one-space)
             (lispy--remove-gaps)
             (unless (looking-back lispy-right)
               (lispy-backward 1)
               (forward-list))))

          ((and (looking-back lispy-left) (not (looking-back "\\\\.")))
           (lispy--out-forward 1)
           (lispy-delete-backward 1))

          ((looking-back "\"")
           (backward-sexp 1)
           (kill-sexp)
           (just-one-space)
           (lispy--remove-gaps)
           (when (lispy-forward 1)
             (backward-list)))

          (t (backward-delete-char-untabify arg)))))

(defun lispy-mark ()
  "Mark the quoted string or the list that includes the point.
Extend region when it's aleardy active."
  (interactive)
  (let ((bounds (or (lispy--bounds-comment)
                    (lispy--bounds-string)
                    (lispy--bounds-list))))
    (when bounds
      (set-mark (car bounds))
      (goto-char (cdr bounds)))))

(defun lispy-mark-list ()
  "Mark list from special position."
  (interactive)
  (cond ((region-active-p)
         (deactivate-mark))
        ((looking-at lispy-left)
         (set-mark (point))
         (forward-list))
        ((looking-back lispy-right)
         (set-mark (point))
         (backward-list))))

(defun lispy-mark-symbol ()
  "Mark current symbol."
  (interactive)
  (cond ((lispy--in-comment-p)
         (lispy--mark (lispy--bounds-comment)))
        ((or (looking-at "[ ]*[()]")
             (and (region-active-p)
                  (looking-at "[ \n]*[()]")))
         (skip-chars-forward "() \n")
         (set-mark-command nil)
         (re-search-forward "[() \n]")
         (while (lispy--in-string-or-comment-p)
           (re-search-forward "[() \n]"))
         (backward-char 1))

        ((looking-back lispy-right)
         (skip-chars-backward "() \n")
         (set-mark-command nil)
         (re-search-backward "[() \n]")
         (while (lispy--in-string-or-comment-p)
           (re-search-backward "[() \n]"))
         (forward-char 1))

        ((region-active-p)
         (ignore-errors
           (forward-sexp)))
        (t
         (lispy--mark (lispy--bounds-dwim)))))

(defun lispy-pop-copy (arg)
  "Pop to mark and copy current list there.
With ARG not nil, cut instead of copying."
  (interactive "P")
  (lispy--out-forward 1)
  (let* ((beg (point))
         (end (progn
                (lispy-backward 1)
                (point)))
         (sexp
          (buffer-substring-no-properties
           beg end)))
    (when arg
      (delete-region beg end)
      (lispy--remove-gaps))
    (set-mark-command 4)
    (insert sexp)))

(defun lispy-kill-at-point ()
  "Kill the quoted string or the list that includes the point."
  (interactive)
  (if (region-active-p)
      (progn
        (kill-new (buffer-substring-no-properties
                   (region-beginning)
                   (region-end)))
        (newline-and-indent)
        (insert (current-kill 0)))
    (let ((bounds (or (lispy--bounds-comment)
                      (lispy--bounds-string)
                      (lispy--bounds-list))))
      (kill-region (car bounds) (cdr bounds)))))

;; ——— Globals: pairs ——————————————————————————————————————————————————————————
(defun lispy-pair (left right space-unless)
  "Return (lambda (arg)(interactive \"p\")...) using LEFT RIGHT SPACE-UNLESS.
When this function is called:
- with region active:
  Wrap region with LEFT RIGHT.
- with arg 1:
  Insert LEFT RIGHT.
- else:
  Wrap current sexp with LEFT RIGHT."
  `(lambda (arg)
     (interactive "p")
     (cond
       ((region-active-p)
        (lispy--surround-region ,left ,right))
       ((lispy--in-string-p)
        (if (looking-back "\\\\\\\\")
            (progn
              (insert ,left "\\\\" ,right)
              (backward-char 3))
          (insert ,left ,right)
          (backward-char 1)))
       ((lispy--in-comment-p)
        (insert ,left ,right)
        (backward-char 1))
       ((looking-back "?\\\\")
        (insert ,left))
       ((= arg 1)
        (indent-for-tab-command)
        (lispy--space-unless ,space-unless)
        (insert ,left ,right)
        (unless (or (eolp)
                    (lispy--in-string-p)
                    (looking-at "\n\\|)\\|}\\|\\]"))
          (just-one-space)
          (backward-char 1))
        (when (looking-at ,(regexp-quote left))
          (insert " ")
          (backward-char))
        (backward-char))
       (t
        (insert ,left )
        (unless (looking-at " ")
          (insert " "))
        (forward-sexp)
        (insert ,right)
        (backward-sexp)
        (indent-sexp)
        (forward-char 1)))))

(defalias 'lispy-parens
    (lispy-pair "(" ")" "^\\|\\s-\\|lambda\\|\\[\\|[(`'#@~_%,]")
  "`lispy-pair' with ().")

(defalias 'lispy-brackets
    (lispy-pair "[" "]" "\\s-\\|\\s(\\|[']")
  "`lispy-pair' with [].")

(defalias 'lispy-braces
    (lispy-pair "{" "}" "\\s-\\|\\s(\\|[{#^']")
  "`lispy-pair' with {}.")

(defun lispy-quotes (arg)
  "Insert a pair of quotes around the point.

When the region is active, wrap it in quotes instead.
When inside string, if ARG is nil quotes are quoted,
otherwise the whole string is unquoted."
  (interactive "P")
  (cond ((region-active-p)
         (lispy--surround-region "\"" "\""))

        ((lispy--in-string-p)
         (if arg
             (let* ((bnd (lispy--bounds-string))
                    (str (lispy--string-dwim bnd)))
               (delete-region (car bnd) (cdr bnd))
               (insert (read str)))
           (insert "\\\"\\\"")
           (backward-char 2)))

        (arg
         (lispy-stringify))

        (t
         (lispy--space-unless "\\s-\\|\\s(\\|[#]")
         (insert "\"\"")
         (unless (or (lispy--in-string-p)
                     (looking-at "\n\\|)\\|}\\|\\]"))
           (just-one-space)
           (backward-char 1))
         (backward-char))))

(defun lispy-parens-down ()
  "Exit the current sexp, and start a new sexp below."
  (interactive)
  (condition-case nil
      (progn
        (lispy--out-forward 1)
        (if (looking-at "\n *\\()\\)")
            (progn
              (goto-char (match-beginning 1))
              (insert "()")
              (indent-for-tab-command)
              (backward-char))

          (insert "\n()")
          (indent-for-tab-command)
          (backward-char)))
    (error (indent-new-comment-line))))

;; ——— Globals: insertion ——————————————————————————————————————————————————————
(defun lispy-space ()
  "Insert one space.
Special case is (|( -> ( |(."
  (interactive)
  (if (and (featurep 'edebug) edebug-active)
      (edebug-step-mode)
    (if (region-active-p)
        (progn
          (goto-char (region-end))
          (deactivate-mark)
          (insert " "))
      (insert " ")
      (when (and (looking-at lispy-left)
                 (looking-back "( "))
        (backward-char)))))

(defun lispy-colon ()
  "Insert :."
  (interactive)
  (lispy--space-unless "\\s-\\|\\s(\\|[:^?]")
  (insert ":"))

(defun lispy-hat ()
  "Insert ^."
  (interactive)
  (lispy--space-unless "\\s-\\|\\s(\\|[:?]")
  (insert "^"))

(defun lispy-newline-and-indent ()
  "Insert newline."
  (interactive)
  (if (eq major-mode 'lisp-interaction-mode)
      (progn
        (setq this-command 'eval-last-sexp)
        (eval-print-last-sexp))
    (newline-and-indent)
    (when (looking-at lispy-left)
      (indent-sexp))))

;; ——— Locals:  Paredit transformations ————————————————————————————————————————
(defun lispy-slurp (arg)
  "Grow current sexp by ARG sexps."
  (interactive "p")
  (cond ((region-active-p)
         (let ((bnd (lispy--bounds-dwim))
               (endp (= (point) (region-end))))
           (when (lispy-forward 1)
             (lispy-backward 1)
             (lispy--teleport (car bnd) (cdr bnd) endp t))))
        ((or (looking-at "()")
             (and (looking-at lispy-left) (not (looking-back "()"))))
         (dotimes-protect arg
           (lispy--slurp-backward)))
        ((looking-back lispy-right)
         (dotimes-protect arg
           (lispy--slurp-forward))))
  (lispy--reindent))

(defun lispy-barf (arg)
  "Shrink current sexp by ARG sexps."
  (interactive "p")
  (cond ((looking-at "()"))

        ((looking-back lispy-right)
         (dotimes-protect arg
           (lispy--barf-backward))
         (save-excursion
           (lispy--out-forward 1)
           (lispy--reindent)))

        ((looking-at lispy-left)
         (dotimes-protect arg
           (lispy--barf-forward)))))

(defun lispy-splice (arg)
  "Splice ARG sexps into containing list."
  (interactive "p")
  (dotimes-protect arg
    (let ((bnd (lispy--bounds-dwim)))
      (cond ((looking-at lispy-left)
             (save-excursion
               (goto-char (cdr bnd))
               (lispy--remove-gaps)
               (backward-delete-char 1))
             (delete-char 1)
             (if (lispy-forward 1)
                 (lispy-backward 1)
               (lispy-backward 1)
               (lispy-flow 1)))

            ((looking-back lispy-right)
             (lispy--remove-gaps)
             (backward-delete-char 1)
             (goto-char (car bnd))
             (delete-char 1)
             (if (lispy-backward 1)
                 (lispy-forward 1)
               (lispy-forward 1)
               (lispy-flow 1)))))))

(defun lispy-raise ()
  "Use current sexp or region as replacement for its parent."
  (interactive)
  (let* ((regionp (region-active-p))
         (at-end (and regionp
                      (= (point) (region-end))))
         bnd1 bnd2)
    (lispy--reindent 1)
    (setq bnd1 (lispy--bounds-dwim))
    (lispy--out-forward 1)
    (setq bnd2 (lispy--bounds-dwim))
    (unless regionp
      (goto-char (car bnd2)))
    (delete-region (cdr bnd2) (cdr bnd1))
    (delete-region (car bnd2) (car bnd1))
    (if regionp
        (progn
          (indent-region (car bnd2) (point))
          (unless at-end
            (goto-char (car bnd2)))
          (lispy--reindent 1)
          (or (looking-at lispy-left)
              (looking-back lispy-right)
              (lispy--out-forward 1)))
      (indent-sexp))))

(defun lispy-raise-some ()
  "Use current sexps as replacement for their parent.
The outcome when ahead of sexps is different from when behind."
  (interactive)
  (let ((pt (point)))
    (cond ((region-active-p))

          ((looking-at lispy-left)
           (lispy--out-forward 1)
           (backward-char 1)
           (set-mark (point))
           (goto-char pt))

          ((looking-back lispy-right)
           (lispy--out-forward 1)
           (backward-list)
           (forward-char 1)
           (set-mark (point))
           (goto-char pt))

          (t (error "Unexpected")))
    (lispy-raise)))

;; TODO add numeric arg: 1 is equivalent to prev behavior 2 will raise containing list twice.
(defun lispy-convolute ()
  "Convolute sexp."
  (interactive)
  (if (save-excursion
        (lispy--out-forward 2))
      (let ((beg (point))
            end)
        (lispy-save-excursion
         (lispy--out-forward 1)
         (setq end (backward-list))
         (lispy--out-forward 1)
         (backward-list)
         (lispy--swap-regions (cons beg end)
                              (cons (point) (point)))
         (lispy--out-forward 1)
         (lispy--reindent)))
    (error "Not enough depth to convolute")))

(defun lispy-join ()
  "Join sexps."
  (interactive)
  (let ((pt (point)))
    (cond ((looking-back lispy-right)
           (when (lispy-forward 1)
             (backward-list)
             (delete-char 1)
             (goto-char pt)
             (backward-delete-char 1)
             (lispy--out-forward 1)
             (lispy--reindent 1)))
          ((looking-at lispy-left)
           (when (lispy-backward 1)
             (forward-list)
             (backward-delete-char 1)
             (goto-char (1- pt))
             (delete-char 1)
             (lispy--out-forward 1)
             (backward-list)
             (indent-sexp))))))

(defun lispy-split ()
  "Split sexps."
  (interactive)
  (cond ((lispy--in-comment-p)
         (indent-new-comment-line))
        ((lispy--in-string-p)
         (insert "\"\"")
         (backward-char)
         (newline-and-indent))
        (t
         (when (looking-back " +")
           (delete-region (match-beginning 0)
                          (match-end 0)))
         (insert ")(")
         (backward-char)
         (newline-and-indent))))

;; ——— Locals:  more transformations ———————————————————————————————————————————
(defun lispy-move-up ()
  "Move current expression up.  Don't exit parent list."
  (interactive)
  (cond ((region-active-p)
         (let ((pt (point))
               (at-start (= (point) (region-beginning)))
               (bnd0 (save-excursion
                       (deactivate-mark)
                       (if (ignore-errors (up-list) t)
                           (lispy--bounds-dwim)
                         (cons (point-min) (point-max)))))
               (bnd1 (lispy--bounds-dwim))
               bnd2)
           (goto-char (car bnd1))
           (if (and (re-search-backward "[^ \n`'#(]" (car bnd0) t)
                    (if (lispy--in-comment-p)
                        (progn
                          (goto-char (car (lispy--bounds-comment)))
                          (backward-sexp)
                          (not (= (point) (point-min))))
                      t))
               (progn
                 (deactivate-mark)
                 (when (eq (char-after) ?\")
                   (forward-char)
                   (backward-sexp))
                 (when (memq (char-after) '(?\) ?\] ?}))
                   (forward-char))
                 (setq bnd2 (lispy--bounds-dwim))
                 (lispy--swap-regions bnd1 bnd2)
                 (setq deactivate-mark nil)
                 (goto-char (car bnd2))
                 (set-mark (point))
                 (forward-char (- (cdr bnd1) (car bnd1)))
                 (when at-start
                   (exchange-point-and-mark)))
             (goto-char pt))))
        ((and (looking-at lispy-left)
              (save-excursion
                (lispy-backward 1)))
         (let (b1 b2 s1 s2)
           (setq s1 (lispy--string-dwim (setq b1 (lispy--bounds-dwim))))
           (lispy-backward 1)
           (setq s2 (lispy--string-dwim (setq b2 (lispy--bounds-dwim))))
           (delete-region (car b1) (cdr b1))
           (save-excursion
             (goto-char (car b1))
             (insert s2))
           (delete-region (car b2) (cdr b2))
           (insert s1)
           (backward-list)))))

(defun lispy-move-down ()
  "Move current expression down.  Don't exit parent list."
  (interactive)
  (cond ((region-active-p)
         (let ((pt (point))
               (at-start (= (point) (region-beginning)))
               (bnd0 (save-excursion
                       (deactivate-mark)
                       (if (ignore-errors (up-list) t)
                           (lispy--bounds-dwim)
                         (cons (point-min) (point-max)))))
               (bnd1 (lispy--bounds-dwim))
               bnd2)
           (goto-char (cdr bnd1))
           (if (and (re-search-forward "[^ \n]" (1- (cdr bnd0)) t)
                    (if (lispy--in-comment-p)
                        (progn
                          (goto-char (cdr (lispy--bounds-comment)))
                          (re-search-forward "[^ \n]" (1- (cdr bnd0)) t))
                      t))
               (progn
                 (deactivate-mark)
                 (when (memq (char-before) '(?\( ?\" ?\[ ?{))
                   (backward-char))
                 (setq bnd2 (lispy--bounds-dwim))
                 (lispy--swap-regions bnd1 bnd2)
                 (setq deactivate-mark nil)
                 (goto-char (cdr bnd2))
                 (set-mark (point))
                 (backward-char (- (cdr bnd1) (car bnd1)))
                 (unless at-start
                   (exchange-point-and-mark)))
             (goto-char pt))))
        ((and (looking-at lispy-left)
              (save-excursion
                (and (lispy-forward 1)
                     (lispy-forward 1))))
         (let (b1 b2 s1 s2)
           (setq s1 (lispy--string-dwim (setq b1 (lispy--bounds-dwim))))
           (lispy-counterclockwise)
           (setq s2 (lispy--string-dwim (setq b2 (lispy--bounds-dwim))))
           (delete-region (car b2) (cdr b2))
           (insert s1)
           (goto-char (car b1))
           (delete-region (car b1) (cdr b1))
           (insert s2)
           (lispy-forward 1)
           (backward-list)))))

(defun lispy-clone (arg)
  "Clone sexp ARG times."
  (interactive "p")
  (let ((str (lispy--string-dwim)))
    (cond ((region-active-p)
           (let ((str (lispy--string-dwim)))
             (let (deactivate-mark)
               (save-excursion
                 (newline-and-indent)
                 (insert str)))))
          ((looking-at lispy-left)
           (save-excursion
             (dotimes-protect arg
               (insert str)
               (newline-and-indent))))
          ((looking-back lispy-right)
           (dotimes-protect arg
             (newline-and-indent)
             (insert str)))
          (t (error "Unexpected")))))

(defun lispy-oneline ()
  "Squeeze current sexp into one line.
Comments will be moved ahead of sexp."
  (interactive)
  (let (str bnd)
    (setq str (lispy--string-dwim (setq bnd (lispy--bounds-dwim))))
    (save-excursion
      (delete-region (car bnd) (cdr bnd))
      (let ((no-comment "")
            comments)
        (loop for s in (split-string str "\n" t)
           do (if (string-match "^ *\\(;\\)" s)
                  (push (substring s (match-beginning 1)) comments)
                (setq no-comment (concat no-comment "\n" s))))
        (when comments
          (insert (mapconcat #'identity comments "\n") "\n"))
        (insert (substring
                 (replace-regexp-in-string "\n *" " " no-comment) 1))))
    ;; work around `( and '(
    (lispy-forward 1)
    (lispy--normalize 0)))

(defun lispy-multiline ()
  "Spread current sexp over multiple lines."
  (interactive)
  (let ((pt (point)))
    (lispy-forward 1)
    (while (and (> (point) pt) (lispy-flow 1))
      (unless (looking-at ")\\|\n")
        (when (looking-at " *")
          (replace-match "\n")
          (backward-char 1))))
    (goto-char pt)
    (indent-sexp)))

(defun lispy-comment (&optional arg)
  "Comment ARG sexps."
  (interactive "p")
  (setq arg (or arg 1))
  (if (and (> arg 1) (lispy--in-comment-p))
      (let ((bnd (lispy--bounds-comment)))
        (uncomment-region (car bnd) (cdr bnd)))
    (dotimes-protect arg
      (let (bnd)
        (cond ((region-active-p)
               (comment-dwim nil)
               (when (lispy--in-string-or-comment-p)
                 (lispy--out-backward 1)))
              ((lispy--in-string-or-comment-p)
               (self-insert-command 1))
              ((looking-at lispy-left)
               (setq bnd (lispy--bounds-dwim))
               (lispy-counterclockwise)
               (comment-region (car bnd) (cdr bnd))
               (when (lispy--in-string-or-comment-p)
                 (lispy--out-backward 1)))
              ((looking-back lispy-right)
               (comment-dwim nil)
               (insert " "))
              ((setq bnd (save-excursion
                           (and (lispy--out-forward 1)
                                (point))))
               (let ((pt (point)))
                 (if (re-search-forward "\n" bnd t)
                     (progn (comment-region pt (point))
                            (lispy-forward 1)
                            (lispy-backward 1))
                   (comment-region (point) (1- bnd))
                   (lispy--out-backward 1))))
              (t (self-insert-command 1)))))))

(defvar lispy-meol-point 1
  "Point where `lispy-move-end-of-line' should go when already at eol.")

(defun lispy-move-end-of-line ()
  "Forward to `move-end-of-line' unless already at end of line.
Then return to the point where it was called last.
If this point is inside string, move outside string."
  (interactive)
  (let ((pt (point)))
    (if (eq pt (line-end-position))
        (if (lispy--in-string-p)
            (goto-char (cdr (lispy--bounds-string)))
          (when (and (< lispy-meol-point pt)
                     (>= lispy-meol-point (line-beginning-position)))
            (goto-char lispy-meol-point)
            (when (lispy--in-string-p)
              (goto-char (cdr (lispy--bounds-string))))))
      (setq lispy-meol-point (point))
      (move-end-of-line 1))))

(defun lispy-string-oneline ()
  "Convert current string to one line."
  (interactive)
  (when (looking-back "\"")
    (backward-char 1))
  (let (bnd str)
    (setq str (lispy--string-dwim (setq bnd (lispy--bounds-string))))
    (delete-region (car bnd) (cdr bnd))
    (insert (replace-regexp-in-string "\n" "\\\\n" str))))

(defun lispy-stringify (&optional arg)
  "Transform current sexp into a string.
Quote newlines if ARG isn't 1."
  (interactive "p")
  (setq arg (or arg 1))
  (let (str bnd)
    (setq str
          (replace-regexp-in-string
           "\"" "\\\\\""
           (replace-regexp-in-string
            "\\\\" "\\\\\\\\"
            (lispy--string-dwim (setq bnd (lispy--bounds-dwim))))))
    (unless (= arg 1)
      (setq str (replace-regexp-in-string "\n" "\\\\n" str)))
    (save-excursion
      (delete-region (car bnd) (cdr bnd))
      (insert "\""
              str
              "\""))
    ;; work around `( and '(
    (lispy-forward 1)
    (lispy-backward 1)))

(defun lispy-teleport (arg)
  "Move ARG sexps inside of result of `lispy-ace-paren'."
  (interactive "p")
  (let ((beg (point))
        end endp regionp)
    (cond ((region-active-p)
           (setq endp (= (point) (region-end)))
           (setq regionp t)
           (lispy-different))
          ((looking-at lispy-left)
           (unless (dotimes-protect arg
                     (forward-list 1))
             (error "Unexpected")))
          ((looking-back lispy-right)
           (setq endp t)
           (unless (dotimes-protect arg
                     (backward-list arg))
             (error "Unexpected")))
          (t (error "Unexpected")))
    (setq end (point))
    (goto-char beg)
    (lispy-ace-paren
     `(lambda()
        (lispy--teleport ,beg ,end ,endp ,regionp))
     t)))

;; ——— Locals:  dialect-related ————————————————————————————————————————————————
(defun lispy-eval ()
  "Eval last sexp."
  (interactive)
  (save-excursion
    (unless (or (looking-back lispy-right) (region-active-p))
      (lispy-forward 1))
    (message (lispy--eval (lispy--string-dwim)))))

(defun lispy-eval-and-insert ()
  "Eval last sexp and insert the result."
  (interactive)
  (cl-labels
      ((doit ()
             (unless (or (looking-back lispy-right) (region-active-p))
               (lispy-forward 1))
             (let ((str (lispy--eval (lispy--string-dwim))))
               (when (> (current-column) 40)
                 (newline-and-indent))
               (insert str))))
    (if (looking-at lispy-left)
        (save-excursion
          (doit))
      (doit))))

(defun lispy-goto ()
  "Jump to symbol entry point."
  (interactive)
  (require 'semantic/bovine/el)
  (semantic-mode 1)
  (lispy--select-candidate
   (mapcar #'lispy--tag-name (semantic-fetch-tags))
   #'lispy--action-jump))

(declare-function cider-jump-to-def "ext:cider")
(declare-function lispy--clojure-resolve "ext:lispy")

(defun lispy-follow ()
  "Follow to `lispy--current-function'."
  (interactive)
  (let ((symbol (lispy--current-function))
        rsymbol)
    (cond ((and (memq major-mode '(emacs-lisp-mode lisp-interaction-mode))
                (setq symbol (intern-soft symbol)))
           (cond ((fboundp symbol)
                  (push-mark)
                  (deactivate-mark)
                  (find-function symbol))
                 ((boundp symbol)
                  (push-mark)
                  (deactivate-mark)
                  (find-variable symbol))))
          ((eq major-mode 'clojure-mode)
           (setq rsymbol (lispy--clojure-resolve symbol))
           (cond ((stringp rsymbol)
                  (cider-jump-to-def rsymbol))
                 ((eq rsymbol 'special)
                  (error "Can't jump to '%s because it's special" symbol))
                 ((eq rsymbol 'keyword)
                  (error "Can't jump to keywords"))
                 ((and (listp rsymbol)
                       (eq (car rsymbol) 'variable))
                  (error "Can't jump to Java variables"))
                 (t
                  (error "Could't resolve '%s" symbol)))
           (lispy--back-to-paren)))))

(defun lispy-describe ()
  "Display documentation for `lispy--current-function'."
  (interactive)
  (let ((symbol (intern-soft (lispy--current-function))))
    (cond ((fboundp symbol)
           (describe-function symbol)))))

(defun lispy-arglist ()
  "Display arglist for `lispy--current-function'."
  (interactive)
  (let ((sym (intern-soft (lispy--current-function))))
    (cond ((fboundp sym)
           (let ((args (car (help-split-fundoc (documentation sym t) sym))))
             (message "%s" args))))))

;; ——— Locals:  ace-jump-mode  —————————————————————————————————————————————————
(defun lispy-ace-char ()
  "Call `ace-jump-char-mode' on current defun."
  (interactive)
  (let ((bnd (save-excursion
               (lispy--out-backward 50)
               (lispy--bounds-dwim))))
    (narrow-to-region (car bnd) (cdr bnd))
    (let ((ace-jump-mode-scope 'window))
      (call-interactively 'ace-jump-char-mode))
    (widen)))

(defun lispy-ace-paren (&optional func no-narrow)
  "Use `lispy--ace-do' to jump to `lispy-left' within current defun.
When FUNC is not nil, call it after a successful move.
When NO-NARROW is not nil, don't narrow."
  (interactive)
  (lispy--ace-do
   lispy-left
   (save-excursion (lispy--out-backward 50) (lispy--bounds-dwim))
   (lambda() (not (lispy--in-string-or-comment-p)))
   func
   no-narrow))

(defun lispy-ace-symbol (arg)
  "Use `lispy--ace-do' to mark to a symbol within a sexp.
Sexp is obtained by exiting list ARG times."
  (interactive "p")
  (lispy--out-forward
   (if (region-active-p)
       (progn (deactivate-mark) arg)
     (1- arg)))
  (lispy--ace-do
   "[([{ ]\\(?:\\sw\\|\\s_\\|\\s(\\|[\"'`#]\\)"
   (lispy--bounds-dwim)
   (lambda() (or (not (lispy--in-string-or-comment-p)) (looking-back ".\"")))
   (lambda() (forward-char 1) (lispy-mark-symbol))))

(defun lispy-ace-symbol-replace (arg)
  "Use `ace-jump-char-mode' to jump to a symbol within a sexp and delete it.
Sexp is obtained by exiting list ARG times."
  (interactive "p")
  (lispy--out-forward
   (if (region-active-p)
       (progn (deactivate-mark) arg)
     (1- arg)))
  (lispy--ace-do
   "[([{ ]\\(?:\\sw\\|\\s_\\|\\s(\\|[\"'`#]\\)"
   (lispy--bounds-dwim)
   (lambda() (or (not (lispy--in-string-or-comment-p)) (looking-back ".\"")))
   (lambda() (forward-char 1) (lispy-mark-symbol) (lispy-delete 1))))

;; ——— Locals:  outline ————————————————————————————————————————————————————————
(defun lispy-tab (arg)
  "Indent code and hide/show outlines."
  (interactive "p")
  (if (looking-at ";")
      (progn
        (outline-minor-mode 1)
        (condition-case e
            (outline-toggle-children)
          (error
           (if (string= (error-message-string e) "before first heading")
               (outline-next-visible-heading 1)
             (signal (car e) (cdr e))))))
    (indent-sexp)))

(defun lispy-shifttab (arg)
  "Hide/show outline summary."
  (interactive "p")
  (require 'noflet)
  (outline-minor-mode 1)
  (noflet ((org-unlogged-message (&rest x)))
    (if (get 'lispy-shifttab 'state)
        (progn
          (org-cycle '(64))
          (put 'lispy-shifttab 'state nil))
      (org-overview)
      (put 'lispy-shifttab 'state 1))))

;; ——— Locals:  miscellanea ————————————————————————————————————————————————————
(defun lispy-ert ()
  "Call (`ert' t)."
  (interactive)
  (ert t))

(defun lispy-normalize ()
  "Normalize current sexp."
  (interactive)
  (save-excursion
    (cond ((looking-at lispy-left)
           (forward-char 1))
          ((looking-back lispy-right)
           (backward-list)
           (forward-char 1))
          (t (error "Unexpected")))
    (lispy--normalize 1)))

(defun lispy-undo ()
  "Deactivate region and `undo'."
  (interactive)
  (when (region-active-p)
    (deactivate-mark t))
  (undo))

(defun lispy-view ()
  "Recenter current sexp to first screen line.
If already there, return it to previous position."
  (interactive)
  (let ((window-line (count-lines (window-start) (point))))
    (if (or (= window-line 0)
            (and (not (bolp)) (= window-line 1)))
        (recenter (or (get 'lispy-recenter :line) 0))
      (put 'lispy-recenter :line window-line)
      (recenter 0))))

;; ——— Predicates ——————————————————————————————————————————————————————————————
(defun lispy--in-string-p ()
  "Test if point is inside a string."
  (let ((beg (nth 8 (syntax-ppss))))
    (and beg
         (eq (char-after beg) ?\"))))

(defun lispy--in-comment-p ()
  "Test if point is inside a comment."
  (save-excursion
    (unless (eolp)
      (forward-char 1))
    (let ((beg (nth 8 (syntax-ppss))))
      (and beg
           (comment-only-p beg (point))))))

(defun lispy--in-string-or-comment-p ()
  "Test if point is inside a string or a comment."
  (let ((beg (nth 8 (syntax-ppss))))
    (and beg
         (or (eq (char-after beg) ?\")
             (comment-only-p beg (point))))))

;; ——— Pure ————————————————————————————————————————————————————————————————————
(defun lispy--bounds-dwim ()
  "Return a cons of region bounds if it's active.
Otherwise return cons of current string, symbol or list bounds."
  (cond ((region-active-p)
         (cons (region-beginning)
               (region-end)))
        ((looking-back lispy-right)
         (backward-list)
         (prog1 (bounds-of-thing-at-point 'sexp)
           (forward-list)))
        ((or (looking-at (format "[`'#]*%s\\|\"" lispy-left))
             (looking-at "[`'#]"))
          (bounds-of-thing-at-point 'sexp))
        ((looking-back "\"")
         (backward-sexp)
         (prog1 (bounds-of-thing-at-point 'sexp)
           (forward-sexp)))
        (t
         (or
          (ignore-errors
            (bounds-of-thing-at-point 'symbol))
          (ignore-errors
            (bounds-of-thing-at-point 'sentence))))))

(defun lispy--bounds-list ()
  "Return the bounds of smallest list that includes the point.
First, try to return `lispy--bounds-string'."
  (save-excursion
    (when (memq (char-after) '(?\( ?\[ ?\{))
      (forward-char))
    (ignore-errors
      (let (beg end)
        (up-list)
        (setq end (point))
        (backward-list)
        (setq beg (point))
        (cons beg end)))))

(defun lispy--bounds-string ()
  "Return bounds of current string."
  (let ((beg (or (nth 8 (syntax-ppss))
                 (and (memq (char-after (point))
                            '(?\" ?\'))
                      (point)))))
    (when beg
      (cons beg (save-excursion
                  (goto-char beg)
                  (forward-sexp)
                  (point))))))

(defun lispy--bounds-comment ()
  "Return bounds of current comment."
  (and (lispy--in-comment-p)
       (save-excursion
         (when (lispy--beginning-of-comment)
           (let ((pt (point)))
             (while (and (lispy--in-comment-p)
                         (forward-comment -1)
                         (= 1 (- (count-lines (point) pt)
                                 (if (bolp) 0 1))))
               (setq pt (point)))
             (goto-char pt))
           (let ((beg (lispy--beginning-of-comment))
                 (pt (point)))
             (while (and (lispy--in-comment-p)
                         (forward-comment 1)
                         (lispy--beginning-of-comment)
                         (= 1 (- (count-lines pt (point))
                                 (if (bolp) 0 1))))
               (setq pt (point)))
             (goto-char pt)
             (end-of-line)
             (cons beg (point)))))))

(defun lispy--beginning-of-comment ()
  "Go to beginning of comment on current line."
  (end-of-line)
  (let ((cs (comment-search-backward (line-beginning-position) t)))
      (when cs
        (goto-char cs))))

(defun lispy--comment-search-forward (dir)
  "Search for a first comment in direction DIR.
Move to the end of line."
  (while (not (lispy--in-comment-p))
    (forward-line dir)
    (end-of-line)))

(defun lispy--string-dwim (&optional bounds)
  "Return the string that corresponds to BOUNDS.
`lispy--bounds-dwim' is used if BOUNDS is nil."
  (destructuring-bind (beg . end) (or bounds (lispy--bounds-dwim))
    (buffer-substring-no-properties beg end)))

(defun lispy--current-function ()
  "Return current function as string."
  (if (region-active-p)
      (let ((str (lispy--string-dwim)))
        (if (string-match "^[#'`]*\\(.*\\)$" str)
            (match-string 1 str)
          nil))
    (save-excursion
      (lispy--back-to-paren)
      (when (looking-at "(\\([^ \n)]+\\)[ )\n]")
        (match-string 1)))))

;; ——— Utilities: movement —————————————————————————————————————————————————————
(defvar lispy-ignore-whitespace nil
  "When set to t, `lispy-out-forward' will not clean up whitespace.")

(defun lispy--out-forward (arg)
  "Move outside list forwards ARG times.
Return nil on failure, (point) otherwise."
  (lispy--exit-string)
  (catch 'break
    (dotimes (i arg)
      (if (ignore-errors (up-list) t)
          (progn
            (unless lispy-ignore-whitespace
              (lispy--remove-gaps))
            (indent-for-tab-command))
        (when (looking-at lispy-left)
          (forward-list))
        (throw 'break nil)))
    (point)))

(defun lispy--out-backward (arg)
  "Move outside list forwards ARG times.
Return nil on failure, t otherwise."
  (lispy--out-forward arg)
  (when (looking-back lispy-right)
    (lispy-backward 1)))

(defun lispy--back-to-paren ()
  "Move to ( going out backwards."
  (let ((lispy-ignore-whitespace t))
    (while (and (not (looking-at "("))
                (lispy--out-backward 1)))))

(defun lispy--exit-string ()
  "When in string, go to its beginning."
  (let ((s (syntax-ppss)))
    (when (nth 3 s)
      (goto-char (nth 8 s)))))

;; ——— Utilities: evaluation ———————————————————————————————————————————————————
(defun lispy--eval (str)
  "Eval STR according to current `major-mode'."
  (funcall
   (cond
     ((memq major-mode '(emacs-lisp-mode lisp-interaction-mode))
      'lispy--eval-elisp)
     ((eq major-mode 'clojure-mode)
      (require 'le-clojure)
      'lispy--eval-clojure)
     ((eq major-mode 'scheme-mode)
      (require 'le-scheme)
      'lispy--eval-scheme)
     ((eq major-mode 'lisp-mode)
      (require 'le-lisp)
      'lispy--eval-lisp)
     (t (error "%s isn't supported currently" major-mode)))
   str))

(defun lispy--eval-elisp (str)
  "Eval STR as Elisp code."
  (prin1-to-string
   (eval (read str))))

;; ——— Utilities: tags —————————————————————————————————————————————————————————
(defvar lispy-tag-arity-alist
  '(("setq" . 2)
    ("setq-default" . 2)
    ("add-to-list" . 2)
    ("add-hook" . 2)
    ("load" . 1)
    ("load-file" . 1)
    ("define-key" . 2)
    ("ert-deftest" . 1)
    ("declare-function" . 1)
    ("defalias" . 2)
    ("make-variable-buffer-local" . 1))
  "Alist of tag arities for `lispy--tag-name-overlay'.")

(defvar lispy-tag-regexp
  (concat
   "\\_<"
   (regexp-opt
    (mapcar #'car lispy-tag-arity-alist))
   "\\_>")
  "Regexp for tags that we'd like to know more about.")

(defun lispy--tag-name (x)
  "Given a semantic tag X, amend it with additional info.
For example, a `setq' statement is amended with variable name that it uses."
  (or
   (catch 'break
     (unless (memq major-mode '(emacs-lisp-mode lisp-interaction-mode))
       (throw 'break nil))
     (cons
      (cond
        ((eq (cadr x) 'include)
         (concat (propertize "require" 'face 'font-lock-keyword-face)
                 " " (car x)))
        ((eq (cadr x) 'package)
         (concat (propertize "provide" 'face 'font-lock-keyword-face)
                 " " (car x)))
        ((eq (cadr x) 'customgroup)
         (concat (propertize "defgroup" 'face 'font-lock-keyword-face)
                 " " (car x)))
        ((eq (cadr x) 'function)
         (propertize (car x) 'face 'font-lock-function-name-face))
        ((eq (cadr x) 'variable)
         (concat (propertize "defvar" 'face 'font-lock-keyword-face)
                 " " (car x)))
        ((string-match lispy-tag-regexp (car x))
         (lispy--tag-name-overlay x))
        (t (throw 'break nil)))
      (cdr x)))
   x))

(defun lispy--tag-name-overlay (x)
  "Return tag info for X based on its overlay."
  (let ((overlay (nth 4 x)))
    (unless (overlayp overlay)
      (throw 'break nil))
    (format
     "%s %s"
     (car x)
     (with-current-buffer (overlay-buffer overlay)
       (save-excursion
         (goto-char (overlay-start overlay))
         (unless (re-search-forward lispy-tag-regexp nil t)
           (throw 'break nil))
         (let ((tag-head (match-string 0))
               beg arity)
           (skip-chars-forward " \n")
           (if (setq arity (cdr (assoc tag-head lispy-tag-arity-alist)))
               (progn
                 (setq beg (point))
                 (forward-sexp arity)
                 (let ((str (replace-regexp-in-string
                             "\n" " " (buffer-substring beg (point)))))
                   (if (> (length str) 60)
                       (concat (substring str 0 57) "...")
                     str)))
             (lispy--string-dwim))))))))

;; ——— Utilities: slurping and barfing —————————————————————————————————————————
(defun lispy--slurp-forward ()
  "Grow current sexp forward by one sexp."
  (unless (looking-back "[()])")
    (just-one-space)
    (backward-char 1))
  (let ((pt (point))
        (char (char-before))
        (beg (save-excursion (backward-list) (point))))
    (when (ignore-errors
            (forward-sexp) t)
      (delete-region (1- pt) pt)
      (insert char))))

(defun lispy--slurp-backward ()
  "Grow current sexp backward by one sexp."
  (let ((pt (point))
        (char (char-after)))
    (backward-sexp)
    (delete-region pt (1+ pt))
    (insert char)
    (backward-char)))

(defun lispy--barf-forward ()
  "Shrink current sexp forward by one sexp."
  (let ((pt (point))
        (char (char-after)))
    (unless (looking-at "()")
      (forward-char)
      (forward-sexp)
      (delete-region pt (1+ pt))
      (skip-chars-forward " \n	")
      (insert char)
      (backward-char)
      (indent-region pt (point))
      (lispy--reindent 1))))

(defun lispy--barf-backward ()
  "Shrink current sexp backward by one sexp."
  (let ((pt (point))
        (char (char-before)))
    (unless (looking-back "()")
      (backward-char)
      (backward-sexp)
      (skip-chars-backward " \n	")
      (while (lispy--in-comment-p)
        (goto-char (comment-beginning))
        (skip-chars-backward " \n	"))
      (delete-region (1- pt) pt)
      (insert char)
      (indent-region (point) pt))))

;; ——— Utilities: rest —————————————————————————————————————————————————————————
(defun lispy--remove-gaps ()
  "Remove dangling `\\s)'."
  (when (or (looking-back "[^ \t\n]\\([ \t\n]+\\)\\s)")
            (and (looking-back "\\s)\\([ \t\n]+\\)")
                 (not (looking-at lispy-left)))
            (looking-at "\\([\t\n ]*\\))"))
    (unless (save-excursion
              (save-match-data
                (goto-char (match-beginning 1))
                (lispy--in-string-or-comment-p)))
      (delete-region (match-beginning 1)
                     (match-end 1)))))

(defun lispy--surround-region (alpha omega)
  "Surround active region with ALPHA and OMEGA and re-indent."
  (let ((beg (region-beginning))
        (end (region-end)))
    (goto-char end)
    (insert omega)
    (goto-char beg)
    (insert alpha)
    (indent-region beg (+ 2 end))))

(defun lispy--mark (bnd)
  "Mark BND.  BND is a cons of beginning and end positions."
  (destructuring-bind (beg . end) bnd
    (goto-char beg)
    (set-mark-command nil)
    (goto-char end)))

(defun lispy--space-unless (context)
  "Insert one space.
Unless inside string or comment, or `looking-back' at CONTEXT."
  (unless (or lispy-no-space (lispy--in-string-or-comment-p)
              (looking-back context))
    (insert " ")))

(defun lispy--reindent (&optional arg)
  "Reindent current sexp.  Up-list ARG times before that."
  (cond (arg
         (lispy-save-excursion
          (lispy--out-forward arg)
          (backward-list)
          (indent-sexp)))

        ((looking-back lispy-right)
         (save-excursion
           (backward-list)
           (indent-sexp)))

        ((looking-at lispy-left)
         (indent-sexp))

        (t
         (save-excursion
           (lispy--out-forward 1)
           (backward-list)
           (indent-sexp)))))

(defun lispy--delete ()
  "Delete one sexp."
  (unless (looking-at lispy-left)
    (error "Bad position"))
  (let ((bnd (lispy--bounds-list)))
    (delete-region (car bnd) (cdr bnd))
    (if (looking-at "[\n ]+")
        (delete-region (match-beginning 0)
                       (match-end 0))
      (just-one-space)
      (when (looking-back "( ")
        (backward-delete-char 1)))
    (lispy-forward 1)
    (backward-list)))

(declare-function helm "ext:helm")

(defun lispy--select-candidate (candidates action)
  "Select from CANDIDATES list with `helm'.
ACTION is called for the selected candidate."
  (require 'helm)
  (require 'helm-help)
  (helm :sources
        `((name . "Candidates")
          (candidates . ,(mapcar
                          (lambda(x)
                            (if (listp x)
                                (if (stringp (cdr x))
                                    (cons (cdr x) (car x))
                                  (cons (car x) x))
                              x)) candidates))
          (action . ,action))))

(defun lispy--action-jump (tag)
  "Jump to TAG."
  (when (semantic-tag-p tag)
    (push-mark)
    (semantic-go-to-tag tag)
    (when (eq major-mode 'clojure-mode)
      (lispy-backward 1))
    (switch-to-buffer (current-buffer))))

(defun lispy--recenter-bounds (bnd)
  "Make sure BND is visible in window.
BND is a cons of start and end points."
  (cond ((> (count-lines (car bnd) (cdr bnd))
            (window-height)))
        ((< (car bnd) (window-start))
         (save-excursion
           (goto-char (car bnd))
           (recenter 0)))
        ((> (cdr bnd) (window-end))
         (save-excursion
           (goto-char (cdr bnd))
           (recenter -1)))))

(defun lispy--ace-do (x bnd &optional filter func no-narrow)
  "Use `ace-jump-do' to X within BND when FILTER holds.
When FUNC is not nil, call it after a successful move."
  (require 'ace-jump-mode)
  (lispy--recenter-bounds bnd)
  (unless no-narrow
    (narrow-to-region (car bnd) (cdr bnd)))
  (when func
    (setq ace-jump-mode-end-hook
          (list `(lambda()
                   (setq ace-jump-mode-end-hook)
                   (,func)))))
  (let ((ace-jump-mode-scope 'window)
        (ace-jump-search-filter filter))
    (ace-jump-do x))
  (widen))

(defun lispy--normalize (arg)
  "Go up ARG times and normalize."
  (lispy--out-backward arg)
  (let ((bnd (lispy--bounds-list)))
    (save-excursion
      (narrow-to-region (car bnd) (cdr bnd))
      (lispy--do-replace "[^ ]\\( \\{2,\\}\\)[^ ]" " ")
      (lispy--do-replace "[^\\\\]\\(([\n ]+\\)" "(")
      (lispy--do-replace "\\([\n ]+)\\)" ")")
      (lispy--do-replace "\\([ ]+\\)\n" "")
      (lispy--do-replace ")\\([^ \n)]\\)" " \\1")
      (widen))))

(defun lispy--do-replace (from to)
  "Replace first match group of FROM to TO."
  (goto-char (point-min))
  (let (mb me ms)
    (while (and (re-search-forward from nil t)
                (setq mb (match-beginning 1))
                (setq me (match-end 1))
                (setq ms (match-string 1)))
      (goto-char mb)
      (if (or (lispy--in-string-or-comment-p)
              (looking-back "^"))
          (goto-char me)
        (delete-region mb me)
        (when (cl-search "\\1" to)
          (setq to (replace-regexp-in-string "\\\\1" ms to)))
        (insert to)))))

(defun lispy--teleport (beg end endp regionp)
  "Move text from between BEG END to point.
Leave point at the beginning or end of text depending on ENDP.
Make text marked if REGIONP is t."
  (let ((str (buffer-substring-no-properties beg end))
        (beg1 (1+ (point)))
        end1
        (size (buffer-size)))
    (if (and (>= (point) beg)
             (<= (point) end))
        (progn
          (message "Can't teleport expression inside itself")
          (goto-char beg))
      (goto-char beg)
      (delete-region beg end)
      (delete-blank-lines)
      (when (> beg1 beg)
        (decf beg1 (- size (buffer-size))))
      (goto-char beg1)
      (insert str)
      (unless (looking-at "[\n)]")
        (insert "\n")
        (backward-char))
      (lispy-save-excursion
        (goto-char (1- beg1))
        (indent-sexp))
      (if regionp
          (progn
            (setq deactivate-mark nil)
            (set-mark-command nil)
            (goto-char beg1)
            (when endp
              (exchange-point-and-mark)))
        (unless endp
          (goto-char beg1))))))

(defun lispy--swap-regions (bnd1 bnd2)
  "Swap buffer regions BND1 and BND2."
  (when (> (car bnd1) (car bnd2))
    (cl-rotatef bnd1 bnd2))
  (let ((str1 (lispy--string-dwim bnd1))
        (str2 (lispy--string-dwim bnd2)))
    (goto-char (car bnd2))
    (delete-region (car bnd2) (cdr bnd2))
    (insert str1)
    (goto-char (car bnd1))
    (delete-region (car bnd1) (cdr bnd1))
    (insert str2)
    (goto-char (car bnd1))))

(defun lispy--insert-or-call (def &optional from-start)
  "Return a lambda to call DEF if position is special.
Otherwise call `self-insert-command'.
When FROM-START is t, call DEF as if it was invoked from beginning of
list."
  `(lambda ,(help-function-arglist def)
     ,(format "Call `%s' when special, self-insert otherwise.\n\n%s"
              (symbol-name def) (documentation def))
     ,(interactive-form def)
     (cond ((region-active-p)
            (call-interactively ',def))

           ((lispy--in-string-or-comment-p)
            (self-insert-command 1))

           ((looking-at lispy-left)
            (call-interactively ',def))

           ((looking-back lispy-right)
            ,@(and from-start '((backward-list)))
            (unwind-protect
                 (call-interactively ',def)
              ,@(and from-start '((forward-list)))))

           ((or (and (looking-back "^ *") (looking-at ";"))
                (and (= (point) (point-max))
                     (memq ',def `(outline-previous-visible-heading))))
            (call-interactively ',def))

           (t
            (self-insert-command 1)))))

(defvar ac-trigger-commands '(self-insert-command))

(defadvice ac-handle-post-command (around ac-post-command-advice activate)
  "Don't `auto-complete' when region is active."
  (unless (region-active-p)
    ad-do-it))

(defun lispy-define-key (keymap key def &optional from-start)
  "Forward to (`define-key' KEYMAP KEY (`lispy-defun' DEF FROM-START))."
  (let ((func (defalias (intern (concat "special-" (symbol-name def)))
                  (lispy--insert-or-call def from-start))))
    (unless (member func ac-trigger-commands)
      (push func ac-trigger-commands))
    (define-key keymap (kbd key) func)))

(let ((map lispy-mode-map))
  ;; ——— globals: navigation ——————————————————
  (define-key map (kbd "]") 'lispy-forward)
  (define-key map (kbd "[") 'lispy-backward)
  (define-key map (kbd ")") 'lispy-out-forward-nostring)
  (define-key map (kbd "C-3") 'lispy-out-forward)
  (define-key map (kbd "C-9") 'lispy-out-forward-newline)
  ;; ——— locals: navigation ———————————————————
  (lispy-define-key map "l" 'lispy-out-forward)
  (lispy-define-key map "a" 'lispy-out-backward)
  (lispy-define-key map "f" 'lispy-flow)
  (lispy-define-key map "j" 'lispy-down)
  (lispy-define-key map "k" 'lispy-up)
  (lispy-define-key map "d" 'lispy-different)
  (lispy-define-key map "o" 'lispy-counterclockwise)
  (lispy-define-key map "p" 'lispy-clockwise)
  (lispy-define-key map "J" 'outline-next-visible-heading)
  (lispy-define-key map "K" 'outline-previous-visible-heading)
  ;; ——— globals: kill-related ————————————————
  (define-key map (kbd "C-k") 'lispy-kill)
  (define-key map (kbd "C-y") 'lispy-yank)
  (define-key map (kbd "C-d") 'lispy-delete)
  (define-key map (kbd "DEL") 'lispy-delete-backward)
  (define-key map (kbd "M-m") 'lispy-mark-symbol)
  (define-key map (kbd "M-o") 'lispy-string-oneline)
  (define-key map (kbd "C-c p") 'lispy-pop-copy)
  (define-key map (kbd "C-,") 'lispy-kill-at-point)
  (define-key map (kbd "C-M-,") 'lispy-mark)
  ;; ——— globals: pairs ———————————————————————
  (define-key map (kbd "(") 'lispy-parens)
  (define-key map (kbd "{") 'lispy-braces)
  (define-key map (kbd "}") 'lispy-brackets)
  (define-key map (kbd "\"") 'lispy-quotes)
  ;; ——— globals: insertion ———————————————————
  (define-key map (kbd "C-8") 'lispy-parens-down)
  (define-key map (kbd "SPC") 'lispy-space)
  (define-key map (kbd ":") 'lispy-colon)
  (define-key map (kbd "^") 'lispy-hat)
  (define-key map (kbd "C-j") 'lispy-newline-and-indent)
  (define-key map (kbd "M-j") 'lispy-split)
  (define-key map (kbd "RET") 'newline-and-indent)
  (define-key map (kbd ";") 'lispy-comment)
  (define-key map (kbd "C-e") 'lispy-move-end-of-line)
  ;; ——— locals: Paredit transformations ——————
  (lispy-define-key map ">" 'lispy-slurp)
  (lispy-define-key map "<" 'lispy-barf)
  (lispy-define-key map "/" 'lispy-splice)
  (lispy-define-key map "r" 'lispy-raise t)
  (lispy-define-key map "R" 'lispy-raise-some)
  (lispy-define-key map "+" 'lispy-join)
  ;; ——— locals: more transformations —————————
  (lispy-define-key map "C" 'lispy-convolute t)
  (lispy-define-key map "w" 'lispy-move-up t)
  (lispy-define-key map "s" 'lispy-move-down t)
  (lispy-define-key map "O" 'lispy-oneline t)
  (lispy-define-key map "M" 'lispy-multiline t)
  (lispy-define-key map "S" 'lispy-stringify)
  ;; ——— globals: miscellanea —————————————————
  (define-key map (kbd "C-1") 'lispy-describe-inline)
  (define-key map (kbd "C-2") 'lispy-arglist-inline)
  ;; ——— locals: marking ——————————————————————
  (lispy-define-key map "h" 'lispy-ace-symbol)
  (lispy-define-key map "H" 'lispy-ace-symbol-replace)
  (lispy-define-key map "m" 'lispy-mark-list)
  ;; ——— locals: dialect-specific —————————————
  (lispy-define-key map "e" 'lispy-eval)
  (lispy-define-key map "E" 'lispy-eval-and-insert)
  (lispy-define-key map "g" 'lispy-goto)
  (lispy-define-key map "F" 'lispy-follow)
  (lispy-define-key map "D" 'lispy-describe)
  (lispy-define-key map "A" 'lispy-arglist)
  ;; ——— locals: miscellanea ——————————————————
  (lispy-define-key map "i" 'lispy-tab t)
  (lispy-define-key map "I" 'lispy-shifttab)
  (lispy-define-key map "N" 'lispy-normalize)
  (lispy-define-key map "c" 'lispy-clone)
  (lispy-define-key map "u" 'lispy-undo)
  (lispy-define-key map "q" 'lispy-ace-paren)
  (lispy-define-key map "Q" 'lispy-ace-char)
  (lispy-define-key map "v" 'lispy-view t)
  (lispy-define-key map "T" 'lispy-ert)
  (lispy-define-key map "t" 'lispy-teleport)
  ;; ——— locals: digit argument ———————————————
  (mapc (lambda (x) (lispy-define-key map (format "%d" x) 'digit-argument))
        (number-sequence 0 9)))

(provide 'lispy)

;;; Local Variables:
;;; outline-regexp: ";; ———"
;;; End:

;;; lispy.el ends here
