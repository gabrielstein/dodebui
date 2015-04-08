require 'dodebui/version'
require 'dodebui/distribution'
require 'logger'
require 'docker'

module Dodebui
  class Cli
    attr_accessor :source_templates, :build_distributions
    attr_reader :wd

    def self.logger
      @@logger ||= Logger.new(STDOUT)
    end

    def initialize
      @dodebuifiles ||= [ 'Dodebuifile' ]
      @original_dir = Dir.getwd
    end

    def have_dodebuifile
      @dodebuifiles.each do |fn|
        if File.exist?(fn)
          return fn
        end
      end
      return nil
    end

    def find_dodebuifile_location # :nodoc:
      here = Dir.pwd
      until (fn = have_dodebuifile)
        Dir.chdir("..")
        return nil if Dir.pwd == here
        here = Dir.pwd
      end
      [fn, here]
    ensure
      Dir.chdir(@original_dir)
    end


    def load_dodebiufile
      dodebuifile, location = find_dodebuifile_location
      if dodebuifile.nil?
        fail "No Dodebuifile found"
      end
      @dodebuifile = File.join(location, dodebuifile)
      @wd = location
      Cli.logger.info("Working directory #{@wd}")
      Cli.logger.info("Config file #{@dodebuifile}")
      load_dodebiufile_raw @dodebuifile
    end

    def load_dodebiufile_raw(path)
      File.open(path, 'r') do |infile|
        code = infile.read
        eval(code)
      end
    end

    def run
      Cli.logger.info("Initializing dodebui #{VERSION}")

      load_dodebiufile

      test_docker

      prepare_distributions build_distributions

      prepare_sources

      build
    end
    def test_docker
      Docker.options[:read_timeout] = 3600
      data = Docker.version
      Cli.logger.info("Connecting to Docker server successful (version #{data['Version']})")

    end

    def logger
      Cli.logger
    end

    def prepare_distributions(distributions=[])
      if distributions == []
        DISTRIBUTIONS.each do |os, value|
          value.each do |codename|
            distributions += ["#{os}:#{codename}"]
          end
        end
      end
      @distributions = distributions.map do |name|
        Distribution.new(name, self)
      end
      ensure_images_updated
    end

    def ensure_images_updated
      # ensure images are up to date
      threads = []
      @distributions.each do |dist|
        threads << Thread.new do
          dist.ensure_image_updated
        end
      end

      # wait for all threads
      threads.each { |thr| thr.join }
    end

    def prepare_sources
      @distributions.each do |dist|
        dist.build.source
      end
    end
    
    def build
      threads = []
      @distributions.each do |dist|
        threads << Thread.new do
          dist.build.build
        end
      end
      # wait for all threads
      threads.each { |thr| thr.join }
    end
  end
end
