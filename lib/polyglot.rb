$:.unshift File.dirname(__FILE__)

module Polyglot
  @registrations ||= {} # Guard against reloading
  @loaded ||= {}

  def self.register(extension, klass)
    Array(extension).each{|e|
      @registrations[e] = klass
    }
  end

  def self.find(file)
    path=rawfind(file,@registrations.keys) or return nil
    return [ path, @registrations[path.gsub(/.*\./,'')]]
  end

  def self.is_absolute?(file)
    file[0] == File::SEPARATOR || file[0] == File::ALT_SEPARATOR || file =~ /\A[A-Z]:\\/i
  end

  def self.dirify(lib)
    # In Windows, repeated SEPARATOR chars have a special meaning, avoid adding them
    if /(\A\Z|[#{File::SEPARATOR}#{File::ALT_SEPARATOR}]\Z/o===lib; lib
    else lib+File::SEPARATOR
    end
  end

  def self.paths_to_try(file)
    is_absolute?(file) ? [""] : $:
  end

  def self.add_exts_to_file(file,extensions)
    unless extensions.include? file[/\.([^.]+)\Z/,1]
      if extensions.size==1
        file += ".{"+extensions+"}"
      else
        file += ".{"+extensions*','+"}"
      end
    end
  end

  def self.rawfind(file,extensions)
    add_exts_to_file
    paths_to_try(file).each{|lib|
      matches = Dir[dirify(lib)+file]
      # Revisit: Should we do more do if more than one candidate found?
      $stderr.puts "Polyglot: found more than one candidate for #{file}: #{matches*", "}" if matches.size > 1
      return path if path = matches[0]
    }
    return nil
  end

  def self.load(file)
    file = file.to_str
    raise SecurityError, "insecure operation on #{file}" if $SAFE>0 and file.tainted?
    return if @loaded[file] # Check for $: changes or file time changes and reload?
    begin
      source_file, loader = Polyglot.find(file)
      if (loader)
        loader.load(source_file)
        @loaded[file] = true
      else
        msg = "Failed to load #{file} using extensions #{(@registrations.keys+["rb"]).sort*", "}"
        if defined?(MissingSourceFile)
          raise MissingSourceFile.new(msg, file)
        else
          raise LoadError.new(msg)
        end
      end
    end
  end
end

module Kernel
  alias polyglot_original_require require

  def require(*a, &b)
    polyglot_original_require(*a, &b)
  rescue LoadError => load_error
    begin
      Polyglot.load(a)
    rescue LoadError
      # Raise the original exception, possibly a MissingSourceFile with a path
      raise load_error
    end
  end
end
