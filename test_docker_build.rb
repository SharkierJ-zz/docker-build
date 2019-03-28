require_relative 'docker_build'


@repo = 'test-docker-versioning'
@service = 'sharkierj/second-service'
@version = '1.0'

def test_build
  Dir.chdir(@repo)
  test = DockerBuild.build_image(@service, @version)
  print test
  if test.eql?(true)
    return true
  else
    return false
  end
end

test_build
