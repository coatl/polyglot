#$:.unshift File.dirname(__FILE__)
require 'polyglot/check_for_absolute_path_in_LOADED_FEATURES'
require 'polyglot/dialect'

module Polyglot
  @registrations ||= {} # Guard against reloading

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

  if is_absolute?($".grep(%r{(\A|/)polyglot/check_for_absolute_path_in_LOADED_FEATURES\.rb\z}).first)
    #ruby >=1.9
    def self.in_LOADED_FEATURES?(file)
      return $".include? file if is_absolute?(file) 
      $".grep( %r{\A(
                  #{$:.map{|dir| dir[%r{/\Z}]=''; Regexp.quote File.expand_path dir}.join("|")}
                  )/
                  #{Regexp.quote file}
                  \z
               }x
      ).empty?
    end

    def self.add_to_LOADED_FEATURES(file)
      return $"<<file if is_absolute?(file) 
      fail
      #abs=nil
      #found=$:.find{|dir| dir[%r{/\Z}]=''; File.exist? abs=File.expand_path dir+"/"+file}
      #$"<<abs if found
    end
  else
    #ruby < 1.9
    def self.in_LOADED_FEATURES?(file)
      $".include? file 
    end

    def self.add_to_LOADED_FEATURES(file)
      $"<<file
    end
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
    if extensions.include? file[/\.([^.]+)\z/,1]
      file
#    elsif extensions.size==1
#      file += ".{"+extensions[0]+"}"
    else
      file += ".{"+extensions*','+"}"
    end
  end

  def self.rawfind(file,extensions)
    file=add_exts_to_file(file,extensions)
    result=nil
    paths_to_try(file).find{|lib|
      matches = Dir[dirify(lib)+file]
      # Revisit: Should we do more do if more than one candidate found?
      $stderr.puts "Polyglot: found more than one candidate for #{file}: #{matches*", "}" if matches.size > 1
      result=matches[0]
    }
    return result
  end

  def self.require(file)
    file = file.to_str
    raise SecurityError, "insecure operation on #{file}" if $SAFE>0 and file.tainted?
    return if in_LOADED_FEATURES?( file )
    begin
      source_file, loader = Polyglot.find(file)
      if (loader)
        loader.load(source_file)
        add_to_LOADED_FEATURES source_file
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

  def self.try_dialects_require(file)
    file = file.to_str
    raise SecurityError, "insecure operation on #{file}" if $SAFE>0 and file.tainted?
    return if in_LOADED_FEATURES? file

    extensions=["rb"]
    for name in %w[DLEXT DLEXT2] do
      value=Config::CONFIG[name]
      extensions<<value unless value.empty?
    end
    path=rawfind(file,extensions)
    if /\.rb\Z/===path
      add_to_LOADED_FEATURES path
      File.open(path,"rb"){|f|
      line=f.readline
      line[0..2]='' if /\A\xEF\xBB\xBF/===line #skip utf8 bom if present
      line=f.readline if /\A\#!/===line  #skip shebang line if present
      line=f.readline if /^\s*#.*(?:en)?coding[:= ](.*)\s*$/===line #skip encoding line if present
      if line[/^\s*Polyglot\.dialects?\s*\(?\s*(.*)\s*\)?\s*$/] #look for dialects line
        dialects=$1
        dialects.split(/\s*,\s*/).map{|v| v[/^:(.*)$/,1].to_sym }
        Dialect.make_chain(*dialects.map{|d| @registrations[d] }).load(path)
      end
      }
    end
  end

  def self.dialects(*names)
    #don't do anything here;
    #the 'macro' implementation of this method is in try_dialects_require, above
  end
end

module Kernel
  alias polyglot_original_require require

  def require(a)
    Polyglot.try_dialects_require(a) or polyglot_original_require(a)
  rescue LoadError => load_error
    begin
      Polyglot.require(a)
    rescue LoadError
      # Raise the original exception, possibly a MissingSourceFile with a path
      raise load_error
    end
  end
end
