#! /usr/bin/env ruby

require 'spec_helper'
require 'puppet/module/null_module'

describe Puppet::Module::NullModule do
  include PuppetSpec::Files

  subject { described_class.instance }

  # These are kind of hard to test, because there isn't really a file for it to
  # ignore or anything. Better than nothing?
  it "shouldn't have manifests" do
    subject.manifest('init.pp').should be_nil
  end

  it "shouldn't have templates" do
    subject.template('template.erb').should be_nil
  end

  it "shouldn't have plugins" do
    subject.plugin('puppet/type/my_type.rb').should be_nil
  end

  it "shouldn't have files" do
    subject.file('bashrc').should be_nil
  end

  describe "#match_manifests" do
    let(:cwd) { tmpdir('manifests') }
    let(:file1) { File.join(cwd, 'foo.pp') }
    let(:file2) { File.join(cwd, 'foo.rb') }

    it "should look for files relative to the specified cwd" do
      FileUtils.touch(file1)
      FileUtils.touch(file2)

      subject.match_manifests('foo.pp', cwd).should == [file1]

      subject.match_manifests('foo.pp', 'another_directory').should be_empty
    end

    it "should look for .pp and .rb files if no extension is given" do
      FileUtils.touch(file1)
      FileUtils.touch(file2)

      subject.match_manifests('foo', cwd).should == [file1, file2]
    end

    it "should return filenames only once" do
      FileUtils.touch(file1)

      subject.match_manifests('foo.{pp,pp}', cwd).should == [file1]
    end

    it "should ignore directories" do
      FileUtils.mkdir(file1)
      FileUtils.touch(file2)

      subject.match_manifests('foo', cwd).should == [file2]
    end

    it "should find files specified with absolute paths" do
      FileUtils.touch(file1)
      FileUtils.touch(file2)

      subject.match_manifests(File.join(cwd, 'foo'), 'not_a_real_directory').should == [file1, file2]
    end
  end
end

