;;;;  -*- Mode: Lisp; Syntax: Common-Lisp; Package: C -*-
;;;;
;;;;  Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
;;;;  Copyright (c) 1990, Giuseppe Attardi.
;;;;
;;;;    This program is free software; you can redistribute it and/or
;;;;    modify it under the terms of the GNU Library General Public
;;;;    License as published by the Free Software Foundation; either
;;;;    version 2 of the License, or (at your option) any later version.
;;;;
;;;;    See file '../Copyright' for full details.

;;;; CMPEXIT  Exit manager.

(in-package "COMPILER")

(defun unwind-bds (bds-lcl bds-bind stack-frame ihs-p)
  (declare (fixnum bds-bind))
  (when stack-frame
    (if (stringp stack-frame)
	(wt-nl "ecl_stack_frame_close(" stack-frame ");")
	(wt-nl "ECL_STACK_SET_INDEX(cl_env_copy," stack-frame ");")))
  (when bds-lcl
    (wt-nl "ecl_bds_unwind(cl_env_copy," bds-lcl ");"))
  (if (< bds-bind 4)
      (dotimes (n bds-bind)
	(declare (fixnum n))
	(wt-nl "ecl_bds_unwind1(cl_env_copy);"))
      (wt-nl "ecl_bds_unwind_n(cl_env_copy," bds-bind ");"))
  (case ihs-p
    (IHS (wt-nl "ecl_ihs_pop(cl_env_copy);"))
    (IHS-ENV (wt-nl "ihs.lex_env = _ecl_debug_env;"))))

(defun unwind-exit (loc &optional (jump-p nil) &aux (bds-lcl nil) (bds-bind 0) (stack-frame nil) (ihs-p nil))
  (declare (fixnum bds-bind))
  (when (consp *destination*)
    (case (car *destination*)
      (JUMP-TRUE
       (set-jump-true loc (second *destination*))
       (when (eq loc t) (return-from unwind-exit)))
      (JUMP-FALSE
       (set-jump-false loc (second *destination*))
       (when (eq loc nil) (return-from unwind-exit)))))
  (dolist (ue *unwind-exit* (baboon))
    ;; perform all unwind-exit's which precede *exit*
    (cond
      ((consp ue)		    ; ( label# . ref-flag )| (STACK n) |(LCL n)
       (cond ((eq (car ue) 'STACK)
	      (setf stack-frame (second ue)))
	     ((eq (car ue) 'LCL)
	      (setq bds-lcl ue bds-bind 0))
	     ((eq ue *exit*)
	      ;; all body forms except the last (returning) are dealt here
	      (cond ((and (consp *destination*)
			  (or (eq (car *destination*) 'JUMP-TRUE)
			      (eq (car *destination*) 'JUMP-FALSE)))
		     (unwind-bds bds-lcl bds-bind stack-frame ihs-p))
		    ((not (or bds-lcl (plusp bds-bind) stack-frame))
		     (set-loc loc))
		    ;; Save the value if LOC may possibly refer
		    ;; to special binding.
		    ((or (loc-refers-to-special loc)
			 (loc-refers-to-special *destination*))
		     (let* ((*temp* *temp*)
			    (temp (make-temp-var)))
		       (let ((*destination* temp))
			 (set-loc loc)) ; temp <- loc
		       (unwind-bds bds-lcl bds-bind stack-frame ihs-p)
		       (set-loc temp))) ; *destination* <- temp
		    (t
		     (set-loc loc)
		     (unwind-bds bds-lcl bds-bind stack-frame ihs-p)))
	      (when jump-p (wt-nl) (wt-go *exit*))
	      (return))
	     (t (setq jump-p t))))
      ((numberp ue) (baboon)
       (setq bds-lcl ue bds-bind 0))
      (t (case ue
	   (IHS (setf ihs-p ue))
           (IHS-ENV (setf ihs-p (or ihs-p ue)))
	   (BDS-BIND (incf bds-bind))
	   (RETURN
	     (unless (eq *exit* 'RETURN) (baboon))
	     ;; *destination* must be either RETURN or TRASH.
	     (cond ((eq loc 'VALUES)
		    ;; from multiple-value-prog1 or values
		    (unwind-bds bds-lcl bds-bind stack-frame ihs-p)
		    (wt-nl "return cl_env_copy->values[0];"))
		   ((eq loc 'RETURN)
		    ;; from multiple-value-prog1 or values
		    (unwind-bds bds-lcl bds-bind stack-frame ihs-p)
		    (wt-nl "return value0;"))      
		   (t
		    (let* ((*destination* 'RETURN))
		      (set-loc loc))
		    (unwind-bds bds-lcl bds-bind stack-frame ihs-p)
		    (wt-nl "return value0;")))
	     (return))
	   ((RETURN-FIXNUM RETURN-CHARACTER RETURN-DOUBLE-FLOAT
	     RETURN-SINGLE-FLOAT RETURN-OBJECT)
	    (when (eq *exit* ue)
	      ;; *destination* must be RETURN-FIXNUM
	      (setq loc (list 'COERCE-LOC
			      (getf '(RETURN-FIXNUM :fixnum
				      RETURN-CHARACTER :char
				      RETURN-SINGLE-FLOAT :float
				      RETURN-DOUBLE-FLOAT :double
				      RETURN-OBJECT :object)
				    ue)
			      loc))
	      (if (or bds-lcl (plusp bds-bind))
		  (let ((lcl (make-lcl-var :type (second loc))))
		    (wt-nl "{cl_fixnum " lcl "= " loc ";")
		    (unwind-bds bds-lcl bds-bind stack-frame ihs-p)
		    (wt-nl "return(" lcl ");}"))
		  (progn
		    (wt-nl "return(" loc ");")))
	      (return)))
	   (FRAME
	    (let ((*destination* (tmp-destination *destination*)))
	      (set-loc loc)
	      (setq loc *destination*))
	    (wt-nl "ecl_frs_pop(cl_env_copy);"))
	   (TAIL-RECURSION-MARK)
	   (JUMP (setq jump-p t))
	   (t (baboon))))))
  ;;; Never reached
  )

(defun unwind-no-exit (exit &aux (bds-lcl nil) (bds-bind 0) (stack-frame nil) (ihs-p nil))
  (declare (fixnum bds-bind))
  (dolist (ue *unwind-exit* (baboon))
    (cond
       ((consp ue)
	(cond ((eq ue exit)
	       (unwind-bds bds-lcl bds-bind stack-frame ihs-p)
	       (return))
	      ((eq (first ue) 'STACK)
	       (setf stack-frame (second ue)))))
       ((numberp ue) (setq bds-lcl ue bds-bind 0))
       ((eq ue 'BDS-BIND) (incf bds-bind))
       ((member ue '(RETURN RETURN-OBJECT RETURN-FIXNUM RETURN-CHARACTER
                            RETURN-DOUBLE-FLOAT RETURN-SINGLE-FLOAT))
        (if (eq exit ue)
          (progn (unwind-bds bds-lcl bds-bind stack-frame ihs-p)
                 (return))
          (baboon))
        ;;; Never reached
        )
       ((eq ue 'FRAME) (wt-nl "ecl_frs_pop(cl_env_copy);"))
       ((eq ue 'TAIL-RECURSION-MARK)
        (if (eq exit 'TAIL-RECURSION-MARK)
          (progn (unwind-bds bds-lcl bds-bind stack-frame ihs-p)
                 (return))
          (baboon))
        ;;; Never reached
        )
       ((eq ue 'JUMP))
       ((eq ue 'IHS-ENV)
        (setf ihs-p ue))
       (t (baboon))
       ))
  ;;; Never reached
  )

;;; Tail-recursion optimization for a function F is possible only if
;;;	1. F receives only required parameters, and
;;;	2. no required parameter of F is enclosed in a closure.
;;;
;;; A recursive call (F e1 ... en) may be replaced by a loop only if
;;;	1. F is not declared as NOTINLINE,
;;;	2. n is equal to the number of required parameters of F,
;;;	3. the form is a normal function call (i.e. args are not ARGS-PUSHED),
;;;	4. (F e1 ... en) is not surrounded by a form that causes dynamic
;;;	   binding (such as LET, LET*, PROGV),
;;;	5. (F e1 ... en) is not surrounded by a form that that pushes a frame
;;;	   onto the frame-stack (such as BLOCK and TAGBODY whose tags are
;;;	   enclosed in a closure, and CATCH),

(defun tail-recursion-possible ()
  (dolist (ue *unwind-exit* (baboon))
    (cond ((eq ue 'TAIL-RECURSION-MARK) (return t))
          ((or (numberp ue) (eq ue 'BDS-BIND) (eq ue 'FRAME))
           (return nil))
          ((or (consp ue) (eq ue 'JUMP) (eq ue 'IHS-ENV)))
          (t (baboon)))))

(defun c2try-tail-recursive-call (fun args)
  (when (and *tail-recursion-info*
	     (eq fun (first *tail-recursion-info*))
	     (last-call-p)
	     (tail-recursion-possible)
	     (inline-possible (fun-name fun))
	     (= (length args) (length (rest *tail-recursion-info*))))
    (let* ((*destination* 'TRASH)
	   (*exit* (next-label))
	   (*unwind-exit* (cons *exit* *unwind-exit*)))
      (c2psetq (cdr *tail-recursion-info*) args)
      (wt-label *exit*))
    (unwind-no-exit 'TAIL-RECURSION-MARK)
    (wt-nl "goto TTL;")
    (cmpnote "Tail-recursive call of ~s was replaced by iteration."
	     (fun-name fun))
    t))
