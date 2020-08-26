module os

pub struct File {
	cfile  voidptr // Using void* instead of FILE*
mut:
	buf_len int = 0
	buf     byteptr = 0
pub:
	fd     int
pub mut:
	is_opened bool
}

struct FileInfo {
	name string
	size int
}

[deprecated]
pub fn (f File) is_opened() bool {
	eprintln('warning: `file.is_opened()` has been deprecated, use `file.is_opened` instead')
	return f.is_opened
}

// **************************** Write ops  ***************************
pub fn (mut f File) write(s string) {
	if !f.is_opened {
		return
	}
	/*
	$if linux {
		$if !android {
			C.syscall(sys_write, f.fd, s.str, s.len)
			return
		}
	}
	*/
	C.fwrite(s.str, s.len, 1, f.cfile)
}

pub fn (mut f File) writeln(s string) {
	if !f.is_opened {
		return
	}
	/*
	$if linux {
		$if !android {
			snl := s + '\n'
			C.syscall(sys_write, f.fd, snl.str, snl.len)
			return
		}
	}
	*/
	// TODO perf
	C.fwrite(s.str, s.len, 1, f.cfile)
	C.fputs('\n', f.cfile)
}

pub fn (mut f File) write_bytes(data voidptr, size int) int {
	return C.fwrite(data, 1, size, f.cfile)
}

pub fn (mut f File) write_bytes_at(data voidptr, size, pos int) int {
	C.fseek(f.cfile, pos, C.SEEK_SET)
	res := C.fwrite(data, 1, size, f.cfile)
	C.fseek(f.cfile, 0, C.SEEK_END)
	return res
}

// **************************** Read ops  ***************************
// read_bytes reads an amount of bytes from the beginning of the file
pub fn (f &File) read_bytes(size int) []byte {
	return f.read_bytes_at(size, 0)
}

// read_bytes_at reads an amount of bytes at the given position in the file
pub fn (f &File) read_bytes_at(size, pos int) []byte {
	mut arr := [`0`].repeat(size)
	C.fseek(f.cfile, pos, C.SEEK_SET)
	nreadbytes := C.fread(arr.data, 1, size, f.cfile)
	C.fseek(f.cfile, 0, C.SEEK_SET)
	return arr[0..nreadbytes]
}

// read_line reads one line (or f.buf_len character) from the file
// modeled after Go's Reader.ReadLine
pub fn (mut f File) read_line() ?(string,bool) {
	if f.buf==0 { return error('read_line buffer not allocated') }
	if C.fgets(f.buf, f.buf_len+1, f.cfile) == 0 { return none }
	mut is_prefix := true
	mut len := vstrlen(f.buf)
	// check and strip EOL - before creating V's string
	if len>0 && unsafe{f.buf[len-1]} == `\n` {
		unsafe{f.buf[len-1] = `0`}
		len--
		is_prefix = false
		if len>0 && unsafe{f.buf[len-1]} == `\r` {
			unsafe{f.buf[len-1] = `0`}
			len--
		}
	}
	line := tos(f.buf, len)
	return line, is_prefix
}


// modeled after Python's readline but with trailing EOL characters removal
pub fn (mut f File) readline(size ...int) ?string {
	// TODO check closed ?
	
	// optional parameter - limit maximum buffer size
	limit := if size.len>0 && size[0]>1 { size[0] } else { 0x7FFFFFFF } // i32_max
	
	// allocate the buffer if there is none
	if f.buf==0 {
		f.buf_len = min(2, limit) // TODO const
		f.buf = malloc(f.buf_len)
	}
	
	mut len := 0
	mut offset := 0
	for {
		// read from file into the buffer
		cap := f.buf_len-offset // TODO limit
		if C.fgets(unsafe{f.buf+offset}, cap, f.cfile) == 0 { return none } // TEST 
		len = vstrlen(unsafe{f.buf+offset})
		
		if len>0 && unsafe{f.buf[len+offset-1]} == `\n` { // EOL
			// strip trailing EOL characters (\n or \r\n) in the buffer
			unsafe{f.buf[len+offset-1] = `0`}
			len--
			if len>0 && unsafe{f.buf[len+offset-1]} == `\r` {
				unsafe{f.buf[len+offset-1] = `0`}
				len--
			}
			break
		} else { // no EOL
			if f.buf_len >= limit { break } // limit reached - incomplete line
			// grow the buffer - double it up to the limit
			f.buf_len *= 2
			f.buf_len = min(f.buf_len, limit)
			f.buf = v_realloc(f.buf, u32(f.buf_len))
			offset += len
		}
	}
	
	return tos(f.buf, offset+len)
}

// **************************** Utility  ops ***********************
// write any unwritten data in stream's buffer
pub fn (mut f File) flush() {
	if !f.is_opened {
		return
	}
	C.fflush(f.cfile)
}

// set_buffer allocates the buffer for the read_line calls
pub fn (mut f File) set_buffer(size int) {
	if f.buf != 0 && f.buf_len > 0 {
		free(f.buf)
	}
	f.buf = malloc(size+1)
	f.buf_len = size
}

fn min(a int, b int) int {
	return if a<b {a} else {b}
}
