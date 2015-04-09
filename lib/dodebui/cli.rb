require 'dodebui/version'
require 'dodebui/distribution'
require 'logger'
require 'docker'

module Dodebui
  ## commandline interface for dodebui
  class Cli
    attr_accessor :source_templates, :build_distributions, :apt_proxy
    attr_reader :wd

    def self.logger
      @logger ||= Logger.new(STDOUT)
    end

    def initialize
      @dodebuifiles ||= ['Dodebuifile']
      @original_dir = Dir.getwd
      @distributions_sem = Mutex.new
    end

    def dodebuifile?
      @dodebuifiles.each do |fn|
        return fn if File.exist?(fn)
      end
      nil
    end

    def find_dodebuifile_location # :nodoc:
      here = Dir.pwd
      until (fn = dodebuifile?)
        Dir.chdir('..')
        return nil if Dir.pwd == here
        here = Dir.pwd
      end
      [fn, here]
    ensure
      Dir.chdir(@original_dir)
    end

    def load_dodebiufile
      dodebuifile, location = find_dodebuifile_location
      fail 'No Dodebuifile found' if dodebuifile.nil?
      @dodebuifile = File.join(location, dodebuifile)
      @wd = location
      Cli.logger.info("Working directory #{@wd}")
      Cli.logger.info("Config file #{@dodebuifile}")
      load_dodebiufile_raw @dodebuifile
    end

    def load_dodebiufile_raw(path)
      File.open(path, 'r') do |infile|
        code = infile.read
        eval(code) # rubocop:disable Lint/Eval
      end
    end

    def check_outcome
      return if @distributions.length == build_distributions.length
      logger.error(
        "Only built #{@distributions.length} out of " \
        "#{build_distributions.length}"
      )
      exit 1
    end

    def run
      Cli.logger.info("Initializing dodebui #{VERSION}")

      load_dodebiufile

      test_docker

      prepare_distributions build_distributions

      prepare_sources

      build

      check_outcome
    end

    def test_docker
      Docker.options[:read_timeout] = 3600
      data = Docker.version
      Cli.logger.info(
        "Connecting to Docker server successful (version #{data['Version']})"
      )
    end

    def logger
      Cli.logger
    end

    def prepare_distributions(distributions = [])
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
          begin
            dist.ensure_image_updated
          rescue => e
            logger.warn(
              "Failed ensuring a updated image '#{dist.image_name}': #{e}"
            )
            @distributions_sem.synchronize do
              @distributions -= [dist]
            end
          end
        end
      end
      # wait for all threads
      threads.each(&:join)
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
          begin
            dist.build.build
          rescue => e
            logger.warn("Failed building on image '#{dist.image_name}': #{e}")
            @distributions_sem.synchronize do
              @distributions -= [dist]
            end
          end
        end
      end
      # wait for all threads
      threads.each(&:join)
    end
  end
end
