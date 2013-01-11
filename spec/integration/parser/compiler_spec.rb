#! /usr/bin/env ruby
require 'spec_helper'

require 'puppet_spec/modules'

describe Puppet::Parser::Compiler do
  before :each do
    @node = Puppet::Node.new "testnode"

    @scope_resource = stub 'scope_resource', :builtin? => true, :finish => nil, :ref => 'Class[main]'
    @scope = stub 'scope', :resource => @scope_resource, :source => mock("source")
  end

  after do
    Puppet.settings.clear
  end

  it "should be able to determine the configuration version from a local version control repository" do
    pending("Bug #14071 about semantics of Puppet::Util::Execute on Windows", :if => Puppet.features.microsoft_windows?) do
      # This should always work, because we should always be
      # in the puppet repo when we run this.
      version = %x{git rev-parse HEAD}.chomp

      Puppet.settings[:config_version] = 'git rev-parse HEAD'

      @parser = Puppet::Parser::Parser.new "development"
      @compiler = Puppet::Parser::Compiler.new(@node)

      @compiler.catalog.version.should == version
    end
  end

  it "should not create duplicate resources when a class is referenced both directly and indirectly by the node classifier (4792)" do
    Puppet[:code] = <<-PP
      class foo
      {
        notify { foo_notify: }
        include bar
      }
      class bar
      {
        notify { bar_notify: }
      }
    PP

    @node.stubs(:classes).returns(['foo', 'bar'])

    catalog = Puppet::Parser::Compiler.compile(@node)

    catalog.resource("Notify[foo_notify]").should_not be_nil
    catalog.resource("Notify[bar_notify]").should_not be_nil
  end

  describe "when resolving class references" do
    it "should favor local scope, even if there's an included class in topscope" do
      Puppet[:code] = <<-PP
        class experiment {
          class baz {
          }
          notify {"x" : require => Class[Baz] }
        }
        class baz {
        }
        include baz
        include experiment
        include experiment::baz
      PP

      catalog = Puppet::Parser::Compiler.compile(Puppet::Node.new("mynode"))

      notify_resource = catalog.resource( "Notify[x]" )

      notify_resource[:require].title.should == "Experiment::Baz"
    end

    it "should favor local scope, even if there's an unincluded class in topscope" do
      Puppet[:code] = <<-PP
        class experiment {
          class baz {
          }
          notify {"x" : require => Class[Baz] }
        }
        class baz {
        }
        include experiment
        include experiment::baz
      PP

      catalog = Puppet::Parser::Compiler.compile(Puppet::Node.new("mynode"))

      notify_resource = catalog.resource( "Notify[x]" )

      notify_resource[:require].title.should == "Experiment::Baz"
    end
  end
  describe "(ticket #13349) when explicitly specifying top scope" do
    ["class {'::bar::baz':}", "include ::bar::baz"].each do |include|
      describe "with #{include}" do
        it "should find the top level class" do
          Puppet[:code] = <<-MANIFEST
            class { 'foo::test': }
            class foo::test {
            	#{include}
            }
            class bar::baz {
            	notify { 'good!': }
            }
            class foo::bar::baz {
            	notify { 'bad!': }
            }
          MANIFEST

          catalog = Puppet::Parser::Compiler.compile(Puppet::Node.new("mynode"))

          catalog.resource("Class[Bar::Baz]").should_not be_nil
          catalog.resource("Notify[good!]").should_not be_nil
          catalog.resource("Class[Foo::Bar::Baz]").should be_nil
          catalog.resource("Notify[bad!]").should be_nil
        end
      end
    end
  end

  it "should recompute the version after input files are re-parsed" do
    Puppet[:code] = 'class foo { }'
    Time.stubs(:now).returns(1)
    node = Puppet::Node.new('mynode')
    Puppet::Parser::Compiler.compile(node).version.should == 1
    Time.stubs(:now).returns(2)
    Puppet::Parser::Compiler.compile(node).version.should == 1 # no change because files didn't change
    Puppet::Resource::TypeCollection.any_instance.stubs(:stale?).returns(true).then.returns(false) # pretend change
    Puppet::Parser::Compiler.compile(node).version.should == 2
  end

  ['class', 'define', 'node'].each do |thing|
    it "should not allow #{thing} inside evaluated conditional constructs" do
      Puppet[:code] = <<-PP
        if true {
          #{thing} foo {
          }
          notify { decoy: }
        }
      PP

      begin
        Puppet::Parser::Compiler.compile(Puppet::Node.new("mynode"))
        raise "compilation should have raised Puppet::Error"
      rescue Puppet::Error => e
        e.message.should =~ /at line 2/
      end
    end
  end

  it "should not allow classes inside unevaluated conditional constructs" do
    Puppet[:code] = <<-PP
      if false {
        class foo {
        }
      }
    PP

    lambda { Puppet::Parser::Compiler.compile(Puppet::Node.new("mynode")) }.should raise_error(Puppet::Error)
  end

  describe "when defining relationships" do
    def extract_name(ref)
      ref.sub(/File\[(\w+)\]/, '\1')
    end

    let(:node) { Puppet::Node.new('mynode') }
    let(:code) do
      <<-MANIFEST
        file { [a,b,c]:
          mode => 0644,
        }
        file { [d,e]:
          mode => 0755,
        }
      MANIFEST
    end
    let(:expected_relationships) { [] }
    let(:expected_subscriptions) { [] }

    before :each do
      Puppet[:code] = code
    end

    after :each do
      catalog = described_class.compile(node)

      resources = catalog.resources.select { |res| res.type == 'File' }

      actual_relationships, actual_subscriptions = [:before, :notify].map do |relation|
        resources.map do |res|
          dependents = Array(res[relation])
          dependents.map { |ref| [res.title, extract_name(ref)] }
        end.inject(&:concat)
      end

      actual_relationships.should =~ expected_relationships
      actual_subscriptions.should =~ expected_subscriptions
    end

    it "should create a relationship" do
      code << "File[a] -> File[b]"

      expected_relationships << ['a','b']
    end

    it "should create a subscription" do
      code << "File[a] ~> File[b]"

      expected_subscriptions << ['a', 'b']
    end

    it "should create relationships using title arrays" do
      code << "File[a,b] -> File[c,d]"

      expected_relationships.concat [
        ['a', 'c'],
        ['b', 'c'],
        ['a', 'd'],
        ['b', 'd'],
      ]
    end

    it "should create relationships using collection expressions" do
      code << "File <| mode == 0644 |> -> File <| mode == 0755 |>"

      expected_relationships.concat [
        ['a', 'd'],
        ['b', 'd'],
        ['c', 'd'],
        ['a', 'e'],
        ['b', 'e'],
        ['c', 'e'],
      ]
    end

    it "should create relationships using resource names" do
      code << "'File[a]' -> 'File[b]'"

      expected_relationships << ['a', 'b']
    end

    it "should create relationships using variables" do
      code << <<-MANIFEST
        $var = File[a]
        $var -> File[b]
      MANIFEST

      expected_relationships << ['a', 'b']
    end

    it "should create relationships using case statements" do
      code << <<-MANIFEST
        $var = 10
        case $var {
          10: {
            file { s1: }
          }
          12: {
            file { s2: }
          }
        }
        ->
        case $var + 2 {
          10: {
            file { t1: }
          }
          12: {
            file { t2: }
          }
        }
      MANIFEST

      expected_relationships << ['s1', 't2']
    end

    it "should create relationships using array members" do
      code << <<-MANIFEST
        $var = [ [ [ File[a], File[b] ] ] ]
        $var[0][0][0] -> $var[0][0][1]
      MANIFEST

      expected_relationships << ['a', 'b']
    end

    it "should create relationships using hash members" do
      code << <<-MANIFEST
        $var = {'foo' => {'bar' => {'source' => File[a], 'target' => File[b]}}}
        $var[foo][bar][source] -> $var[foo][bar][target]
      MANIFEST

      expected_relationships << ['a', 'b']
    end

    it "should create relationships using resource declarations" do
      code << "file { l: } -> file { r: }"

      expected_relationships << ['l', 'r']
    end

    it "should chain relationships" do
      code << "File[a] -> File[b] ~> File[c] <- File[d] <~ File[e]"

      expected_relationships << ['a', 'b'] << ['d', 'c']
      expected_subscriptions << ['b', 'c'] << ['e', 'd']
    end
  end

  describe "when working with modules" do
    include PuppetSpec::Files

    let(:catalog) { Puppet::Parser::Compiler.compile(@node) }

    before :each do
      moduledir = tmpdir('modules')
      Puppet[:modulepath] = moduledir

      @foo = PuppetSpec::Modules.create("foo", moduledir, :metadata => {:author => "somebody", :version => "1.2.3"})
      @bar = PuppetSpec::Modules.create("bar", moduledir, :metadata => {:author => "nobody", :version => "4.5.6"})

      Dir.mkdir(@foo.manifests)
      Dir.mkdir(@bar.manifests)
    end

    it "uses the module where a class is defined, not declared" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "class foo { }" }
      File.open(File.join(@bar.manifests, 'init.pp'), 'w') { |f| f.puts "class bar { class { foo: } }" }

      Puppet[:code] = "class { bar: }"

      catalog = Puppet::Parser::Compiler.compile(@node)

      catalog.resource('Class[foo]').module.should == @foo
      catalog.resource('Class[bar]').module.should == @bar
    end

    it "uses the module where a class is defined, not included" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "class foo { }" }
      File.open(File.join(@bar.manifests, 'init.pp'), 'w') { |f| f.puts "class bar { include foo }" }

      Puppet[:code] = "include bar"

      catalog = Puppet::Parser::Compiler.compile(@node)

      catalog.resource('Class[foo]').module.should == @foo
      catalog.resource('Class[bar]').module.should == @bar
    end

    it "uses the module where a class is defined, even if it's imported with an absolute path" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "class foo { }" }
      File.open(File.join(@bar.manifests, 'init.pp'), 'w') do |f|
        f.puts <<-MANIFEST
          import '#{@foo.manifest('init.pp')}'
          class bar { class { foo: } }
        MANIFEST
      end

      Puppet[:code] = "class { bar: }"

      catalog = Puppet::Parser::Compiler.compile(@node)

      catalog.resource('Class[foo]').module.should == @foo
      catalog.resource('Class[bar]').module.should == @bar
    end

    it "uses the module where a resource is declared" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "class foo { notify { heyo: } }" }
      File.open(File.join(@bar.manifests, 'init.pp'), 'w') { |f| f.puts "class bar { class { foo: } }" }

      Puppet[:code] = "class { bar: }"

      catalog = Puppet::Parser::Compiler.compile(@node)

      catalog.resource('Notify[heyo]').module.should == @foo
    end

    it "uses the module where an instance of a define is declared, not where the define is defined" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "define foo { }" }
      File.open(File.join(@bar.manifests, 'init.pp'), 'w') { |f| f.puts "class bar { foo { something: } }" }

      Puppet[:code] = "class { bar: }"

      catalog = Puppet::Parser::Compiler.compile(@node)

      catalog.resource('Foo[something]').module.should == @bar
    end

    it "uses the module where the resource was declared, not where the define was declared, for resources in defines" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "define foo { notify { heyo: } }" }
      File.open(File.join(@bar.manifests, 'init.pp'), 'w') { |f| f.puts "class bar { foo { something: } }" }

      Puppet[:code] = "class { bar: }"

      catalog.resource('Notify[heyo]').module.should == @foo
    end

    it "handles nested defines properly" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "define foo { foo::nested { $name: } }" }
      File.open(File.join(@foo.manifests, 'nested.pp'), 'w') { |f| f.puts "define foo::nested { notify { heyo: } }" }
      File.open(File.join(@bar.manifests, 'init.pp'), 'w') { |f| f.puts "class bar { foo { something: } }" }

      Puppet[:code] = "class { bar: }"

      catalog.resource('Foo[something]').module.should == @bar
      catalog.resource('Foo::Nested[something]').module.should == @foo
      catalog.resource('Notify[heyo]').module.should == @foo
    end

    it "handles classes inside defines properly" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "define foo { class { foo::nested: } }" }
      File.open(File.join(@foo.manifests, 'nested.pp'), 'w') { |f| f.puts "class foo::nested { notify { heyo: } }" }
      File.open(File.join(@bar.manifests, 'init.pp'), 'w') { |f| f.puts "class bar { foo { something: } }" }

      Puppet[:code] = "class { bar: }"

      catalog.resource('Foo[something]').module.should == @bar
      catalog.resource('Class[Foo::Nested]').module.should == @foo
      catalog.resource('Notify[heyo]').module.should == @foo
    end

    it "uses the module where the class was defined for classes included by an ENC" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "class foo { }" }
      File.open(File.join(@bar.manifests, 'init.pp'), 'w') { |f| f.puts "class bar { }" }

      @node.classes = ["foo", "bar"]

      catalog = Puppet::Parser::Compiler.compile(@node)

      catalog.resource('Class[foo]').module.should == @foo
      catalog.resource('Class[bar]').module.should == @bar
    end

    it "uses the NullModule for resources outside modules" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "class foo { }" }

      Puppet[:code] = <<-MANIFEST
        class { foo: }
        notify { hi: }
      MANIFEST

      catalog.resource('Class[foo]').module.should == @foo
      catalog.resource('Notify[hi]').module.should == Puppet::Module::NullModule.instance
    end

    it "uses the NullModule for node definitions outside modules" do
      Puppet[:code] = "node default { }"

      catalog.resource('Node[default]').module.should == Puppet::Module::NullModule.instance
    end

    it "uses the module where a node was defined" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "node default { }" }

      Puppet[:code] = "import '#{@foo.manifest('init.pp')}'"

      catalog.resource('Node[default]').module.should == @foo
    end

    it "uses the module where a node was defined even if it was defined tangentially" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') do |f|
        f.puts <<-MANIFEST
          class foo { }
          node default { }
        MANIFEST
      end

      Puppet[:code] = "include foo"

      catalog.resource('Node[default]').module.should == @foo
    end

    it "uses the module where a resource was declared if it was declared inside a node" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "node default { notify { hi: } }" }

      Puppet[:code] = "import '#{@foo.manifest('init.pp')}'"

      catalog.resource('Notify[hi]').module.should == @foo
    end

    it "uses the NullModule if a resource is declared in a node outside a module" do
      Puppet[:code] = "node default { notify { hi: } }"

      catalog.resource('Notify[hi]').module.should == Puppet::Module::NullModule.instance
    end

    it "uses the right modules when importing a glob that spans multiple modules" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "class foo { }" }
      File.open(File.join(@bar.manifests, 'init.pp'), 'w') { |f| f.puts "class bar { }" }

      Puppet[:code] = <<-MANIFEST
        import '#{File.join(File.dirname(@foo.path), '*', 'manifests', 'init.pp')}'
        class { foo: }
        class { bar: }
      MANIFEST

      catalog.resource('Class[foo]').module.should == @foo
      catalog.resource('Class[bar]').module.should == @bar
    end

    it "uses the right module when importing using a relative path inside a module" do
      File.open(File.join(@foo.manifests, 'init.pp'), 'w') { |f| f.puts "class foo { }" }

      Puppet[:code] = <<-MANIFEST
        import '#{Pathname.new(@foo.manifest('init.pp')).relative_path_from(Pathname.new(Dir.getwd))}'
        class { foo: }
      MANIFEST

      catalog.resource('Class[foo]').module.should == @foo
    end
  end
end
