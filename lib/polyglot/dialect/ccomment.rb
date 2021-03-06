require 'rubylexer'
module Polyglot
  class Dialect

    class CComment<RedParseDialect
      def initialize
        super(LexerHack)
      end

      module LexerHack
        def regex_or_div ch
          start=input_position
          if contents=@file.scan %r{/\* (?: [^\*] | \*[^/] )* \*/}mx
            @linenum+=contents.count("\n")
            RubyLexer::IgnoreToken.new(contents,start)
          else
            @file.move -2
            super
          end
        end
      end

      Polyglot.register(:ccomment,self)
    end

  end
end

