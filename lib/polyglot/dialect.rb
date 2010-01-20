module Polyglot
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
