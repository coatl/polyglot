#$:.unshift File.dirname(__FILE__)
require 'polyglot/check_for_absolute_path_in_LOADED_FEATURES'

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

  def self.require(file)
    file = file.to_str
    raise SecurityError, "insecure operation on #{file}" if $SAFE>0 and file.tainted?
    return in_LOADED_FEATURES? file
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
      f=File.open(path,"rb")
      line=f.readline
      line[0..2]='' if /\A\xEF\xBB\xBF/===line #skip utf8 bom if present
      line=f.readline if /\A\#!/===line  #skip shebang line if present
      line=f.readline if /^\s*#.*(?:en)?coding[:= ](.*)\s*$/===line #skip encoding line if present
      if f.readline[/^\s*Polyglot\.dialects\s*\(?\s*(.*)\s*\)?\s*$/] #look for dialects line
        dialects=$1
        dialects.split(/\s*,\s*/).map{|v| v[/^:(.*)$/,1].to_sym }
        Dialect.make_chain(*dialects.map{|d| @registrations[d] }).load(path)
      end
    end
  end

  def self.dialects(*names)
    #don't do anything here;
    #the 'macro' implementation of this method is in try_dialects_require, above
  end

  class Dialect
    def load(path)
      src=File.read(path)
      eval src, path, 1, TOPLEVEL_BINDING.dup
    end

    def eval src, *rest
      rest.push rest.shift if Binding===rest.first
      rest.unshift "(eval)" unless String===rest.first
      rest[1,0]=1 unless Integer===rest[1]
      rest.push Binding.of_caller unless Binding===rest.last
      fail if rest.size>3
      file,line,binding=*rest

      src=transform src, file, line, binding
      ::Kernel::unpolyglotted_eval src, file, line, binding #but this could be recursive!
    end

    def transform src, *rest
      src
    end

    def priority; 1 end  

    def chain_class; Chain end

    def self.make_chain(*dialects)
      prio2dialects=Hash.new{|h,k| h[k]=[] }
      dialects.each{|dialect| prio2dialects[dialect.priority]=dialect }
      list=prio2dialects.keys.sort.map{|prio| 
        list=prio2dialects[prio]
        list.first.chain_class.new(*list) 
      }
      list.first.chain_class.new(*list)
    end

    class Chain<Dialect
      class <<self
        alias noncollapsing_new new
        def new *args
          list=[]
          args.each{|arg| arg.class==self ? list.concat arg : list<<arg }
          noncollapsing_new list
        end
      end

      def initialize(list)
        @list=list
      end

      def chain; @list end
 
      def priority; 1 end

      def transform src, *rest
        @list.inject(src){|src,x| x.transform(src, *rest) }
      end
    end
  end

  class RedParseDialect<Dialect
    def priority; 2 end

    def chain_class; Chain end

    def initialize lexer_mixin, parser_mixin=nil, tree_rewriter=nil
      @lexer_mixin,@parser_mixin,@tree_rewriter = 
        lexer_mixin,parser_mixin,tree_rewriter
    end
 
    attr_reader :lexer_mixin,:parser_mixin,:tree_rewriter

    def transform src, file,line,binding
      lexer=RubyLexer.new(file,src,line,huh(binding))
      x= lexer_mixin; lexer.extend x if x 
      parser=RedParse.new(lexer,file,line,huh(binding))
      x= parser_mixin; parser.extend x if x 

      @tree_rewriter[parser.parse].unparse({})
    end

    class Chain<Dialect::Chain
      def priority; 2 end
      def transform src, file,line,binding
        lexer=RubyLexer.new(file,src,line,huh(binding))
        @list.each{|x| x= x.lexer_mixin; lexer.extend x if x }
        parser=RedParse.new(lexer,file,line,huh(binding))
        @list.each{|x| x= x.parser_mixin; parser.extend x if x }
      
        tree=parser.parse
        @list.each{|x| x= x.tree_rewriter; tree=x[tree] if x }
        tree.unparse({})
      end
    end
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
