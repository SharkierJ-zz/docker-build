# frozen_string_literal: false

require 'optparse'
require 'json'
require 'httparty'
require_relative 'imqs_git'
#require_relative 'aws_helper'

BUILD_DIR = "#{__dir__}/build"
CP_DIR = "#{__dir__}/cherrypick"

class CherryPicker
  attr_reader :release_version, :service_name, :service_version, :commit_hash

  def self.initialize(release_version, service_name, service_version, commit_hash)
    @release_version = release_version
    @service_name = service_name
    @service_version = service_version
    @commit_hash = commit_hash
  end

  def self.configure_pick_branch(git_repo, service_name, service_version)
    print "------------------------------------Opening Pick Folder: #{CP_DIR} ---------------------------------------------------------------------\n"
    open_cp_dir
    print "------------------------------------Cherry Picking to Service #{service_name}-----------------------------------------------------------\n"
    print "service: #{service_name}, version: #{service_version}\n"
    GitRepository.new(git_repo[0])
    find_or_create_branch(service_version)
  end

  def self.tag_git_repo(version)
    `git tag v#{version}`
    `git push origin --tags`
    `git push`
  end

  def self.verify_docker_hub_tag(service, version)
    docker_hub = HTTParty.get("https://hub.docker.com/v2/repositories/#{service}/tags")
    return false unless docker_hub.response.code.eql?('200')
    res = docker_hub['results'].map {|result| result['name']}.select {|name| name == version}
    return false unless res[0].eql?(version)
    true
  end

  def self.create_new_manifest(release)
    Dir.chdir('../')
    release_manifest = create_release_hash(read_release_manifest(find_max_release(release.to_s)))
    pick_manifest = create_pick_hash(read_pick_manifest(find_max_pick(release.to_f.to_s)))
    new_manifest = ''
    release_manifest.each {|release_service|
      pick_manifest.each {|pick_service|
        if release_service['service'] == pick_service['service']
          new_manifest << create_manifest_prop(pick_service['service'], pick_service['version'])
        else
          new_manifest << create_manifest_prop(release_service['service'], release_service['version'])
        end
      }
    }
    # Create the manifest file and send to S3 bucket.
    manifest_file = create_pick_manifest(new_manifest, increment_minor_version(release))
    puts "Sending #{manifest_file} to manifest registry"
    #ImqsAws.send_file_to_aws_s3_bucket(manifest_file)
    puts 'Completed'
    exit(0)
  end

  private

  def self.increment_minor_release_version(release_version)
    increment_minor_version(find_max_release(release_version))
  end

  # expects array from Dir.glob or normal string
  def self.find_max_version(version)
    if version.class.eql?(String)
      split_version = version.split('.')
    else
      split_version = version.map {|value| value.split('.')}
    end
      service_version = split_version.map { |major| major[0] }.max
      max_minor_version = split_version.map { |minor| minor[1].to_i }.max
      "#{service_version}.#{max_minor_version}"
  end

  def self.increment_minor_version(service_version)
    version_number = service_version.to_s.split('.')
    version_number = "#{version_number[0]}.#{version_number[1].to_i + 1}".to_s
    version_number
  end

  # expects major version string and builds array from Dir.glob
  # returns release and max minor version
  def self.find_max_release(ver)
    open_build_dir
    release = Dir.glob("#{ver.to_i}*")
    max_release = find_max_version(release)
    max_release
  end

  # expects major service version string and builds array from Dir.glob
  # returns release and max minor version
  def self.find_max_pick(ver)
    open_cp_dir
    pick = Dir.glob("#{ver.to_i}*")
    max_pick = find_max_version(pick)
    max_pick
  end

  def self.find_max_git_tag
    `git fetch origin`
    tags = `git tag`
    tags = 'v1.0' if tags.empty?
    tags = tags.chomp.tr('v', '')
    max_tag = find_max_version(tags)
    max_tag
  end

  def self.open_build_dir
    Dir.mkdir(BUILD_DIR) unless File.exist?(BUILD_DIR)
    Dir.chdir(BUILD_DIR)
  end

  def self.open_cp_dir
    Dir.mkdir(CP_DIR) unless File.exist?(CP_DIR)
    Dir.chdir(CP_DIR)
  end

  def self.create_release_manifest(manifest, version)
    file = "#{BUILD_DIR}/#{version}"
    File.open(file, 'w') do |f|
      f.write(manifest)
    end
  end

  def self.create_pick_manifest(manifest, version)
    file = "#{CP_DIR}/#{version}"
    File.open(file, 'w') do |f|
      f.write(manifest)
    end
  end

  def self.read_release_manifest(manifest)
    File.readlines("#{BUILD_DIR}/#{manifest}")
  end

  def self.read_pick_manifest(manifest)
    File.readlines("#{CP_DIR}/#{manifest}")
  end

  # expects array from File.readlines
  # returns release hash map array
  def self.create_release_hash(release_manifest)
    split_release = release_manifest.map {|value| value.chomp.split('=')}
    services = []
    split_release.each {|arg| services << {'service' => arg[0], 'version'=> arg[1] }}
  return services
  end

  # expects array from File.readlines
  # returns pick hash map array
  def self.create_pick_hash(pick_manifest)
    split_picks = pick_manifest.map {|value| value.chomp.split('=')}
    services = []
    split_picks.each {|arg| services << {'service' => arg[0], 'version'=> arg[1] }}
  return services
  end

  def self.fetch_json_file(file, read_from_disk = false)
    read_file = read_from_disk ? File.read(file) : ImqsAws.fetch_file_from_aws_s3_bucket(file)
    JSON.parse(read_file.to_s)
  end

  def self.find_or_create_branch(service_version)
    return 'Checking out local CP branch' unless cp_branch_exists_locally?(service_version.to_f.to_s).eql?(false)
    return 'Adding remote CP branch' unless cp_branch_exists_remotely?(service_version.to_f.to_s).eql?(false)
    puts 'Creating new CP branch'
    create_cp_branch(service_version.to_f.to_s)
  end

  def self.cp_branch_exists_locally?(service_version)
    print "checking if local branch exists\n"
    cp_branch = "cp-#{service_version}"
    verify = system("git rev-parse --verify --quiet #{cp_branch}")
    return false unless verify.eql?(true)
    system("git checkout #{cp_branch}")
    true
  end

  def self.cp_branch_exists_remotely?(service_version)
    print "checking if remote branch exists\n"
    cp_branch = "cp-#{service_version}"
    verify = `git ls-remote --heads origin #{cp_branch}`
    return false unless !verify.empty?
    add_remote_branch(cp_branch)
    system("git checkout #{cp_branch}")
    true
  end

  def self.create_cp_branch(service_version)
    cp_branch = "cp-#{service_version}"
    system("git branch #{cp_branch} v#{service_version}")
    system("git push -u origin #{cp_branch}")
    system("git checkout #{cp_branch}")
  end

  def self.update_master_branch
    system('git checkout master')
    system('git pull')
  end

  def self.cherry_pick_commit(hash)
    print "Picking commit: #{hash}\n"
    system("git cherry-pick #{hash}")
  end

  def self.add_remote_branch(branch)
   system("git remote set-branches --add origin #{branch}")
  end

  def self.create_manifest_prop(service_name, version)
    "#{service_name}=#{version}\n"
  end

  def self.prepare_docker_image(service_name, version, info)
    ENV['servicename'] = service_name
    ENV['tag'] = version.to_s
    build_out = `#{info}`
    if build_out.include? 'Successfully built'
      system("docker tag #{service_name}:master #{service_name}:#{version}", out: $stdout, err: :out)
      system("docker push #{service_name}:#{version}", out: $stdout, err: :out)
      true
    else
      puts `echo Build Failed`
      false
    end
  end
end

def generate_cherrypick_hash(arguments)
  split_arguments = arguments.map {|value| value.split(':')}
  cherrypicks = []
  split_arguments.each {|arg| cherrypicks << {'release' => arg[0], 'service' => arg[1], 'version'=> arg[2], 'commits' => arg.drop(3) }}
  return cherrypicks
end

def run_all_cherry_picks(pick_array)
  release_candidates = CherryPicker.fetch_json_file('releaseCandidates.json', true)
  release_version = (CherryPicker.find_max_release(pick_array[0]['release'].to_f.to_s))
  manifest = ''
  pick_array.each { |pick|
    repository = release_candidates.find_all {|service, value| value['VersionVariable'] == pick['service']}
    docker_service = repository.map {|service, value| service}
    docker_build = repository.map {|service, value| value['DockerBuild']}
    repo = repository.map {|service, value| value['GitRepo']}
    service = repository.map {|service, value| value['VersionVariable']}
    version = pick['version']
    latest_tag =  CherryPicker.find_max_git_tag
    new_tag = CherryPicker.increment_minor_version(latest_tag)
    CherryPicker.configure_pick_branch(repo, service, version)
    pick['commits'].each { |commit|
      cherry_pick_success = CherryPicker.cherry_pick_commit(commit)
      if cherry_pick_success.eql?(false)
        raise "Cherry Pick failure on: #{commit}, verify the commit before running this script again"
      end
    }
    docker_hub_tag = CherryPicker.verify_docker_hub_tag(docker_service[0], new_tag)
    if docker_hub_tag.eql?(true)
      raise "Docker Hub tag #{new_tag} already exists, not building image"
    end
    build_docker_image = CherryPicker.prepare_docker_image(docker_service[0], new_tag, docker_build[0])
    if build_docker_image.eql?(false)
      raise "Building Docker Image for #{service} has failed, not tagging git repo"
    end
    new_tag = CherryPicker.increment_minor_version(latest_tag)
    CherryPicker.tag_git_repo(new_tag)
    manifest << CherryPicker.create_manifest_prop(service[0], new_tag)
  }
  manifest_version = CherryPicker.increment_minor_version(release_version)
  CherryPicker.create_pick_manifest(manifest, manifest_version)
end

def create_minor_release_manifest(version)
  release_version = CherryPicker.increment_minor_release_version(version)
  CherryPicker.create_new_manifest(release_version)
end

if $PROGRAM_NAME == __FILE__

  options = []

  optparse = OptionParser.new do |opts|
    opts.banner =  'Usage: cherrypicker.rb [option] release_version:service_name:service_version:commit_hash1:..commit_hash_n'
    opts.separator ''
    opts.separator 'Example: Single service'
    opts.separator '   ruby cherrypicker.rb -c release_version:service_name:service_version:commit_hash'
    opts.separator ''
    opts.separator 'Example: Multiple services'
    opts.separator '   ruby cherrypicker.rb -c release_version:service_name:service_version:commit_hash,release_version:service_name:service_version:commit_hash'
    opts.separator ''
    opts.on('-c', '--cherrypick=CHERRYPICK', Array, 'commits to be picked') {|c| options = c  }
    opts.on('-h', 'Help') { |h| puts opts; exit(0) }
  end

  begin
    optparse.parse!

    if options.empty?
      raise OptionParser::MissingArgument
    end

    picks = generate_cherrypick_hash(options)
    run_all_cherry_picks(picks)
    create_minor_release_manifest(picks[0]['release'])

  rescue OptionParser::ParseError => msg
    puts msg
    puts optparse
    exit(1)
  rescue RuntimeError => msg
    puts msg
    exit(1)
  end
end

