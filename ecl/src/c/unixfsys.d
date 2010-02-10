/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    unixfsys.c  -- Unix file system interface.
*/
/*
    Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
    Copyright (c) 1990, Giuseppe Attardi.
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
#include <limits.h>
#ifndef _MSC_VER
# include <unistd.h>
#else
# include <io.h>
# define access _access
# define F_OK 0
#endif
#include <sys/types.h>
#ifdef HAVE_PWD_H
# include <pwd.h>
#endif
#include <sys/stat.h>
#include <stdlib.h>
#include <ecl/ecl-inl.h>
#include <ecl/internal.h>
#ifdef HAVE_DIRENT_H
# include <dirent.h>
#else
# if !defined(_MSC_VER)
#  include <sys/dir.h>
# endif
#endif
#if defined(_MSC_VER) || defined(mingw32)
# include <windows.h>
# undef ERROR
#endif
#include <fcntl.h>
#include <errno.h>

static int
safe_chdir(const char *path, cl_object prefix)
{
	if (prefix != Cnil) {
		cl_object aux = make_constant_base_string(path);
		aux = si_base_string_concatenate(2, prefix, aux);
		return safe_chdir(aux->base_string.self, Cnil);
	} else {
		int output;
		ecl_disable_interrupts();
		output = chdir(path);
		ecl_enable_interrupts();
		return output;
	}
}

static int
safe_stat(const char *path, struct stat *sb)
{
	int output;
	ecl_disable_interrupts();
	output = stat(path, sb);
	ecl_enable_interrupts();
	return output;
}

#ifdef HAVE_LSTAT
static int
safe_lstat(const char *path, struct stat *sb)
{
	int output;
	ecl_disable_interrupts();
	output = lstat(path, sb);
	ecl_enable_interrupts();
	return output;
}
#endif

#if defined(_MSC_VER) || defined(mingw32)
static cl_object
drive_host_prefix(cl_object pathname)
{
	cl_object device = pathname->pathname.device;
	cl_object host = pathname->pathname.host;
	cl_object output = Cnil;
	if (device != Cnil) {
		output = make_base_string_copy("X:");
		output->base_string.self[0] = device->base_string.self[0];
	}
	if (host != Cnil) {
		cl_object slash = make_constant_base_string("/");
		if (output != Cnil)
			output = si_base_string_concatenate(5, output, slash, slash,
							    host, slash);
		else
			output = si_base_string_concatenate(4, slash, slash, host,
							    slash);
	}
	return output;
}
#else
#define drive_host_prefix(x) Cnil
#endif

/*
 * string_to_pathanme, to be used when s is a real pathname
 */
cl_object
ecl_cstring_to_pathname(char *s)
{
	cl_object string = make_simple_base_string(s);
	return cl_parse_namestring(1, string);
}

/*
 * Finds current directory by using getcwd() with an adjustable
 * string which grows until it can host the whole path.
 */
static cl_object
current_dir(void) {
	cl_object output;
	const char *ok;
#ifdef _MSC_VER
	unsigned char *c;
#endif
	cl_index size = 128;

	do {
		output = ecl_alloc_adjustable_base_string(size);
		ecl_disable_interrupts();
		ok = getcwd((char*)output->base_string.self, size);
		ecl_enable_interrupts();
		size += 256;
	} while (ok == NULL);
	size = strlen((char*)output->base_string.self);
	if ((size + 1 /* / */ + 1 /* 0 */) >= output->base_string.dim) {
		/* Too large to host the trailing '/' */
		cl_object other = ecl_alloc_adjustable_base_string(size+2);
		strcpy((char*)other->base_string.self, (char*)output->base_string.self);
		output = other;
	}
#ifdef _MSC_VER
	for (c = output->base_string.self; *c; c++)
		if (*c == '\\')
			*c = '/';
#endif
	if (output->base_string.self[size-1] != '/') {
		output->base_string.self[size++] = '/';
		output->base_string.self[size] = 0;
	}
	output->base_string.fillp = size;
	return output;
}

/*
 * Using a certain path, guess the type of the object it points to.
 */

static cl_object
file_kind(char *filename, bool follow_links) {
	cl_object output;
#if defined(_MSC_VER) || defined(mingw32)
	DWORD dw;
	ecl_disable_interrupts();
	dw = GetFileAttributes( filename );
	if (dw == -1)
		output = Cnil;
	else if ( dw & FILE_ATTRIBUTE_DIRECTORY )
		output = @':directory';
	else
		output = @':file';
	ecl_enable_interrupts();
#else
	struct stat buf;
# ifdef HAVE_LSTAT
	if ((follow_links? safe_stat : safe_lstat)(filename, &buf) < 0)
# else
	if (safe_stat(filename, &buf) < 0)
# endif
		output = Cnil;
# ifdef HAVE_LSTAT
	else if (S_ISLNK(buf.st_mode))
		output = @':link';
# endif
	else if (S_ISDIR(buf.st_mode))
		output = @':directory';
	else if (S_ISREG(buf.st_mode))
		output = @':file';
	else
		output = @':special';
#endif
	return output;
}

cl_object
si_file_kind(cl_object filename, cl_object follow_links) {
	filename = si_coerce_to_filename(filename);
	@(return file_kind((char*)filename->base_string.self, !Null(follow_links)))
}

#if defined(HAVE_LSTAT) && !defined(mingw32) && !defined(_MSV_VER)
static cl_object
si_readlink(cl_object filename) {
	/* Given a filename which is a symlink, this routine returns
	 * the value of this link in the form of a pathname. */
	cl_index size = 128, written;
	cl_object output, kind;
	do {
		output = ecl_alloc_adjustable_base_string(size);
		ecl_disable_interrupts();
		written = readlink((char*)filename->base_string.self,
				   (char*)output->base_string.self, size);
		ecl_enable_interrupts();
		size += 256;
	} while (written == size);
	output->base_string.self[written] = '\0';
	kind = file_kind((char*)output->base_string.self, FALSE);
	if (kind == @':directory') {
		output->base_string.self[written++] = '/';
		output->base_string.self[written] = '\0';
	}
	output->base_string.fillp = written;
	return output;
}
#endif /* HAVE_LSTAT */


/*
 * Search the actual name of the directory of a pathname,
 * going through links if they exist. Default is
 * current directory
 */
cl_object
cl_truename(cl_object orig_pathname)
{
	const cl_env_ptr the_env = ecl_process_env();
	cl_object dir;
	cl_object previous = current_dir();

	cl_object pathname = coerce_to_file_pathname(orig_pathname);
	if (pathname->pathname.directory == Cnil)
		pathname = ecl_merge_pathnames(previous, pathname, @':newest');

	/* We process the directory part of the filename, removing all
	 * possible symlinks. To do so, we only have to change to the
	 * directory which contains our file, and come back. We also have to
	 * ensure that the filename itself does not point to a symlink: if so,
	 * then we resolve the value of the symlink and continue traversing
	 * the filesystem.
	 */
	CL_UNWIND_PROTECT_BEGIN(the_env) {
		cl_object kind, filename, prefix;
	BEGIN:
		filename = si_coerce_to_filename(pathname);
		kind = file_kind((char*)filename->base_string.self, FALSE);
		if (kind == Cnil) {
			FEcannot_open(orig_pathname);
#ifdef HAVE_LSTAT
		} else if (kind == @':link') {
			/* The link might be a relative pathname. In that case we have
			 * to merge with the original pathname */
			filename = cl_merge_pathnames(2, si_readlink(filename),
						      ecl_make_pathname(Cnil, Cnil,
									cl_pathname_directory(1,filename),
									Cnil, Cnil, Cnil));
#endif
		} else {
                        /* If the pathname is a directory but we have supplied
                           a file name, correct the type by appending a directory
                           separator and re-parsing again the namestring */
                        if (kind == @':directory' &&
                            (pathname->pathname.name != Cnil ||
                             pathname->pathname.type != Cnil)) {
                                pathname = si_base_string_concatenate
                                        (2, filename,
                                         make_constant_base_string("/"));
                                pathname = cl_pathname(pathname);
                                goto BEGIN;
                        }
                        filename = OBJNULL;
		}
		prefix = drive_host_prefix(pathname);
		for (dir = pathname->pathname.directory;
		     !Null(dir);
		     dir = ECL_CONS_CDR(dir))
		{
			volatile cl_object part = ECL_CONS_CAR(dir);
			if (type_of(part) == t_base_string) {
				if (safe_chdir((char*)part->base_string.self, prefix) < 0) {
ERROR:					FElibc_error("Can't change the current directory to ~S",
						     1, pathname);
				}
			} else if (part == @':absolute') {
				if (Null(prefix)) {
					if (safe_chdir("/", prefix) < 0)
						goto ERROR;
				} else {
					cl_object aux = make_constant_base_string("/");
					prefix = si_base_string_concatenate(2, prefix, aux);
					continue;
				}
			} else if (part == @':relative') {
				/* Nothing to do */
			} else if (part == @':up') {
				if (safe_chdir("..", prefix) < 0)
					goto ERROR;
			} else {
				FEerror("~S is not allowed in TRUENAME", 1, part);
			}
			prefix = Cnil;
		}
#ifdef HAVE_LSTAT
		if (filename) {
			/* It was a symlink. We take the content of this
			 * link and try to find its truename. */
			pathname = cl_parse_namestring(3, filename, Cnil, Cnil);
			goto BEGIN;
		}
#endif
                {
                        /* ECL does not contemplate version numbers
                           in directory pathnames */
                        cl_object version = @':newest';
                        if (pathname->pathname.name == Cnil &&
                            pathname->pathname.type == Cnil) {
                                version = Cnil;
                                /* We have to destructively change the
                                 * pathname version here. Otherwise
                                 * merge_pathnames will not do it. It is
                                 * safe because coerce_to_file_pathname
                                 * created a copy. */
                                pathname->pathname.version = version;
                        }
                        pathname = ecl_merge_pathnames(si_getcwd(0), pathname,
                                                       version);
                }
	} CL_UNWIND_PROTECT_EXIT {
		safe_chdir((char*)previous->base_string.self, Cnil);
	} CL_UNWIND_PROTECT_END;

	@(return pathname)
}

int
ecl_backup_open(const char *filename, int option, int mode)
{
	char *backupfilename = ecl_alloc(strlen(filename) + 5);
	if (backupfilename == NULL) {
		FElibc_error("Cannot allocate memory for backup filename", 0);
	}

	strcat(strcpy(backupfilename, filename), ".BAK");
	ecl_disable_interrupts();
#if defined(_MSC_VER) || defined(mingw32)
	/* Windows' rename doesn't replace an existing file */
	if (access(backupfilename, F_OK) == 0 && unlink(backupfilename)) {
		ecl_enable_interrupts();
		FElibc_error("Cannot remove the file ~S", 1, make_simple_base_string(backupfilename));
	}
#endif
	if (rename(filename, backupfilename)) {
		ecl_enable_interrupts();
		FElibc_error("Cannot rename the file ~S to ~S.", 2,
			     make_constant_base_string(filename), make_simple_base_string(backupfilename));
	}
	ecl_enable_interrupts();
	ecl_dealloc(backupfilename);
	return open(filename, option, mode);
}

cl_object
ecl_file_len(int f)
{
	struct stat filestatus;
	ecl_disable_interrupts();
	fstat(f, &filestatus);
	ecl_enable_interrupts();
	return ecl_make_integer(filestatus.st_size);
}

@(defun rename-file (oldn newn &key (if_exists @':error'))
	cl_object old_filename, new_filename, old_truename, new_truename;
	int error;
@

	/* 1) Get the old filename, and complain if it has wild components,
	 *    or if it does not exist. Notice that the filename to be renamed
	 *    is not the truename, because we might be renaming a symbolic link.
	 */
	old_filename = si_coerce_to_filename(oldn);
	old_truename = cl_truename(oldn);

	/* 2) Create the new file name. */
	newn = ecl_merge_pathnames(newn, oldn, @':newest');
	new_filename = si_coerce_to_filename(newn);

	ecl_disable_interrupts();
	while (if_exists == @':error' || if_exists == Cnil) {
#if defined(_MSC_VER) || defined(mingw32)
		error = SetErrorMode(0);
		if (MoveFile((char*)old_filename->base_string.self,
			     (char*)new_filename->base_string.self)) {
			SetErrorMode(error);
			goto SUCCESS;
		}
		SetErrorMode(error);
		switch (GetLastError()) {
		case ERROR_ALREADY_EXISTS:
		case ERROR_FILE_EXISTS:
			break;
		default:
			goto FAILURE_CLOBBER;
		};
#else
		if (link((char*)old_filename->base_string.self,
			 (char*)new_filename->base_string.self) == 0) {
			(void)unlink((char*)old_filename->base_string.self);
			goto SUCCESS;
		}
		if (errno != EEXIST && errno != ENOTEMPTY) {
			goto FAILURE_CLOBBER;
		}
#endif
		/* if the file already exists */
		if (if_exists != Cnil) {
			ecl_enable_interrupts();
			if_exists = CEerror(@':supersede',
					"When trying to rename ~S, ~S already exists", 2,
					oldn, new_filename);
			ecl_disable_interrupts();
			if (if_exists == Ct) if_exists= @':error';
		}

		if (if_exists == Cnil) {
			ecl_enable_interrupts();
			@(return Cnil Cnil Cnil)
		}
	}
	
	if (if_exists == @':supersede' || if_exists == Ct) {
#if defined(_MSC_VER) || defined(mingw32)
		error = SetErrorMode(0);
		if (MoveFile((char*)old_filename->base_string.self,
			     (char*)new_filename->base_string.self)) {
			SetErrorMode(error);
			goto SUCCESS;
		}
		switch (GetLastError()) {
		case ERROR_ALREADY_EXISTS:
		case ERROR_FILE_EXISTS:
			break;
		default:
			goto FAILURE_CLOBBER;
		};
		if (MoveFileEx((char*)old_filename->base_string.self,
			       (char*)new_filename->base_string.self,
			       MOVEFILE_REPLACE_EXISTING)) {
			SetErrorMode(error);
			goto SUCCESS;
		}
		/* hack for win95/novell */
		chmod((char*)old_filename->base_string.self, 0777);
		chmod((char*)new_filename->base_string.self, 0777);
		SetFileAttributesA((char*)new_filename->base_string.self,
				   FILE_ATTRIBUTE_NORMAL);
		SetFileAttributesA((char*)new_filename->base_string.self,
				   FILE_ATTRIBUTE_TEMPORARY);
		if (MoveFile((char*)old_filename->base_string.self,
			     (char*)new_filename->base_string.self)) {
			SetErrorMode(error);
			goto SUCCESS;
		}
		/* fallback on old behavior */
		(void)DeleteFileA((char*)new_filename->base_string.self);
		if (MoveFile((char*)old_filename->base_string.self,
			     (char*)new_filename->base_string.self)) {
			SetErrorMode(error);
			goto SUCCESS;
		}
		/* fall through */
#else
		if (rename((char*)old_filename->base_string.self,
			   (char*)new_filename->base_string.self) == 0) {
			goto SUCCESS;
		}
#endif
	} else {
		/* invalid key */
		ecl_enable_interrupts();
		FEerror("~S is an illegal IF-EXISTS option for RENAME-FILE.", 1, if_exists);
	}
FAILURE_CLOBBER:
	ecl_enable_interrupts();
	FElibc_error("Cannot rename the file ~S to ~S.", 2, oldn, newn);

SUCCESS:
	ecl_enable_interrupts();
	new_truename = cl_truename(newn);
	@(return newn old_truename new_truename)
@)

cl_object
cl_delete_file(cl_object file)
{
	cl_object filename = si_coerce_to_filename(file);
	int ok;

	ecl_disable_interrupts();
	ok = unlink((char*)filename->base_string.self);
	ecl_enable_interrupts();

	if (ok < 0)
		FElibc_error("Cannot delete the file ~S.", 1, file);
	@(return Ct)
}

cl_object
cl_probe_file(cl_object file)
{
	/* INV: Both SI:FILE-KIND and TRUENAME complain if "file" has wildcards */
	@(return (si_file_kind(file, Ct) != Cnil? cl_truename(file) : Cnil))
}

cl_object
cl_file_write_date(cl_object file)
{
	cl_object time, filename = si_coerce_to_filename(file);
	struct stat filestatus;
	if (safe_stat((char*)filename->base_string.self, &filestatus) < 0)
		time = Cnil;
	else
		time = UTC_time_to_universal_time(filestatus.st_mtime);
	@(return time)
}

cl_object
cl_file_author(cl_object file)
{
	cl_object output, filename = si_coerce_to_filename(file);
	struct stat filestatus;
	if (safe_stat((char*)filename->base_string.self, &filestatus) < 0)
		FElibc_error("Cannot get the file status of ~S.", 1, file);
#ifdef HAVE_PWD_H
	{
		struct passwd *pwent;
		ecl_disable_interrupts();
		pwent = getpwuid(filestatus.st_uid);
		ecl_enable_interrupts();
		output = make_base_string_copy(pwent->pw_name);
	}
#else
	output = make_constant_base_string("UNKNOWN");
#endif
	@(return output)
}

cl_object
ecl_homedir_pathname(cl_object user)
{
	cl_index i;
	cl_object namestring;
	const char *h, *d;
	if (!Null(user)) {
#ifdef HAVE_PWD_H
		struct passwd *pwent = NULL;
#endif
		char *p;
		/* This ensures that our string has the right length
		   and it is terminated with a '\0' */
		user = si_copy_to_simple_base_string(user);
		p = (char*)user->base_string.self;
		i = user->base_string.fillp;
		if (i > 0 && *p == '~') {
			p++;
			i--;
		}
		if (i == 0)
			return ecl_homedir_pathname(Cnil);
#ifdef HAVE_PWD_H
		pwent = getpwnam(p);
		if (pwent == NULL)
			FEerror("Unknown user ~S.", 1, p);
		namestring = make_base_string_copy(pwent->pw_dir);
#endif
		FEerror("Unknown user ~S.", 1, p);
	} else if ((h = getenv("HOME"))) {
		namestring = make_base_string_copy(h);
#if defined(_MSC_VER) || defined(ming32)
	} else if ((h = getenv("HOMEPATH")) && (d = getenv("HOMEDRIVE"))) {
		namestring =
			si_base_string_concatenate(2,
						   make_constant_base_string(d),
						   make_constant_base_string(h));
#endif
	} else {
		namestring = make_constant_base_string("/");
	}
	if (namestring->base_string.self[0] == '~') {
		FEerror("Not a valid home pathname ~S", 1, namestring);
	}
	i = namestring->base_string.fillp;
	if (!IS_DIR_SEPARATOR(namestring->base_string.self[i-1]))
		namestring = si_base_string_concatenate(2, namestring,
						        CODE_CHAR(DIR_SEPARATOR));
	return cl_parse_namestring(3, namestring, Cnil, Cnil);
}

@(defun user_homedir_pathname (&optional host)
@
	/* Ignore optional host argument. */
	@(return ecl_homedir_pathname(Cnil));
@)

/*
 * Take two C strings and check if the first one matches
 * against the pattern given by the second one. The pattern
 * is that of a Unix shell except for brackets and curly
 * braces
 */
static bool
string_match(const char *s, const char *p) {
	const char *next;
	while (*s) {
	  switch (*p) {
	  case '*':
	    /* Match any group of characters */
	    next = p+1;
	    if (*next != '?') {
	      if (*next == '\\')
		next++;
	      while (*s && *s != *next) s++;
	    }
	    if (string_match(s,next))
	      return TRUE;
	    /* starts back from the '*' */
	    if (!*s)
	      return FALSE;
	    s++;
	    break;
	  case '?':
	    /* Match any character */
	    s++, p++;
	    break;
	  case '\\':
      /* Interpret a pattern character literally.
         Trailing slash is interpreted as a slash. */
	    if (p[1]) p++;
	    if (*s != *p)
	      return FALSE;
	    s++, p++;
	    break;
	  default:
	    if (*s != *p)
	      return FALSE;
	    s++, p++;
	    break;
	  }
	}
	while (*p == '*')
	  p++;
	return (*p == 0);
}

/*
 * list_current_directory() lists the files and directories which are contained
 * in the current working directory (as given by current_dir()). If ONLY_DIR is
 * true, the list is made of only the directories -- a propert which is checked
 * by following the symlinks.
 */
static cl_object
list_current_directory(const char *mask, bool only_dir, cl_object prefix)
{
	cl_object out = Cnil;
	char *text;
#if defined(HAVE_DIRENT_H)
	DIR *dir;
	struct dirent *entry;

	ecl_disable_interrupts();
	dir = opendir("./");
	if (dir == NULL) {
		out = Cnil;
		goto OUTPUT;
	}

	while ((entry = readdir(dir))) {
		text = entry->d_name;
#else
# ifdef _MSC_VER
	WIN32_FIND_DATA fd;
	HANDLE hFind = NULL;
	BOOL found = FALSE;

	ecl_disable_interrupts();
	for (;;) {
		if (hFind == NULL) {
			const char *mask = ".\\*";
			if (prefix != Cnil) {
				cl_object aux = make_constant_base_string(mask);
				prefix = si_base_string_concatenate(2, prefix, aux);
				mask = (const char *)prefix->base_string.self;
			}
			hFind = FindFirstFile(mask, &fd);
			if (hFind == INVALID_HANDLE_VALUE) {
				out = Cnil;
				goto OUTPUT;
			}
			found = TRUE;
		} else {
			found = FindNextFile(hFind, &fd);
		}
		if (!found)
			break;
		text = fd.cFileName;
# else /* sys/dir.h as in SYSV */
	FILE *fp;
	char iobuffer[BUFSIZ];
	DIRECTORY dir;

	ecl_disable_interrupts();
	fp = fopen("./", OPEN_R);
	if (fp == NULL) {
		out = Cnil;
		goto OUTPUT;
	}
	setbuf(fp, iobuffer);
	for (;;) {
		if (fread(&dir, sizeof(DIRECTORY), 1, fp) <= 0)
			break;
		if (dir.d_ino == 0)
			continue;
		text = dir.d_name;
# endif /* !_MSC_VER */
#endif /* !HAVE_DIRENT_H */
		if (text[0] == '.' &&
		    (text[1] == '\0' ||
		     (text[1] == '.' && text[2] == '\0')))
			continue;
		if (only_dir && file_kind(text, TRUE) != @':directory')
			continue;
		if (mask && !string_match(text, mask))
			continue;
		out = ecl_cons(make_base_string_copy(text), out);
	}
#ifdef HAVE_DIRENT_H
	closedir(dir);
#else
# ifdef _MSC_VER
        FindClose(hFind);
# else
	fclose(fp);
# endif /* !_MSC_VER */
#endif /* !HAVE_DIRENT_H */
	ecl_enable_interrupts();
OUTPUT:
	return cl_nreverse(out);
}

/*
 * dir_files() lists all files which are contained in the current directory and
 * which match the masks in PATHNAME. This routine is essentially a wrapper for
 * list_current_directory(), which transforms the list of strings into a list
 * of pathnames. BASEDIR is the truename of the current directory and it is
 * used to build these pathnames.
 */
static cl_object
dir_files(cl_object basedir, cl_object pathname)
{
	cl_object all_files, output = Cnil;
	cl_object mask;
	cl_object name = pathname->pathname.name;
	cl_object type = pathname->pathname.type;
	if (name == Cnil && type == Cnil) {
		return cl_list(1, basedir);
	}
	mask = ecl_make_pathname(Cnil, Cnil, Cnil, name, type, pathname->pathname.version);
	all_files = list_current_directory(NULL, FALSE, Cnil);
	loop_for_in(all_files) {
		cl_object new = CAR(all_files);
		char *text = (char*)new->base_string.self;
		if (file_kind(text, TRUE) == @':directory')
			continue;
		if (ecl_stringp(new) && ecl_member_char(':', new)) {
			/* File names are allowed to have ':', but ECL
			 * interprets colons as separators for device names
			 * By prepending the name with a ':', we set the device
			 * to NIL and parse the file name properly */
			new = si_base_string_concatenate(2, make_constant_base_string(":"),
							 new);
		}
		new = cl_pathname(new);
		if (Null(cl_pathname_match_p(new, mask)))
			continue;
		new->pathname.host = basedir->pathname.host;
		new->pathname.device = basedir->pathname.device;
		new->pathname.directory = basedir->pathname.directory;
#ifdef HAVE_LSTAT
		/* Resolve symbolic links */
		if (file_kind(text, FALSE) == @':link') {
			new = cl_truename(new);
		}
#endif
		output = CONS(new, output);
	} end_loop_for_in;
	return output;
}

/*
 * dir_recursive() performs the dirty job of DIRECTORY. The routine moves
 * through the filesystem looking for files and directories which match
 * the masks in the arguments PATHNAME and DIRECTORY, collecting them in a
 * list.
 */
static cl_object
dir_recursive(cl_object pathname, cl_object directory, cl_object prefix)
{
	cl_object item, next_dir, prev_dir = current_dir(), output = Cnil;

	/* There are several possibilities here:
	 *
	 * 1) The list of subdirectories DIRECTORY is empty, and only PATHNAME
	 * remains to be inspected. If there is no file name or type, then
	 * we simply output the truename of the current directory. Otherwise
	 * we have to find a file which corresponds to the description.
	 */
	if (directory == Cnil) {
		prev_dir = cl_pathname(prev_dir);
		return dir_files(prev_dir, pathname);
	}
	/*
	 * 2) We have not yet exhausted the DIRECTORY component of the
	 * pathname. We have to enter some subdirectory, determined by
	 * CAR(DIRECTORY) and scan it.
	 */
	item = CAR(directory);

	if (type_of(item) == t_base_string || item == @':wild') {
		/*
		 * 2.1) If CAR(DIRECTORY) is a string or :WILD, we have to
		 * enter & scan all subdirectories in our curent directory.
		 */
		next_dir = list_current_directory((item == @':wild')? "*" :
						  (const char *)item->base_string.self,
						  TRUE, prefix);
		loop_for_in(next_dir) {
			char *text = (char*)(CAR(next_dir)->base_string.self);
			/* We are unable to move into this directory! */
			if (safe_chdir(text, prefix) < 0)
				continue;
			item = dir_recursive(pathname, CDR(directory), Cnil);
			output = ecl_nconc(item, output);
			safe_chdir((char*)prev_dir->base_string.self, prefix);
		} end_loop_for_in;
	} else if (item == @':absolute') {
		/*
		 * 2.2) If CAR(DIRECTORY) is :ABSOLUTE, we have to scan the
		 * root directory.
		 */
		if (safe_chdir("/", prefix) < 0)
			return Cnil;
		if (Null(prefix)) {
			if (safe_chdir("/", Cnil) < 0)
				return Cnil;
		} else {
			cl_object aux = make_constant_base_string("/");
			prefix = si_base_string_concatenate(2, prefix, aux);
		}
		output = dir_recursive(pathname, CDR(directory), prefix);
		safe_chdir((char*)prev_dir->base_string.self, Cnil);
	} else if (item == @':relative') {
		/*
		 * 2.3) If CAR(DIRECTORY) is :RELATIVE, we have to scan the
		 * current directory.
		 */
		output = dir_recursive(pathname, CDR(directory), Cnil);
	} else if (item == @':up') {
		/*
		 * 2.4) If CAR(DIRECTORY) is :UP, we have to scan the directory
		 * which contains this one.
		 */
		if (safe_chdir("..", Cnil) < 0)
			return Cnil;
		output = dir_recursive(pathname, CDR(directory), Cnil);
		safe_chdir((char*)prev_dir->base_string.self, Cnil);
	} else if (item == @':wild-inferiors') {
		/*
		 * 2.5) If CAR(DIRECTORY) is :WILD-INFERIORS, we have to do
		 * scan all subdirectories from _all_ levels, looking for a
		 * tree that matches the remaining part of DIRECTORY.
		 */
		next_dir = list_current_directory("*", TRUE, prefix);
		loop_for_in(next_dir) {
			char *text = (char*)(CAR(next_dir)->base_string.self);
			if (safe_chdir(text, prefix) < 0)
				continue;
			item = dir_recursive(pathname, directory, Cnil);
			output = ecl_nconc(item, output);
			safe_chdir((char*)prev_dir->base_string.self, Cnil);
		} end_loop_for_in;
		output = ecl_nconc(output, dir_recursive(pathname, CDR(directory), Cnil));
	}
	return output;
}

@(defun directory (mask &key &allow_other_keys)
	cl_object prev_dir = Cnil;
	volatile cl_object output;
@
	CL_UNWIND_PROTECT_BEGIN(the_env) {
		prev_dir = current_dir();
		mask = coerce_to_file_pathname(mask);
		output = dir_recursive(mask, mask->pathname.directory,
				       drive_host_prefix(mask));
	} CL_UNWIND_PROTECT_EXIT {
		if (prev_dir != Cnil)
			safe_chdir((char*)prev_dir->base_string.self, Cnil);
	} CL_UNWIND_PROTECT_END;
	@(return output)
@)

@(defun ext::getcwd (&optional (change_d_p_d Cnil))
	cl_object output;
@
	output = cl_parse_namestring(3, current_dir(), Cnil, Cnil);
	if (!Null(change_d_p_d)) {
		ECL_SETQ(the_env, @'*default-pathname-defaults*', output);
	}
	@(return output)
@)

cl_object
si_get_library_pathname(void)
{
        cl_object s = cl_core.library_pathname;
        if (!Null(s)) {
                goto OUTPUT_UNCHANGED;
        } else {
                const char *v = getenv("ECLDIR");
                if (v) {
                        s = make_constant_base_string(v);
                        goto OUTPUT;
                }
        }
#if defined(_MSC_VER) || defined(mingw32)
	{
        char *buffer;
	HMODULE hnd;
	cl_index len, ep;
        s = ecl_alloc_adjustable_base_string(cl_core.path_max);
        buffer = (char*)s->base_string.self;
	ecl_disable_interrupts();
	hnd = GetModuleHandle("ecl.dll");
	len = GetModuleFileName(hnd, buffer, cl_core.path_max-1);
	ecl_enable_interrupts();
	if (len == 0) {
		FEerror("GetModuleFileName failed (last error = ~S)",
			1, MAKE_FIXNUM(GetLastError()));
	}
	s->base_string.fillp = len;
        /* GetModuleFileName returns a file name. We have to strip
         * the directory component. */
        s = cl_make_pathname(8, @':name', Cnil, @':type', Cnil,
			     @':version', Cnil,
                             @':defaults', s);
        s = ecl_namestring(s, ECL_NAMESTRING_FORCE_BASE_STRING);
	}
#else
        s = make_constant_base_string(ECLDIR "/");
#endif
 OUTPUT:
        {
                cl_object true_pathname = cl_probe_file(s);
                if (Null(true_pathname)) {
                        ecl_internal_error("Cannot find ECL's directory");
                }
                /* Produce a string */
                s = ecl_namestring(s, ECL_NAMESTRING_FORCE_BASE_STRING);
        }
        cl_core.library_pathname = s;
 OUTPUT_UNCHANGED:
        @(return s);
}

@(defun ext::chdir (directory &optional (change_d_p_d Ct))
	cl_object previous = si_getcwd(0);
	cl_object namestring;
@
	/* This will fail if the new directory does not exist */
	directory = cl_truename(directory);
	if (directory->pathname.name != Cnil ||
	    directory->pathname.type != Cnil)
		FEerror("~A is not a directory pathname.", 1, directory);
	namestring = ecl_namestring(directory,
                                    ECL_NAMESTRING_TRUNCATE_IF_ERROR |
                                    ECL_NAMESTRING_FORCE_BASE_STRING);
	if (safe_chdir((char*)namestring->base_string.self, Cnil) < 0)
		FElibc_error("Can't change the current directory to ~A",
			     1, namestring);
	if (change_d_p_d != Cnil)
		ECL_SETQ(the_env, @'*default-pathname-defaults*', directory);
	@(return previous)
@)

cl_object
si_mkdir(cl_object directory, cl_object mode)
{
	cl_object filename = si_coerce_to_filename(directory);
	cl_index modeint = ecl_fixnum_in_range(@'si::mkdir',"mode",mode,0,0777);
	int ok;

	if (filename->base_string.fillp)
	    filename->base_string.self[--filename->base_string.fillp] = 0;

	ecl_disable_interrupts();
#ifdef mingw32
	ok = mkdir((char*)filename->base_string.self);
#else
	ok = mkdir((char*)filename->base_string.self, modeint);
#endif
	ecl_enable_interrupts();

	if (ok < 0)
		FElibc_error("Could not create directory ~S", 1, filename);
	@(return filename)
}

cl_object
si_mkstemp(cl_object template)
{
	cl_object output;
	cl_index l;
	int fd;

#if defined(mingw32) || defined(_MSC_VER)
	cl_object phys, dir, file;
	char strTempDir[MAX_PATH];
	char strTempFileName[MAX_PATH];
	char *s;
	int ok;

	phys = cl_translate_logical_pathname(1, template);
	dir = cl_make_pathname(8,
	                       @':type', Cnil,
	                       @':name', Cnil,
	                       @':version', Cnil,
	                       @':defaults', phys);
	dir = si_coerce_to_filename(dir);
	file = cl_file_namestring(phys);
	
	l = dir->base_string.fillp;
	memcpy(strTempDir, dir->base_string.self, l);
	strTempDir[l] = 0;
	for (s = strTempDir; *s; s++)
		if (*s == '/')
			*s = '\\';

	ecl_disable_interrupts();
	ok = GetTempFileName(strTempDir, (char*)file->base_string.self, 0,
			     strTempFileName);
	ecl_enable_interrupts();
	if (!ok) {
		output = Cnil;
	} else {
		l = strlen(strTempFileName);
		output = ecl_alloc_simple_base_string(l);
		memcpy(output->base_string.self, strTempFileName, l);
	}
#else
	template = si_coerce_to_filename(template);
	l = template->base_string.fillp;
	output = ecl_alloc_simple_base_string(l + 6);
	memcpy(output->base_string.self, template->base_string.self, l);
	memcpy(output->base_string.self + l, "XXXXXX", 6);

	ecl_disable_interrupts();
# ifdef HAVE_MKSTEMP
	fd = mkstemp((char*)output->base_string.self);
# else
	if (mktemp((char*)output->base_string.self)) {
		fd = open((char*)output->base_string.self, O_CREAT|O_TRUNC, 0666);
	} else {
		fd = -1;
	}
# endif
	ecl_enable_interrupts();

	if (fd < 0) {
		output = Cnil;
	} else {
		close(fd);
	}
#endif
	@(return (Null(output)? output : cl_truename(output)))
}

cl_object
si_rmdir(cl_object directory)
{
	int code;
	directory = si_coerce_to_filename(directory);

	ecl_disable_interrupts();
	code = rmdir((char*)directory->base_string.self);
	ecl_enable_interrupts();

        if (code != 0)
             FElibc_error("Can't remove directory ~A.", 1, directory);
        @(return Cnil)
}

cl_object
si_copy_file(cl_object orig, cl_object dest)
{
	FILE *in, *out;
	int ok = 0;
	orig = si_coerce_to_filename(orig);
	dest = si_coerce_to_filename(dest);
	ecl_disable_interrupts();
	in = fopen((char*)orig->base_string.self, "r");
	if (in) {
		out = fopen((char*)dest->base_string.self, "w");
		if (out) {
			unsigned char *buffer = ecl_alloc_atomic(1024);
			cl_index size;
			do {
				size = fread(buffer, 1, 1024, in);
				fwrite(buffer, 1, size, out);
			} while (size == 1024);
			ok = 1;
			fclose(out);
		}
		fclose(in);
	}
	ecl_enable_interrupts();
	@(return (ok? Ct : Cnil))
}
