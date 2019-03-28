require 'json'
require_relative 'GitPick'
require_relative 'docker_build'

class GitCherryPick
  # The main runner method to be called
  def self.prepare_cherry_pick
    cherry_picks = fetch_json_file('cherrypicks.json')
    manifest_json = []

    cherry_picks.each { |repo|
      if run_flag(repo['RunFlag']).eql?(true)
        docker_service_name = repo['DockerServiceName']
        repository_name = repo['GitRepo']
        version = find_or_create_pick_branch(repository_name)
        temp_hash = create_service_hash(docker_service_name, version)
        manifest_json.push(temp_hash)
      end
    }

    create_manifest_file(manifest_json)
  end

  private

  def self.run_flag(flag)
    return false unless flag.upcase.eql?('YES')
    true
  end
  # Creates a physical file called manifest.json
  # Writes to the the above mentioned file, the content of the hash as json.
  # @param : Ruby hash.
  def self.create_manifest_file(manifest_json)
    file_name = '../manifest.json'
    File.open(file_name, 'w') do |f|
      f.write(manifest_json.to_json)
    end
  end

  # Build the docker image and pushes if successful.
  # ToDO : Docker Build
  # ToDo : Docker Push

  # Creates a ruby hash containing the following
  # @param1 : The docker image service name.
  # @param2 : The version number as an integer, of the image.
  def self.create_service_hash(docker_service_name, version)
    {
        :ServiceName => docker_service_name,
        :Version => version
    }
  end

  # Fetch the release candidated from a specified json file.
  # @param :
  def self.fetch_json_file(file)
    json_from_file = File.read(file)
    return JSON.parse(json_from_file)
  end

  # Creates the cherry pick branch and does the minor version calculation.
  #
  def self.find_or_create_pick_branch(repository_name)
    repository = GitRepository.new(repository_name)
    puts (repository.tag)
    if (repository.head) == (repository.fetch_revision(repository.version))
      puts "Nothing has changed. Keeping #{repository.version}"
      exit(0)
    end

  rescue ImqsGitError => error
    puts("#{error.message} : #{error.backtrace}")
    exit (1)
  end

  def self.increment_minor_version(repository)
    version_number = repository.version.tr("\n", '').tr('').to_i
    version_number = (version_number.to_i + 1).to_f
    repository.tag(version_number)
    return version_number
  end
end

class String
  def is_float?
    /\A[+-]?\d+[.]\d+\z/ === self
  end
end

GitCherryPick.prepare_cherry_pick
#GitCherryPick.prepare_version
