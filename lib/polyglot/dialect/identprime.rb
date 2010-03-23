require 'rubylexer'
module Polyglot
  class Dialect

    class IdentPrime<RedParseDialect
      def initialize
        super(LexerHack)
      end

      module LexerHack
        def disabled_special_identifier? name,oldpos
          result=super
          while nextchar==?'
            result[0].ident<<read( 1 )
          end
          return result
        end

        def identifier_as_string context
          result=super
          result<<@file.scan(/'*/)
          result.gsub! /_prime/, '__prime'
          result.gsub! /'/, '_prime'
          return result
        end
      end

      Polyglot.register(:identprime,self)
    end

  end
end

