/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    load.d -- Binary loader (contains also open_fasl_data).
*/
/*
    Copyright (c) 1990, Giuseppe Attardi and William F. Schelter.
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <ecl/ecl.h>
#include <string.h>
#include <stdio.h>
#ifdef ENABLE_DLOPEN
# ifdef cygwin
#  include <w32api/windows.h>
# endif
# ifdef HAVE_DLFCN_H
#  include <dlfcn.h>
#  define INIT_PREFIX "init_fas_"
# endif
# ifdef HAVE_MACH_O_DYLD_H
#  ifndef HAVE_DLFCN_H
#   include <mach-o/dyld.h>
#   define INIT_PREFIX "_init_fas_"
#  else
#   undef HAVE_MACH_O_DYLD_H
#  endif
#  ifdef bool
#   undef bool
#  endif
# endif
# ifdef HAVE_LINK_H
#  include <link.h>
# endif
# if defined(mingw32) || defined(_MSC_VER)
#  include <windows.h>
#  include <windef.h>
#  include <winbase.h>
#  include <tlhelp32.h>
#  define INIT_PREFIX "init_fas_"
# else
#  include <unistd.h>
# endif
#endif
#include <ecl/ecl-inl.h>
#include <ecl/internal.h>
#include <sys/stat.h>

#ifndef HAVE_LSTAT
static void
symlink(const char *orig, const char *dest)
{
}
#endif

static cl_object
copy_object_file(cl_object original)
{
	int err;
	cl_object copy = make_constant_base_string("TMP:ECL");
	copy = si_coerce_to_filename(si_mkstemp(copy));
        /*
         * We either have to make a full copy to convince the loader to load this object
         * file again, or we want to retain the possibility of overwriting the object
         * file we load later on (case of Windows, which locks files that are loaded).
         * The symlinks do not seem to work in latest versions of Linux.
         */
#if defined(mingw32) || defined(_MSC_VER)
	ecl_disable_interrupts();
	err = !CopyFile(original->base_string.self, copy->base_string.self, 0);
	ecl_enable_interrupts();
	if (err) {
		FEwin32_error("Error when copying file from~&~3T~A~&to~&~3T~A",
			      2, original, copy);
	}
#else
	err = Null(si_copy_file(original, copy));
	if (err) {
		FEerror("Error when copying file from~&~3T~A~&to~&~3T~A",
			2, original, copy);
	}
#endif
#ifdef cygwin
	{
		cl_object new_copy = make_constant_base_string(".dll");
		new_copy = si_base_string_concatenate(2, copy, new_copy);
		cl_rename_file(2, copy, new_copy);
		copy = new_copy;
	}
	ecl_disable_interrupts();
	err = chmod(copy->base_string.self, S_IRWXU) < 0;
	ecl_enable_interrupts();
	if (err) {
		FElibc_error("Unable to give executable permissions to ~A",
			     1, copy);
	}
#endif
	return copy;
}

#ifdef ENABLE_DLOPEN
static cl_object
ecl_library_find_by_name(cl_object filename)
{
	cl_object l;
	for (l = cl_core.libraries; l != Cnil; l = ECL_CONS_CDR(l)) {
		cl_object other = ECL_CONS_CAR(l);
		cl_object name = other->cblock.name;
		if (!Null(name) && ecl_string_eq(name, filename)) {
			return other;
		}
	}
	return Cnil;
}

static cl_object
ecl_library_find_by_handle(void *handle)
{
	cl_object l;
	for (l = cl_core.libraries; l != Cnil; l = ECL_CONS_CDR(l)) {
		cl_object other = ECL_CONS_CAR(l);
		if (handle == other->cblock.handle) {
			return other;
		}
	}
	return Cnil;
}

cl_object
ecl_library_open(cl_object filename, bool force_reload) {
	cl_object block;
	bool self_destruct = 0;
	char *filename_string;

	/* Coerces to a file name but does not merge with cwd */
	filename = coerce_to_physical_pathname(filename);
        filename = ecl_namestring(filename,
                                  ECL_NAMESTRING_TRUNCATE_IF_ERROR |
                                  ECL_NAMESTRING_FORCE_BASE_STRING);

	if (!force_reload) {
		/* When loading a foreign library, such as a dll or a
		 * so, it cannot contain any executable top level
		 * code. In that case force_reload=0 and there is no
		 * need to reload it if it has already been loaded. */
		block = ecl_library_find_by_name(filename);
		if (!Null(block)) {
			return block;
		}
	} else {
		/* We are using shared libraries as modules and
		 * force_reload=1.  Here we have to face the problem
		 * that many operating systems do not allow to load a
		 * shared library twice, even if it has changed. Hence
		 * we have to make a unique copy to be able to load
		 * the same FASL twice. In Windows this copy is
		 * _always_ made because otherwise it cannot be
		 * overwritten. In Unix we need only do that when the
		 * file has been previously loaded. */
#if defined(mingw32) || defined(_MSC_VER) || defined(cygwin)
		filename = copy_object_file(filename);
		self_destruct = 1;
#else
		block = ecl_library_find_by_name(filename);
		if (!Null(block)) {
			filename = copy_object_file(filename);
			self_destruct = 1;
		}
#endif
	}
 DO_LOAD:
	block = ecl_alloc_object(t_codeblock);
	block->cblock.self_destruct = self_destruct;
	block->cblock.locked = 0;
	block->cblock.handle = NULL;
	block->cblock.entry = NULL;
	block->cblock.data = NULL;
	block->cblock.data_size = 0;
	block->cblock.temp_data = NULL;
	block->cblock.temp_data_size = 0;
	block->cblock.data_text = NULL;
	block->cblock.data_text_size = 0;
	block->cblock.name = filename;
	block->cblock.next = Cnil;
	block->cblock.links = Cnil;
	block->cblock.cfuns_size = 0;
	block->cblock.cfuns = NULL;
        block->cblock.source = Cnil;
	filename_string = (char*)filename->base_string.self;

	ecl_disable_interrupts();
#ifdef HAVE_DLFCN_H
	block->cblock.handle = dlopen(filename_string, RTLD_NOW|RTLD_GLOBAL);
#endif
#ifdef HAVE_MACH_O_DYLD_H
	{
	NSObjectFileImage file;
        static NSObjectFileImageReturnCode code;
	code = NSCreateObjectFileImageFromFile(filename_string, &file);
	if (code != NSObjectFileImageSuccess) {
		block->cblock.handle = NULL;
	} else {
		NSModule out = NSLinkModule(file, filename_string,
					    NSLINKMODULE_OPTION_PRIVATE|
					    NSLINKMODULE_OPTION_BINDNOW|
					    NSLINKMODULE_OPTION_RETURN_ON_ERROR);
		block->cblock.handle = out;
	}}
#endif
#if defined(mingw32) || defined(_MSC_VER)
	block->cblock.handle = LoadLibrary(filename_string);
#endif
	ecl_enable_interrupts();
	/*
	 * A second pass to ensure that the dlopen routine has not
	 * returned a library that we had already loaded. If this is
	 * the case, we close the new copy to ensure we do refcounting
	 * right.
	 *
	 * INV: We can modify "libraries" in a multithread environment
	 * because we have already taken the +load-compile-lock+
	 */
	{
	cl_object other = ecl_library_find_by_handle(block->cblock.handle);
	if (other != Cnil) {
		ecl_library_close(block);
                if (force_reload) {
                        filename = copy_object_file(filename);
                        self_destruct = 1;
                        goto DO_LOAD;
                }
		block = other;
	} else {
		si_set_finalizer(block, Ct);
		cl_core.libraries = CONS(block, cl_core.libraries);
	}
	}
	return block;
}

void *
ecl_library_symbol(cl_object block, const char *symbol, bool lock) {
	void *p;
	if (block == @':default') {
		cl_object l;
		for (l = cl_core.libraries; l != Cnil; l = ECL_CONS_CDR(l)) {
			cl_object block = ECL_CONS_CAR(l);
			p = ecl_library_symbol(block, symbol, lock);
			if (p) return p;
		}
		ecl_disable_interrupts();
#if defined(mingw32) || defined(_MSC_VER)
 		{
		HANDLE hndSnap = NULL;
		HANDLE hnd = NULL;
		hndSnap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, GetCurrentProcessId());
		if (hndSnap != INVALID_HANDLE_VALUE)
		{
			MODULEENTRY32 me32;
			me32.dwSize = sizeof(MODULEENTRY32);
			if (Module32First(hndSnap, &me32))
			{
				do
					hnd = GetProcAddress(me32.hModule, symbol);
				while (hnd == NULL && Module32Next(hndSnap, &me32));
			}
			CloseHandle(hndSnap);
		}
		p = (void*)hnd;
		}
#endif
#ifdef HAVE_DLFCN_H
		p = dlsym(0, symbol);
#endif
#if !defined(mingw32) && !defined(_MSC_VER) && !defined(HAVE_DLFCN_H)
		p = 0;
#endif
		ecl_enable_interrupts();
	} else {
		ecl_disable_interrupts();
#ifdef HAVE_DLFCN_H
		p = dlsym(block->cblock.handle, symbol);
#endif
#if defined(mingw32) || defined(_MSC_VER)
		{
			HMODULE h = (HMODULE)(block->cblock.handle);
			p = GetProcAddress(h, symbol);
		}
#endif
#ifdef HAVE_MACH_O_DYLD_H
		NSSymbol sym;
		sym = NSLookupSymbolInModule((NSModule)(block->cblock.handle),
					     symbol);
		if (sym == 0) {
			p = 0;
		} else {
			p = NSAddressOfSymbol(sym);
		}
#endif
		ecl_enable_interrupts();
		/* Libraries whose symbols are being referenced by the FFI should not
		 * get garbage collected. Until we find a better solution we simply lock
		 * them for the rest of the runtime */
		if (p) {
			block->cblock.locked |= lock;
		}
	}
	return p;
}

cl_object
ecl_library_error(cl_object block) {
	cl_object output;
	ecl_disable_interrupts();
#ifdef HAVE_DLFCN_H
	output = make_base_string_copy(dlerror());
#endif
#ifdef HAVE_MACH_O_DYLD_H
	{
		NSLinkEditErrors c;
		int number;
		const char *filename;
		NSLinkEditError(&c, &number, &filename, &message);
		output = make_base_string_copy(message);
	}
#endif
#if defined(mingw32) || defined(_MSC_VER)
	{
		const char *message;
		FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM |
			      FORMAT_MESSAGE_ALLOCATE_BUFFER,
			      0, GetLastError(), 0, (void*)&message, 0, NULL);
		output = make_base_string_copy(message);
		LocalFree(message);
	}
#endif
	ecl_enable_interrupts();
	return output;
}

void
ecl_library_close(cl_object block) {
	const char *filename;
	bool verbose = ecl_symbol_value(@'si::*gc-verbose*') != Cnil;

	if (Null(block->cblock.name))
		filename = "<anonymous>";
	else
		filename = (char*)block->cblock.name->base_string.self;
        if (block->cblock.handle != NULL) {
		if (verbose) {
			fprintf(stderr, ";;; Freeing library %s\n", filename);
		}
		ecl_disable_interrupts();
#ifdef HAVE_DLFCN_H
		dlclose(block->cblock.handle);
#endif
#ifdef HAVE_MACH_O_DYLD_H
		NSUnLinkModule(block->cblock.handle, NSUNLINKMODULE_OPTION_NONE);
#endif
#if defined(mingw32) || defined(_MSC_VER)
		FreeLibrary(block->cblock.handle);
#endif
		ecl_enable_interrupts();
        }
	if (block->cblock.self_destruct) {
		if (verbose) {
			fprintf(stderr, ";;; Removing file %s\n", filename);
		}
		unlink(filename);
        }
	cl_core.libraries = ecl_remove_eq(block, cl_core.libraries);
}

void
ecl_library_close_all(void)
{
	while (cl_core.libraries != Cnil) {
		ecl_library_close(ECL_CONS_CAR(cl_core.libraries));
	}
}

cl_object
si_load_binary(cl_object filename, cl_object verbose, cl_object print)
{
	const cl_env_ptr the_env = ecl_process_env();
	cl_object block;
	cl_object basename;
	cl_object prefix;
	cl_object output;

	/* We need the full pathname */
	filename = cl_truename(filename);

#ifdef ECL_THREADS
	/* Loading binary code is not thread safe. When another thread tries
	   to load the same file, we may end up initializing twice the same
	   module. */
	mp_get_lock(1, ecl_symbol_value(@'mp::+load-compile-lock+'));
	CL_UNWIND_PROTECT_BEGIN(the_env) {
#endif
	/* Try to load shared object file */
	block = ecl_library_open(filename, 1);
	if (block->cblock.handle == NULL) {
		output = ecl_library_error(block);
		goto OUTPUT;
	}

	/* Fist try to call "init_CODE()" */
	block->cblock.entry = ecl_library_symbol(block, INIT_PREFIX "CODE", 0);
	if (block->cblock.entry != NULL)
		goto GO_ON;

	/* Next try to call "init_FILE()" where FILE is the file name */
	prefix = ecl_symbol_value(@'si::*init-function-prefix*');
	if (Null(prefix))
		prefix = make_constant_base_string(INIT_PREFIX);
	else
		prefix = @si::base-string-concatenate(3,
						 make_constant_base_string(INIT_PREFIX),
						 prefix,
						 make_constant_base_string("_"));
	basename = cl_pathname_name(1,filename);
	basename = @si::base-string-concatenate(2, prefix, @string-upcase(1, funcall(4, @'nsubstitute', CODE_CHAR('_'), CODE_CHAR('-'), basename)));
	block->cblock.entry = ecl_library_symbol(block, (char*)basename->base_string.self, 0);

	if (block->cblock.entry == NULL) {
		output = ecl_library_error(block);
		ecl_library_close(block);
		goto OUTPUT;
	}

	/* Finally, perform initialization */
GO_ON:	
	read_VV(block, (void (*)(cl_object))(block->cblock.entry));
	output = Cnil;
OUTPUT:
#ifdef ECL_THREADS
	(void)0; /* MSVC complains about missing ';' before '}' */
	} CL_UNWIND_PROTECT_EXIT {
	mp_giveup_lock(ecl_symbol_value(@'mp::+load-compile-lock+'));
	} CL_UNWIND_PROTECT_END;
#endif
	@(return output)
}
#endif /* !ENABLE_DLOPEN */

cl_object
si_load_source(cl_object source, cl_object verbose, cl_object print)
{
	cl_env_ptr the_env = ecl_process_env();
	cl_object x, strm;

	/* Source may be either a stream or a filename */
	if (type_of(source) != t_pathname && type_of(source) != t_base_string) {
		/* INV: if "source" is not a valid stream, file.d will complain */
		strm = source;
	} else {
		strm = ecl_open_stream(source, smm_input, Cnil, Cnil, 8,
				       ECL_STREAM_DEFAULT_FORMAT | ECL_STREAM_C_STREAM,
                                       Cnil);
		if (Null(strm))
			@(return Cnil)
	}
	CL_UNWIND_PROTECT_BEGIN(the_env) {
		cl_object form_index = MAKE_FIXNUM(0);
		cl_object location = CONS(source, form_index);
		ecl_bds_bind(the_env, @'ext::*source-location*', location);
		for (;;) {
                        form_index = ecl_file_position(strm);
                        ECL_RPLACD(location, form_index);
			x = si_read_object_or_ignore(strm, OBJNULL);
			if (x == OBJNULL)
				break;
                        if (the_env->nvalues) {
                                si_eval_with_env(1, x);
                                if (print != Cnil) {
                                        @write(1, x);
                                        @terpri(0);
                                }
                        }
		}
		ecl_bds_unwind1(the_env);
	} CL_UNWIND_PROTECT_EXIT {
		/* We do not want to come back here if close_stream fails,
		   therefore, first we frs_pop() current jump point, then
		   try to close the stream, and then jump to next catch
		   point */
		if (strm != source)
			cl_close(3, strm, @':abort', @'t');
	} CL_UNWIND_PROTECT_END;
	@(return Cnil)
}

@(defun load (source
	      &key (verbose ecl_symbol_value(@'*load-verbose*'))
		   (print ecl_symbol_value(@'*load-print*'))
		   (if_does_not_exist @':error')
	           (search_list ecl_symbol_value(@'si::*load-search-list*'))
	      &aux pathname pntype hooks filename function ok)
	bool not_a_filename = 0;
@
	/* If source is a stream, read conventional lisp code from it */
	if (type_of(source) != t_pathname && !ecl_stringp(source)) {
		/* INV: if "source" is not a valid stream, file.d will complain */
		filename = source;
		function = Cnil;
		not_a_filename = 1;
		goto NOT_A_FILENAME;
	}
	/* INV: coerce_to_file_pathname() creates a fresh new pathname object */
	source   = cl_merge_pathnames(1, source);
	pathname = coerce_to_file_pathname(source);
	pntype   = pathname->pathname.type;

	filename = Cnil;
	hooks = ecl_symbol_value(@'si::*load-hooks*');
	if (Null(pathname->pathname.directory) &&
	    Null(pathname->pathname.host) &&
	    Null(pathname->pathname.device) &&
	    !Null(search_list))
	{
		loop_for_in(search_list) {
			cl_object d = CAR(search_list);
			cl_object f = cl_merge_pathnames(2, pathname, d);
			cl_object ok = cl_load(9, f, @':verbose', verbose,
					       @':print', print,
					       @':if-does-not-exist', Cnil,
					       @':search-list', Cnil);
			if (!Null(ok)) {
				@(return ok);
			}
		} end_loop_for_in;
	}
	if (!Null(pntype) && (pntype != @':wild')) {
		/* If filename already has an extension, make sure
		   that the file exists */
                cl_object kind;
		filename = si_coerce_to_filename(pathname);
                kind = si_file_kind(filename, Ct);
		if (kind != @':file' && kind != @':special') {
			filename = Cnil;
		} else {
			function = cl_cdr(ecl_assoc(pathname->pathname.type, hooks));
		}
	} else loop_for_in(hooks) {
		/* Otherwise try with known extensions until a matching
		   file is found */
                cl_object kind;
		filename = pathname;
		filename->pathname.type = CAAR(hooks);
		function = CDAR(hooks);
                kind = si_file_kind(filename, Ct);
		if (kind == @':file' || kind == @':special')
			break;
		else
			filename = Cnil;
	} end_loop_for_in;
	if (Null(filename)) {
		if (Null(if_does_not_exist))
			@(return Cnil)
		else
			FEcannot_open(source);
	}
NOT_A_FILENAME:
	if (verbose != Cnil) {
		cl_format(3, Ct, make_constant_base_string("~&;;; Loading ~s~%"),
			  filename);
	}
	ecl_bds_bind(the_env, @'*package*', ecl_symbol_value(@'*package*'));
	ecl_bds_bind(the_env, @'*readtable*', ecl_symbol_value(@'*readtable*'));
	ecl_bds_bind(the_env, @'*load-pathname*', not_a_filename? Cnil : source);
	ecl_bds_bind(the_env, @'*load-truename*',
		     not_a_filename? Cnil : (filename = cl_truename(filename)));
	if (!Null(function)) {
		ok = funcall(4, function, filename, verbose, print);
	} else {
#if 0 /* defined(ENABLE_DLOPEN) && !defined(mingw32) && !defined(_MSC_VER)*/
		/*
		 * DISABLED BECAUSE OF SECURITY ISSUES!
		 * In systems where we can do this, we try to load the file
		 * as a binary. When it fails, we will revert to source
		 * loading below. Is this safe? Well, it depends on whether
		 * your op.sys. checks integrity of binary exectables or
		 * just loads _anything_.
		 */
		if (not_a_filename) {
			ok = Ct;
		} else {
			ok = si_load_binary(filename, verbose, print);
		}
		if (!Null(ok))
#endif
		ok = si_load_source(filename, verbose, print);
	}
	ecl_bds_unwind_n(the_env, 4);
	if (!Null(ok))
		FEerror("LOAD: Could not load file ~S (Error: ~S)",
			2, filename, ok);
	if (print != Cnil) {
		cl_format(3, Ct, make_constant_base_string("~&;;; Loading ~s~%"),
			  filename);
	}
	@(return filename)
@)
