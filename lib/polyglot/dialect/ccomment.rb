require 'rubylexer'
module Polyglot
  class Dialect

    class CComment<RedParseDialect
      def initialize
        super(LexerHack)
      end

      module LexerHack
        def regex_or_div ch
          if read(2)=='/*'
            start=input_position-2
            contents=scan_until('*/')
            @linenum+=contents.count("\n")
            RubyLexer::IgnoreToken.new(contents,start)
          else
            move -2
            super
          end
        end
      end

      Polyglot.register(:ccomment,self)
    end

  end
end

