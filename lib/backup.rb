require "pathname"
require "path_list"
class Backup
  def Backup.root
    (ENV["BACKUP_ROOT"] or (defined?(BACKUP_ROOT) and BACKUP_ROOT))
  end

  def Backup.update_options(options)
    options = options.dup
    options[:backup_root] ||= Backup.root
    options[:host_name] ||= (ENV["HOST"] or (defined?(HOST) and HOST))
    options[:domain] ||= (ENV["NET"] or (defined?(NET) and NET))

    raise "Backup root not defined." if options[:backup_root].nil? or options[:backup_root] == ""
    options[:backup_root] = Pathname.new(options[:backup_root]).cleanpath
    raise "Backup root not found '#{options[:backup_root]}'" if !options[:backup_root].exist?

    options[:state_path] ||= options[:backup_root] + "state"
    options[:state_path] = Pathname.new(options[:state_path])
#    raise "State path not found '#{options[:state_path]}'" if !options[:state_path].exist?

    options.keys.each {|k|
      raise "#{k} not defined" if options[k].nil? or options[k] == ""
    }
    options
  end

  def Backup.glob_directories(hosts = nil, modes = nil, sets = nil, options = {})
    options = update_options(options)
    h = {}
    if hosts.nil? or hosts.length == 0
      pattern = "*" 
    else 
      pattern = "{" + hosts.join(",") + "}"
    end

    if sets.nil? or hosts.length == 0
      pattern = "*" 
    else 
    end
    
    sets = Backup.sets if sets.nil?
    sets = "{" + sets.join(",") + "}"
    modes = ["full","incr","diff"] if modes.nil?
    
    $log.debug("Looking for directories for hosts '#{pattern}' and modes #{modes}.")
    dirs = []
    modes.select {|m| m == "full"}.each {|mode|
      glob = "#{options[:backup_root]}/#{sets}/#{mode}/*/#{pattern}"
      $log.debug("Globbing '#{glob}'.")
      Dir.glob(glob).each {|d|
	if d =~ /^.*\/([^\/]+)\/(full)\/([^\/]+)\/([^\/]+)$/
	  dirs.push({:dir => d, :set => $1, :mode => $2, :domain => $3, :date => nil, :host_name => $4})
	else
	  #        dirs.push([:dir => d])
	  $log.warn("Illegal directory found #{d}")
	end
      }
    }
    modes.select {|m| m == "incr" or m == "diff"}.each {|mode|
      glob = "#{options[:backup_root]}/#{sets}/#{mode}/*/*/#{pattern}"
      $log.debug("Globbing '#{glob}'.")
      Dir.glob(glob).each{|d|
	if d =~ /^.*\/([^\/]+)\/(incr|diff)\/([^\/]+)\/(\d\d\d\d-\d\d-\d\d)\/([^\/]+)$/
	  dirs.push({:dir => d,  :set => $1, :mode => $2, :domain => $3, :date => $4, :host_name => $5})
	else
	  $log.warn("Illegal directory found #{d}")
	  #        dirs.push([:dir => d])
	end
      }
    }
    dirs
  end

  def Backup.sets(options = {})
    options = update_options(options)
    root = options[:backup_root]
    glob_path = options[:backup_root] + "*/full/#{options[:domain]}/#{options[:host_name]}"
    $log.debug{"Globbing for sets with: #{glob_path}"}
    sets = Dir.glob(glob_path).map {|dir|
      dir.gsub(options[:backup_root].to_s,"").split("/")[1]
    }
    sets = ["data","config","system"] if sets.length == 0
    $log.debug("Found the following sets: #{sets.inspect}")
    sets
  end

  # config
  def Backup.load_defaults 
    # Default configuration
    set_config("ISIBACKUP_CONFIGDIR",get_config("ISIBACKUP_CONFIGDIR","/etc/isibackup"))
    set_config("ISIBACKUP_CONFIG_DEFAULTS",get_config("ISIBACKUP_CONFIG_DEFAULTS","#{get_config("ISIBACKUP_CONFIGDIR")}/defaults.conf"))
    
    source("#{get_config("ISIBACKUP_CONFIG_DEFAULTS")}")
  end
  # Load configuration
  def Backup.load_config 
  # Config file option:
    # 1. command line
    # 2. default: isibackup.conf

    # Source config, abort if config file cannot be sourced
    conffile = get_config("ISIBACKUP_CONFIG")
    $log.info{"Reading configuration '#{conffile}'"}
    source(conffile)
  end

  def Backup.set_config(name, value)
    raise "Configuration name is nil." if name.nil?
    raise "Cannot set something else than a string to #{name}: #{value.class.name}" if
      !value.nil? and value.class.name != "String"
    ENV[name] = value
    $log.config("ENV['#{name}'] is now: #{ENV[name].inspect}") if $log.respond_to?(:config)
    value
  end
  def Backup.get_config(name, default = nil)
    raise "Configuration name is nil." if name.nil?
    raise "Name must be a string: #{name.inspect}" unless name.class.name == "String"
    if ENV[name].nil? or ENV[name] == ""
      $log.config{"Using default config value #{default.inspect} for #{name}."} if $log.respond_to?(:config)
      return default
    end
    $log.config{"Configuration #{name} has value #{ENV[name].inspect}"} if $log.respond_to?(:config)
    ENV[name]
  end

  # Backup control configuration is 
  # stored here:
  CONTROL_FILE="/etc/isibackup/control" unless defined?(CONTROL_FILE)

  def Backup.control
    configs = {}
    open(CONTROL_FILE,"r") {|f|
      f.each {|line|
	case line
	when /^\s*\#/, /^\s*$/
	  # ignore
	when /^\s*(\S+)\s*\:\s*(\d+|\*|\*\/\d+)\s*\,\s*(\d+|\*|\*\/\d+)\s*\,\s*(\d+|\*|\*\/\d+)\s*$/
	  raise "Multiple definitions for confiuration '#{$1}' found in '#{CONTROL_FILE}'" if configs[$1]
	  configs[$1.to_sym] = {
	    :full => parse_interval($2),
	    :incr => parse_interval($3),
	    :diff => parse_interval($4)
	  }
	else
	  raise "Unexpected line in '#{CONTROL_FILE}': #{line.inspect}"
	end     
      } 
    }
    if (media = configs.delete(:media))      
      if medias = get_config("MEDIAS")
	medias = Dir.glob(medias)
	medias.each {|m| path = Pathname.new(m)
	  if path.mountpoint?
	    configs["media-#{path.basename.to_s}".to_sym] = media.dup
	  end
	}
      end
    end
    
    configs
  end


  def initialize(set, options = {})
    raise "Set is nil." if set.nil?

    options = Backup.update_options(options)
    @host = options[:host_name]
    @domain = options[:domain]
    @set = set
    @root = Pathname.new(options[:backup_root])
    raise "Backup root does not exist '#{@root}'" unless @root.directory?
    @state_path = options[:state_path]
    @options = options
  end

  def to_s
    "Backup of #{@host} #{@set}"
  end
  
  def stamp_file(mode)
    @state_path + "#{@host}.#{@domain}-#{@set}-#{mode}.date"
  end
  def state_log
    @state_path + "#{@host}.#{@domain}.log"
  end
  
  def get_stamp(mode, options = {})
    case mode
    when "full"
      return nil    
    when "diff"
      lStampFName = stamp_file("full")
    when "incr"
      lStampFName_incr=stamp_file("incr")
      lStampFName_full=stamp_file("full")

      #use the timestamp from a previous backup if the last incremental backup was today and not using dirnumbering
      if !@options[:dir_numbering] and
	  !@options[:dir_with_time] and
	  lStampFName_incr.exist? and
	  lStampFName_incr.read(10) == (ENV["START_TIME"][0..9] or "")
	
	lStampFName_incr = Pathname.new("#{lStampFName_incr.to_s}.rotated")
      end
      
      if !lStampFName_incr.exist?
	lStampFName=lStampFName_full
      else
	#get the newest Stamp, either full or incr
	if lStampFName_incr.mtime >= lStampFName_full.mtime
	  lStampFName=lStampFName_incr
	else
	  lStampFName=lStampFName_full
	end
      end
    else
      raise "Unexpected OPT_MODE '#{mode}'"
    end
    
    if lStampFName.exist?
      DateTime.parse(lStampFName.read(19)).strftime("%F %T")
    else
      return nil
    end
  end

  def get_logs
    ret = []
    state_log.each_line {|line|
      fields = line.split(",")
      unless fields.length == 19
	# This is probably because of out of space. ignoring this line.
	$log.info("Ignoring line, too few fields: #{line.inspect}")
	next
      end
            
      hash = {
	:start_time => fields[0],
	:finish_time => fields[1],
	:action => fields[2].downcase.to_sym,
	:set => fields[3],
	:mode => fields[4],
	:pack_method => fields[5],
	:cmd_crypt => fields[6],
	:total_dirs_found => fields[7],
	:total_input_count => fields[8],
	:total_input_size => fields[9],
	:total_output_count => fields[10],
	:total_output_size => fields[11],
	:program_version => fields[12],
	:host => fields[13],
	:domain => fields[14],
	:net => fields[14],
	:crypt_key_id => fields[15],
	:crypt_key_name => fields[16],
	:result => fields[18].strip
      }
      
      if fields[17] =~ /^\".*\"$/
	hash[:target_dir] = Pathname.new(eval(fields[17]))
      else
	hash[:target_dir] = Pathname.new(fields[17])
      end

      if hash[:host] == @host and
	  hash[:domain] == @domain and
	  hash[:set].to_s == @set.to_s then
	ret.push(hash)
      end
    }
    ret
  end

  def get_current_backup_runs(only_completed = false)
    logs = get_logs
    logs = logs.select {|hash|
      $log.debug{"Mode: #{hash[:mode].inspect} Action: #{hash[:action].inspect} => #{hash[:action] == :backup}"}
      hash[:action] == :backup
    }

    latest_full = nil
    logs.each_with_index {|hash, index|
      if hash[:mode] == "full" and hash[:result] != "started" and !(hash[:result] =~ /^safe/)
	$log.debug{"New latest full: #{hash[:start_time]} result: #{hash[:result]}"}
	latest_full = index
      end
    }
   
    if latest_full.nil?
      $log.debug{"No full found."}
      return [] 
    end
    
    logs = logs[latest_full..-1]
    logs = logs.select {|hash| 
      $log.debug{"Backup result: #{hash[:result]}"}
      hash[:result] =~ /^completed/
    } if only_completed
    logs.each_with_index {|log,index|
      raise "Current target directory is already in log!!" if log[:mode] != "full" and @root.to_s == log[:target_dir].to_s
      raise "'#{log[:target_dir]}' does not exist!" unless Pathname.new(log[:target_dir]).exist?
    }
    logs.map {|log| BackupRun.new(log)}
  end
  
  def get_latest_completed_runs    
    return nil unless state_log.exist?
    return @current_completed_runs if @current_completed_runs and (@current_completed_runs_date == state_log.mtime)
    @current_completed_runs_date == state_log.mtime
    @current_completed_runs = get_current_backup_runs(true)
  end

  def latest_full
    runs = get_latest_completed_runs
    runs = runs.select {|r| r[:mode] == "full"}
    runs[-1]
  end
  def latest
    get_latest_completed_runs[-1]    
  end

  def get_latest_dirlist(full_only = nil)
    if full_only
      l = latest_full
    else
      l = latest
    end
    $log.debug{"Latest backup run: #{l.inspect}"}
    return nil if l.nil?

    return nil unless PathList.contains_list?(l[:target_dir],"dirlist")
    ArchivePathList.new(l[:target_dir],"dirlist")
  end

  def get_latest_filelist_for(directory, alternative_root = nil, full_only = nil)
    runs = get_latest_completed_runs
    runs = runs.select {|r| r[:mode] == "full"} if full_only
    runs.reverse.each {|run|
      filelist = run.filelist_for(directory)
      return filelist if filelist
    }
    if alternative_root
      return BackupRun.filelist_for(alternative_root,directory)
    end
    return nil
  end
  
end


EXTRACT_COMMAND = "gpg -q -d '%s' | bunzip2 | cpio --extract --to-stdout --quiet"

class BackupRun

  def BackupRun.filelist_for(root, directory)
    raise "Only relative directories allowed: '#{directory}'" if
      directory.to_s =~ /^\//
    dir = root + directory
    $log.debug{"Looking for file list in #{dir}"}
    return nil unless dir.directory?
    return nil unless PathList.contains_list?(dir)
    $log.debug{"Found file list in #{dir}"}
    ArchivePathList.new(dir)
  end
  def BackupRun.dirlist_for(root)    
    $log.debug{"Looking for dir list in #{root}"}
    
    raise "No pathlist found for backup root #{root}." unless
      PathList.contains_list?(root, "dirlist")
    $log.debug{"Found dir list in #{root}"}
    pl = ArchivePathList.new(root, "dirlist")
  end

  def initialize(log)
    @log = log
    raise "Log for initializing is nil." if log.nil?
    raise "Target directory '#{@log[:target_dir]}' does not exist." unless
      @log[:target_dir].directory?
  end

  def uncrypt(f)
    raise "Could not uncrypt." unless system("gpg","-q","--batch",f)
  end
  def unzip(f)
    raise "Could not unzip." unless system("bunzip2",f)
  end

  def extract(backup_file, filename = nil, target_file = nil)
    $log.debug{"Extracting #{filename or "all files"} from #{backup_file}"}
    raise "No backup file given" unless backup_file
    bf = root + backup_file.to_s
    raise "Backup file #{bf} not found" unless 
      bf.exist?
    
    if filename
      tmp_dir = Pathname.new("/tmp/isirestore-#{Process.pid}")
      FileUtils.mkdir(tmp_dir)
      begin
	FileUtils.cd(tmp_dir) {
	  tmp_file = tmp_dir.to_s + "/restore-#{Process.pid}"
	  FileUtils.copy(bf, tmp_file + ".cpio.bz2.gpg")
	  
	  uncrypt(tmp_file + ".cpio.bz2.gpg")
	  unzip(tmp_file + ".cpio.bz2")
	  
	  execute_command_popen3(["cpio","--quiet","--extract","--preserve-modification-time","--no-absolute-filenames","-F",tmp_file + ".cpio", filename])
	}
	FileUtils.copy(tmp_dir + filename, target_file)
      ensure
	FileUtils.rm_rf(tmp_dir)
      end
      $log.info{"File extracted to '#{target_file}'"}
    else
      fn = "isirestore-#{Process.pid}"
      begin
	FileUtils.copy(bf, "#{fn}.cpio.bz2.gpg")
	uncrypt("#{fn}.cpio.bz2.gpg")
	unzip("#{fn}.cpio.bz2")
	execute_command_popen3(["cpio","--unconditional","--quiet","--extract","--preserve-modification-time","--no-absolute-filenames","-F","#{fn}.cpio"])
      ensure
	Dir.glob("#{fn}.cpio*").each {|f|
	  FileUtils.rm(f)
	}
      end
      $log.info{"File extracted to '#{FileUtils.pwd}'"}
    end

    return target_file
  end

  def extract_directory(directory, target_directory)
    raise "Only relative directories allowed: '#{directory}'" if
      directory.to_s =~ /^\//
    directory = Pathname.new(directory)
    target_directory = Pathname.new(target_directory)
    
    target_directory.mkpath
    $log.info("Extracting #{directory} to #{target_directory}")
    directories_in(directory).each {|d|
      extract_directory(directory + d, target_directory + d)
    }
    
    backup_files = files_in(directory).map {|f| f.backup_file }.uniq.compact
    backup_files.each {|bf|
      FileUtils.cd(target_directory) { 
	begin
	  extract(bf)
	rescue
	  $log.error($!)
	  if $log.debug?
	    $!.backtrace.each {|l| $log.debug(l)}
	  end
	end
      }
    }
  end

  def root; @log[:target_dir]; end
  def log; @log; end

  def filelist_for(directory)
    BackupRun.filelist_for(root,directory)
  end
  
  def dirlist
    BackupRun.dirlist_for(root)
  end
  
  def directories_in(directory)
    raise "Only relative directories allowed: '#{directory}'" if
      directory.to_s =~ /^\//
    dirs = []
    d = root + directory
    d.entries.each {|e|
      if (d + e).directory?
	$log.debug("Found directory #{d + e}")
	next if [".",".."].include?(e.to_s)
	dirs << e
      end
    } if d.directory?
    dirs
  end
  def files_in(directory)
    files = []
    fl = filelist_for(directory)
    (fl or []).each {|e|
      files << e
    }
    files
  end

  def entries_in(directory)    
    raise "Only relative directories allowed: '#{directory}'" if
      directory.to_s =~ /^\//
    files = files_in(directory)
    dirs = directories_in(directory)
    #reg = Regexp.new("^#{Regexp.escape(directory.to_s)}\\/[^\\/]")
    #dirlist.each {|e|
    #ret << e if e.pathname.to_s =~ reg
    #
    [files, dirs]
  end
  
  def [](index)
    @log[index]
  end

end
