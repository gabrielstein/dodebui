require 'dodebui/template_namespace'
require 'open3'
require 'erb'

module Dodebui
  # Handles the build process of a package
  class Build
    attr_reader :distribution

    def initialize(distribution)
      @distribution = distribution
      @cli = distribution.cli
    end

    def local_expect(desc, *args)
      Open3.popen3(*args) do |_i, o, e, t|
        if args[0].is_a? Hash
          cmd = args[1]
        else
          cmd = args[0]
        end
        ret_val = t.value.exitstatus
        if ret_val == 0
          logger.debug("#{desc} (cmd=#{cmd}): succeed")
        else
          output = "Exec failed cmd=#{cmd} ret_val=#{ret_val}"
          output += "stdout=#{o.read} stderr=#{e.read}"
          fail output
        end
      end
    end

    def write_log(name, o, e)
      o_path = File.join(build_dir, "#{name}.stdout.log")
      e_path = File.join(build_dir, "#{name}.stderr.log")
      File.open(o_path, 'w') { |file| file.write(o.join '') }
      File.open(e_path, 'w') { |file| file.write(e.join '') }
    end

    def build_container_create_start
      logger.info("Creating container #{@distribution.codename}")
      @container = Docker::Container.create(
        'Image' => @distribution.image_name,
        'Cmd' => %w(sleep 3600),
        'WorkingDir' => '/_build/source'
      )
      logger.info("Starting container #{@distribution.codename}")
      @container.start('Binds' => [
        "#{build_dir}:/_build"
      ])
    end

    def build_dependencies
      logger.info("Installing dependencies #{@distribution.codename}")
      stdout, stderr, ret_val = @container.exec([
        '/usr/lib/pbuilder/pbuilder-satisfydepends-aptitude'
      ])
      write_log('apt_install_deps', stdout, stderr)
      if ret_val != 0
        logger.warn("Failed installing dependencies #{@distribution.codename}")
        fail
      end
      logger.info("Finished installing dependencies #{@distribution.codename}")
    end

    def build_package
      logger.info("Building package #{@distribution.codename}")
      stdout, stderr, ret_val = @container.exec([
        'dpkg-buildpackage'
      ])
      write_log('build', stdout, stderr)
      if ret_val != 0
        logger.warn("Failed building package #{@distribution.codename}")
        fail
      end
      logger.info("Finished building package #{@distribution.codename}")
    end

    def build_apt_proxy
      return if @cli.apt_proxy.nil?
      logger.info("Setting apt_proxy #{@distribution.codename}")
      stdout, stderr, ret_val = @container.exec([
        'bash',
        '-c',
        @distribution.apt_proxy
      ])
      write_log('apt_proxy', stdout, stderr)
      logger.warn(
        "Failed setting apt proxy #{@distribution.codename}"
      ) if ret_val != 0
    end

    def build
      build_container_create_start

      build_apt_proxy

      build_dependencies

      build_package

      @container.stop

      true
    rescue RuntimeError
      false
    end

    def cache_dir
      File.expand_path(
        File.join(
          '/var/lib/dodebui',
          "#{distribution.os}_#{distribution.codename}"
        )
      )
    end

    def build_dir
      File.expand_path(
        File.join(
          @cli.wd,
          '..',
          '_build',
          "#{distribution.os}_#{distribution.codename}"
        )
      )
    end

    def source
      source_copy
      source_changelog
      source_templates
    end

    def logger
      @cli.logger
    end

    def source_dir
      File.join(build_dir, 'source')
    end

    def source_template_namespace
      TemplateNamespace.new(
        os: @distribution.os,
        codename: @distribution.codename,
        codename_int: @distribution.codename_int
      )
    end

    def source_template_eval(path)
      logger.debug "Evaluate template #{path}"
      erb = ERB.new(
        File.read(path),
        nil,
        '-'
      )
      erb.result(source_template_namespace.priv_binding)
    end

    def source_templates
      @cli.source_templates.each do |template|
        src = File.join(source_dir, template)
        dest = src[0...-4]
        File.open(dest, 'w') do |file|
          file.write(source_template_eval(src))
        end
        sh "chmod +x #{template}" if template == 'debian/rules'
      end
    end

    def source_copy
      logger.debug "Start copying sources to #{source_dir}"
      FileUtils.mkdir_p build_dir
      FileUtils.rm_rf source_dir
      FileUtils.cp_r @cli.wd, source_dir
      logger.debug "Finished copying sources to #{source_dir}"
    end

    def source_changelog_dch(path)
      output = 'dch --changelog %{path} -l "+%{cn_str}%{cn}" -D "%{cn}" '
      output += '--force-distribution '
      output += '"Build a changelog entry for %{cn} %{cn}"'

      output % {
        cn: @distribution.codename,
        cn_str: @distribution.codename_str,
        path: path
      }
    end

    def source_changelog
      path = File.join(source_dir, 'debian/changelog')
      logger.debug "Modify changelog file #{path}"
      local_expect(
        'append distribution build to changelog',
        {
          'DEBFULLNAME' => 'Jenkins Autobuilder',
          'DEBEMAIL' => 'jenkins@former03.de'
        },
        source_changelog_dch(path)
      )
    end
  end
end
