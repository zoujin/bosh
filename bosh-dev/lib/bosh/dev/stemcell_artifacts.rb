require 'bosh/stemcell/definition'
require 'bosh/stemcell/archive_filename'

module Bosh::Dev
  class StemcellArtifacts
    def self.all(version)
      definitions = [
        Bosh::Stemcell::Definition.for('vsphere', 'ubuntu', 'lucid', 'go'),
        Bosh::Stemcell::Definition.for('vsphere', 'ubuntu', 'trusty', 'go'),
        Bosh::Stemcell::Definition.for('vsphere', 'centos', nil, 'go'),

        Bosh::Stemcell::Definition.for('aws', 'ubuntu', 'lucid', 'go'),
        Bosh::Stemcell::Definition.for('aws', 'ubuntu', 'trusty', 'go'),
        Bosh::Stemcell::Definition.for('aws', 'centos', nil, 'go'),

        Bosh::Stemcell::Definition.for('openstack', 'ubuntu', 'trusty', 'go'),
        Bosh::Stemcell::Definition.for('openstack', 'centos', nil, 'go'),
      ]

      new(version, definitions)
    end

    def initialize(version, matrix)
      @version = version
      @matrix = matrix
    end

    def list
      artifact_names = []

      matrix.each do |definition|
        versions.each do |version|
          filename = Bosh::Stemcell::ArchiveFilename.new(version, definition, 'bosh-stemcell', false)
          artifact_names << archive_path(filename.to_s, definition.infrastructure)

          if definition.infrastructure.light?
            light_filename = Bosh::Stemcell::ArchiveFilename.new(version, definition, 'bosh-stemcell', true)
            artifact_names << archive_path(light_filename.to_s, definition.infrastructure)
          end
        end
      end

      artifact_names
    end

    private

    attr_reader :version, :matrix

    def versions
      [version, 'latest']
    end

    def archive_path(filename, infrastructure)
      File.join('bosh-stemcell', infrastructure.name, filename)
    end
  end
end
