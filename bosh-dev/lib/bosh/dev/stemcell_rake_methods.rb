require 'fileutils'

module Bosh::Dev
  class StemcellRakeMethods
    def bosh_micro_options(manifest, tarball)
      {
        bosh_micro_enabled: 'yes',
        bosh_micro_package_compiler_path: File.expand_path('../../../../../package_compiler', __FILE__),
        bosh_micro_manifest_yml_path: manifest,
        bosh_micro_release_tgz_path: tarball,
      }
    end

    # GIT CHANGES

    def changes_in_bosh_agent?
      gem_components_changed?('bosh_agent') || component_changed?('stemcell_builder')
    end

    def changes_in_microbosh?
      microbosh_components = COMPONENTS - %w(bosh_cli bosh_cli_plugin_aws bosh_cli_plugin_micro)
      components_changed = microbosh_components.reduce(false) do |changes, component|
        changes || gem_components_changed?(component)
      end
      components_changed || component_changed?('stemcell_builder')
    end

    def diff
      @diff ||= changed_components
    end

    def changed_components(new_commit_sha = ENV['GIT_COMMIT'], old_commit_sha = ENV['GIT_PREVIOUS_COMMIT'])
      repo = Rugged::Repository.new('.')
      old_trees = old_commit_sha ? repo.lookup(old_commit_sha).tree.to_a : []
      new_trees = repo.lookup(new_commit_sha || repo.head.target).tree.to_a
      (new_trees - old_trees).map { |entry| entry[:name] }
    end

    def component_changed?(path)
      diff.include?(path)
    end

    def gem_components_changed?(gem_name)
      gem = Gem::Specification.load(File.join(gem_name, "#{gem_name}.gemspec"))

      components =
        %w(Gemfile Gemfile.lock) + [gem_name] + gem.runtime_dependencies.map { |d| d.name }.select { |d| Dir.exists?(d) }

      components.reduce(false) do |changes, component|
        changes || component_changed?(component)
      end
    end

    # DEFAULT OPTIONS (DONE)

    def default_options(args)
      infrastructure = args[:infrastructure]
      unless infrastructure
        STDERR.puts 'Please specify target infrastructure (vsphere, aws, openstack)'
        exit 1
      end

      options = {
        'system_parameters_infrastructure' => infrastructure,
        'stemcell_name' => ENV['STEMCELL_NAME'],
        'stemcell_infrastructure' => infrastructure,
        'stemcell_hypervisor' => get_hypervisor(infrastructure),
        'bosh_protocol_version' => Bosh::Agent::BOSH_PROTOCOL,
        'UBUNTU_ISO' => ENV['UBUNTU_ISO'],
        'UBUNTU_MIRROR' => ENV['UBUNTU_MIRROR'],
        'TW_LOCAL_PASSPHRASE' => ENV['TW_LOCAL_PASSPHRASE'],
        'TW_SITE_PASSPHRASE' => ENV['TW_SITE_PASSPHRASE'],
        'ruby_bin' => ENV['RUBY_BIN'] || File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name']),
        'bosh_release_src_dir' => File.expand_path('../../../../../release/src/bosh', __FILE__),
        'bosh_agent_src_dir' => File.expand_path('../../../../../bosh_agent', __FILE__),
        'image_create_disk_size' => (args[:disk_size] || 2048).to_i
      }

      p options

      case infrastructure
        when 'vsphere'
          # Pass OVFTOOL environment variable when targeting vsphere
          options[:image_vsphere_ovf_ovftool_path] = ENV['OVFTOOL']
        when 'openstack'
          # Increase the disk size to 10Gb to deal with flavors that doesn't have ephemeral disk
          options[:image_create_disk_size] = 10240 unless args[:disk_size]
      end

      options
    end

    def get_hypervisor(infrastructure)
      return ENV['STEMCELL_HYPERVISOR'] if ENV['STEMCELL_HYPERVISOR']

      case infrastructure
        when 'vsphere'
          hypervisor = 'esxi'
        when 'aws'
          hypervisor = 'xen'
        when 'openstack'
          hypervisor = 'kvm'
        else
          raise "Unknown infrastructure: #{infrastructure}"
      end
      hypervisor
    end

    # BUILDING

    def get_working_dir
      ENV['BUILD_PATH'] || "/var/tmp/bosh/bosh_agent-#{Bosh::Agent::VERSION}-#{$$}"
    end

    def env
      keep = %w{
      HTTP_PROXY
      http_proxy
      NO_PROXY
      no_proxy
      }

      format_env(ENV.select { |k| keep.include?(k) })
    end

    # Format a hash as an env command.
    def format_env(h)
      'env ' + h.map { |k, v| "#{k}='#{v}'" }.join(' ')
    end

    def build(spec, options)
      root = get_working_dir
      FileUtils.mkdir_p root
      puts "MADE ROOT: #{root}"
      puts "PWD: #{Dir.pwd}"

      build_path = File.join(root, 'build')

      FileUtils.rm_rf build_path
      FileUtils.mkdir_p build_path
      stemcell_build_dir = File.expand_path('../../../../../stemcell_builder', __FILE__)
      FileUtils.cp_r Dir.glob("#{stemcell_build_dir}/*"), build_path, preserve: true

      work_path = ENV['WORK_PATH'] || File.join(root, 'work')
      FileUtils.mkdir_p work_path

      # Apply options
      settings_dir = File.join(build_path, 'etc')
      settings_path = File.join(settings_dir, 'settings.bash')
      File.open(settings_path, 'a') do |f|
        f.printf("\n# %s\n\n", '=' * 20)
        options.each do |k, v|
          f.print "#{k}=#{v}\n"
        end
      end

      builder_path = File.join(build_path, 'bin', 'build_from_spec.sh')
      spec_path = File.join(build_path, 'spec', "#{spec}.spec")

      # Run builder
      STDOUT.puts "building in #{work_path}..."
      cmd = "sudo #{env} #{builder_path} #{work_path} #{spec_path} #{settings_path}"

      puts cmd
      system cmd
    end
  end
end
