require 'thread'
require 'yaml'
class PathlistIteratorBannIfNotExist
  def initialize(pathlist, function_on_remove = nil)
    @pathlist = pathlist
    @function_on_remove = function_on_remove
  end

  def each
    @pathlist.each {|entry|
      if !entry.pathname.symlink? and !entry.pathname.exist?
	@pathlist.bann_in_iterator(entry)
	@function_on_remove.call(entry) if @function_on_remove
      else
	yield entry
      end
    }
  end
end

class PathListEntry
  def PathListEntry.stat_hash(file)
    #<File::Stat dev=0x802, ino=2, mode=040755, nlink=25, uid=0, gid=0, rdev=0x0, size=4096, blksize=4096, blocks=8, atime=Mon Mar 09 11:27:20 +0100 2009, mtime=Fri Aug 15 12:41:03 +0200 2008, ctime=Fri Aug 15 12:41:03 +0200 2008>
    begin
      str = file.lstat.inspect
    rescue Errno::ENOENT
      raise "File '#{file}' does not exist in '#{FileUtils.pwd}'"
    end
      
    hash = {}
    str.split(", ")[1..-1].each {|s|
      key, val = s.split("=",2)
      key = key.to_sym
      case key
      when :ino,:nlink,:uid,:gid,:size,:blksize,:blocks
	v = val.to_i
	raise "'#{val}' is not an integer." if v.to_s != val
	val = v      
      when :atime,:mtime,:ctime
	val = Time.parse(val)
      end
      hash[key] = val
    }
    hash
  end

  def initialize(pathname, oldstat = nil, output_mode = :full)
    raise "Pathname includes newlines." if pathname.to_s.include?("\n")
    @oldstat = oldstat
    @pathname = Pathname.new(pathname)
    
    raise "unexpected output_mode: #{val}" unless PathList::OUTPUT_MODES.include?(output_mode)
    @output_mode = output_mode
  end

  def pathname; @pathname; end
  def stat
    return @oldstat if @oldstat
    realstat
  end
  def save_stat
    @oldstat = realstat
  end
  def realstat
    PathListEntry.stat_hash(@pathname)
  end

  attr_accessor :output_mode
  attr_accessor :backup_file

  def to_s
    case @output_mode
    when :full
      pathname.to_s 
    when :filename
      pathname.basename.to_s
    else
      raise "Unexpected output_mode: #{@output_mode}"
    end
  end

  OUTPUT_FIELDS = {
    :simple => [:mtime,:size],
    :normal => [:atime, :mtime, :ctime, :mode, :size],
    :full => nil
  }
  def explain(mode = :normal)
    ret = ["Name: #{pathname.basename}",
      "Original directory: #{pathname.dirname}",
      "Backup file : #{backup_file}"].join("\n") + "\n"
    (OUTPUT_FIELDS[mode] or stat.keys).each {|key|
      ret += "#{key}: #{stat[key]}"
      ret += " bytes" if key == :size
      ret += "\n"
    }
    ret
  end
end

class PathList

  FILE_LIST_FILENAME = "filelist"

  def PathList.contains_list?(directory, filename = "filelist")
    directory = Pathname.new(directory)
    raise "Directory does not exist: #{directory}" unless directory.exist?
    zipfile = directory + ((filename or FILE_LIST_FILENAME) + ".bz2")
    zipfile.exist?
  end
 
  def initialize
    raise "Not for instantiating."
  end

  def save_list_and_stat(dir, filename = FILE_LIST_FILENAME)
    file = dir + filename
    zipfile = dir + "#{filename}.bz2"
    $log.debug{"Saving file list to #{file}"}
    FileUtils.rm(file) if file.exist?
    FileUtils.rm(zipfile) if zipfile.exist?
    raise "File does already exist: #{file}" if file.exist?
    file.open("w") {|f|
      self.each {|entry|
	if entry.pathname.symlink? or entry.pathname.exist?
	  entry.save_stat
	  f.write(entry.to_yaml.inspect + "\n")
	end
      }
    }
    raise "Could not zip '#{file}'." unless system("bzip2",file)
  end
  
  def append_entries(directory)
    check_ro
    append(directory, "each_entry") {|entry| yield entry }
  end
  def append(directory, method = "find")
    check_ro
    if self.respond_to?(:open)
      file = self.open("a")
    else
      file = nil
    end

    if directory.class.name =~ /PathList$/
      directory.each {|l|
	if file
	  file.write("#{l.to_s}\n")
	else
	  self.append_entry("#{l.to_s}")
	end
      }	
    else

      $log.debug{"Appending files in '#{directory}' with method #{method}."}
      directory = Pathname.new(directory)
      raise "No directory: '#{directory}'" unless directory.directory?
      
      directory.send(method) {|entry|	
	if method == "each_entry"
	  next if entry.to_s == ".." or entry.to_s == "."    
	  entry = directory + entry
	end
	
	if entry.to_s =~ /\n/
	  $log.warn{"Found entry that contains newlines: '#{entry.to_s.inspect.inspect}' while appending files of '#{directory}' with #{method}"}
	  next
	end
	
	unless entry.to_s == entry.to_s.strip
	  $log.warn{"Found entry that can be stripped: '#{entry.to_s}' while appending files of '#{directory}' with #{method}"}
	  next
	end
	
	raise "Found entry with empty string." if
	  entry.to_s == ""
      
	$log.debug{"Processing #{entry}"}
	ret = yield(entry)
	if ret
	  $log.debug{"Adding to pathlist: '#{entry}'"}
	  
	  if file
	    file.write("#{entry}\n")
	  else
	    self.append_entry("#{l.to_s}")
	  end
	end
      }
    end
    file.close if file
  end

  
  OUTPUT_MODES = [:full, :filename]
  def output_mode=(val)
    raise "unexpected output_mode: #{val}" unless OUTPUT_MODES.include?(val)
    @index = nil
    @output_mode = val
    if @list 
      @list.each{|e| e.output_mode = output_mode }
    end
  end
  def output_mode
    @output_mode or  :full
  end

  
  def clean_up
  end

  def [](key)
    unless @list
      @list = []
      @index = {}
      self.each {|e| 
	@list.push(e)
	@index[e.to_s] = e
      }
    end
    if (key.class.name == "String" or key.class.name == "PathListEntry") and @index
      entry = @index[key.to_s]
      return nil if banned?(entry)      
      return entry
    end
    @list.each {|entry|
      next if banned?(entry)
      case key.class.name
      when "String"
	return entry if entry.to_s == key
      when "Regexp"
	return entry if entry.to_s =~ key
      when "PathListEntry"
	return entry if entry.to_s == key.to_s	
      else
	raise "Unexpected key class #{key.class.name}."
      end
    }
    return nil
  end
  
  def banned?(key)
    return false unless @banned_files
    raise "Banned for archive not implemented." if @archive
    @banned_files.each {|f|
      return true if key.to_s == f.to_s
    }
    return false
  end
  def bann_in_iterator(key)
    @banned_files ||= []
    @banned_files.push(key.to_s)
  end

  def split_combine(old_list)
    new_lists = {}
    $log.debug{"Output mode: #{output_mode}"}
    if old_list
      $log.debug{"Output modes: #{output_mode} =?= #{old_list.output_mode}"}
      raise "I dont have the same output_mode '#{output_mode}' as old file list #{old_list.output_mode}." unless
	output_mode ==  old_list.output_mode
    end

    combined_list = {}
    self.each {|e|
      combined_list[e.pathname.to_s] = [e,nil]
    }
    (old_list or []).each {|e|
      key = e.pathname.to_s
      arr = combined_list[key]
      if arr
	arr[1] = e
      else
	arr = [nil, e]
      end
      combined_list[key] = arr
    }
    keys = combined_list.keys.sort

    keys.each {|key|
      cur,old = combined_list[key]
      raise "Neither old nor current entry found for #{e.inspect}!" if cur.nil? and old.nil?
      raise "Same object?? cannot be." if cur.object_id == old.object_id
      ret = yield(cur,old)
      if ret
	if ret === true
	  new_name = "default"
	else
	  new_name = ret.to_s
	end
	
	new_list = new_lists[new_name.to_sym]
	unless new_list
	  new_list = (new_lists[new_name.to_sym] = MemoryPathList.new)
	end
	$log.debug{"Adding to #{new_name.to_sym.inspect}:'#{key}'"}
	new_list.append_entry(key)
      else
	$log.debug("Not using element '#{key}'.")
      end
    }

    new_lists
  end

  def new_list(old_list, tmp_file, negate)
    # using alsways memor list now
    raise "Deprecated use" if tmp_file
    nl = MemoryPathList.new
    # nl.temp_file = tmp_file if tmp_file
    #nl.open("w") {|f|
      self.each {|entry|
	if yield(entry, old_list[entry]) ^ negate
	  nl.append_entry(entry.to_s) #f.write(entry.to_s + "\n")
	end
      }
#    }
    nl
  end

  def select(old_list, tmp_file = nil, &block)
    new_list(old_list, tmp_file, false, &block)
  end
  def reject(old_list, tmp_file = nil, &block)
    new_list(old_list, tmp_file, true, &block)
  end
        
  # to treat as normal file
  def readlines
    a = []
    self.each {|entry|
      a.push(entry.to_s + "\n")
    }
    a
  end

end


class ArchivePathList < PathList
  def initialize(directory, filename = FILE_LIST_FILENAME)
    $log.debug{"Creating file list in '#{directory}' and name '#{filename}'"}
    directory = Pathname.new(directory)
    raise "Directory does not exist: #{directory}" unless directory.exist?
    @archive_directory = directory
    @zipfile = Pathname.new((@archive_directory + ((filename or FILE_LIST_FILENAME))).to_s + ".bz2")
    raise "File '#{@zipfile}' does not exist." unless @zipfile.exist?
  end

  def check_ro; @list = nil; true; end
  def source_file; @zipfile; end

  def each
    raise "File '#{@zipfile}' does not exist." unless @zipfile.exist?
    cmd = "| bunzip2 < '#{@zipfile}'"
    $log.debug{"Opening archive file with: #{cmd}"}
    Kernel.open(cmd) {|f| f.each {|line|
	raise "unexpected line: #{line.inspect}" unless line =~ /^\".*\"$/
	entry = YAML.load(eval(line))
	raise "Unexpected line in #{cmd.inspect} found: #{line.inspect}" unless 
	  entry.respond_to?(:output_mode)
	entry.output_mode = output_mode
	yield entry
      }
    }
  end

  def length
    raise "Archive file not found: #{@zipfile}" unless @zipfile.exist?
    unless Kernel.open("|cat '#{@zipfile}' | bunzip2 | wc -l") {|f| f.readlines[0]} =~ /^(\d+)/
      raise "unexpected result while counting lines"
    end
    $1.to_i      
  end

end

class FilePathList < PathList
  def initialize(directory = nil, filename = "filelist")
    if directory
      $log.debug{"Creating file list in '#{directory}' and name '#{filename}'"}
      directory = Pathname.new(directory)
      raise "Directory does not exist: #{directory}" unless directory.exist?
      @archive = true
      @archive_directory = directory
      @zipfile = Pathname.new((@archive_directory + ((filename or FILE_LIST_FILENAME))).to_s + ".bz2")
      raise "File '#{@zipfile}' does not exist." unless @zipfile.exist?
    else
      @archive = false
    end
  end

  def check_ro; false; end
  def source_file; temp_file; end

  @@mutex = Mutex.new

  def override_temp_file=(val); @temp_file = val; end
  def temp_file=(val)
    raise "Tempfile already set to '#{@temp_file}'" if @temp_file
    @temp_file = Pathname.new(val)
    raise "'#{@temp_file}' already exist." if @temp_file.exist?
  end
  
  def temp_file
    return @temp_file if @temp_file
    raise "No tempdir defined. in envronment." unless ENV["TMPDIR"]
    tdir = Pathname.new(ENV["TMPDIR"])
    name = "path_list-#{Process.pid}-"
    i = 0
    @@mutex.synchronize {
      @temp_file = tdir + (name + i.to_s)
      while @temp_file.exist?
	i += 1
	@temp_file = tdir + (name + i.to_s)
	$log.debug(@temp_file)
      end
    }
    @temp_file
  end
  
  def each
    @temp_file.each_line {|f|
      f = PathListEntry.new(f.strip, nil, output_mode)
      next if banned?(f)
      yield f
    }
  end

  # to treat as normal file
  def readlines
    @temp_file.readlines
  end

  def length
    return 0 unless temp_file.exist?
    unless Kernel.open("| wc -l #{temp_file}") {|f| f.readlines[0]} =~ /^(\d+) /
      raise "unexpected result while counting lines"
    end
    $1.to_i
  end

  def clean_up
    $log.debug{"Cleaning up file list '#{temp_file}'"}
    FileUtils.rm_f(temp_file) if temp_file.exist?
  end

  def open(*args, &block) # :yield: file
    temp_file.open(*args, &block)
  end

  def make_relative_to(directory)
    check_ro
    dir = directory.to_s
    File.open("#{temp_file}.tmp", "w") {|f|
      each {|entry|
	str = entry.pathname.to_s
	raise "'#{str}' does not start with directory '#{directory}'" unless
	  str.index(dir) == 0
	if str == dir or str == "#{dir}/"
	  f.write("." + "\n")
	else
	  str = str.sub(dir,"")
	  str = str[1..-1] if str =~ /^\//
	  f.write(str + "\n")
	end
      }
    }
    FileUtils.mv("#{temp_file}.tmp", temp_file)
  end

  def sort_uniq
    check_ro
    raise "Could not sort full list." unless system("sort -u < '#{temp_file}' | uniq > '#{temp_file}.tmp'")    
    FileUtils.mv("#{temp_file}.tmp", temp_file)    
  end

end

class MemoryPathList < PathList
  def initialize
    @list = []
  end
  def append_entry(entry)
    e = PathListEntry.new(entry)
    e.output_mode = output_mode
    @list.push(e)
  end

  def length
    @list.length
  end

  def each
    @list.each {|e|
      e.output_mode = output_mode
      yield(e)
    }
  end

  def check_ro; false; end
end


