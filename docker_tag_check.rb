require 'httparty'


username='sharkierj'
servicename='version-test'
version='1.8'


def docker_tag_exists?(user, service, ver)
  docker_hub = HTTParty.get("https://hub.docker.com/v2/repositories/#{user}/#{service}/tags")
  res = docker_hub['results'].map {|value| value['name']}.select {|value| value == ver}
  return false unless res[0].eql?(ver)
  print "Version #{ver} exists on docker hub"
  true
end

if docker_tag_exists?(username, servicename, version).eql?(false)
  print "Tag #{version} does not exist on docker hub"
end
