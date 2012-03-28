require 'puppet/parser/ast/branch'

class Puppet::Parser::AST
  # An AST object to call a function.
  class Function < AST::Branch

    associates_doc

    attr_accessor :name, :arguments

    @settor = true

    def evaluate(scope)
      if @name.include?('.')
        receivers, method = @name.split('.', 2)
        receiver = receivers.split('::').inject(Kernel) do |parent,const|
          next parent if const.empty?
          parent.const_get(const)
        end
      else
        method = "function_#{@name}"

        # Make sure it's a defined function
        raise Puppet::ParseError, "Unknown function #{@name}" unless Puppet::Parser::Functions.function(@name)

        # Now check that it's been used correctly
        case @ftype
        when :rvalue
          raise Puppet::ParseError, "Function '#{@name}' does not return a value" unless Puppet::Parser::Functions.rvalue?(@name)
        when :statement
          if Puppet::Parser::Functions.rvalue?(@name)
            raise Puppet::ParseError,
              "Function '#{@name}' must be the value of a statement"
          end
        else
          raise Puppet::DevError, "Invalid function type #{@ftype.inspect}"
        end
      end

      # We don't need to evaluate the name, because it's plaintext
      args = @arguments.safeevaluate(scope).map { |x| x == :undef ? '' : x }

      if receiver
        receiver.send(method, *args)
      else
        scope.send(method, args)
      end
    end

    def initialize(hash)
      @ftype = hash[:ftype] || :rvalue
      hash.delete(:ftype) if hash.include? :ftype

      super(hash)

      # Lastly, check the parity
    end

    def to_s
      args = arguments.is_a?(ASTArray) ? arguments.to_s.gsub(/\[(.*)\]/,'\1') : arguments
      "#{name}(#{args})"
    end
  end
end
