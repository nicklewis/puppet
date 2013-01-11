#! /usr/bin/env ruby
require 'spec_helper'

require 'puppet/parser/files'

describe Puppet::Parser::Files do
  include PuppetSpec::Files

  before do
    @basepath = make_absolute("/somepath")
  end

  describe "when searching for templates" do
    it "should return fully-qualified templates directly" do
      Puppet::Parser::Files.expects(:modulepath).never
      Puppet::Parser::Files.find_template(@basepath + "/my/template").should == @basepath + "/my/template"
    end

    it "should return the template from the specified module" do
      env = Puppet::Node::Environment.new
      mod = Puppet::Module.new('mymod', '/etc/puppet/modules/mymod', env)
      env.stubs(:modules).returns [mod]

      mod.expects(:template).returns("/etc/puppet/modules/mymod/templates/mytemplate.erb")
      Puppet::Parser::Files.find_template("mymod/mytemplate.erb").should == "/etc/puppet/modules/mymod/templates/mytemplate.erb"
    end

    it "should return the file in the templatedir if it exists" do
      Puppet[:templatedir] = "/my/templates"
      Puppet[:modulepath] = "/one:/two"
      File.stubs(:directory?).returns(true)
      FileTest.stubs(:exist?).returns(true)
      Puppet::Parser::Files.find_template("mymod/mytemplate").should == File.join(Puppet[:templatedir], "mymod/mytemplate")
    end

    it "should not raise an error if no valid templatedir exists and the template exists in a module" do
      env = Puppet::Node::Environment.new
      mod = Puppet::Module.new('mymod', '/etc/puppet/modules/mymod', env)
      env.stubs(:modules).returns [mod]

      mod.expects(:template).returns("/etc/puppet/modules/mymod/templates/mytemplate")
      Puppet::Parser::Files.stubs(:templatepath).with(nil).returns(nil)

      Puppet::Parser::Files.find_template("mymod/mytemplate").should == "/etc/puppet/modules/mymod/templates/mytemplate"
    end

    it "should return unqualified templates if they exist in the template dir" do
      FileTest.stubs(:exist?).returns true
      Puppet::Parser::Files.stubs(:templatepath).with(nil).returns(["/my/templates"])
      Puppet::Parser::Files.find_template("mytemplate").should == "/my/templates/mytemplate"
    end

    it "should return templates if they actually exist" do
      FileTest.expects(:exist?).with("/my/templates/mytemplate").returns true
      Puppet::Parser::Files.stubs(:templatepath).with(nil).returns(["/my/templates"])
      Puppet::Parser::Files.find_template("mytemplate").should == "/my/templates/mytemplate"
    end

    it "should return nil when asked for a template that doesn't exist" do
      FileTest.expects(:exist?).with("/my/templates/mytemplate").returns false
      Puppet::Parser::Files.stubs(:templatepath).with(nil).returns(["/my/templates"])
      Puppet::Parser::Files.find_template("mytemplate").should be_nil
    end

    it "should search in the template directories before modules" do
      FileTest.stubs(:exist?).returns true
      Puppet::Parser::Files.stubs(:templatepath).with(nil).returns(["/my/templates"])
      Puppet::Module.expects(:find).never
      Puppet::Parser::Files.find_template("mytemplate")
    end

    it "should accept relative templatedirs" do
      FileTest.stubs(:exist?).returns true
      Puppet[:templatedir] = "my/templates"
      # We expand_path to normalize backslashes and slashes on Windows
      File.expects(:directory?).with(File.expand_path(File.join(Dir.getwd,"my/templates"))).returns(true)
      Puppet::Parser::Files.find_template("mytemplate").should == File.expand_path(File.join(Dir.getwd,"my/templates/mytemplate"))
    end

    it "should use the environment templatedir if no module is found and an environment is specified" do
      FileTest.stubs(:exist?).returns true
      Puppet::Parser::Files.stubs(:templatepath).with("myenv").returns(["/myenv/templates"])
      Puppet::Parser::Files.find_template("mymod/mytemplate", "myenv").should == "/myenv/templates/mymod/mytemplate"
    end

    it "should use first dir from environment templatedir if no module is found and an environment is specified" do
      FileTest.stubs(:exist?).returns true
      Puppet::Parser::Files.stubs(:templatepath).with("myenv").returns(["/myenv/templates", "/two/templates"])
      Puppet::Parser::Files.find_template("mymod/mytemplate", "myenv").should == "/myenv/templates/mymod/mytemplate"
    end

    it "should use a valid dir when templatedir is a path for unqualified templates and the first dir contains template" do
      Puppet::Parser::Files.stubs(:templatepath).returns(["/one/templates", "/two/templates"])
      FileTest.expects(:exist?).with("/one/templates/mytemplate").returns(true)
      Puppet::Parser::Files.find_template("mytemplate").should == "/one/templates/mytemplate"
    end

    it "should use a valid dir when templatedir is a path for unqualified templates and only second dir contains template" do
      Puppet::Parser::Files.stubs(:templatepath).returns(["/one/templates", "/two/templates"])
      FileTest.expects(:exist?).with("/one/templates/mytemplate").returns(false)
      FileTest.expects(:exist?).with("/two/templates/mytemplate").returns(true)
      Puppet::Parser::Files.find_template("mytemplate").should == "/two/templates/mytemplate"
    end

    it "should use the node environment if specified" do
      env = Puppet::Node::Environment.new("myenv")
      mod = Puppet::Module.new('mymod', '/etc/puppet/modules/mymod', env)
      env.stubs(:modules).returns [mod]

      mod.expects(:template).returns("/etc/puppet/modules/mymod/templates/envtemplate")

      Puppet::Parser::Files.find_template("mymod/envtemplate", "myenv").should == "/etc/puppet/modules/mymod/templates/envtemplate"
    end

    it "should return nil if no template can be found" do
      Puppet::Parser::Files.find_template("foomod/envtemplate", "myenv").should be_nil
    end
  end

  describe "#split_file_path" do
    it "should return nil module and empty path if the path is empty" do
      Puppet::Parser::Files.split_file_path('').should == [nil, '']
    end

    it "should return nil module and the path if the path is absolute" do
      Puppet::Parser::Files.split_file_path(@basepath).should == [nil, @basepath]
    end

    it "should treat a single segment as a module name with an empty path" do
      Puppet::Parser::Files.split_file_path('apache').should == ['apache', '']
    end

    it "should return the module name and the relative path if the path is relative" do
      Puppet::Parser::Files.split_file_path("mymod/foo/bar/baz.pp").should == ['mymod', 'foo/bar/baz.pp']
    end
  end

  describe "#find_manifests" do
    describe "when no module is found" do
      before do
        Puppet::Module.stubs(:find).returns(nil)
      end

      it "should return the path when the path is fully qualified" do
        file = tmpfile('manifest.pp')
        FileUtils.touch(file)

        Puppet::Parser::Files.find_manifests(file).should == [file]
      end

      it "should return all matching files when the path is fully qualified" do
        dir = tmpdir('manifests')
        file1 = File.join(dir, "manifest.pp")
        file2 = File.join(dir, "manifest.rb")
        FileUtils.touch(file1)
        FileUtils.touch(file2)

        pattern = File.join(dir, "manifest")

        Puppet::Parser::Files.find_manifests(pattern).should == [file1, file2]
      end

      it "should look for files relative to the current directory" do
        # We expand_path to normalize backslashes and slashes on Windows
        cwd = File.expand_path(Dir.getwd)
        path = File.join(cwd, 'foobar/init.pp')

        Dir.expects(:glob).with(path).returns([path])

        Puppet::Parser::Files.find_manifests("foobar/init.pp").should == [path]
      end

      it "should only return files, not directories" do
        parent = tmpdir('manifests')
        pattern = File.join(parent, '*')
        file = File.join(parent, 'file.pp')
        dir = File.join(parent, 'dir.pp')

        FileUtils.touch(file)
        FileUtils.mkdir(dir)

        Puppet::Parser::Files.find_manifests(pattern).should == [file]
      end

      it "should return files once only" do
        pattern = @basepath + "/fully/qualified/pattern/*"
        Dir.expects(:glob).with(pattern+'{.pp,.rb}').returns(%w{one two one})
        Puppet::Parser::Files.find_manifests(pattern).should == %w{one two}
      end
    end

    describe "in an existent module" do
      def a_module_in_environment(env, name)
        mod = Puppet::Module.new(name, "/one/#{name}", env)
        env.stubs(:module).with(name).returns mod
        mod.stubs(:match_manifests).with("init.pp", Dir.getwd).returns(["/one/#{name}/manifests/init.pp"])
        mod
      end

      it "should return the manifests found in the module" do
        mod = a_module_in_environment(Puppet::Node::Environment.new, "mymod")

        Puppet::Parser::Files.find_manifests("mymod/init.pp").should == ["/one/mymod/manifests/init.pp"]
      end

      it "should use the node environment if specified" do
        mod = a_module_in_environment(Puppet::Node::Environment.new("myenv"), "mymod")

        Puppet::Parser::Files.find_manifests("mymod/init.pp", :environment => "myenv").should == ["/one/mymod/manifests/init.pp"]
      end

      it "does not find the module when it is a different environment" do
        mod = a_module_in_environment(Puppet::Node::Environment.new("myenv"), "mymod")

        Puppet::Parser::Files.find_manifests("mymod/init.pp", :environment => "different").should == []
      end
    end
  end
end
