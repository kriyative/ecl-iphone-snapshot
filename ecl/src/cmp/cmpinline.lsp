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

;;;; CMPINLINE  Open coding optimizer.

(in-package "COMPILER")

;;; Valid property names for open coded functions are:
;;;  :INLINE-ALWAYS
;;;  :INLINE-SAFE	safe-compile only
;;;  :INLINE-UNSAFE	non-safe-compile only
;;;
;;; Each property is a list of 'inline-info's, where each inline-info is:
;;; ( types { type | boolean } { string | function } ).
;;;
;;; For each open-codable function, open coding will occur only if there exits
;;; an appropriate property with the argument types equal to 'types' and with
;;; the return-type equal to 'type'.  The third element
;;; is T if and only if side effects may occur by the call of the function.
;;; Even if *DESTINATION* is TRASH, open code for such a function with side
;;; effects must be included in the compiled code.
;;; The forth element is T if and only if the result value is a new Lisp
;;; object, i.e., it must be explicitly protected against GBC.

(defun make-inline-temp-var (expected-type value-type &optional loc)
  (let ((out-rep-type (lisp-type->rep-type expected-type)))
    (if (eq out-rep-type :object)
        (make-temp-var)
        (let ((var (make-lcl-var :rep-type out-rep-type
                                 :type (type-and expected-type value-type))))
          (if loc
              (wt-nl "{" (rep-type-name out-rep-type) " " var "=" loc ";")
              (wt-nl "{" (rep-type-name out-rep-type) " " var ";"))
          (incf *inline-blocks*)
          var))))

(defun emit-inlined-variable (form expected-type rest-forms)
  (let ((var (c1form-arg 0 form))
        (value-type (c1form-primary-type form)))
    (if (var-changed-in-form-list var rest-forms)
        (let* ((temp (make-inline-temp-var expected-type value-type var)))
          (let ((*destination* temp)) (set-loc var))
          (list value-type temp))
        (list value-type var))))

(defun emit-inlined-setq (form expected-type rest-forms)
  (let ((vref (c1form-arg 0 form))
        (form1 (c1form-arg 1 form)))
    (let ((*destination* vref)) (c2expr* form1))
    (if (eq (c1form-name form1) 'LOCATION)
        (list (c1form-primary-type form1) (c1form-arg 0 form1))
        (emit-inlined-variable (make-c1form 'VAR form vref) expected-type rest-forms))))

(defun emit-inlined-call-global (form expected-type)
  (let* ((fname (c1form-arg 0 form))
         (args (c1form-arg 1 form))
         (return-type (c1form-primary-type form))
         (loc (call-global-loc fname nil args return-type expected-type))
         (type (loc-type loc))
         (temp (make-inline-temp-var expected-type type))
         (*destination* temp))
    (set-loc loc)
    (list type temp)))

(defun emit-inlined-structure-ref (form expected-type rest-forms)
  (let ((type (c1form-primary-type form)))
    (if (args-cause-side-effect rest-forms)
        (let* ((temp (make-inline-temp-var expected-type type))
               (*destination* temp))
          (c2expr* form)
          (list type temp))
        (list type
              (list 'SYS:STRUCTURE-REF
                    (first (coerce-locs
                            (inline-args (list (c1form-arg 0 form)))))
                    (c1form-arg 1 form)
                    (c1form-arg 2 form)
                    (c1form-arg 3 form))))))

(defun emit-inlined-instance-ref (form expected-type rest-forms)
  (let ((type (c1form-primary-type form)))
    (if (args-cause-side-effect rest-forms)
        (let* ((temp (make-inline-temp-var expected-type type))
               (*destination* temp))
          (c2expr* form)
          (list type temp))
        (list type
              (list 'SYS:INSTANCE-REF
                    (first (coerce-locs
                            (inline-args (list (c1form-arg 0 form)))))
                    (c1form-arg 1 form)
                    #+nil (c1form-arg 2 form))))))

;;;
;;; inline-args:
;;;   returns a list of pairs (type loc)
;;;   side effects: emits code for temporary variables
;;;
;;; Whoever calls inline-args must bind *inline-blocks* to 0 and afterwards
;;; call close-inline-blocks
;;;
(defun inline-args (forms &optional types)
  (do* ((forms forms)
        (expected-type)
        (form)
        (locs '()))
       ((endp forms) (nreverse locs))
    (setq form (pop forms)
          expected-type (if types (pop types) t))
    (case (c1form-name form)
      (LOCATION
       (push (list (c1form-primary-type form) (c1form-arg 0 form)) locs))
      (VAR
       (push (emit-inlined-variable form expected-type forms) locs))

      (CALL-GLOBAL
       (push (emit-inlined-call-global form expected-type) locs))

      (SYS:STRUCTURE-REF
       (push (emit-inlined-structure-ref form expected-type forms) locs))

      #+clos
      (SYS:INSTANCE-REF
       (push (emit-inlined-instance-ref form expected-type forms) locs))

      (SETQ
       (push (emit-inlined-setq form expected-type forms) locs))

      (t (let* ((type (c1form-primary-type form))
                (temp (make-inline-temp-var expected-type type)))
           (let ((*destination* temp)) (c2expr* form))
           (push (list type temp) locs))))))

(defun destination-type ()
  (rep-type->lisp-type (loc-representation-type *destination*))
  ;;(loc-type *destination*)
)

;;;
;;; inline-function:
;;;   locs are typed locs as produced by inline-args
;;;   returns NIL if inline expansion of the function is not possible
;;;
(defun inline-function (fname arg-types return-type &optional (return-rep-type 'any))
  ;; Those functions that use INLINE-FUNCTION must rebind
  ;; the variable *INLINE-BLOCKS*.
  (and (inline-possible fname)
       (not (get-sysprop fname 'C2))
       (let* ((dest-rep-type (loc-representation-type *destination*))
              (dest-type (rep-type->lisp-type dest-rep-type))
              (ii (get-inline-info fname arg-types return-type return-rep-type)))
         ii)))

(defun apply-inline-info (ii inlined-locs)
  (let* ((arg-types (inline-info-arg-types ii))
         (out-rep-type (inline-info-return-rep-type ii))
         (out-type (inline-info-return-type ii))
         (side-effects-p (function-may-have-side-effects (inline-info-name ii)))
         (fun (inline-info-expansion ii))
         (one-liner (inline-info-one-liner ii)))
    (produce-inline-loc inlined-locs arg-types (list out-rep-type)
                        fun side-effects-p one-liner)))

(defun choose-inline-info (ia ib return-type return-rep-type)
  (cond
    ;; Only accept inliners that have the right rep type
    ((not (or (eq return-rep-type 'any)
              (eq return-rep-type :void)
              (let ((info-type (inline-info-return-rep-type ib)))
                (or (eq return-rep-type info-type)
                    ;; :bool can be coerced to any other location type
                    (eq info-type :bool)))))
     ia)
    ((null ia)
     ib)
    ;; Keep the first one, which is typically the least safe but fastest. 
    ((equal (inline-info-arg-types ia) (inline-info-arg-types ib))
     ia)
    ;; More specific?
    ((every #'type>= (inline-info-arg-types ia) (inline-info-arg-types ib))
     ib)
    ;; Keep the first one, which is typically the least safe but fastest. 
    (t
     ia)))

(defun get-inline-info (fname types return-type return-rep-type)
  (declare (si::c-local))
  (let ((output nil))
    (dolist (x *inline-functions*)
      (when (eq (car x) fname)
        (let ((other (inline-type-matches (cdr x) types return-type)))
          (setf output (choose-inline-info output other return-type return-rep-type)))))
    (unless (safe-compile)
      (dolist (x (get-sysprop fname ':INLINE-UNSAFE))
        (let ((other (inline-type-matches x types return-type)))
          (when other
            (setf output (choose-inline-info output other return-type return-rep-type))))))
    (dolist (x (get-sysprop fname ':INLINE-SAFE))
      (let ((other (inline-type-matches x types return-type)))
        (when other
          (setf output (choose-inline-info output other return-type return-rep-type)))))
    (dolist (x (get-sysprop fname ':INLINE-ALWAYS))
      (let ((other (inline-type-matches x types return-type)))
        (when other
          (setf output (choose-inline-info output other return-type return-rep-type)))))
    output))

(defun to-fixnum-float-type (type)
  (dolist (i '(FIXNUM DOUBLE-FLOAT SINGLE-FLOAT
               #+short-float SHORT-FLOAT #+long-float LONG-FLOAT)
           nil)
    (when (type>= i type)
      (return i))))

(defun maximum-float-type (t1 t2)
  (cond ((null t1)
         t2)
        #+long-float
        ((or (eq t1 'LONG-FLOAT) (eq t2 'LONG-FLOAT))
         'LONG-FLOAT)
        ((or (eq t1 'DOUBLE-FLOAT) (eq t2 'DOUBLE-FLOAT))
         'DOUBLE-FLOAT)
        ((or (eq t1 'SINGLE-FLOAT) (eq t2 'SINGLE-FLOAT))
         'SINGLE-FLOAT)
        #+short-float
        ((or (eq t1 'SHORT-FLOAT) (eq t2 'SHORT-FLOAT))
         'SHORT-FLOAT)
        (T
         'FIXNUM)))

(defun inline-type-matches (inline-info arg-types return-type)
  (let* ((rts nil)
         (number-max nil))
    ;;
    ;; Check that the argument types match those of the inline expression
    ;;
    (do* ((arg-types arg-types (cdr arg-types))
          (types (inline-info-arg-types inline-info) (cdr types)))
         ((or (endp arg-types) (endp types))
          (when (or arg-types types)
            (return-from inline-type-matches nil)))
      (let* ((arg-type (first arg-types))
             (type (first types)))
        (cond ((eq type 'FIXNUM-FLOAT)
               (let ((new-type (to-fixnum-float-type arg-type)))
                 (unless new-type
                   (return-from inline-type-matches nil))
                 (push new-type rts)
                 (setq number-max (maximum-float-type number-max new-type))))
              ((type>= type arg-type)
               (push type rts))
              (t (return-from inline-type-matches nil)))))
    ;;
    ;; Now there is an optional check of the return type. This check is
    ;; only used when enforced by the inliner.
    ;;
    (when (or (eq (inline-info-return-rep-type inline-info) :bool)
              (null (inline-info-exact-return-type inline-info))
              (let ((inline-return-type (inline-info-return-type inline-info)))
                (if number-max
                    ;; for arithmetic operators we take the maximal
                    ;; type as possible result type. Note that FIXNUM
                    ;; is not an option, because the product, addition
                    ;; or difference of fixnums may be a larger
                    ;; integer.
                    (and (setf number-max (if (eq number-max 'fixnum)
                                              'integer
                                              number-max))
                         (type>= inline-return-type number-max)
                         (type>= number-max return-type))
                    ;; no contravariance
                    (type>= inline-return-type return-type))))
      (let ((inline-info (copy-structure inline-info)))
        (setf (inline-info-arg-types inline-info)
              (nreverse rts))
        inline-info))))

(defun need-to-protect (forms &aux ii)
  (do ((forms forms (cdr forms))
       (res nil))
      ((or res (endp forms)) res)
    (let ((form (car forms)))
      (declare (object form))
      (case (c1form-name form)
	(LOCATION)
	(VAR
	 (when (var-changed-in-form-list (c1form-arg 0 form) (cdr forms))
	   (setq res t)))
	(CALL-GLOBAL
	 (let ((fname (c1form-arg 0 form))
	       (args (c1form-arg 1 form)))
	   (or (function-may-have-side-effects fname)
	       (need-to-protect args))))
	(SYS:STRUCTURE-REF
	 (when (need-to-protect (list (c1form-arg 0 form)))
	   (setq res t)))
	(t (setq res t)))))
  )

(defun close-inline-blocks ()
  (dotimes (i *inline-blocks*) (declare (fixnum i)) (wt #\})))

(defun form-causes-side-effect (form)
  (case (c1form-name form)
    ((LOCATION VAR SYS:STRUCTURE-REF #+clos SYS:INSTANCE-REF)
     nil)
    (CALL-GLOBAL
     (let ((fname (c1form-arg 0 form))
	   (args (c1form-arg 1 form)))
       (or (function-may-have-side-effects fname)
	   (args-cause-side-effect args))))
    (t t)))

(defun args-cause-side-effect (forms)
  (some #'form-causes-side-effect forms))

(defun function-may-have-side-effects (fname)
  (declare (si::c-local))
  (not (get-sysprop fname 'no-side-effects)))

(defun function-may-change-sp (fname)
  (not (or (get-sysprop fname 'no-side-effects)
	   (get-sysprop fname 'no-sp-change))))
