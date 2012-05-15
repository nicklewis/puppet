require 'puppet/parser/ast'
require 'puppet/parser/ast/branch'

class Puppet::Parser::AST::ParameterLookup < Puppet::Parser::AST::Branch
  attr_accessor :resource, :parameter

  def evaluate(scope)
    real_resources = [resource.evaluate(scope)].flatten

    real_resources = real_resources.map {|r| r.is_a?(Puppet::Parser::Collector) ? r.evaluate : r}.flatten.reject {|r| r == false}

    invalid_resources = real_resources.select {|r| !r.is_a? Puppet::Resource}
    if invalid_resources.any?
      raise Puppet::ParseError, "Parameter lookup must be on a Puppet::Resource, not #{invalid_resources.first.class}"
    end

    values = real_resources.map do |res|
      scope.findresource(res.ref)[parameter.to_sym]
    end

    values.length == 1 ? values.first : values
  end

  def to_s
    "#{resource.to_s}.#{parameter}"
  end
end
