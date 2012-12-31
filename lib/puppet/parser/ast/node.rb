require 'puppet/parser/ast/top_level_construct'

class Puppet::Parser::AST::Node < Puppet::Parser::AST::TopLevelConstruct
  attr_accessor :names, :context

  def initialize(names, context = {})
    raise ArgumentError, "names should be an array" unless names.is_a? Array
    @names = names
    @context = context
  end

  def instantiate(mod)
    @names.collect do |name|
      Puppet::Resource::Type.new(:node, name, @context.merge(:module_name => mod.name))
    end
  end
end
