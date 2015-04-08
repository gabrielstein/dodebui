require 'dodebui/template_namespace'
require 'open3'
require 'erb'

module Dodebui
  class Build

    attr_reader :distribution

    def initialize(distribution)
      @distribution = distribution
      @cli = distribution.cli
    end

    def local_expect(desc, *args)
      Open3.popen3(*args) do |i, o, e, t|
        if args[0].is_a? Hash
          cmd = args[1]
        else
          cmd = args[0]
        end
        ret_val = t.value.exitstatus
        if ret_val == 0
          logger.debug("#{desc} (cmd=#{cmd}): succeed")
        else
          raise "Exec failed cmd=#{cmd} ret_val=#{ret_val} stdout=#{o.read()} stderr=#{e.read()}"
        end
      end
    end

    def write_log(name, o, e)
        o_path = File.join(build_dir, "#{name}.stdout.log")
        e_path = File.join(build_dir, "#{name}.stderr.log")
        File.open(o_path, 'w') { |file| file.write(o.join '') }
        File.open(e_path, 'w') { |file| file.write(e.join '') }
    end

    def build
      logger.info("Creating container #{@distribution.codename}")
      container = Docker::Container.create(
        'Image' => @distribution.image_name,
        'Cmd' => ['sleep', '3600'],
        'WorkingDir' => '/_build/source',
      )

      logger.info("Starting container #{@distribution.codename}")
      container.start('Binds' => [
        "#{File.join(cache_dir, 'archives')}:/var/cache/apt/archives",
        "#{build_dir}:/_build",
      ])

      logger.info("Installing dependencies #{@distribution.codename}")
      stdout, stderr, ret_val = container.exec([
        '/usr/lib/pbuilder/pbuilder-satisfydepends-aptitude',
      ])
      write_log('apt_install_deps', stdout, stderr)
      if ret_val != 0
        logger.warn("Failed installing dependencies #{@distribution.codename}")
        return false
      end
      logger.info("Finished installing dependencies #{@distribution.codename}")

      logger.info("Building package #{@distribution.codename}")
      stdout, stderr, ret_val = container.exec([
        'dpkg-buildpackage',
      ])
      write_log('build', stdout, stderr)
      if ret_val != 0
        logger.warn("Failed building package #{@distribution.codename}")
        return false
      end
      logger.info("Finished building package #{@distribution.codename}")

      container.stop

      return True
    end

    def cache_dir
      File.expand_path(
        File.join('/var/lib/dodebui', "#{distribution.os}_#{distribution.codename}")
      )
    end

    def build_dir
      File.expand_path(
        File.join(@cli.wd, '..', '_build', "#{distribution.os}_#{distribution.codename}")
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

    def source_templates
      @cli.source_templates.each do |template|
        path = File.join(source_dir, template)
        logger.debug "Evaluate template #{path}"
        erb = ERB.new(
          File.read(path),
          nil,
          '-',
        )
        dest = path[0...-4]
        File.open(dest, 'w') do |file|
          namespace = TemplateNamespace.new({
            os: @distribution.os,
            codename: @distribution.codename,
            codename_int: @distribution.codename_int,
          })
          file.write(erb.result(namespace.get_binding)) 
        end
        if template == 'debian/rules'
          sh "chmod +x #{template}"
        end
        puts template
      end
    end

    def source_copy
        logger.debug "Start copying sources to #{source_dir}"
        FileUtils.mkdir_p build_dir
        FileUtils.rm_rf source_dir
        FileUtils.cp_r @cli.wd, source_dir
        logger.debug "Finished copying sources to #{source_dir}"
    end

    def source_changelog
      path = File.join(source_dir, 'debian/changelog')
      logger.debug "Modify changelog file #{path}"
      local_expect(
        'append distribution build to changelog',
        {
          'DEBFULLNAME' => 'Jenkins Autobuilder',
          'DEBEMAIL' => 'jenkins@former03.de',
        },
        [
          'dch',
          "--changelog #{path}",
          "-l '+#{distribution.codename_str}#{distribution.codename}'",
          "-D '#{distribution.codename}'",
            '--force-distribution',
            "\"Build a changelog entry for #{distribution.os} #{distribution.codename}\"",
        ].join(' ')
      )
    end
  end
end
