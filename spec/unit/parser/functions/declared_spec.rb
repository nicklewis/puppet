#!/usr/bin/env rspec
require 'spec_helper'

describe "the 'declared' function" do
  before :all do
    Puppet::Parser::Functions.autoloader.loadall
  end

  before :each do
    Puppet::Node::Environment.stubs(:current).returns(nil)
    @compiler = Puppet::Parser::Compiler.new(Puppet::Node.new("foo"))
    @scope = Puppet::Parser::Scope.new(:compiler => @compiler)
  end

  it "should exist" do
    Puppet::Parser::Functions.function("declared").should == "function_declared"
  end

  it "should be false when a resource reference is provided and the resource is in the catalog" do
    resource = Puppet::Resource.new("file", "/my/file")
    @scope.function_declared(resource).should be_false
  end

  it "should be true when a resource reference is provided and the resource is in the catalog" do
    resource = Puppet::Resource.new("file", "/my/file")
    @compiler.add_resource(@scope, resource)
    @scope.function_declared(resource).should be_true
  end
end
