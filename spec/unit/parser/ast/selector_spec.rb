#!/usr/bin/env rspec
require 'spec_helper'

describe Puppet::Parser::AST::Selector do
  let(:scope) { Puppet::Parser::Scope.new }
  let(:opt1)  { Puppet::Parser::AST::ResourceParam.new :param => ast_name('abc'), :value => ast_name('foo') }
  let(:opt2)  { Puppet::Parser::AST::ResourceParam.new :param => ast_name('def'), :value => ast_name('bar') }
  let(:default) do
    Puppet::Parser::AST::ResourceParam.new(
      :param => Puppet::Parser::AST::Default.new(:value => 'default'),
      :value => ast_name('the_default')
    )
  end
  let(:values) { Puppet::Parser::AST::ASTArray.new :children => [opt1, opt2, default] }

  def ast_name(value)
    Puppet::Parser::AST::Name.new :value => value
  end

  def selector_for(param)
    Puppet::Parser::AST::Selector.new :param => ast_name(param), :values => values
  end

  describe "when evaluating" do
    describe "when scanning values" do
      it "should return the first matching evaluated option" do
        selector_for('def').evaluate(scope).should == 'bar'
      end

      it "should return the default evaluated option if none matched" do
        selector_for('nothing').evaluate(scope).should == 'the_default'
      end

      it "should unset scope ephemeral variables after option evaluation" do
        scope.stubs(:ephemeral_level).returns(:level)
        scope.expects(:unset_ephemeral_var).with(:level)

        selector_for('nothing').evaluate(scope)
      end

      it "should not leak ephemeral variables even if evaluation fails" do
        scope.stubs(:ephemeral_level).returns(:level)
        scope.expects(:unset_ephemeral_var).with(:level)

        opt1.param.stubs(:evaluate).raises

        expect { selector_for('nothing').evaluate(scope) }.to raise_error
      end

      it "should fail if there is no default" do
        values.children.pop

        expect { selector_for('nothing').evaluate(scope) }.to raise_error(Puppet::ParseError, /No matching value/)
      end
    end
  end

  describe "#to_s" do
    it "should produce a string version of this selector" do
      values = Puppet::Parser::AST::ASTArray.new :children => [ Puppet::Parser::AST::ResourceParam.new(:param => "type", :value => "value", :add => false) ]
      param = Puppet::Parser::AST::Variable.new :value => "myvar"
      selector = Puppet::Parser::AST::Selector.new :param => param, :values => values
      selector.to_s.should == "$myvar ? { type => value }"
    end
  end
end
