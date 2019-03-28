require 'json'
require_relative 'GitPick'

def run_flag(flag)
  return false unless flag.upcase.eql?('YES')
  true
end


def fetch_json_file(file)
  json_from_file = File.read(file)
  return JSON.parse(json_from_file)
end

def testing_array(flag, service, repo, version)
    if run_flag(flag).eql?(true)
      service_name = service
      repo_name = repo
      ver = version
      print "#{service_name} #{repo_name} #{version} RUN=#{flag}"
    end
end

cherry_picks = fetch_json_file('cherrypicks.json')

cherry_picks.each { |repo|
  testing_array(repo['RunFlag'], repo['DockerServiceName'], repo['GitRepo'], repo['ServiceVersion'])
}

