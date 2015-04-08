require 'date'
require 'docker'
require 'dodebui/build'
# docker debian build
module Dodebui
  MAX_IMAGE_AGE = 86_400

  DISTRIBUTIONS = {
    debian: [
      :squeeze,
      :wheezy,
      :jessie
    ],
    ubuntu: [
      :precise,
      :quantal,
      :raring,
      :saucy,
      :trusty
    ]
  }

  # handle distribution releases
  class Distribution
    attr_reader :os, :codename, :cli
    def initialize(name, cli)
      @cli = cli
      # convert string
      if name.is_a? String
        split = name.split(':')
        os = split[0].to_sym
        codename = split[1].to_sym
      end

      if (!DISTRIBUTIONS.key? os) || (!DISTRIBUTIONS[os].include? codename)
        fail "Operating system #{os} with codename #{codename} not found"
      end
      @os = os
      @codename = codename
    end

    def logger
      @cli.logger
    end

    def codename_str
      format('%02d', codename_int)
    end

    def codename_int
      DISTRIBUTIONS[os].index(codename) + 1
    end

    def image_age(i)
      age = DateTime.now - DateTime.parse(i.info['Created'])
      (age * 24 * 60 * 60).to_i
    end

    def ensure_image_updated
      # Test if image_name exists
      @image = Docker::Image.get(image_name)
      if image_age(@image) > MAX_IMAGE_AGE
        logger.info "Image #{image_name} is outdated renew it"
        @image = create_image
      end
    rescue Docker::Error::NotFoundError
      @image = create_image
    end

    def pbuilder_files
      [
        'pbuilder-satisfydepends-aptitude',
        'pbuilder-satisfydepends-checkparams',
        'pbuilder-satisfydepends-funcs'
      ]
    end

    def share_path
      File.expand_path(
        File.join(
          File.expand_path(
            File.dirname(__FILE__)
          ),
          '../../share'
        )
      )
    end

    def pbuilder_dir
      '/usr/lib/pbuilder'
    end

    def create_image_dockerfile_contents
      dockerfile = (
        "FROM #{base_image_name}\n" \
        "ENV DEBIAN_FRONTEND=noninteractive\n" \
        "RUN apt-get update && \\ \n" \
        "    apt-get -y dist-upgrade && \\ \n" \
        "    apt-get -y install wget curl build-essential aptitude \n" \
        "RUN mkdir -p #{pbuilder_dir}\n"
      )

      # add pbuilder dep resolver
      pbuilder_files.each do |file|
        dockerfile += "ADD #{file} #{pbuilder_dir}/#{file}\n"
      end

      # make dep resolver executable
      dockerfile += 'RUN chmod +x '
      dockerfile += "#{pbuilder_dir}/pbuilder-satisfydepends-aptitude\n"
      dockerfile
    end

    def create_image_copy_dep_resolver(dir)
      pbuilder_files.each do |file|
        src = File.join(share_path, 'pbuilder', file)
        dest = File.join(dir, file)
        logger.debug("Copy file from #{src} to #{dest}")
        FileUtils.cp src, dest
      end
    end

    def create_image_build(dir)
      image = Docker::Image.build_from_dir(
        dir,
        nocache: true
      )

      logger.info(
        "Finished building a new image #{image_name} from #{base_image_name}"
      )
      image.tag(
        repo: repo_name,
        tag: @codename.to_s,
        force: true
      )
    end

    def create_image
      logger.info("Start building a new image from #{base_image_name}")

      # build docker build directory
      Dir.mktmpdir do |dir|
        # Write docker file
        dockerfile_path = File.join(dir, 'Dockerfile')
        File.open(dockerfile_path, 'w') do |file|
          file.write(create_image_dockerfile_contents)
        end

        create_image_copy_dep_resolver(dir)

        # build image
        create_image_build(dir)
      end
    end

    def build
      @build ||= Build.new self
    end

    def repo_name
      "dodebui_#{@os}"
    end

    def base_image_name
      "#{@os}:#{@codename}"
    end

    def image_name
      "#{repo_name}:#{@codename}"
    end
  end
end
