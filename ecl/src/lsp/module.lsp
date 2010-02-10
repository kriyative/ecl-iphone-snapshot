;;;;  -*- Mode: Lisp; Syntax: Common-Lisp; Package: SYSTEM -*-
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

;;;;	module routines

;; This is taken from SBCL's code/module.lisp which is in the public
;; domain.

(in-package "SYSTEM")

;;;; exported specials

(defvar *modules* ()
  "This is a list of module names that have been loaded into Lisp so far.
It is used by PROVIDE and REQUIRE.")

(defvar *module-provider-functions* nil
  "See function documentation for REQUIRE")

;;;; PROVIDE and REQUIRE

(defun provide (module-name)
  "Adds a new module name to *MODULES* indicating that it has been loaded.
Module-name is a string designator"
  (pushnew (string module-name) *modules* :test #'string=)
  t)

(defvar *requiring* nil)

(defun require-error (control &rest arguments)
  (error "Module error: ~?" control arguments))

(defun require (module-name &optional pathnames)
  "Loads a module, unless it already has been loaded. PATHNAMES, if supplied,
is a designator for a list of pathnames to be loaded if the module
needs to be. If PATHNAMES is not supplied, functions from the list
*MODULE-PROVIDER-FUNCTIONS* are called in order with MODULE-NAME
as an argument, until one of them returns non-NIL.  User code is
responsible for calling PROVIDE to indicate a successful load of the
module."
  (let ((name (string module-name)))
    (when (member name *requiring* :test #'string=)
      (require-error "~@<Could not ~S ~A: circularity detected. Please check ~
                     your configuration.~:@>" 'require module-name))
    (let ((saved-modules (copy-list *modules*))
	  (*requiring* (cons name *requiring*)))
      (unless (member name *modules* :test #'string=)
	(cond (pathnames
	       (unless (listp pathnames) (setf pathnames (list pathnames)))
	       ;; ambiguity in standard: should we try all pathnames in the
	       ;; list, or should we stop as soon as one of them calls PROVIDE?
	       (dolist (ele pathnames t)
		 (load ele)))
	      (t
	       (unless (some (lambda (p) (funcall p module-name))
			     *module-provider-functions*)
		 (require-error "Don't know how to ~S ~A."
				'require module-name)))))
      (set-difference *modules* saved-modules))))

(pushnew #'(lambda (module)
	     (let* ((sysdir (translate-logical-pathname #P"SYS:"))
		    (module (string module)))
	       (or
		(let ((path (merge-pathnames (make-pathname :name module) sysdir)))
		  (load path :if-does-not-exist nil))
		(let ((path (merge-pathnames (make-pathname :name (string-downcase module)) sysdir)))
		  (load path :if-does-not-exist nil)))))
	 *module-provider-functions*)
